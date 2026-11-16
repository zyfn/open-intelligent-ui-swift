// Private bridge budget outcomes. Public Lang query values and callbacks keep
// their existing semantics; Swift uses these counters inside its dispatch gate.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: { Box: { type: 'object', properties: { value: {} }, required: ['value'] } },
  properties: { Box: { $ref: '#/$defs/Box' } },
  functions: { Reenter: { params: { type: 'object', properties: {} } } },
};
const list = '[0,1,2,3,4,5,6]';
const expensive = ['a', 'b', 'c', 'd', 'e']
  .reduceRight((body, key) => `@Each($items,${key},${body})`, '1');
const plain = value => JSON.parse(JSON.stringify(value));
const settle = () => new Promise(resolve => setImmediate(resolve));

function runtime(t) {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
    setInterval, clearInterval,
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const bridge = realm.SwiftCore, core = bridge.api, library = bridge.library(schema, {});
  const parse = source => {
    const result = core.createParser(schema).parse(source);
    assert.deepEqual(plain(result.meta.errors), []);
    return result;
  };
  function fixture(result, provider) {
    const store = core.createStore(); store.initialize(result.stateDeclarations, {});
    const calls = []; let failures = 0;
    const manager = bridge.queryManager(provider ?? { callTool(name, args) {
      calls.push({ name, args }); return new Promise(() => {});
    } });
    t.after(() => manager.dispose());
    const context = { getState: name => store.get(name), resolveRef: () => null,
      reportNativeLimit: () => failures++ };
    return { store, manager, context, calls, failures: () => failures };
  }
  return { bridge, core, library, parse, fixture };
}

test('query tool, arguments and defaults report successful nonzero work without changing their values', t => {
  const { bridge, parse, fixture } = runtime(t);
  const parsed = parse('$suffix="_items"\nq=Query("load"+$suffix,{count:2+3},@Each([1,2],item,item+1))\nroot=Box("ok")');
  const f = fixture(parsed);
  const outcome = bridge.boundedQueryStatements(f.manager, parsed.queryStatements, f.context);
  assert.equal(outcome.limitExceeded, false); assert(outcome.work > 0);
  assert.deepEqual(plain(f.calls), [{ name: 'load_items', args: { count: 5 } }]);
  assert.deepEqual(plain(f.manager.getResult('q')), [2, 3]);
  assert.equal(f.failures(), 0);
});

test('two individually allowed query defaults share one batch budget', t => {
  const { bridge, parse, fixture } = runtime(t);
  const parsed = parse(`$items=${list}\nq=Query("q",{},${expensive})\nr=Query("r",{},${expensive})\nroot=Box("ok")`);
  const individual = parsed.queryStatements.map(statement => {
    const f = fixture(parsed);
    const outcome = bridge.boundedQueryStatements(f.manager, [statement], f.context);
    assert.equal(outcome.limitExceeded, false);
    assert(outcome.work > 50_000 && outcome.work < 100_000);
    return outcome.work;
  });
  assert(individual[0] + individual[1] > 100_000);
  const f = fixture(parsed);
  const outcome = bridge.boundedQueryStatements(f.manager, parsed.queryStatements, f.context);
  assert.equal(outcome.limitExceeded, true); assert.equal(outcome.value, null);
  assert.equal(outcome.work, 100_001); assert.equal(f.failures(), 1);
});

test('query evaluation stops at the borrowed remaining allowance and defaults to the original limit', t => {
  const { bridge, parse, fixture } = runtime(t);
  const parsed = parse(`$items=${list}\nq=Query("q",{},${expensive})\nroot=Box("ok")`);
  const limited = fixture(parsed);
  const outcome = bridge.boundedQueryStatements(limited.manager, parsed.queryStatements, limited.context, 1000);
  assert.equal(outcome.limitExceeded, true); assert.equal(outcome.work, 1001);
  assert.equal(limited.failures(), 1);
  const next = fixture(parsed);
  const recovered = bridge.boundedQueryStatements(next.manager, parsed.queryStatements, next.context);
  assert.equal(recovered.limitExceeded, false); assert(recovered.work > 50_000);
});

test('root and expression private entries honor the remaining allowance', t => {
  const { bridge, library, parse, fixture } = runtime(t);
  const parsed = parse(`$items=${list}\nq=Query("q",{},${expensive})\nroot=Box(${expensive})`);
  const f = fixture(parsed);
  const root = bridge.boundedRoot(parsed, f.context, library, f.store, [], 1000);
  assert.equal(root.limitExceeded, true); assert.equal(root.work, 1001);
  const expression = bridge.boundedEvaluate(parsed.queryStatements[0].defaultsAST, f.context, library, 1000);
  assert.equal(expression.limitExceeded, true); assert.equal(expression.work, 1001);
  const recovered = bridge.boundedRoot(parsed, f.context, library, f.store, []);
  assert.equal(recovered.limitExceeded, false);
});

test('a nested query entry cannot reset the outer remaining allowance', t => {
  const { bridge, library, parse, fixture } = runtime(t);
  const parsed = parse(`$items=${list}\nq=Query("q",{},${expensive})\nroot=Box(@Reenter())`);
  const f = fixture(parsed); let nested;
  const context = { ...f.context, functions: {
    Reenter: { params: { type: 'object', properties: {} }, fn() {
      nested = bridge.boundedQueryStatements(f.manager, parsed.queryStatements, f.context, 100_000);
      return null;
    } },
  } };
  const outer = bridge.boundedRoot(parsed, context, library, f.store, [], 1000);
  assert.equal(nested.limitExceeded, true); assert.equal(nested.work, 1001);
  assert.equal(outer.limitExceeded, true); assert.equal(outer.work, 1001);
});

test('invalidation lends its allowance to synchronous host notification evaluation', async t => {
  const { bridge, library, parse, fixture } = runtime(t);
  const parsed = parse(`$items=${list}\nq=Query("q",{},[])\nprobe=Query("probe",{},${expensive})\nroot=Box("ok")`);
  const f = fixture(parsed, { callTool: async () => [] });
  bridge.boundedQueryStatements(f.manager, [parsed.queryStatements[0]], f.context);
  await settle(); await settle();
  let nested;
  const unsubscribe = f.manager.subscribe(() => {
    nested = bridge.boundedEvaluate(parsed.queryStatements[1].defaultsAST, f.context, library, 100_000);
  });
  const outcome = bridge.boundedQueryInvalidation(f.manager, 'q', 1000);
  unsubscribe();
  assert.equal(nested.limitExceeded, true); assert.equal(nested.work, 1001);
  assert.equal(outcome.limitExceeded, true); assert.equal(outcome.work, 1001);
  // Tool callbacks retain their normal ordering here. The native deferred gate,
  // not this counter-only entry, decides whether an external request may start.
});

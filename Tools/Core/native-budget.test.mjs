// Real shipped-core regressions. The optional path is only for an isolated
// source-build probe before regenerating the committed Swift resource.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: {
    Box: { type: 'object', properties: { value: {} }, required: ['value'] },
    Stack: { type: 'object', properties: { children: {} }, required: ['children'] },
    Button: { type: 'object', properties: { label: {}, action: {} }, required: ['label'] },
  },
  properties: Object.fromEntries(['Box', 'Stack', 'Button'].map(name => [name, { $ref: '#/$defs/' + name }])),
};
const nestedEach = array => ['a', 'b', 'c', 'd', 'e'].reduceRight((body, key) => `@Each(${array},${key},${body})`, '1');
const list = size => '[' + Array.from({ length: size }, (_, i) => i).join(',') + ']';
const plain = value => JSON.parse(JSON.stringify(value));
const settle = () => new Promise(resolve => setImmediate(resolve));
function runtime() {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
    setInterval, clearInterval,
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const bridge = realm.SwiftCore, core = bridge.api;
  const library = bridge.library(schema, {});
  const parse = source => core.createParser(schema).parse(source);
  const render = (result, context) => {
    const store = core.createStore(); store.initialize(result.stateDeclarations, {});
    realm.result = result; realm.library = library; realm.store = store; realm.errors = [];
    realm.ctx = context ?? { getState: name => store.get(name), resolveRef: () => null };
    // A broken budget fails this safety deadline; a passing test must return
    // the SDK's explicit outcome, not rely on the Node deadline for protection.
    return vm.runInContext('SwiftCore.boundedRoot(result,ctx,library,store,errors)', realm, { timeout: 2000 });
  };
  return { realm, bridge, core, parse, render };
}

test('normal nested Each keeps all 3125 values and permits the next operation', () => {
  const { bridge, parse, render } = runtime();
  const result = parse(`$items=${list(5)}\nroot=Box(${nestedEach('$items')})`);
  assert.equal(bridge.nativeBudgetExceeded(result), false);
  assert.deepEqual(plain(result.meta.errors), []);
  const outcome = render(result);
  assert.equal(outcome.limitExceeded, false);
  const leaves = value => Array.isArray(value) ? value.reduce((sum, child) => sum + leaves(child), 0) : 1;
  assert.equal(leaves(outcome.value.props.value), 3125);
  assert.equal(render(parse('root=Box("next")')).value.props.value, 'next');
});

test('24.3 million Each leaves stop by the deterministic work budget', () => {
  const { bridge, parse, render } = runtime();
  const source = `$items=${list(30)}\nroot=Box(${nestedEach('$items')})`;
  assert(source.length < 200);
  const result = parse(source);
  assert.equal(bridge.nativeBudgetExceeded(result), false);
  const outcome = render(result);
  assert.equal(outcome.limitExceeded, true);
  assert.equal(outcome.value, null);
  assert(outcome.work <= 100001);
  assert.equal(render(parse('root=Box("recovered")')).value.props.value, 'recovered');
});

test('the prop fallback does not swallow budget exhaustion', () => {
  const { realm, parse, render } = runtime();
  const result = parse(`$items=${list(30)}\nroot=Stack([Box(${nestedEach('$items')}),Box("tail")])`);
  const outcome = render(result);
  assert.equal(outcome.limitExceeded, true);
  assert.equal(outcome.value, null);
  assert.deepEqual(plain(realm.errors), []);
});

test('materialization exhaustion has private metadata before any native projection', () => {
  const { bridge, core } = runtime();
  const parser = core.createStreamingParser(schema);
  const source = 'root=Button("Go",@OpenUrl("https://example.test"))\nq=Query("load",{x:$x},[])\n$x=a0\n'
    + Array.from({ length: 256 }, (_, i) => `a${i}=${i === 255 ? '"ok"' : `a${i + 1}`}`).join('\n');
  const before = parser.set('root=Box("before")', true);
  const failed = parser.set(source, true);
  assert.equal(bridge.nativeBudgetExceeded(failed), true);
  assert.equal(bridge.nativeBudgetExceeded(parser.getResult(true)), true);
  assert.equal(bridge.nativeBudgetExceeded(before), false);
  assert.equal(bridge.sourceComplete(before.root), true);
  assert(failed.meta.errors.length > 0);
  failed.meta.errors[0].message = '本地化错误说明';
  assert.equal(bridge.nativeBudgetExceeded(failed), true, 'failure detection must not match English text');
  assert.equal(Object.keys(failed).some(key => key.includes('native')), false);
  const recovered = parser.set('root=Box("after")', true);
  assert.equal(bridge.nativeBudgetExceeded(recovered), false);
  assert.equal(recovered.root.props.value, 'after');
});

test('alias occurrence cost is bounded before state-default projection', () => {
  const { realm, bridge, parse } = runtime();
  const source = levels => 'a0=[1]\n'
    + Array.from({ length: levels }, (_, i) => `a${i + 1}=[a${i},a${i}]`).join('\n')
    + `\n$data=a${levels}\nroot=Box("ok")`;
  assert.equal(bridge.nativeBudgetExceeded(parse(source(10))), false);
  realm.source = source(40); realm.schema = schema;
  const failed = vm.runInContext('SwiftCore.api.createParser(schema).parse(source)', realm, { timeout: 2000 });
  assert.equal(bridge.nativeBudgetExceeded(failed), true);
});

test('repeated element occurrences are counted instead of deduplicated', () => {
  const { bridge, parse } = runtime();
  const source = levels => 'a0=Box("leaf")\n'
    + Array.from({ length: levels }, (_, i) => `a${i + 1}=Stack([a${i},a${i}])`).join('\n')
    + `\nroot=a${levels}`;
  assert.equal(bridge.nativeBudgetExceeded(parse(source(10))), false, '2047 elements remain accepted');
  assert.equal(bridge.nativeBudgetExceeded(parse(source(12))), true, '8191 occurrences exceed the native tree budget');
});

test('host data is rechecked after mutation and cyclic output is rejected', () => {
  const { parse, render } = runtime();
  const result = parse('root=Box($value)');
  const value = { text: 'ready' };
  const context = { getState: () => value, resolveRef: () => null };
  assert.equal(render(result, context).limitExceeded, false);
  value.self = value;
  assert.equal(render(result, context).limitExceeded, true);
  delete value.self;
  assert.equal(render(result, context).limitExceeded, false);
});

test('elementwise builtins inspect a compact hostile DAG before expanding it', () => {
  const { parse, render } = runtime();
  let value = [1];
  for (let i = 0; i < 40; i++) value = [value, value];
  const outcome = render(parse('root=Box(@Abs($value))'), { getState: () => value, resolveRef: () => null });
  assert.equal(outcome.limitExceeded, true);
  assert.equal(outcome.value, null);
});

test('string concatenation is bounded before producing an oversized string', () => {
  const { parse, render } = runtime();
  const outcome = render(parse('root=Box($value+$value)'), {
    getState: () => 'x'.repeat(600_000), resolveRef: () => null,
  });
  assert.equal(outcome.limitExceeded, true);
  assert.equal(outcome.value, null);
});

test('query argument exhaustion cancels the batch before any tool dispatch', () => {
  const { core, parse } = runtime();
  const result = parse(`$items=${list(30)}\nq=Query("load",{value:${nestedEach('$items')}},[])\nroot=Box("ok")`);
  const store = core.createStore(); store.initialize(result.stateDeclarations, {});
  const calls = []; let failures = 0;
  const manager = core.createQueryManager({ callTool: async (name, args) => { calls.push({ name, args }); return []; } });
  manager.evaluateStatements(result.queryStatements, {
    getState: name => store.get(name), resolveRef: () => null, reportNativeLimit: () => failures++,
  });
  assert.equal(failures, 1);
  assert.deepEqual(calls, []);
  manager.invalidate();
  assert.deepEqual(calls, []);
  manager.dispose();
});

test('automatic query reader exhaustion never dispatches truncated arguments', async () => {
  const { core, parse } = runtime();
  const result = parse(`rows=Query("rows",{},[])\nnext=Query("next",{value:${nestedEach('rows')}},[])\nroot=Box("ok")`);
  const calls = []; let resolveRows, failures = 0;
  const manager = core.createQueryManager({ callTool: (name, args) => {
    calls.push({ name, args });
    return new Promise(resolve => { resolveRows = resolve; });
  } });
  manager.evaluateStatements(result.queryStatements, {
    getState: () => null, resolveRef: name => manager.getResult(name), reportNativeLimit: () => failures++,
  });
  assert.deepEqual(calls.map(call => call.name), ['rows']);
  resolveRows(Array.from({ length: 30 }, (_, i) => i));
  await settle(); await settle();
  assert.equal(failures, 1);
  assert.deepEqual(calls.map(call => call.name), ['rows']);
  manager.dispose();
});

test('one query batch shares work rather than resetting the budget per statement', () => {
  const { core, parse } = runtime();
  const source = `$items=${list(5)}\n`
    + Array.from({ length: 8 }, (_, i) => `q${i}=Query("load",{value:${nestedEach('$items')}},[])`).join('\n')
    + '\nroot=Box("ok")';
  const result = parse(source), store = core.createStore();
  store.initialize(result.stateDeclarations, {});
  const calls = []; let failures = 0;
  const manager = core.createQueryManager({ callTool: async name => { calls.push(name); return []; } });
  manager.evaluateStatements(result.queryStatements, {
    getState: name => store.get(name), resolveRef: () => null, reportNativeLimit: () => failures++,
  });
  assert.equal(failures, 1);
  assert.deepEqual(calls, []);
  manager.dispose();
});

test('state-default evaluation exhaustion marks the parse before null can initialize state or queries', () => {
  const { bridge, core, parse } = runtime();
  const source = `$items=${list(30)}\n$x=${nestedEach('$items')}\nroot=Box($x)\nq=Query("load",{x:$x},[])`;
  const failed = parse(source);
  assert.equal(bridge.nativeBudgetExceeded(failed), true);
  assert(failed.meta.errors.length > 0);
  assert.deepEqual(plain(failed.stateDeclarations), {});
  assert.deepEqual(plain(failed.queryStatements), []);
  const calls = [];
  const manager = core.createQueryManager({ callTool: async (name, args) => { calls.push({ name, args }); return []; } });
  manager.evaluateStatements(failed.queryStatements, { getState: () => null, resolveRef: () => null });
  assert.deepEqual(calls, []);
  manager.dispose();
  assert.equal(bridge.nativeBudgetExceeded(parse('$x=2+3\nroot=Box($x)')), false);
});

test('all state declarations share a budget rather than resetting for each default', () => {
  const { bridge, parse } = runtime();
  const one = parse(`$items=${list(5)}\n$x=${nestedEach('$items')}\nroot=Box($x)`);
  assert.equal(bridge.nativeBudgetExceeded(one), false);
  assert.equal(one.stateDeclarations.$x.length, 5);
  const source = `$items=${list(5)}\n`
    + Array.from({ length: 8 }, (_, i) => `$x${i}=${nestedEach('$items')}`).join('\n')
    + '\nroot=Box($x0)';
  const failed = parse(source);
  assert.equal(bridge.nativeBudgetExceeded(failed), true);
  assert.deepEqual(plain(failed.stateDeclarations), {});
});

test('ordinary expression and recursive collection defaults retain Lang 1.1 values', () => {
  const { bridge, parse } = runtime();
  const result = parse('$n=2\n$total=$n*3\n$rounded=@Round([1.4,2.6])\n$data={a:$total,b:[@Abs(-2),$n+1]}\nroot=Box($data)');
  assert.equal(bridge.nativeBudgetExceeded(result), false);
  assert.deepEqual(plain(result.meta.errors), []);
  assert.deepEqual(plain(result.stateDeclarations), {
    $n: 2, $total: 6, $rounded: [1, 3], $data: { a: 6, b: [2, 3] },
  });
});

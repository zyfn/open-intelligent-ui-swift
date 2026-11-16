import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const maximumSource = 1_048_576;
const schema = {
  $defs: { Box: { type: 'object', properties: { value: {} }, required: ['value'] } },
  properties: { Box: { $ref: '#/$defs/Box' } },
};
const plain = value => JSON.parse(JSON.stringify(value));
function runtime() {
  const realm = vm.createContext({ setInterval, clearInterval,
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8') });
  vm.runInContext(script, realm, { timeout: 5_000 });
  const bridge = realm.SwiftCore, core = bridge.api;
  function merge(existing, patch, rootId = 'root') {
    realm.mergeArguments = [existing, patch, rootId];
    // A regression must return the SDK's explicit failure. The deadline is
    // only a harness safety net and can never satisfy the failure assertion.
    return vm.runInContext('SwiftCore.merge(...mergeArguments)', realm, { timeout: 2_000 });
  }
  return { core, bridge, merge };
}
function rejected(outcome) {
  assert.equal(outcome.limitExceeded, true);
  assert.equal(outcome.value, null, 'No partially merged source can escape a failed operation');
  assert(outcome.work <= 100_001);
}

test('raw merge input limits reject before trimming or starting the core algorithm', () => {
  const { merge } = runtime();
  const oversized = ' '.repeat(maximumSource + 1);
  for (const args of [
    ['root=Box("before")', ' '.repeat(2 * maximumSource) + 'root=Box("after")'],
    ['root=Box("before")', oversized + 'root=Box("after")'],
    [oversized + 'root=Box("before")', 'root=Box("after")'],
    ['root=Box("before")', 'root=Box("after")', oversized],
    ['root=Box("before")', '😀'.repeat(maximumSource / 2 + 1)],
  ]) {
    const outcome = merge(...args);
    rejected(outcome);
    assert.equal(outcome.work, 0, 'Raw input is refused before token/merge work');
  }
  assert.equal(merge('root=Box("before")', 'root=Box("recovered")').value, 'root=Box("recovered")');
});

test('an exact-limit input and independent valid inputs still permit replacement', () => {
  const { merge } = runtime();
  const patch = 'root=Box("after")';
  const padded = ' '.repeat(maximumSource - patch.length) + patch;
  assert.equal(padded.length, maximumSource);
  const boundary = merge('root=Box("before")', padded);
  assert.equal(boundary.limitExceeded, false);
  assert.equal(boundary.value, patch);
  const existing = 'root=Box("' + 'a'.repeat(600_000) + '")';
  const replacement = 'root=Box("' + 'b'.repeat(600_000) + '")';
  assert(existing.length + replacement.length > maximumSource);
  const outcome = merge(existing, replacement);
  assert.equal(outcome.limitExceeded, false);
  assert.equal(outcome.value, replacement);
  assert(outcome.work >= Math.ceil((existing.length + replacement.length + 4) / 64));
});

test('both inputs, repeated deletes and GC share one work allowance', () => {
  const { merge } = runtime();
  const declarations = Array.from({ length: 1_000 }, (_, i) => `$v${i}=0`);
  const deletions = Array.from({ length: 1_000 }, (_, i) => `$v${i}=null`);
  const existing = ['root=Box("before")', ...declarations].join('\n');
  const patch = ['root=Box("after")', ...deletions].join('\n');
  assert.equal(merge('', existing).limitExceeded, false, 'Each source separately fits the allowance');
  assert.equal(merge('', patch).limitExceeded, false);
  rejected(merge(existing, patch));
  assert.equal(merge('root=Box("before")', 'root=Box("recovered")').value, 'root=Box("recovered")');
});

test('token allocation, expression recursion and recursive AST walking stop within the budget', () => {
  const { merge } = runtime();
  for (const patch of [
    'root=[' + '1,'.repeat(80_000) + '1]',
    'root=Box(' + '('.repeat(5_000) + '1' + ')'.repeat(5_000) + ')',
    'root=Box(' + Array.from({ length: 1_500 }, () => '1').join('+') + ')',
  ]) {
    assert(patch.length < maximumSource);
    rejected(merge('root=Box("before")', patch));
  }
  assert.equal(merge('root=Box("before")', 'root=Box("recovered")').limitExceeded, false);
});

test('merged source must fit the output limit even when both raw inputs fit', () => {
  const { merge } = runtime();
  const existing = '$a="' + 'a'.repeat(600_000) + '"\nroot=Box($a)';
  const patch = '$b="' + 'b'.repeat(600_000) + '"';
  assert(existing.length < maximumSource && patch.length < maximumSource);
  rejected(merge(existing, patch));
});

test('valid merging keeps custom roots, multiline ternaries, fences and duplicate-ID semantics', () => {
  const { merge } = runtime();
  assert.equal(merge('unused=1\nvalue="old"\nscreen=Box(value)', 'value="new"', 'screen').value,
    'value="new"\nscreen=Box(value)');
  const conditional = 'root=$show\n\n ? Box("🧭")\n\n : Box("返回")';
  const outcome = merge('$show=true\n' + conditional, '```openui-lang\n$show=false\n```');
  assert.equal(outcome.limitExceeded, false);
  assert.equal(outcome.value, '$show=false\n' + conditional);
  assert.equal(merge('root=Box(item)\nitem="old"\nitem="new"', 'item="patched"').value,
    'root=Box(item)\nitem="patched"');
});

test('a ternary newline run has a linear token-read bound', () => {
  const { core } = runtime();
  for (const count of [250, 500, 1_000, 2_000, 5_000]) {
    const tokens = core.tokenize('root=1' + '\n'.repeat(count) + '?2:3');
    let reads = 0;
    const observed = new Proxy(tokens, { get(target, key, receiver) {
      if (typeof key === 'string' && /^(0|[1-9][0-9]*)$/.test(key)) reads++;
      return Reflect.get(target, key, receiver);
    } });
    const statements = core.split(observed);
    assert.equal(statements.length, 1);
    assert.equal(statements[0].id, 'root');
    assert.deepEqual(plain(core.parseExpression(statements[0].tokens)), {
      k: 'Ternary', cond: { k: 'Num', v: 1 }, then: { k: 'Num', v: 2 }, else: { k: 'Num', v: 3 },
    });
    assert(reads < tokens.length * 12, `${count} newlines caused ${reads} indexed token reads`);
  }
});

test('newline lookahead preserves ordinary statement boundaries and streamed ternary prefixes', () => {
  const { core } = runtime();
  for (const source of ['root=1\n\n\nnext=2', 'root=1\n// comment\n# comment\nnext=2']) {
    const statements = core.split(core.tokenize(source));
    assert.deepEqual(plain(statements.map(statement => ({ id: statement.id,
      ast: core.parseExpression(statement.tokens) }))), [
      { id: 'root', ast: { k: 'Num', v: 1 } }, { id: 'next', ast: { k: 'Num', v: 2 } },
    ]);
  }
  const source = '$show=true\nroot=$show' + '\n'.repeat(7)
    + '? Box("yes")' + '\n'.repeat(5) + ': Box("no")\nnext=4';
  for (const width of [1, 7, 31]) {
    const stream = core.createStreamingParser(schema);
    let prefix = '';
    for (let offset = 0; offset < source.length; offset += width) {
      const chunk = source.slice(offset, offset + width);
      prefix += chunk;
      assert.deepEqual(plain(stream.push(chunk)), plain(core.createStreamingParser(schema).set(prefix)),
        `width ${width}, prefix ${JSON.stringify(prefix)}`);
    }
    assert.deepEqual(plain(stream.getResult(true)), plain(core.createStreamingParser(schema).set(source, true)));
  }
});

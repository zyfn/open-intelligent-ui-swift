import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const realm = vm.createContext({
  __utf8Encode: value => [...Buffer.from(value)],
  __utf8Decode: value => Buffer.from(value).toString('utf8'),
  setInterval, clearInterval,
});
vm.runInContext(readFileSync(process.env.OPENUI_NATIVE_CORE_JS ??
  new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8'), realm, { timeout: 5000 });
const bridge = realm.SwiftCore;
const textResult = text => ({ content: [{ type: 'text', text }] });
const plain = value => JSON.parse(JSON.stringify(value));
const expectLimit = outcome => {
  assert.equal(outcome.limitExceeded, true);
  assert.deepEqual(Object.keys(outcome), ['limitExceeded']);
};

test('MCP text preserves a scalar at the native maximum depth', () => {
  const source = '['.repeat(256) + '42' + ']'.repeat(256);
  const outcome = bridge.extract(textResult(source));
  assert.equal(outcome.limitExceeded, undefined);
  let value = outcome.value;
  for (let level = 0; level < 256; level++) {
    assert.equal(Array.isArray(value), true);
    assert.equal(value.length, 1);
    value = value[0];
  }
  assert.equal(value, 42);
});

test('MCP text cannot expand into a graph beyond the native depth limit', () => {
  const source = '['.repeat(257) + '0' + ']'.repeat(257);
  expectLimit(bridge.extract(textResult(source)));
});

test('MCP text cannot expand into a graph beyond the native node limit', () => {
  const source = '[' + Array(100_000).fill('0').join(',') + ']';
  expectLimit(bridge.extract(textResult(source)));
});

test('MCP structured output is checked before native projection', () => {
  expectLimit(bridge.extract({ structuredContent: Array(100_000).fill(0) }));
});

test('MCP ordinary extraction and error semantics match the fixed upstream API', () => {
  for (const input of [
    { structuredContent: 0, ...textResult('ignored') },
    { structuredContent: false },
    { structuredContent: { text: '\ud800', rows: [1, 2, 3] } },
    { content: [{ type: 'text', text: '{"a":' }, { type: 'text', text: '1}' }] },
    textResult('plain text'),
  ]) {
    assert.deepEqual(plain(bridge.extract(input)), { value: plain(bridge.api.extractToolResult(input)) });
  }
  assert.deepEqual(plain(bridge.extract({ isError: true, ...textResult('provider failed') })),
    { error: 'provider failed' });
});

test('MCP rejected extraction does not poison the next bounded result', () => {
  assert.equal(bridge.extract(textResult('['.repeat(257) + '0' + ']'.repeat(257))).limitExceeded, true);
  assert.deepEqual(plain(bridge.extract({ structuredContent: { recovered: true } })),
    { value: { recovered: true } });
});

test('malformed MCP envelopes report extraction errors without escaping the bridge', () => {
  for (const input of [null, { content: 7 }]) {
    assert.throws(() => bridge.api.extractToolResult(input), { name: 'TypeError' });
    const outcome = bridge.extract(input);
    assert.deepEqual(Object.keys(outcome), ['error']);
    assert.match(outcome.error, /^Tool result extraction failed: /);
  }
  assert.deepEqual(plain(bridge.extract({ structuredContent: 42 })), { value: 42 });
});

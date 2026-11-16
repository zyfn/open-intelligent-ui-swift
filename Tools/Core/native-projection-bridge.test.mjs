import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: { Box: { type: 'object', properties: { value: {} }, required: ['value'] } },
  properties: { Box: { $ref: '#/$defs/Box' } },
};
function runtime() {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const bridge = realm.SwiftCore;
  return { bridge, library: bridge.library(schema, {}) };
}
function fields(bridge, value) {
  const flat = bridge.entries(value);
  assert.equal(flat.length % 2, 0);
  return Array.from({ length: flat.length / 2 }, (_, index) => [flat[index * 2], flat[index * 2 + 1]]);
}

test('ordered bridge entries preserve UTF-16, undefined, prototypes and reference identity', () => {
  const { bridge } = runtime();
  const shared = { preserved: true };
  const value = Object.create({ inherited: 'not an own property' });
  Object.defineProperty(value, 'hidden', { value: 'not enumerable' });
  Object.assign(value, { z: shared, 10: 'ten', 2: 'two', absent: undefined });
  Object.defineProperty(value, '__proto__', { value: shared, enumerable: true });
  value['\ud800'] = '\udc00';
  value['e\u0301'] = 'decomposed';
  value['é'] = 'composed';
  const projected = fields(bridge, value);
  assert.deepEqual(projected.map(([key]) => key),
    ['2', '10', 'z', 'absent', '__proto__', '\ud800', 'e\u0301', 'é']);
  assert.strictEqual(projected[2][1], shared);
  assert.strictEqual(projected[3][1], undefined);
  assert.strictEqual(projected[4][1], shared);
  assert.equal(projected[5][0].charCodeAt(0), 0xd800);
  assert.equal(projected[5][1].charCodeAt(0), 0xdc00);
});

test('entry batching captures the full key list before any value getter runs', () => {
  const { bridge } = runtime();
  const order = [];
  const value = {};
  Object.defineProperty(value, 'first', { enumerable: true, get() {
    order.push('first');
    Object.defineProperty(value, 'second', { enumerable: false });
    value.late = 3;
    return 1;
  } });
  Object.defineProperty(value, 'second', { configurable: true, enumerable: true,
    get() { order.push('second'); return 2; } });
  assert.deepEqual(fields(bridge, value), [['first', 1], ['second', 2]]);
  assert.deepEqual(order, ['first', 'second']);
});

test('projection batching keeps direct and pending Each occurrences separate without copying Lang values', () => {
  const { bridge, library } = runtime();
  const child = bridge.tagNativeSource({ type: 'element', typeName: 'Box',
    props: { value: 'kept' }, hasDynamicProps: false }, true);
  const shared = [child];
  const context = { getState: name => name === '$shared' ? shared : [1], resolveRef: () => null };
  const parser = bridge.api.createParser(schema);
  const parsed = parser.parse('root=Box([$shared,@Each($items,item,$shared)])\n$items=[1');
  const outcome = bridge.boundedRoot(parsed, context, library, null, []);
  assert.equal(outcome.limitExceeded, false);
  const [direct, each] = outcome.value.props.value;
  const directScope = bridge.projectionMetadata(direct, outcome.sourceSnapshot)[1];
  const eachScope = bridge.projectionMetadata(each, outcome.sourceSnapshot)[1];
  const pendingArray = each[0];
  const pendingScope = bridge.projectionMetadata(pendingArray, eachScope)[1];
  const directChild = direct[0], pendingChild = pendingArray[0];
  assert.strictEqual(directChild, child);
  assert.strictEqual(pendingChild, child);
  assert.equal(bridge.identity(directChild), bridge.identity(pendingChild));
  assert.equal(bridge.sourceStatus(directChild, directScope)[0], true);
  assert.equal(bridge.sourceStatus(pendingChild, pendingScope)[0], false);
  assert.equal(bridge.sourceStatus(pendingChild, pendingScope)[1].complete, false);
  assert.equal(bridge.sourceStatus(child)[0], true, 'the native baseline remains complete');

  const finished = bridge.boundedRoot(parser.parse('root=Box(@Each([1],item,$shared))'), context, library, null, []);
  const finishedScope = bridge.projectionMetadata(finished.value.props.value, finished.sourceSnapshot)[1];
  assert.equal(bridge.sourceStatus(child, finishedScope)[0], true);
  assert.equal(bridge.sourceStatus(child, pendingScope)[0], false, 'later evaluation keeps the old occurrence snapshot');
});

test('projection batching preserves ordinary-data tags and keeps helper metadata out of values', () => {
  const { bridge } = runtime();
  const data = { type: 'element', typeName: 'Box', props: { value: 'ordinary' } };
  bridge.tag(data, 'object');
  const before = JSON.stringify(data);
  const identity = bridge.identity(data);
  const first = bridge.projectionMetadata(data);
  assert.equal(first[0], 'object');
  assert.strictEqual(first[1], undefined);
  assert.equal(identity, bridge.identity(data));
  assert.equal(JSON.stringify(data), before);
});

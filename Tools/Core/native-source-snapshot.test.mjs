// Source readiness is native metadata. Shared Lang values keep their ordinary
// identity while different evaluations retain independent immutable snapshots.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: {
    Box: { type: 'object', properties: { value: {} }, required: ['value'] },
    Button: { type: 'object', properties: { label: {}, action: {} }, required: ['label'] },
  },
  properties: Object.fromEntries(['Box', 'Button'].map(name => [name, { $ref: '#/$defs/' + name }])),
  functions: { Reenter: { params: { type: 'object', properties: {} } } },
};
function runtime() {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const bridge = realm.SwiftCore;
  const library = bridge.library(schema, {});
  const plan = bridge.tagNativeSource(bridge.nativePlan({ steps: [{ type: 'reset', targets: ['$x'] }] }), true);
  const child = bridge.tagNativeSource({ type: 'element', typeName: 'Button',
    props: { label: 'Go', action: plan }, partial: false }, true, { complete: true, closed: true });
  const nested = Object.freeze([child]);
  const shared = Object.freeze([child, nested, Object.freeze({ child })]);
  const parse = source => bridge.api.createParser(schema).parse(source);
  const render = (source, extra = {}) => {
    const parsed = parse(source);
    assert.deepEqual(Array.from(parsed.meta.errors), []);
    return bridge.boundedRoot(parsed, {
      getState: name => name === '$shared' ? shared : name === '$items' ? [1, 2] : null,
      resolveRef: () => [1, 2], ...extra,
    }, library, null, []);
  };
  return { bridge, plan, child, nested, shared, parse, render };
}

test('incomplete shared descendants stay scoped and recover in another document', () => {
  const { bridge, plan, child, nested, shared, render } = runtime();
  const pending = render('root=Box(@Each([1,2],item,$shared');
  const pendingScope = bridge.sourceChildSnapshot(pending.value.props.value, pending.sourceSnapshot);
  assert.equal(pending.limitExceeded, false);
  assert.equal(pending.value.props.value[0], shared);
  assert.equal(pending.value.props.value[1], shared, 'metadata must not clone Lang values');
  for (const value of [shared, nested, child, plan]) {
    assert.equal(bridge.sourceComplete(value, pendingScope), false);
    assert.equal(bridge.sourceComplete(value, pending.sourceSnapshot), true, 'the root scope cannot poison another occurrence');
    assert.equal(bridge.sourceComplete(value), true, 'native baseline remains intact');
  }
  const complete = render('root=Box(@Each([1,2],item,$shared))');
  const otherDocument = render('root=Box($shared)');
  for (const value of [shared, nested, child, plan]) {
    assert.equal(bridge.sourceComplete(value, complete.sourceSnapshot), true);
    assert.equal(bridge.sourceComplete(value, otherDocument.sourceSnapshot), true);
    assert.equal(bridge.sourceComplete(value, pendingScope), false, 'old projection is immutable');
  }
});

test('query dependency inheritance does not escape its evaluation', () => {
  const { bridge, child, shared, render } = runtime();
  const first = render('root=Box(@Each(q,item,$shared))\nq=Query("load",{},[])');
  const firstScope = bridge.sourceChildSnapshot(first.value.props.value, first.sourceSnapshot);
  assert.equal(first.limitExceeded, false);
  assert.deepEqual(Array.from(bridge.sourcePresentation(child, firstScope).queries), ['q']);
  assert.equal(bridge.sourcePresentation(child, first.sourceSnapshot).queries, undefined);
  assert.equal(bridge.sourcePresentation(child).queries, undefined);
  const other = render('root=Box($shared)');
  // The official property evaluator maps the immediate array. Its nested
  // reference is still shared and must not inherit another document's metadata.
  assert.equal(other.value.props.value[1], shared[1]);
  assert.equal(bridge.sourcePresentation(child, other.sourceSnapshot).queries, undefined);
  assert.deepEqual(Array.from(bridge.sourcePresentation(child, firstScope).queries), ['q']);
});

test('synchronous nested evaluation restores its caller scope and parser metadata', () => {
  const { bridge, child, shared, parse, render } = runtime();
  let inner, parsedInsideCallback, outerBefore, outerAfter;
  const outer = render('root=Box([@Each($items,item,$shared),@Reenter()])\n$items=[1', {
    functions: { Reenter: { params: { type: 'object', properties: {} }, fn() {
      outerBefore = bridge.currentSourceSnapshot();
      inner = render('root=Box($shared)');
      outerAfter = bridge.currentSourceSnapshot();
      parsedInsideCallback = parse('root=alias\nalias=box\nbox=Box("ready")');
      return null;
    } } },
  });
  assert.equal(outer.limitExceeded, false);
  assert(inner, 'native callback must actually reenter evaluation');
  assert.equal(outerBefore, outer.sourceSnapshot);
  assert.equal(outerAfter, outer.sourceSnapshot, 'nested evaluation restores the active caller');
  assert.notEqual(inner.sourceSnapshot, outer.sourceSnapshot);
  assert.equal(bridge.currentSourceSnapshot(), undefined, 'a completed bridge call cannot retain the active scope');
  assert.equal(inner.value.props.value[1], shared[1]);
  assert.equal(bridge.sourceComplete(child, inner.sourceSnapshot), true);
  const outerScope = bridge.sourceChildSnapshot(outer.value.props.value[0], outer.sourceSnapshot);
  assert.equal(bridge.sourceComplete(child, outerScope), false);
  assert.equal(bridge.sourceComplete(child, outer.sourceSnapshot), true);
  assert.equal(bridge.sourceComplete(child), true);
  assert.equal(bridge.sourceComplete(parsedInsideCallback.root), true, 'nested parsing writes its own base metadata');
});

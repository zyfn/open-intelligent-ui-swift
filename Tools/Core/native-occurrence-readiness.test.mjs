// Exercise the published bundle and its real output paths. Native inputs are
// deliberately shared/frozen; a presentation fix must not clone Lang values.
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
  functions: { Shared: { params: { type: 'object', properties: {} } } },
};

function fixture() {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const bridge = realm.SwiftCore, library = bridge.library(schema, {});
  const captured = Object.freeze({ record: Object.freeze({ id: 'kept' }) });
  const plan = bridge.tagNativeSource(bridge.nativePlan({
    steps: [{ type: 'continue_conversation', message: 'Go', context: captured }],
  }), true);
  const child = bridge.tagNativeSource({ type: 'element', typeName: 'Button',
    props: { label: 'Go', action: plan }, partial: false }, true, { complete: true, closed: true });
  const nested = Object.freeze([child]);
  const shared = Object.freeze([child, nested, Object.freeze({ child })]);
  const render = source => {
    const parsed = bridge.api.createParser(schema).parse(source);
    assert.deepEqual(Array.from(parsed.meta.errors), []);
    const result = bridge.boundedRoot(parsed, {
      getState: name => name === '$shared' ? shared : name === '$items' ? [1, 2] : null,
      resolveRef: () => [1, 2],
      functions: { Shared: { params: { type: 'object', properties: {} }, fn: () => shared } },
    }, library, null, []);
    assert.equal(result.limitExceeded, false);
    return result;
  };
  function buttons(value, context, result = []) {
    if (!value || typeof value !== 'object') return result;
    const children = bridge.sourceChildSnapshot(value, context);
    if (Array.isArray(value)) value.forEach(item => buttons(item, children, result));
    else if (value.type === 'element') {
      if (value.typeName === 'Button') result.push({ value, context,
        complete: bridge.sourceComplete(value, context),
        actionComplete: bridge.sourceComplete(value.props.action, children),
        queries: Array.from(bridge.sourcePresentation(value, context).queries ?? []),
      });
      Object.values(value.props).forEach(item => buttons(item, children, result));
    } else Object.values(value).forEach(item => buttons(item, children, result));
    return result;
  }
  return { bridge, child, plan, captured, nested, shared, render, buttons };
}

for (const template of ['$shared', '@Shared()']) {
  for (const directFirst of [true, false]) {
    test(`shared ${template} keeps sibling and Each occurrence readiness independent (${directFirst})`, () => {
      const { bridge, child, plan, captured, nested, shared, render, buttons } = fixture();
      const each = `@Each($items,item,${template})`;
      const source = `root=Box([${directFirst ? [template, each] : [each, template]}])\n$items=[1`;
      const pending = render(source);
      const values = pending.value.props.value;
      const direct = values[directFirst ? 0 : 1], loop = values[directFirst ? 1 : 0];
      assert.equal(direct[1], nested, 'the direct nested Lang array remains shared');
      for (const value of loop) assert.equal(value, shared, 'Each keeps the original Lang array');
      assert.equal(loop[0][1][0], child);
      assert.equal(loop[0][0].props.action, plan);
      for (const item of buttons(direct, pending.sourceSnapshot)) {
        assert.equal(item.complete, true);
        assert.equal(item.actionComplete, true);
      }
      const pendingButtons = buttons(loop, pending.sourceSnapshot);
      assert(pendingButtons.length > 0);
      for (const item of pendingButtons) {
        assert.equal(item.complete, false);
        assert.equal(item.actionComplete, false);
        assert.equal(item.value.props.action.steps[0].context, captured,
          'presentation cannot rewrite opaque action data');
      }
      const scope = bridge.sourceChildSnapshot(loop, pending.sourceSnapshot);
      assert.equal(bridge.sourceChildSnapshot(shared, scope), scope, 'repeated graph edges reuse one scope');
      assert.equal(bridge.sourceChildSnapshot(loop, pending.sourceSnapshot), scope, 'scope lookup is stable');
      const complete = render(source + ']\n');
      for (const item of buttons(complete.value, complete.sourceSnapshot)) {
        assert.equal(item.complete, true);
        assert.equal(item.actionComplete, true);
      }
      for (const item of pendingButtons) assert.equal(bridge.sourceComplete(item.value, item.context), false,
        'another evaluation cannot rewrite an earlier occurrence scope');
      assert.equal(bridge.sourceComplete(child), true);
      assert.equal(bridge.sourceComplete(plan), true);
    });
  }
}

test('two query-backed Each occurrences do not share dependencies with each other or a direct sibling', () => {
  const { render, buttons } = fixture();
  const result = render('root=Box([$shared,@Each(q,item,$shared),@Each(r,item,$shared)])\nq=Query("q",{},[])\nr=Query("r",{},[])');
  const [direct, first, second] = result.value.props.value;
  for (const item of buttons(direct, result.sourceSnapshot)) assert.deepEqual(item.queries, []);
  for (const item of buttons(first, result.sourceSnapshot)) assert.deepEqual(item.queries, ['q']);
  for (const item of buttons(second, result.sourceSnapshot)) assert.deepEqual(item.queries, ['r']);
});

test('pure Lang Button and Action aliases keep independent evaluated occurrences', () => {
  const { render, buttons } = fixture();
  const result = render('root=Box([shared,@Each(items,item,shared)])\nshared=Button("Go",action)\naction=Action([@OpenUrl("https://example.com")])\nitems=[1');
  const [direct, loop] = result.value.props.value;
  const [ready] = buttons(direct, result.sourceSnapshot), [pending] = buttons(loop, result.sourceSnapshot);
  assert.equal(ready.complete, true); assert.equal(ready.actionComplete, true);
  assert.equal(pending.complete, false); assert.equal(pending.actionComplete, false);
  assert.notEqual(ready.value, pending.value, 'ordinary Lang aliases do not inject a shared native object');
});

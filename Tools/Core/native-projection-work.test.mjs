// Count the actual metadata identities crossing the shipped-core boundary.
// This is a work/allocation regression, not an Apple timing or FPS measurement.
import assert from 'node:assert/strict';
import test from 'node:test';
import { createNativeRuntime } from './native-test-runtime.mjs';
import vm from 'node:vm';

const schema = {
  $defs: {
    Text: { type: 'object', properties: { value: { type: 'string' } }, required: ['value'] },
    Stack: { type: 'object', properties: { children: {} }, required: ['children'] },
    Image: { type: 'object', properties: { alt: { type: 'string' }, src: { type: 'string' } }, required: ['alt', 'src'] },
    Box: { type: 'object', properties: { value: {} }, required: ['value'] },
  },
  properties: Object.fromEntries(['Text', 'Stack', 'Image', 'Box'].map(name => [name, { $ref: '#/$defs/' + name }])),
};
const plain = value => JSON.parse(JSON.stringify(value));
function runtime() {
  const realm = createNativeRuntime();
  const bridge = realm.SwiftCore;
  return { bridge, library: bridge.library(schema, {}), realm };
}

test('a changing tail does not rescan settled literal descendants for query dependencies', () => {
  const { bridge, realm } = runtime();
  const names = Array.from({ length: 200 }, (_, i) => 'row' + i);
  const parser = bridge.api.createStreamingParser(schema);
  let previous = parser.push(['root=Stack([' + [...names, 'tail'].join(',') + '])',
    ...names.map((name, i) => `${name}=Box({title:"settled literal ${i}",items:[1,2,3]})`),
    'tail=Text("'].join('\n'));
  // Count actual AST-child enumeration after the declarations have settled.
  // This observes traversal work without depending on WeakMap internals or a
  // machine-specific timing threshold.
  vm.runInContext(`
    globalThis.settledLiteralVisits = 0;
    const originalValues = Object.values;
    Object.values = value => {
      if (value?.k === 'Str' && value.v.startsWith('settled literal ')) settledLiteralVisits++;
      return originalValues(value);
    };
  `, realm);
  for (const chunk of ['streaming ', 'text ', 'continues', '")']) {
    realm.settledLiteralVisits = 0;
    const result = parser.push(chunk);
    assert.equal(bridge.nativeBudgetExceeded(result), false);
    assert.equal(result.meta.errors.length, 0);
    assert.equal(realm.settledLiteralVisits, 0, 'settled literal syntax has no query dependencies to rediscover');
    assert.equal(result.root.props.children.length, 201);
    const before = previous.root.props.children[0], after = result.root.props.children[0];
    assert.notEqual(after, before, 'materialization still creates fresh elements');
    assert.notEqual(after.props.value, before.props.value, 'materialization still creates fresh literal containers');
    assert.deepEqual(plain(after.props.value), { title: 'settled literal 0', items: [1, 2, 3] });
    previous = result;
  }
  assert.equal(previous.root.props.children.at(-1).props.value, 'streaming text continues');
});

for (const width of [24, 128]) {
  test(`201 stable declarations share settled metadata through ${width}-unit chunks`, () => {
    const { bridge, library } = runtime();
    const [closed, open] = bridge.sourcePresentationDefaults();
    assert(Object.isFrozen(closed));
    assert(Object.isFrozen(open));
    assert.deepEqual(plain(closed), { complete: true, closed: true });
    assert.deepEqual(plain(open), { complete: false, closed: false });
    const names = Array.from({ length: 200 }, (_, i) => 'row' + i);
    const source = ['root=Stack([' + [...names, 'tail'].join(',') + '])',
      ...names.map((name, i) => `${name}=Text("stable row ${i}")`),
      'tail=Text("' + 'streaming text '.repeat(128) + '")'].join('\n');
    const parser = bridge.api.createStreamingParser(schema);
    let settledLeaves = 0, last;
    const identities = new Set();
    for (let offset = 0; offset < source.length; offset += width) {
      const parsed = parser.push(source.slice(offset, offset + width));
      assert.equal(bridge.nativeBudgetExceeded(parsed), false);
      last = bridge.boundedRoot(parsed, { getState: () => null, resolveRef: () => null }, library, null, []);
      assert.equal(last.limitExceeded, false);
      for (const child of last.value?.props.children ?? []) {
        const details = bridge.sourcePresentation(child, last.sourceSnapshot);
        if (!details.complete || Object.keys(details).length !== 2) continue;
        settledLeaves++;
        identities.add(details);
        assert.equal(details, closed, 'a settled sibling must not allocate another equivalent description');
      }
    }
    assert(settledLeaves > 1000, 'exercise repeated siblings across a changing source, not a repeated final snapshot');
    assert.equal(identities.size, 1);
    assert.equal(last.value.props.children.length, 201);
    assert.equal(last.value.props.children.at(-1).props.value, 'streaming text '.repeat(128));
  });
}

test('complete query dependencies are not folded into the plain closed description', () => {
  const { bridge, library } = runtime();
  const [closed] = bridge.sourcePresentationDefaults();
  const parsed = bridge.api.createParser(schema).parse('root=Box(q)\nq=Query("load",{},1)');
  const before = bridge.sourcePresentation(parsed.root);
  assert.equal(before.complete, true);
  assert.notEqual(before, closed);
  assert.deepEqual(Array.from(before.queries), ['q']);
  const outcome = bridge.boundedRoot(parsed, { getState: () => null, resolveRef: () => 7 }, library, null, []);
  assert.equal(outcome.limitExceeded, false);
  const details = bridge.sourcePresentation(outcome.value, outcome.sourceSnapshot);
  assert.notEqual(details, closed);
  assert.equal(details.complete, true);
  assert.deepEqual(Array.from(details.queries), ['q']);
  assert.equal(details.observed, true);
  assert.equal(outcome.value.props.value, 7);
  assert.deepEqual(plain(closed), { complete: true, closed: true }, 'query attachment never mutates the shared default');
});

test('missing-image slots and separate library validation keep their detailed metadata', () => {
  const { bridge } = runtime();
  const [closed, open] = bridge.sourcePresentationDefaults();
  const parsed = bridge.api.createStreamingParser(schema).set('root=Stack([Text("ready"),Image("alt"');
  const details = bridge.sourcePresentation(parsed.root);
  assert.notEqual(details, closed);
  assert.notEqual(details, open);
  const children = details.children.children;
  assert.deepEqual(Array.from(children.slots), [0, null]);
  assert.equal(children.pending['1'].placeholder.name, 'Image');
  assert.equal(children.children['0'], closed);

  const strict = structuredClone(schema);
  strict.$defs.Text.properties.value.type = 'number';
  const invalid = bridge.api.createParser(strict).parse('root=Text("ready")');
  assert.equal(invalid.root, null);
  assert(invalid.meta.errors.some(error => error.code === 'type-mismatch'));
  const valid = bridge.api.createParser(schema).parse('root=Text("ready")');
  assert.equal(valid.root.props.value, 'ready');
  assert.equal(bridge.sourcePresentation(valid.root), closed);
});

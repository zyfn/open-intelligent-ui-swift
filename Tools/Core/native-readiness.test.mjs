// Exercise the shipped native bridge where Lang 1.1 memoizes and copies
// statement aliases. Readiness is host metadata, separate from protocol data.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createNativeRuntime } from './native-test-runtime.mjs';

const schema = {
  $defs: {
    Box: { type: 'object', properties: { value: {} }, required: ['value'] },
    Stack: { type: 'object', properties: { children: {} }, required: ['children'] },
    Button: { type: 'object', properties: { label: { type: 'string' }, action: {} }, required: ['label'] },
  },
  properties: Object.fromEntries(['Box', 'Stack', 'Button'].map(name => [name, { $ref: '#/$defs/' + name }])),
};

function runtime() {
  const realm = createNativeRuntime();
  const core = realm.SwiftCore;
  return { core, parser: core.api.createStreamingParser(schema) };
}

test('a final component becomes ready when its own delimiter arrives before stream completion', () => {
  const { core, parser } = runtime();
  const pending = parser.push('root=Box("stable').root;
  assert.equal(core.sourceComplete(pending), false);
  const result = parser.push('")');
  assert.equal(result.meta.incomplete, false);
  assert.equal(result.root.props.value, 'stable');
  assert.equal(core.sourceComplete(result.root), true);
  assert.equal(core.sourcePresentation(result.root).closed, true);
  assert.equal(core.sourceComplete(pending), false, 'the earlier preview remains immutable');
});

test('a pending final statement retains its unfinished token and nested action gates', () => {
  for (const input of ['root=Box("text', 'root=Box(1', 'root=Box(true', 'root=Box([1,2',
    'root=Button("Go",@OpenUrl("https://example.test/path']) {
    const { core, parser } = runtime();
    const result = parser.push(input);
    assert.equal(core.sourceComplete(result.root), false, input);
  }
  const { core, parser } = runtime();
  const pending = parser.push('root=Button("Go",@OpenUrl("https://example.test/path').root;
  const result = parser.push('"))');
  assert.equal(core.sourceComplete(result.root), true);
  assert.equal(core.sourcePresentation(result.root).closed, true);
  assert.equal(core.sourceComplete(pending), false);
});

test('a final closed chart data declaration is ready and survives an open replacement', () => {
  const catalog = JSON.parse(readFileSync(new URL('../../Sources/SwiftOpenUI/Resources/upstream-catalog.json', import.meta.url), 'utf8'));
  const definition = catalog.components.find(component => component.name === 'PieChart');
  const chartSchema = {
    $defs: { PieChart: { type: 'object',
      properties: Object.fromEntries(definition.params.map(parameter => [parameter.name, parameter.schema])),
      required: definition.params.filter(parameter => parameter.required).map(parameter => parameter.name),
    } },
    properties: { PieChart: { $ref: '#/$defs/PieChart' } },
  };
  const { core } = runtime();
  const parser = core.api.createStreamingParser(chartSchema), library = core.library(chartSchema, {});
  const context = { getState: () => undefined, resolveRef: () => undefined };
  for (const [chunk, expected] of [
    ['root=PieChart(["A","B"],values)\nvalues=[1,3]\n', [1, 3]],
    ['values=[3', [1, 3]],
    [',1]\n', [3, 1]],
  ]) {
    const result = parser.push(chunk), errors = [];
    const evaluated = core.boundedRoot(result, context, library, null, errors);
    assert.equal(evaluated.limitExceeded, false);
    assert.deepEqual(errors, []);
    assert.deepEqual(Array.from(evaluated.value.props.values), expected);
    assert.equal(core.sourceComplete(evaluated.value, evaluated.sourceSnapshot), true, chunk);
    assert.equal(core.sourcePresentation(evaluated.value, evaluated.sourceSnapshot).complete, true, chunk);
  }
});

test('a closed aliased root remains ready while an unrelated statement streams', () => {
  const { core, parser } = runtime();
  parser.push('root=alias\nalias=card\ncard=Box("ready")\nother=Box("tail');
  const result = parser.getResult();
  assert.equal(result.root.statementId, 'root');
  assert.equal(result.root.partial, true, 'the upstream partial flag describes the whole parse');
  assert.equal(core.sourceComplete(result.root), true, 'native readiness follows this root\'s own source');
  assert.equal(core.sourcePresentation(result.root).closed, true);
});

test('an alias preserves per-property readiness of a partially streamed action', () => {
  const { core, parser } = runtime();
  parser.push('root=alias\nalias=button\nbutton=Button("Go",@OpenUrl("https://example.test/pa');
  const first = parser.getResult().root;
  const pending = core.sourcePresentation(first);
  assert.equal(pending.children.label.complete, true);
  assert.equal(pending.children.action.complete, false);
  assert.equal(core.sourceComplete(first), false);
  parser.push('th"))');
  const completed = parser.push('', true);
  assert.equal(core.sourceComplete(completed.root), true);
  assert.equal(core.sourceComplete(first), false, 'a later chunk must not rewrite an earlier snapshot');
});

test('memoized sibling aliases keep separate statement identities and readiness', () => {
  const { core, parser } = runtime();
  parser.push('root=Stack([first,second])\nfirst=shared\nsecond=shared\nshared=Box("ready")\nother=Box("tail');
  const [first, second] = parser.getResult().root.props.children;
  assert.notEqual(first, second);
  assert.equal(first.statementId, 'first');
  assert.equal(second.statementId, 'second');
  assert.equal(core.sourceComplete(first), true);
  assert.equal(core.sourceComplete(second), true);
});

test('query dependencies survive statement alias copies without entering wire data', () => {
  const { core, parser } = runtime();
  const root = parser.push('root=alias\nalias=card\ncard=Box(q)\nq=Query("load",{},[])', true).root;
  assert.deepEqual(Array.from(core.sourcePresentation(root).queries), ['q']);
  assert.equal(root.props.value.refType, 'query');
  assert.equal(root.props.value.n, 'q');
  assert.equal(JSON.stringify(root).includes('native.'), false);
});

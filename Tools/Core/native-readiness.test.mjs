// Exercise the shipped native bridge where Lang 1.1 memoizes and copies
// statement aliases. Readiness is host metadata, separate from protocol data.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(new URL('../../Sources/OpenUILang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: {
    Box: { type: 'object', properties: { value: {} }, required: ['value'] },
    Stack: { type: 'object', properties: { children: {} }, required: ['children'] },
    Button: { type: 'object', properties: { label: { type: 'string' }, action: {} }, required: ['label'] },
  },
  properties: Object.fromEntries(['Box', 'Stack', 'Button'].map(name => [name, { $ref: '#/$defs/' + name }])),
};

function runtime() {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const core = realm.SwiftCore;
  return { core, parser: core.api.createStreamingParser(schema) };
}

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

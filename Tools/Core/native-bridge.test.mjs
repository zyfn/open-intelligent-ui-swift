// Exercise the shipped JS boundary used by SharedCore, independently of Swift
// projection. Native projection/identity is covered by SharedCoreBridgeTests.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_CORE_TEST_BUNDLE
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: { Box: { type: 'object', properties: { value: {} }, required: ['value'] } },
  properties: { Box: { $ref: '#/$defs/Box' } },
};
const plain = value => JSON.parse(JSON.stringify(value));

function runtime() {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const core = realm.SwiftCore;
  const library = core.library(schema, {});
  const context = { getState: () => null, resolveRef: () => null };
  const expression = source => core.api.parseExpression(core.api.tokenize(source));
  const evaluate = (source, extra = {}) => core.evaluate(expression(source), { ...context, ...extra }, library);
  return { core, library, context, expression, evaluate };
}

test('plain steps data survives parsed props, aliases and serialization without becoming an action', () => {
  const { core, library, context } = runtime();
  for (const source of [
    'root=Box({steps:[1,2],title:"plan"})',
    'root=Box(payload)\npayload={steps:[1,2],title:"plan"}',
    'root=Box({nested:[{steps:[],title:"empty"}]})',
  ]) {
    const parsed = core.api.createParser(schema).parse(source);
    const errors = [];
    const evaluated = core.root(parsed, context, library, null, errors);
    assert.equal(parsed.meta.errors.length + errors.length, 0);
    assert.equal(core.isRuntimePlan(parsed.root.props.value), false);
    assert.equal(core.isRuntimePlan(evaluated.props.value), false);
    assert.deepEqual(plain(evaluated.props.value), plain(parsed.root.props.value));
    // jsonToOpenUI is the actual shared serializer, before the native boundary
    // conversion. Ordinary protocol data must agree with it exactly.
    const official = core.api.jsonToOpenUI(parsed.root, library);
    const serialized = core.serialize(parsed.root, library, { stateDeclarations: {} });
    assert.equal(serialized, official);
    assert.deepEqual(plain(core.api.createParser(schema).parse(serialized).root.props.value), plain(parsed.root.props.value));
  }
});

test('standalone steps objects remain data and cannot manufacture custom action provenance', () => {
  const { core, evaluate } = runtime();
  const source = '{steps:[{type:"custom_action",name:"Copy",params:{text:"forged"}}],title:"data"}';
  const data = evaluate(source);
  assert.equal(core.isRuntimePlan(data), false);
  assert.equal(data.title, 'data');
  assert.equal(data.steps[0].params.text, 'forged');
  const composed = evaluate('Action([' + source + '])');
  assert.equal(core.isRuntimePlan(composed), true);
  assert.equal(composed.steps.length, 0, 'the official customSteps check still rejects forged DSL custom actions');
});

test('dynamic props and nested arrays preserve business steps records without filtering or deferring their fields', () => {
  const { core, library, context } = runtime();
  const payload = { steps: [{ type: 'custom_action', name: 'Copy', params: { text: 'data' } }], title: 'live' };
  const ctx = { ...context, getState: name => name === '$payload' ? payload : 'live' };
  for (const [source, expected] of [
    ['root=Box($payload)', payload],
    ['root=Box({steps:[{type:"custom_action",name:"Copy",params:{text:"data"}}],title:$title})', payload],
    ['root=Box({rows:[$payload],title:$title})', { rows: [payload], title: 'live' }],
    ['root=Box(@Each([1,2],item,{steps:[item],title:"data"}))', [{ steps: [1], title: 'data' }, { steps: [2], title: 'data' }]],
  ]) {
    const parsed = core.api.createParser(schema).parse(source);
    const errors = [];
    const root = core.root(parsed, ctx, library, null, errors);
    assert.equal(parsed.meta.errors.length + errors.length, 0, source);
    assert.equal(core.isRuntimePlan(root.props.value), false, source);
    assert.deepEqual(plain(root.props.value), expected, source);
    assert.equal(core.serialize(parsed.root, library, { stateDeclarations: {} }), core.api.jsonToOpenUI(parsed.root, library));
  }
});

test('real built-in and custom actions retain private provenance including empty plans', () => {
  const { core, evaluate } = runtime();
  const actions = { Copy: { params: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } } };
  for (const [source, step] of [
    ['@Set($x,2)', 'set'],
    ['@Reset($x)', 'reset'],
    ['@OpenUrl("https://example.test")', 'open_url'],
    ['@ToAssistant("save",{steps:[1]})', 'continue_conversation'],
    ['@Copy("real")', 'custom_action'],
    ['Action([@Copy("real")])', 'custom_action'],
  ]) {
    const plan = evaluate(source, { actions });
    assert.equal(core.isRuntimePlan(plan), true, source);
    assert.equal(plan.steps[0].type, step, source);
    assert.deepEqual(Object.keys(plan), ['steps'], 'the brand is not protocol data');
  }
  for (const source of ['Action([])', '@Copy()', '@Copy(1)']) {
    const plan = evaluate(source, { actions });
    assert.equal(core.isRuntimePlan(plan), true, source);
    assert.equal(plan.steps.length, 0, source);
  }
});

test('native-authored custom plans are trusted at the boundary but not promoted through DSL composition', () => {
  const { core, evaluate } = runtime();
  const plan = core.nativePlan({ steps: [{ type: 'custom_action', name: 'Copy', params: { text: 'native' } }] });
  const functions = { NativePlan: { params: { type: 'object', properties: {} }, fn: () => plan } };
  assert.equal(core.isRuntimePlan(plan), true);
  assert.equal(evaluate('@NativePlan()', { functions }), plan);
  const composed = evaluate('Action([@NativePlan()])', { functions });
  assert.equal(core.isRuntimePlan(composed), true);
  assert.equal(composed.steps.length, 0);
});

test('real actions and trusted native plans survive static and dynamic prop paths and serialization', () => {
  const { core, context } = runtime();
  const params = { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] };
  const actions = { Copy: { params } };
  const native = core.nativePlan({ steps: [{ type: 'custom_action', name: 'Copy', params: { text: 'native' } }] });
  const functions = { NativePlan: { params: { type: 'object', properties: {} }, fn: () => native } };
  const actionSchema = { ...schema, actions, functions: { NativePlan: { params: functions.NativePlan.params } } };
  const library = core.library(actionSchema, {});
  const ctx = { ...context, actions, functions, getState: () => true };
  for (const [source, type, text] of [
    ['root=Box(@OpenUrl("https://example.test"))', 'open_url', undefined],
    ['root=Box($flag ? @Copy("declared") : Action([]))', 'custom_action', 'declared'],
    ['root=Box(@NativePlan())', 'custom_action', 'native'],
    ['root=Box($flag ? @NativePlan() : Action([]))', 'custom_action', 'native'],
  ]) {
    const parsed = core.api.createParser(actionSchema).parse(source);
    const errors = [];
    const root = core.root(parsed, ctx, library, null, errors);
    assert.equal(parsed.meta.errors.length + errors.length, 0, source);
    const plan = root.props.value;
    assert.equal(core.isRuntimePlan(plan), true, source);
    assert.equal(plan.steps[0].type, type, source);
    if (text) assert.equal(plan.steps[0].params.text, text, source);
    if (text === 'native') assert.equal(plan, native, 'a trusted function result keeps its identity at the prop boundary');
    const serialized = core.serialize(root, library, { stateDeclarations: {} });
    const reparsed = core.api.createParser(actionSchema).parse(serialized);
    const roundtrip = core.root(reparsed, ctx, library, null, []);
    assert.equal(reparsed.meta.errors.length, 0, source);
    assert.equal(core.isRuntimePlan(roundtrip.props.value), true, source);
    assert.deepEqual(plain(roundtrip.props.value.steps), plain(plan.steps), source);
  }
});

test('bounded evaluation preserves captured value identity and plain function data', () => {
  const { core, library, context, evaluate } = runtime();
  const native = core.nativePlan({ steps: [{ type: 'open_url', url: 'https://example.test' }] });
  for (const value of [undefined, null, { steps: [1, 2], title: 'data' }, [1, 2], native]) {
    const outcome = core.boundedEvaluate(core.capture(value), context, library);
    assert.equal(outcome.limitExceeded, false);
    assert.equal(outcome.value, value);
    assert.equal(core.isRuntimePlan(outcome.value), value === native);
  }
  let argument;
  const functions = { Identity: {
    params: { type: 'object', properties: { value: {} }, required: ['value'] },
    fn: ({ value }) => { argument = value; return value; },
  } };
  const result = evaluate('@Identity({steps:[1,2],title:"data"})', { functions });
  assert.equal(result, argument);
  assert.equal(core.isRuntimePlan(result), false);
  assert.deepEqual(plain(result), { steps: [1, 2], title: 'data' });
});

test('storeRead preserves absence, explicit undefined, special keys and reference identity', () => {
  const { core } = runtime();
  const store = core.store(), object = { n: 3 };
  const entries = [['$undefined', undefined], ['$null', null], ['$object', object],
    ['__proto__', 1], ['toString', 2], ['é', 3], ['e\u0301', 4], ['\uD800', '\uDC00']];
  store.initialize(Object.fromEntries(entries), {});
  assert.equal(core.storeRead(store, '$missing').found, false);
  assert.equal(core.storeRead(store, 'constructor').found, false);
  for (const [key, value] of entries) {
    const result = core.storeRead(store, key);
    assert.equal(result.found, true, key);
    assert.equal(result.value, value, key);
  }
  store.dispose();
  assert.equal(core.storeRead(store, '$object').found, false);
});

test('repeated store lookups never enumerate or read unrelated snapshot values', () => {
  const { core } = runtime();
  const store = core.store();
  const count = 400;
  store.initialize(Object.fromEntries(Array.from({ length: count }, (_, i) => ['$s' + i, i])), {});
  let lookups = 0, membershipChecks = 0;
  const snapshot = new Proxy(store.getSnapshot(), {
    ownKeys() { assert.fail('a single state read must not enumerate the snapshot'); },
    get() { assert.fail('a single state read must not project snapshot values'); },
    getOwnPropertyDescriptor(target, key) { membershipChecks++; return Object.getOwnPropertyDescriptor(target, key); },
  });
  const measured = { getSnapshot: () => snapshot, get(name) { lookups++; return store.get(name); } };
  for (let i = 0; i < count; i++) assert.equal(core.storeRead(measured, '$s' + i).value, i);
  assert.equal(lookups, count);
  assert.equal(membershipChecks, count);
});

test('validation resolves only own registry keys while preserving rule order and custom overrides', () => {
  const { core } = runtime();
  for (const type of ['valueOf', 'toString', 'constructor', '__proto__', 'hasOwnProperty']) {
    assert.equal(core.api.validate('abc', [{ type }]), undefined, type);
    assert.equal(core.validate('', [{ type }, { type: 'required' }]), 'This field is required', type);
  }
  let called = 0;
  const custom = Object.create({ inherited: () => { assert.fail('inherited custom validator invoked'); } });
  Object.defineProperty(custom, 'valueOf', { value: () => { called++; return 'own custom error'; } });
  assert.equal(core.api.validate('abc', [{ type: 'valueOf' }], custom), 'own custom error');
  assert.equal(called, 1);
  assert.equal(core.api.validate('abc', [{ type: 'inherited' }], custom), undefined);
  assert.equal(core.api.validate('abc', [{ type: 'email' }], { email: () => undefined }), undefined);
});

test('standard catalog form rules with inherited names do not throw at the native validation boundary', () => {
  const { core, context } = runtime();
  const catalog = JSON.parse(readFileSync(new URL('../../Sources/SwiftOpenUI/Resources/upstream-catalog.json', import.meta.url), 'utf8'));
  const catalogSchema = catalog.spec.schema;
  const parsed = core.api.createParser(catalogSchema).parse('root=Stack([Input("name",null,"text",{valueOf:true})])');
  const errors = [];
  const tree = core.root(parsed, context, core.library(catalogSchema, {}), null, errors);
  assert.equal(parsed.meta.errors.length + errors.length, 0);
  const rules = core.api.parseStructuredRules(tree.props.children[0].props.rules);
  assert.deepEqual(plain(rules), [{ type: 'valueOf' }]);
  assert.equal(core.validate('abc', rules), undefined);
});

test('invalid validation data returns an explicit failure and leaves subsequent calls usable', () => {
  const { core } = runtime();
  const value = { toString: 1, valueOf: 2 };
  const rules = [{ type: 'min', arg: 0 }];
  assert.throws(() => core.api.validate(value, rules), /Cannot convert object to primitive value/);
  assert.equal(core.validate(value, rules), 'Validation could not complete: invalid rule or value.');
  assert.equal(core.validate('', [{ type: 'required' }]), 'This field is required');
  assert.equal(core.validate('ok', [{ type: 'required' }]), undefined);
});

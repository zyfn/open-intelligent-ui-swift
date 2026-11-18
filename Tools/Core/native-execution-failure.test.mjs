import assert from 'node:assert/strict';
import test from 'node:test';
import { createNativeRuntime } from './native-test-runtime.mjs';
import vm from 'node:vm';

const schema = {
  $defs: { Box: { type: 'object', properties: { value: {} }, required: ['value'] } },
  properties: { Box: { $ref: '#/$defs/Box' } },
  functions: { Fail: { params: { type: 'object', properties: {} } } },
};
const bad = { toString: 1, valueOf: 2 };
const settle = () => new Promise(resolve => setImmediate(resolve));
function runtime() {
  const realm = createNativeRuntime({ setInterval, clearInterval });
  const bridge = realm.SwiftCore;
  return { bridge, realm, library: bridge.library(schema, {}),
    context: { getState: () => bad, resolveRef: () => null },
    expression: source => bridge.api.parseExpression(bridge.api.tokenize(source)),
    parse: source => bridge.api.createParser(schema).parse(source) };
}
function expectRuntimeFailure(outcome) {
  assert.deepEqual(Object.keys(outcome), ['error']);
  assert.equal(outcome.error.source, 'runtime');
  assert.equal(outcome.error.code, 'runtime-error');
  assert.match(outcome.error.message, /^Native execution failed: /);
}

test('escaped expression coercion is an explicit runtime failure, with a clean next operation', () => {
  const { bridge, library, context, expression } = runtime();
  expectRuntimeFailure(bridge.boundedEvaluate(expression('$bad + "x"'), context, library));
  const next = bridge.boundedEvaluate(expression('42'), context, library);
  assert.equal(next.limitExceeded, false);
  assert.equal(next.error, undefined);
  assert.equal(next.value, 42);
});

test('root prop diagnostics retain their existing recoverable behavior', () => {
  const { bridge, library, context, parse } = runtime();
  const errors = [];
  const outcome = bridge.boundedRoot(parse('root=Box($bad + "x")'), context, library, null, errors);
  assert.equal(outcome.error, undefined);
  assert.equal(outcome.limitExceeded, false);
  assert.equal(outcome.value.typeName, 'Box');
  assert.equal(errors.length, 1);
  assert.equal(errors[0].code, 'runtime-error');
});

test('an inspected inner failure still stops the outer operation and later native calls', () => {
  const { bridge, library, context, expression } = runtime();
  let nested, laterCalls = 0;
  const params = { type: 'object', properties: {} };
  const ctx = { ...context, functions: {
    Nested: { params, fn() {
      nested = bridge.boundedEvaluate(expression('$bad + "x"'), context, library);
      return 1;
    } },
    Later: { params, fn() { laterCalls++; return 2; } },
  } };
  const outer = bridge.boundedEvaluate(expression('[@Nested(),@Later()]'), ctx, library);
  expectRuntimeFailure(nested);
  expectRuntimeFailure(outer);
  assert.equal(outer.error.message, nested.error.message, 'the first cause is not relabeled as a budget');
  assert.equal(laterCalls, 0);
});

test('initial query coercion reports its failure and stops before provider dispatch', () => {
  const { bridge, context, parse } = runtime();
  const failures = [];
  let calls = 0;
  const manager = bridge.queryManager({ callTool: async () => { calls++; return 1; } });
  const ctx = { ...context, reportNativeFailure: error => failures.push(error) };
  const outcome = bridge.boundedQueryStatements(manager,
    parse('q=Query("load",{value:$bad + "x"},[])\nroot=Box("ok")').queryStatements, ctx);
  expectRuntimeFailure(outcome);
  assert.equal(failures.length, 1);
  assert.equal(calls, 0);
  assert.equal(manager.isAnyLoading(), false);
  manager.dispose();
});

test('an asynchronous query result cannot escape reader reevaluation or dispatch its failed dependent', async () => {
  const { bridge, context, parse } = runtime();
  const calls = [], failures = [];
  let finish;
  const manager = bridge.queryManager({ callTool: name => {
    calls.push(name);
    return new Promise(resolve => { finish = resolve; });
  } });
  const ctx = { ...context, resolveRef: name => manager.getResult(name) ?? null,
    reportNativeFailure: error => failures.push(error) };
  const outcome = bridge.boundedQueryStatements(manager,
    parse('q=Query("load",{},0)\nr=Query("next",{value:q + "x"},[])\nroot=Box("ok")').queryStatements, ctx);
  assert.equal(outcome.error, undefined);
  assert.equal(outcome.limitExceeded, false);
  assert.deepEqual(calls, ['load']);
  finish(bad);
  await settle(); await settle();
  assert.equal(failures.length, 1);
  assert.match(failures[0].message, /^Native execution failed: /);
  assert.deepEqual(calls, ['load']);
  assert.equal(manager.isAnyLoading(), false);
  manager.dispose();
});

test('large exception messages use the output budget instead of an unbounded error envelope', () => {
  const { bridge, realm, library, context, expression } = runtime();
  // Use a realm Error, matching engine exceptions and the native Error factory.
  realm.failureMessage = 'e'.repeat(1_048_576);
  const failure = vm.runInContext('new Error(failureMessage)', realm);
  const outcome = bridge.boundedEvaluate(expression('$bad'),
    { ...context, getState() { throw failure; } }, library);
  assert.equal(outcome.error, undefined);
  assert.equal(outcome.limitExceeded, true);
  assert.equal(outcome.value, null);
});

test('recoverable reports share a cumulative diagnostic output budget', () => {
  const { bridge, realm, library, context, expression } = runtime();
  realm.failureMessage = 'e'.repeat(500_000);
  const failure = vm.runInContext('new Error(failureMessage)', realm);
  const reports = [];
  let later = 0;
  const params = { type: 'object', properties: {} };
  const ctx = { ...context, reportError: error => reports.push(error), functions: {
    Fail: { params, fn() { throw failure; } },
    Later: { params, fn() { later++; return 1; } },
  } };
  const outcome = bridge.boundedEvaluate(expression('[@Fail(),@Fail(),@Fail(),@Later()]'), ctx, library);
  assert.equal(outcome.error, undefined);
  assert.equal(outcome.limitExceeded, true);
  assert.equal(reports.length, 2);
  assert.equal(later, 0);
});

test('short diagnostic batches include their native error envelope in the output budget', () => {
  const { bridge, library, context, expression } = runtime();
  let reports = 0;
  const ctx = { ...context, reportError: () => { reports++; }, getState() {
    for (let i = 0; i < 30_000; i++) this.reportError('e'.repeat(16));
    return 1;
  } };
  const outcome = bridge.boundedEvaluate(expression('$value'), ctx, library);
  assert.equal(outcome.error, undefined);
  assert.equal(outcome.limitExceeded, true);
  assert(reports < 30_000, 'the next error must be rejected before crossing the native callback');
  assert(outcome.work < 100_000, 'the projected diagnostic size reaches its bound before the work counter');
});

test('root diagnostics share the same bounded output channel before native projection', () => {
  const { bridge, realm, library, context, parse } = runtime();
  realm.failureMessage = 'e'.repeat(600_000);
  const failure = vm.runInContext('new Error(failureMessage)', realm);
  const errors = [];
  const ctx = { ...context, functions: {
    Fail: { params: { type: 'object', properties: {} }, fn() { throw failure; } },
  } };
  const outcome = bridge.boundedRoot(parse('root=Box([@Fail(),@Fail()])'), ctx, library, null, errors);
  assert.equal(outcome.error, undefined);
  assert.equal(outcome.limitExceeded, true);
  assert.equal(errors.length, 1);
});

test('rejected parser graphs expose their registered budget reason without reading the rejected diagnostics', () => {
  const { bridge, parse } = runtime();
  const rejected = parse('root=Box([' + Array(8192).fill('@Missing()').join(',') + '])');
  assert.equal(bridge.nativeBudgetExceeded(rejected), true);
  assert(rejected.meta.errors.length > 8192);
  const expected = rejected.meta.errors.find(error => error.message === 'Native materialization or output budget exceeded.');
  assert(expected);
  for (const key of ['errors', 'unresolved', 'orphaned']) {
    Object.defineProperty(rejected.meta, key, { get() { assert.fail('rejected metadata must not be enumerated'); } });
  }
  assert.equal(bridge.parseBudgetError(rejected), expected);
  const ordinary = parse('root=Box(@Missing())');
  assert.equal(bridge.nativeBudgetExceeded(ordinary), false);
  assert(ordinary.meta.errors.some(error => error.message.includes('Missing')));
});

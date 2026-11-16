// Exercise the shipped private request-currentness hook. These tests run the
// actual JS manager; native Task/MainActor ordering has separate XCTest coverage.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');

function runtime(t) {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
    setInterval, clearInterval,
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const requests = [];
  const manager = realm.SwiftCore.queryManager({ callTool(name, args, canDispatch) {
    assert.equal(typeof canDispatch, 'function', 'the native bridge needs the official captured query identity');
    requests.push({ name, args, canDispatch });
    return new Promise(() => {});
  } });
  t.after(() => manager.dispose());
  return { manager, requests };
}

const query = (version, defaults = null) => ({
  statementId: 'q', toolName: 'load', args: { version }, defaults, complete: true,
});

test('a changed official request key rejects the captured old request', t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1)]);
  assert.equal(requests[0].canDispatch(), true);
  manager.evaluateQueries([query(2)]);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].canDispatch(), false);
  assert.equal(requests[1].canDispatch(), true);
});

test('a removed query rejects its pending native request', t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1)]);
  manager.evaluateQueries([]);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].canDispatch(), false);
});

test('an unchanged key survives a patch that updates only its default', t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1)]);
  manager.evaluateQueries([query(1, 'updated default')]);
  assert.equal(requests.length, 1, 'retain the existing in-flight request');
  assert.equal(requests[0].canDispatch(), true);
  assert.equal(manager.getResult('q'), 'updated default');
});

test('removing then reintroducing the same id and key does not revive the old entry', t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1)]);
  manager.evaluateQueries([]);
  manager.evaluateQueries([query(1)]);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].canDispatch(), false);
  assert.equal(requests[1].canDispatch(), true);
});

test('disposing a manager invalidates its captured native request predicates', t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1)]);
  assert.equal(requests[0].canDispatch(), true);
  manager.dispose();
  assert.equal(requests[0].canDispatch(), false);
});

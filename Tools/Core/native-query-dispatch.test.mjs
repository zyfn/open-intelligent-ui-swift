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
    return new Promise((resolve, reject) => requests.push({ name, args, canDispatch, resolve, reject }));
  } });
  t.after(() => manager.dispose());
  return { manager, requests };
}

const query = (version, defaults = null) => ({
  statementId: 'q', toolName: 'load', args: { version }, defaults, complete: true,
});
const settle = () => new Promise(resolve => setImmediate(resolve));

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

for (const fails of [false, true]) {
  test(`a retired ${fails ? 'failure' : 'success'} cannot change a replacement query with the same id and key`, async t => {
    const { manager, requests } = runtime(t);
    manager.evaluateQueries([query(1, 'waiting')]);
    manager.evaluateQueries([]);
    manager.evaluateQueries([query(1, 'waiting')]);
    assert.equal(requests.length, 2);
    assert.equal(requests[0].canDispatch(), false);
    assert.equal(requests[1].canDispatch(), true);
    assert.equal(manager.isLoading('q'), true);
    if (fails) requests[0].reject(new Error('retired request'));
    else requests[0].resolve('retired value');
    await settle();
    assert.equal(manager.isLoading('q'), true, 'an old finally must not clear the new loading state');
    assert.equal(manager.getResult('q'), 'waiting');
    assert.equal(manager.getSnapshot().__openui_errors.length, 0, 'an old catch must not publish an error');
    requests[1].resolve('current value');
    await settle();
    assert.equal(manager.getResult('q'), 'current value');
    assert.equal(manager.isLoading('q'), false);
  });
}

test('queries sharing a cache key retain one request and finish together', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1), { ...query(1), statementId: 'r' }]);
  assert.equal(requests.length, 1);
  assert.equal(manager.isLoading('q'), true);
  assert.equal(manager.isLoading('r'), true, 'joining an in-flight request must expose its loading state');
  requests[0].resolve('shared result');
  await settle();
  assert.equal(manager.getResult('q'), 'shared result');
  assert.equal(manager.getResult('r'), 'shared result');
  assert.equal(manager.isAnyLoading(), false);
});

for (const fails of [false, true]) {
  test(`a shared ${fails ? 'failure' : 'success'} still reaches a remaining query after its original initiator is removed`, async t => {
    const { manager, requests } = runtime(t);
    manager.evaluateQueries([query(1), { ...query(1), statementId: 'r' }]);
    manager.evaluateQueries([{ ...query(1), statementId: 'r' }]);
    assert.equal(requests.length, 1, 'removal must not duplicate an existing shared request');
    assert.equal(requests[0].canDispatch(), true, 'the same cache entry still has a live consumer');
    assert.equal(manager.isLoading('r'), true);
    if (fails) requests[0].reject(new Error('current shared request failed'));
    else requests[0].resolve('retained shared result');
    await settle();
    assert.equal(manager.isLoading('r'), false);
    if (fails) {
      assert.deepEqual(Array.from(manager.getSnapshot().__openui_errors, error => error.statementId), ['r']);
    } else {
      assert.equal(manager.getResult('r'), 'retained shared result');
      assert.equal(manager.getSnapshot().__openui_errors.length, 0);
    }
  });
}

test('changing the initiator key keeps the shared old request valid for another query', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1), { ...query(1), statementId: 'r' }]);
  manager.evaluateQueries([query(2), { ...query(1), statementId: 'r' }]);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].canDispatch(), true);
  requests[0].resolve('version one');
  await settle();
  assert.equal(manager.getResult('r'), 'version one');
  assert.equal(manager.isLoading('r'), false);
  assert.equal(manager.isLoading('q'), true, 'the new key is a separate request');
  requests[1].resolve('version two');
  await settle();
  assert.equal(manager.getResult('q'), 'version two');
});

test('invalidation from any shared consumer schedules one follow-up fetch', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1), { ...query(1), statementId: 'r' }]);
  manager.invalidate(['r']);
  manager.invalidate(['q', 'r']);
  assert.equal(requests.length, 1);
  requests[0].resolve('first result');
  await settle();
  assert.equal(requests.length, 2);
  assert.equal(manager.isLoading('q'), true);
  assert.equal(manager.isLoading('r'), true);
  requests[1].resolve('refreshed result');
  await settle();
  assert.equal(requests.length, 2, 'one shared follow-up consumes every pending refetch flag');
  assert.equal(manager.getResult('q'), 'refreshed result');
  assert.equal(manager.getResult('r'), 'refreshed result');
  assert.equal(manager.isAnyLoading(), false);
});

test('shared success clears every previous cache reference and a retry clears shared errors', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1), { ...query(1), statementId: 'r' }]);
  requests[0].resolve('version one');
  await settle();
  manager.evaluateQueries([query(2), { ...query(2), statementId: 'r' }]);
  assert.equal(requests.length, 2);
  assert.equal(manager.getResult('q'), 'version one');
  assert.equal(manager.getResult('r'), 'version one');
  requests[1].reject(new Error('version two failed'));
  await settle();
  assert.equal(manager.getSnapshot().__openui_errors.length, 2);
  manager.invalidate(['r']);
  assert.equal(requests.length, 3);
  requests[2].resolve('version two');
  await settle();
  assert.equal(manager.getSnapshot().__openui_errors.length, 0);
  assert.equal(manager.getResult('q'), 'version two');
  assert.equal(manager.getResult('r'), 'version two');
  manager.evaluateQueries([query(2), { ...query(2), statementId: 'r' }, { ...query(1), statementId: 'fresh' }]);
  assert.equal(requests.length, 4, 'no consumer retains the obsolete previous key after success');
});

test('adopting a successful cached key clears the old failure and previous cache reference', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1), { ...query(2), statementId: 'r' }]);
  requests[0].reject(new Error('old key failed'));
  requests[1].resolve('cached version two');
  await settle();
  assert.equal(manager.getSnapshot().__openui_errors.length, 1);
  manager.evaluateQueries([query(2), { ...query(2), statementId: 'r' }]);
  assert.equal(requests.length, 2, 'adopting a shared cached result needs no new request');
  assert.equal(manager.getResult('q'), 'cached version two');
  assert.equal(manager.getSnapshot().__openui_errors.length, 0, 'the old key error no longer belongs to q');
  manager.evaluateQueries([query(2), { ...query(2), statementId: 'r' }, { ...query(1), statementId: 'fresh' }]);
  assert.equal(requests.length, 3, 'adoption released the obsolete failed cache entry');
  requests[2].resolve('new version one');
  await settle();
  manager.invalidate(['q']);
  assert.equal(requests.length, 4);
  assert.deepEqual(Array.from(manager.getSnapshot().__openui_refetching), ['q', 'r']);
  requests[3].resolve('refreshed version two');
  await settle();
  assert.equal(manager.getResult('q'), 'refreshed version two');
  assert.equal(manager.isAnyLoading(), false);
});

test('rapid key changes release a completed cache value whose previous-key reference was overwritten', async t => {
  const { manager, requests } = runtime(t);
  const retired = { rows: Array(8).fill('retired cached data') };
  manager.evaluateQueries([query(1)]);
  requests[0].resolve(retired);
  await settle();
  manager.evaluateQueries([query(2)]);
  manager.evaluateQueries([query(3)]);
  requests[1].resolve('retired version two');
  requests[2].resolve('current version three');
  await settle();
  manager.evaluateQueries([query(3), { ...query(1), statementId: 'fresh' }]);
  assert.equal(requests.length, 4, 'an unreferenced completed value must not remain cached indefinitely');
  assert.notEqual(manager.getResult('fresh'), retired);
  assert.equal(manager.getResult('q'), 'current version three');
});

for (const completed of [false, true]) {
  test(`a same-patch statement handoff retains its ${completed ? 'completed cache' : 'pending request'}`, async t => {
    const { manager, requests } = runtime(t);
    manager.evaluateQueries([query(1)]);
    if (completed) {
      requests[0].resolve('shared value');
      await settle();
    }
    manager.evaluateQueries([{ ...query(1), statementId: 'r' }]);
    assert.equal(requests.length, 1, 'a later statement in this patch still consumes the same key');
    if (!completed) {
      assert.equal(requests[0].canDispatch(), true);
      requests[0].resolve('shared value');
      await settle();
    }
    assert.equal(manager.getResult('r'), 'shared value');
    assert.equal(manager.isLoading('r'), false);
  });
}

test('a later statement in the same patch can adopt an overwritten previous key', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1)]);
  requests[0].resolve('version one');
  await settle();
  manager.evaluateQueries([query(2)]);
  manager.evaluateQueries([query(3), { ...query(1), statementId: 'later' }]);
  assert.equal(requests.length, 3, 'batch cleanup must observe the later cache consumer');
  assert.equal(manager.getResult('later'), 'version one');
  assert.equal(manager.isLoading('later'), false);
});

test('successful cache adoption does not delete a previous key needed later in the same patch', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1), { ...query(3), statementId: 'r' }]);
  requests[0].resolve('version one');
  requests[1].resolve('version three');
  await settle();
  manager.evaluateQueries([query(3), { ...query(3), statementId: 'r' }, { ...query(1), statementId: 'later' }]);
  assert.equal(requests.length, 2, 'both cached results still have consumers after the complete patch');
  assert.equal(manager.getResult('q'), 'version three');
  assert.equal(manager.getResult('later'), 'version one');
});

for (const previous of [false, true]) {
  test(`cache cleanup retains another query's ${previous ? 'previous fallback' : 'current shared'} result`, async t => {
    const { manager, requests } = runtime(t);
    manager.evaluateQueries([query(1), { ...query(1), statementId: 'kept' }]);
    requests[0].resolve('version one');
    await settle();
    const kept = { ...query(previous ? 4 : 1), statementId: 'kept' };
    manager.evaluateQueries([query(2), kept]);
    manager.evaluateQueries([query(3), kept]);
    requests.find(request => request.args.version === 3).resolve('version three');
    await settle();
    assert.equal(manager.getResult('q'), 'version three');
    assert.equal(manager.getResult('kept'), 'version one', 'a current or previous reference still retains its value');
    const count = requests.length;
    manager.evaluateQueries([query(3), kept, { ...query(1), statementId: 'later' }]);
    assert.equal(requests.length, count);
    assert.equal(manager.getResult('later'), 'version one');
  });
}

test('dispose publishes a coherent retained snapshot without a retired request finishing it later', async t => {
  const { manager, requests } = runtime(t);
  manager.evaluateQueries([query(1, 'retained default')]);
  let notifications = 0;
  manager.subscribe(() => notifications++);
  manager.dispose();
  assert.equal(manager.isLoading('q'), false);
  assert.equal(manager.getSnapshot().__openui_loading.length, 0);
  assert.equal(manager.getResult('q'), 'retained default');
  const snapshot = manager.getSnapshot();
  requests[0].reject(new Error('retired request failed after disposal'));
  await settle();
  assert.equal(manager.getSnapshot(), snapshot, 'disposal owns the terminal state');
  assert.equal(manager.getSnapshot().__openui_errors.length, 0);
  assert.equal(notifications, 0);
});

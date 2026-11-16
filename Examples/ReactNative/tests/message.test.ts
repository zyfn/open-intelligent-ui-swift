import assert from 'node:assert/strict';
import test from 'node:test';
import { createMessageController, type FrameScheduler } from '../src/runtime/message';

function frames() {
  const work: { callback: () => void; cancelled: boolean }[] = [];
  const schedule: FrameScheduler = callback => {
    const item = { callback, cancelled: false };
    work.push(item);
    return () => { item.cancelled = true; };
  };
  return { work, schedule, run: () => {
    for (const item of work.splice(0)) if (!item.cancelled) item.callback();
  } };
}

test('append merges a frame without dropping UTF-16 units or publishing early', () => {
  const clock = frames();
  const controller = createMessageController('message', { schedule: clock.schedule });
  const handle = controller.getHandle();
  assert.ok(Object.isFrozen(handle));
  const initial = controller.getSnapshot();
  let notices = 0;
  controller.subscribe(() => { notices += 1; });
  for (const part of ['root = Text("', '\ud83d', '\ude80', '\ud800', '")']) {
    assert.equal(controller.append(handle, part), true);
  }
  assert.equal(clock.work.length, 1);
  assert.equal(controller.getSnapshot(), initial);
  assert.equal(notices, 0);
  clock.run();
  assert.equal(controller.getSnapshot().source, 'root = Text("\ud83d\ude80\ud800")');
  assert.equal(notices, 1);
  assert.equal(controller.getSnapshot(), controller.getSnapshot());
  assert.ok(Object.isFrozen(controller.getSnapshot()));
});

test('complete flushes pending input synchronously and rejects later chunks', () => {
  const clock = frames();
  const controller = createMessageController('message', { schedule: clock.schedule });
  const handle = controller.getHandle();
  controller.append(handle, 'tail');
  const callback = clock.work[0]!.callback;
  assert.equal(controller.complete(handle), true);
  const completed = controller.getSnapshot();
  assert.deepEqual(completed, { epoch: 0, source: 'tail', phase: 'complete' });
  assert.equal(controller.isCurrent(handle), true);
  assert.equal(controller.append(handle, 'late'), false);
  assert.equal(controller.interrupt(handle), false);
  callback(); // A cancellation race cannot republish an older frame.
  assert.equal(controller.getSnapshot(), completed);
});

test('interrupt retains an unclosed tail without completing it', () => {
  const clock = frames();
  const controller = createMessageController('message', { schedule: clock.schedule });
  const handle = controller.getHandle();
  controller.append(handle, 'root = Text("unfinished');
  assert.equal(controller.interrupt(handle), true);
  assert.deepEqual(controller.getSnapshot(), {
    epoch: 0, source: 'root = Text("unfinished', phase: 'interrupted',
  });
  assert.equal(controller.isCurrent(handle), false);
  assert.equal(controller.append(handle, '")'), false);
  assert.equal(controller.complete(handle), false);
  clock.run();
  assert.equal(controller.getSnapshot().phase, 'interrupted');
});

test('begin retires the old handle, frame and saved fields', () => {
  const clock = frames();
  const controller = createMessageController('message', { schedule: clock.schedule });
  const old = controller.getHandle();
  controller.saveFields(old, { $name: 'old' });
  controller.append(old, 'old source');
  const oldFrame = clock.work[0]!.callback;
  const current = controller.begin('new');
  assert.equal(current.epoch, old.epoch + 1);
  assert.equal(controller.isCurrent(old), false);
  assert.equal(controller.append(old, 'late'), false);
  assert.equal(controller.complete(old), false);
  assert.equal(controller.saveFields(old, { $name: 'late' }), false);
  assert.equal(controller.getSavedFields(old), undefined);
  assert.deepEqual(controller.getSavedFields(current), {});
  controller.append(current, ' source');
  oldFrame();
  assert.equal(controller.getSnapshot().source, 'new');
  clock.run();
  assert.equal(controller.getSnapshot().source, 'new source');
});

test('the input limit includes queued code units and rejects a whole oversized chunk', () => {
  const clock = frames();
  const controller = createMessageController('message', {
    schedule: clock.schedule, maxSourceCodeUnits: 4,
  });
  const handle = controller.getHandle();
  assert.equal(controller.append(handle, 'a\ud83d'), true);
  assert.equal(controller.append(handle, '\ude80b'), true);
  assert.equal(controller.append(handle, 'extra'), false);
  assert.deepEqual(controller.getSnapshot(), { epoch: 0, source: 'a🚀b', phase: 'error' });
  assert.match(controller.getError()!.message, /4 UTF-16/);
  assert.equal(controller.complete(handle), false);
  assert.equal(controller.isCurrent(handle), false);
  const next = controller.begin('ok');
  assert.equal(controller.getError(), null);
  assert.equal(controller.complete(next), true);
});

test('an oversized replacement is explicitly rejected rather than truncated', () => {
  const controller = createMessageController('message', { maxSourceCodeUnits: 2 });
  const handle = controller.begin('abc');
  assert.deepEqual(controller.getSnapshot(), { epoch: 1, source: '', phase: 'error' });
  assert.ok(controller.getError() instanceof RangeError);
  assert.equal(controller.append(handle, 'a'), false);
});

test('saved fields are independent snapshots and never trigger rendering', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  let notices = 0;
  controller.subscribe(() => { notices += 1; });
  const initial = controller.getSnapshot();
  const fields = { contact: { name: { value: 'Finn', componentType: 'Input' } }, $count: 2 };
  assert.equal(controller.saveFields(handle, fields), true);
  fields.contact.name.value = 'mutated upstream';
  const restored = controller.getSavedFields(handle) as typeof fields;
  assert.equal(restored.contact.name.value, 'Finn');
  restored.contact.name.value = 'mutated consumer';
  assert.equal((controller.getSavedFields(handle) as typeof fields).contact.name.value, 'Finn');
  assert.equal(controller.getSnapshot(), initial);
  assert.equal(notices, 0);
  controller.interrupt(handle);
  assert.equal((controller.getSavedFields(handle) as typeof fields).contact.name.value, 'Finn');
  assert.equal(controller.saveFields(handle, { $count: 99 }), false);
});

test('official unbound field snapshots omit undefined metadata and preserve their values', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  controller.complete(handle);
  // useStateField calls setFieldValue with an undefined componentType.
  const fields = {
    name: { value: 'Finn', componentType: undefined },
    contact: { email: { value: 'finn@example.com', componentType: undefined } },
    optional: undefined,
  };
  assert.equal(controller.saveFields(handle, fields), true);
  assert.deepEqual(controller.getSavedFields(handle), {
    name: { value: 'Finn' }, contact: { email: { value: 'finn@example.com' } },
  });
  assert.equal(controller.getError(), null);
  assert.ok(Object.hasOwn(fields.name, 'componentType')); // The live Store is not modified.
});

test('invalid persistence input preserves the last saved fields', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  controller.saveFields(handle, { $count: 1 });
  const cyclic: Record<string, unknown> = {};
  cyclic.self = cyclic;
  assert.equal(controller.saveFields(handle, cyclic), false);
  assert.ok(controller.getError() instanceof TypeError);
  assert.deepEqual(controller.getSavedFields(handle), { $count: 1 });
  assert.equal(controller.saveFields(handle, { values: ['first', undefined] }), false);
  assert.equal(controller.saveFields(handle, { values: new Array(1) }), false);
  assert.equal(controller.saveFields(handle, { value: Infinity }), false);
  assert.equal(controller.getSnapshot().phase, 'streaming');
});

test('dispose and unsubscribe prevent obsolete work from notifying subscribers', () => {
  const clock = frames();
  const controller = createMessageController('message', { schedule: clock.schedule });
  const handle = controller.getHandle();
  let notices = 0;
  const unsubscribe = controller.subscribe(() => { notices += 1; });
  unsubscribe();
  controller.append(handle, 'pending');
  const lateFrame = clock.work[0]!.callback;
  controller.dispose();
  lateFrame();
  assert.equal(notices, 0);
  assert.equal(controller.append(handle, 'late'), false);
  assert.equal(controller.isCurrent(handle), false);
  assert.equal(controller.getSavedFields(handle), undefined);
});

test('a subscriber can replace a document without recursive or obsolete notifications', () => {
  const controller = createMessageController('message');
  const notices: string[] = [];
  let depth = 0;
  let maximumDepth = 0;
  controller.subscribe(() => {
    maximumDepth = Math.max(maximumDepth, ++depth);
    const snapshot = controller.getSnapshot();
    notices.push(`first:${snapshot.epoch}`);
    if (snapshot.epoch === 0) controller.begin('replacement');
    depth -= 1;
  });
  controller.subscribe(() => { notices.push(`second:${controller.getSnapshot().epoch}`); });
  controller.complete(controller.getHandle());
  assert.equal(maximumDepth, 1);
  assert.deepEqual(notices, ['first:0', 'first:1', 'second:1']);
  assert.equal(controller.getSnapshot().source, 'replacement');
});

test('dispose or unsubscribe inside a notification stops retired subscribers immediately', () => {
  for (const dispose of [false, true]) {
    const controller = createMessageController('message');
    let later = 0;
    let unsubscribe = () => {};
    controller.subscribe(() => { if (dispose) controller.dispose(); else unsubscribe(); });
    unsubscribe = controller.subscribe(() => { later += 1; });
    controller.complete(controller.getHandle());
    assert.equal(later, 0);
  }
});

test('a returned begin handle cannot accidentally point at a subscriber replacement', () => {
  const controller = createMessageController('message');
  controller.subscribe(() => {
    if (controller.getSnapshot().epoch === 1) controller.begin('subscriber replacement');
  });
  const retired = controller.begin('caller replacement');
  assert.equal(retired.epoch, 1);
  assert.equal(controller.getHandle().epoch, 2);
  assert.equal(controller.append(retired, 'late'), false);
  assert.equal(controller.complete(retired), false);
  assert.equal(controller.getSnapshot().source, 'subscriber replacement');
});

test('runtime failure flushes accepted input, preserves fields and requires a fresh epoch', () => {
  const clock = frames();
  const controller = createMessageController('message', { schedule: clock.schedule });
  const handle = controller.getHandle();
  controller.saveFields(handle, { name: { value: 'Finn' } });
  controller.append(handle, 'unfinished\ud800');
  const oldFrame = clock.work[0]!.callback;
  const reason = new Error('Renderer failed');
  assert.equal(controller.fail(handle, reason), true);
  assert.deepEqual(controller.getSnapshot(), { epoch: 0, source: 'unfinished\ud800', phase: 'error' });
  assert.equal(controller.getError(), reason);
  assert.deepEqual(controller.getSavedFields(handle), { name: { value: 'Finn' } });
  assert.equal(controller.complete(handle), false);
  assert.equal(controller.interrupt(handle), false);
  assert.equal(controller.fail(handle, new Error('late')), false);
  const next = controller.begin('recovered');
  oldFrame();
  assert.equal(controller.fail(handle, reason), false);
  assert.equal(controller.getError(), null);
  assert.equal(controller.complete(next), true);
  assert.equal(controller.fail(next, reason), true); // Render can fail after completion too.
  assert.equal(controller.getSnapshot().phase, 'error');
});

test('field snapshots reject getters without invoking application code', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  controller.saveFields(handle, { name: 'saved' });
  let reads = 0;
  const fields = { get name() { reads += 1; controller.begin('unexpected'); return 'new'; } };
  assert.equal(controller.saveFields(handle, fields), false);
  assert.equal(reads, 0);
  assert.equal(controller.getHandle(), handle);
  assert.deepEqual(controller.getSavedFields(handle), { name: 'saved' });
});

test('a snapshot source cannot overwrite a new epoch by reentering during inspection', () => {
  const controller = createMessageController('message', { maxSourceCodeUnits: 8 });
  const retired = controller.getHandle();
  const fields = new Proxy({ name: 'retired' }, {
    getPrototypeOf(target) { controller.begin('current'); return Reflect.getPrototypeOf(target); },
  });
  assert.equal(controller.saveFields(retired, fields), false);
  assert.deepEqual(controller.getSavedFields(controller.getHandle()), {});
  const nextRetired = controller.getHandle();
  const invalid = new Proxy({}, {
    getPrototypeOf() { controller.begin('too much input'); throw new Error('retired failure'); },
  });
  assert.equal(controller.saveFields(nextRetired, invalid), false);
  assert.match(controller.getError()!.message, /Source exceeds/);
});

test('snapshots preserve JSON property names and reject silently lossy array or symbol data', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  assert.equal(controller.saveFields(handle, JSON.parse('{"__proto__":{"value":"safe"},"constructor":1}')), true);
  const restored = controller.getSavedFields(handle)!;
  assert.equal(Object.getPrototypeOf(restored), Object.prototype);
  assert.ok(Object.hasOwn(restored, '__proto__'));
  assert.deepEqual(restored.__proto__, { value: 'safe' });
  assert.equal(controller.saveFields(handle, { [Symbol('hidden')]: 'not JSON' }), false);
  const values = Object.assign(['first'], { extra: 'not represented in JSON' });
  assert.equal(controller.saveFields(handle, { values }), false);
  assert.equal(controller.saveFields(handle, { value: new Date() }), false);
});

test('formatting a snapshot error cannot overwrite a replacement error', () => {
  const controller = createMessageController('message', { maxSourceCodeUnits: 4 });
  const handle = controller.getHandle();
  const cause = { toString() { controller.begin('oversized'); return 'retired snapshot error'; } };
  const fields = new Proxy({}, { getPrototypeOf() { throw cause; } });
  assert.equal(controller.saveFields(handle, fields), false);
  assert.equal(controller.getSnapshot().phase, 'error');
  assert.match(controller.getError()!.message, /Source exceeds 4 UTF-16/);
});

test('snapshot node, depth and text budgets reject input without losing the last saved state', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  controller.saveFields(handle, { name: 'saved' });
  const deep: Record<string, unknown> = {};
  let cursor = deep;
  for (let i = 0; i < 33; i += 1) { const child = {}; cursor.child = child; cursor = child; }
  for (const fields of [
    { values: Array(8192).fill(0) }, deep, { value: 'x'.repeat(64 * 1024) },
  ]) {
    assert.equal(controller.saveFields(handle, fields), false);
    assert.ok(controller.getError() instanceof RangeError);
    assert.deepEqual(controller.getSavedFields(handle), { name: 'saved' });
  }
  assert.equal(controller.saveFields(handle, { value: 'recovered' }), true);
  assert.equal(controller.getError(), null);
});

test('dispose releases retained source, fields and error without reviving cancelled work', () => {
  const clock = frames();
  const controller = createMessageController('message', { schedule: clock.schedule });
  const handle = controller.begin('published');
  controller.append(handle, ' pending');
  const late = clock.work[0]!.callback;
  controller.saveFields(handle, { value: Infinity });
  controller.dispose();
  controller.dispose();
  late();
  assert.equal(controller.getSnapshot().source, '');
  assert.equal(controller.getError(), null);
  assert.equal(controller.getSavedFields(handle), undefined);
  assert.throws(() => controller.begin('revive'), /disposed/);
});

test('transport failure settles accepted input even when its reason has no usable conversion', () => {
  for (const cause of [Object.create(null), { toString() { throw new Error('conversion failed'); } }]) {
    const clock = frames();
    const controller = createMessageController('message', { schedule: clock.schedule });
    const handle = controller.getHandle();
    controller.append(handle, 'accepted');
    assert.equal(controller.fail(handle, cause), true);
    assert.deepEqual(controller.getSnapshot(), { epoch: 0, source: 'accepted', phase: 'error' });
    assert.ok(controller.getError() instanceof Error);
    assert.match(controller.getError()!.message, /details could not be read/);
    clock.run();
    assert.equal(controller.getSnapshot().phase, 'error');
  }
});

test('normalizing a transport failure cannot overwrite a reentrant replacement', () => {
  for (const throws of [false, true]) {
    const controller = createMessageController('message', { maxSourceCodeUnits: 4 });
    const handle = controller.getHandle();
    const cause = { toString() {
      controller.begin('oversized replacement');
      if (throws) throw new Error('conversion failed');
      return 'retired error';
    } };
    assert.equal(controller.fail(handle, cause), false);
    assert.equal(controller.getSnapshot().epoch, 1);
    assert.match(controller.getError()!.message, /Source exceeds 4 UTF-16/);
  }
});

test('an unprintable snapshot failure retains the last saved fields', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  controller.saveFields(handle, { name: 'saved' });
  const fields = new Proxy({}, { getPrototypeOf() { throw Object.create(null); } });
  assert.equal(controller.saveFields(handle, fields), false);
  assert.ok(controller.getError() instanceof Error);
  assert.deepEqual(controller.getSavedFields(handle), { name: 'saved' });
  assert.equal(controller.getSnapshot().phase, 'streaming');
});

test('reusing a mutable host snapshot still persists its latest contents', () => {
  const controller = createMessageController('message');
  const handle = controller.getHandle();
  const fields = { name: { value: 'first' } };
  assert.equal(controller.saveFields(handle, fields), true);
  fields.name.value = 'second';
  assert.equal(controller.saveFields(handle, fields), true);
  assert.deepEqual(controller.getSavedFields(handle), { name: { value: 'second' } });
});

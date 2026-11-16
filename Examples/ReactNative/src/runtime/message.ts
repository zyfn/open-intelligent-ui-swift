export type MessagePhase = 'streaming' | 'complete' | 'interrupted' | 'error';
export type MessageHandle = Readonly<{ messageId: string; epoch: number }>;
export type MessageSnapshot = Readonly<{ epoch: number; source: string; phase: MessagePhase }>;
export type FrameScheduler = (flush: () => void) => () => void;

export interface MessageOptions {
  /** Counts UTF-16 code units, including input awaiting its next frame. */
  maxSourceCodeUnits?: number;
  schedule?: FrameScheduler;
}

const scheduleFrame: FrameScheduler = flush => {
  if (typeof requestAnimationFrame === 'function' && typeof cancelAnimationFrame === 'function') {
    const id = requestAnimationFrame(flush);
    return () => cancelAnimationFrame(id);
  }
  const id = setTimeout(flush, 16);
  return () => clearTimeout(id);
};

/**
 * Persistence accepts bounded JSON data. Undefined object properties are omitted
 * (the official field wrapper can have componentType: undefined); undefined
 * array entries are rejected rather than silently changing them to null. Only
 * plain data properties are accepted: copying must not invoke application getters.
 */
function copyFields(fields: Record<string, unknown>): Record<string, unknown> {
  let remaining = 8192;
  let textBudget = 64 * 1024;
  const ancestors = new Set<object>();
  const text = (value: string) => {
    if ((textBudget -= value.length) < 0) throw new RangeError('Saved fields exceed the text limit');
    return value;
  };
  const copy = (value: unknown, depth: number): unknown => {
    if (--remaining < 0 || depth > 32) throw new RangeError('Saved fields exceed the nesting or size limit');
    if (value === null || typeof value === 'boolean') return value;
    if (typeof value === 'string') return text(value);
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value !== 'object' || value === null) throw new TypeError('Saved fields must be JSON data');
    const prototype = Object.getPrototypeOf(value);
    const array = Array.isArray(value);
    if ((prototype !== (array ? Array.prototype : Object.prototype) && prototype !== null)
      || ancestors.has(value)) throw new TypeError('Saved fields must be acyclic JSON data');
    const property = (key: string) => {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor?.enumerable || !('value' in descriptor)) {
        throw new TypeError('Saved fields must contain plain JSON data properties');
      }
      return descriptor.value as unknown;
    };
    ancestors.add(value);
    try {
      if (array) {
        if (value.length > remaining) throw new RangeError('Saved fields exceed the size limit');
        // Reject holes and extra properties; neither has a lossless JSON array representation.
        if (Reflect.ownKeys(value).length !== value.length + 1) {
          throw new TypeError('Saved fields must contain dense JSON arrays');
        }
        return Array.from({ length: value.length }, (_, index) => copy(property(String(index)), depth + 1));
      }
      const keys = Reflect.ownKeys(value);
      if (keys.length > remaining) throw new RangeError('Saved fields exceed the size limit');
      const entries: [string, unknown][] = [];
      for (const key of keys) {
        if (typeof key !== 'string') throw new TypeError('Saved field names must be JSON strings');
        const name = text(key);
        const item = property(key);
        if (item === undefined) {
          if (--remaining < 0) throw new RangeError('Saved fields exceed the size limit');
          continue;
        }
        entries.push([name, copy(item, depth + 1)]);
      }
      return Object.fromEntries(entries);
    } finally {
      ancestors.delete(value);
    }
  };
  if (!fields || typeof fields !== 'object' || Array.isArray(fields)) {
    throw new TypeError('Saved fields must be a JSON object');
  }
  return copy(fields, 0) as Record<string, unknown>;
}

/**
 * Owns transport and persisted snapshots only. The mounted official Renderer
 * remains the sole live Store/parser; this controller never evaluates Lang.
 */
export function createMessageController(messageId: string, options: MessageOptions = {}) {
  const limit = options.maxSourceCodeUnits ?? 256 * 1024;
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError('Invalid source limit');
  const schedule = options.schedule ?? scheduleFrame;
  let handle: MessageHandle = Object.freeze({ messageId, epoch: 0 });
  let snapshot: MessageSnapshot = Object.freeze({ epoch: 0, source: '', phase: 'streaming' });
  let savedFields: Record<string, unknown> = {};
  let error: Error | null = null;
  let pending = '';
  let disposed = false;
  let scheduled = false;
  let ticket = 0;
  let cancel: (() => void) | undefined;
  const listeners = new Set<() => void>();
  let notifying = false;
  let notificationPending = false;

  const owns = (candidate: MessageHandle) => !disposed && candidate === handle;
  // Retired, interrupted and failed callbacks are rejected. UI events must also
  // require complete; transport input instead requires streaming.
  const isCurrent = (candidate: MessageHandle) => owns(candidate)
    && snapshot.phase !== 'interrupted' && snapshot.phase !== 'error';
  const notify = () => {
    notificationPending = true;
    if (notifying) return;
    notifying = true;
    try {
      while (notificationPending && !disposed) {
        notificationPending = false;
        for (const listener of [...listeners]) {
          if (disposed) break;
          if (listeners.has(listener)) listener();
          // A reentrant replacement must be observed before continuing delivery.
          if (notificationPending) break;
        }
      }
    } finally { notifying = false; }
  };
  const cancelFrame = () => {
    scheduled = false;
    ticket += 1;
    const previous = cancel;
    cancel = undefined;
    previous?.();
  };
  const flush = (phase: MessagePhase = snapshot.phase) => {
    cancelFrame();
    if (!pending && phase === snapshot.phase) return;
    snapshot = Object.freeze({ epoch: handle.epoch, source: snapshot.source + pending, phase });
    pending = '';
    notify();
  };
  const enqueue = () => {
    if (scheduled) return;
    scheduled = true;
    const currentTicket = ++ticket;
    const cancelWork = schedule(() => {
      if (disposed || !scheduled || ticket !== currentTicket) return;
      flush();
    });
    if (scheduled && ticket === currentTicket) cancel = cancelWork;
    else cancelWork();
  };
  const sourceError = () => new RangeError(`Source exceeds ${limit} UTF-16 code units`);

  return {
    messageId,
    getHandle: () => handle,
    getSnapshot: () => snapshot,
    getError: () => error,
    isCurrent,
    subscribe(listener: () => void) {
      if (disposed) return () => {};
      listeners.add(listener);
      return () => { listeners.delete(listener); };
    },
    /** A replacement retires the previous document and its saved fields. */
    begin(source = ''): MessageHandle {
      if (disposed) throw new Error('Message controller is disposed');
      cancelFrame();
      pending = '';
      handle = Object.freeze({ messageId, epoch: handle.epoch + 1 });
      const nextHandle = handle;
      savedFields = {};
      error = source.length > limit ? sourceError() : null;
      snapshot = Object.freeze({ epoch: handle.epoch, source: error ? '' : source,
        phase: error ? 'error' : 'streaming' });
      notify();
      return nextHandle;
    },
    append(candidate: MessageHandle, chunk: string): boolean {
      if (!owns(candidate) || snapshot.phase !== 'streaming') return false;
      if (snapshot.source.length + pending.length + chunk.length > limit) {
        error = sourceError();
        flush('error'); // Retain every previously accepted unit; reject this whole chunk.
        return false;
      }
      if (chunk) { pending += chunk; enqueue(); }
      return true;
    },
    complete(candidate: MessageHandle): boolean {
      if (!owns(candidate) || snapshot.phase !== 'streaming') return false;
      flush('complete');
      return true;
    },
    interrupt(candidate: MessageHandle): boolean {
      if (!owns(candidate) || snapshot.phase !== 'streaming') return false;
      flush('interrupted');
      return true;
    },
    /** A transport or fatal render failure is not a successful finalization. */
    fail(candidate: MessageHandle, cause: unknown): boolean {
      if (!isCurrent(candidate)) return false;
      const nextError = cause instanceof Error ? cause : new Error(String(cause));
      if (!isCurrent(candidate)) return false;
      error = nextError;
      flush('error');
      return true;
    },
    /** Save-only: no subscribers fire, and initialState must stay fixed per mount. */
    saveFields(candidate: MessageHandle, fields: Record<string, unknown>): boolean {
      if (!isCurrent(candidate)) return false;
      try {
        const copied = copyFields(fields);
        // Even a Proxy's inspection traps can retire the document synchronously.
        if (!isCurrent(candidate)) return false;
        savedFields = copied;
        error = null;
        return true;
      } catch (cause) {
        if (!isCurrent(candidate)) return false;
        const nextError = cause instanceof Error ? cause : new Error(String(cause));
        if (isCurrent(candidate)) error = nextError;
        return false;
      }
    },
    /** Read once at mount; reads remain valid for the same interrupted/error epoch. */
    getSavedFields(candidate: MessageHandle): Record<string, unknown> | undefined {
      return owns(candidate) ? copyFields(savedFields) : undefined;
    },
    /** Permanently release the host record; view unmount alone must not dispose it. */
    dispose() {
      if (disposed) return;
      disposed = true;
      try { cancelFrame(); }
      finally {
        pending = '';
        savedFields = {};
        error = null;
        snapshot = Object.freeze({ epoch: handle.epoch, source: '', phase: 'interrupted' });
        notificationPending = false;
        listeners.clear();
      }
    },
  };
}

export type MessageController = ReturnType<typeof createMessageController>;

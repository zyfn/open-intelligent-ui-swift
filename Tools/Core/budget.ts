// Native execution limits. They are host metadata, never Lang values or fields.
// One synchronous operation shares its work counter across recursive calls.
export const nativeBudgetLimits = Object.freeze({
  work: 100_000, nodes: 100_000, depth: 256, elements: 4_096, utf16: 1_048_576,
});
type Cost = { nodes: number; depth: number; elements: number; utf16: number };
type Reason = 'work' | 'depth' | 'output';
type Scope = { work: number; depth: number; reason?: Reason; memo: WeakMap<object, Cost> };
export type BudgetOutcome<T> = { value: T | null; limitExceeded: boolean; work: number };
const failedValues = new WeakSet<object>();
const materializationScopes = new WeakMap<object, Scope>();
// Only parser-owned static root snapshots are reusable across operations.
// Values supplied by state/tool/custom-function callbacks always use a local memo.
const staticRoots = new WeakMap<object, Cost>();
const limit = Object.freeze({ nativeBudget: true });
let active: Scope | undefined;
const scope = (): Scope => ({ work: 0, depth: 0, memo: new WeakMap() });
const object = (value: unknown): value is object => value !== null && typeof value === 'object';
const add = (a: number, b: number, max: number) => Math.min(max + 1, a + b);
const oversized: Cost = { nodes: nativeBudgetLimits.nodes + 1, depth: nativeBudgetLimits.depth + 1,
  elements: nativeBudgetLimits.elements + 1, utf16: nativeBudgetLimits.utf16 + 1 };

export function nativeBudgetExceeded(value: unknown): boolean {
  return object(value) && failedValues.has(value);
}
export function markBudgetExceeded<T extends object>(value: T): T {
  failedValues.add(value); return value;
}
export function isNativeBudgetError(error: unknown): boolean { return error === limit; }
export function hasActiveBudget(): boolean { return active !== undefined; }
function fail(state: Scope, reason: Reason): never {
  state.reason ??= reason; throw limit;
}
function exceeds(cost: Cost): boolean {
  return cost.nodes > nativeBudgetLimits.nodes || cost.depth > nativeBudgetLimits.depth
    || cost.elements > nativeBudgetLimits.elements || cost.utf16 > nativeBudgetLimits.utf16;
}
function appendCost(total: Cost, value: unknown, keyUnits: number, memo: WeakMap<object, Cost>, path: Set<object>): void {
  total.utf16 += keyUnits;
  if (!object(value)) {
    total.nodes++;
    if (typeof value === 'string') total.utf16 += value.length;
    return;
  }
  const next = cost(value, memo, path);
  total.nodes += next.nodes;
  total.elements += next.elements;
  total.utf16 += next.utf16;
  total.depth = Math.max(total.depth, next.depth + 1);
}

// Count occurrences in the projected tree, not unique identities. A shared
// subtree is measured once, then its cached cost is added at every reference.
// Saturation bounds both arithmetic and traversal; cycles cannot be projected.
function cost(value: unknown, memo: WeakMap<object, Cost>, path = new Set<object>()): Cost {
  if (!object(value)) return { nodes: 1, depth: 0, elements: 0,
    utf16: typeof value === 'string' ? Math.min(nativeBudgetLimits.utf16 + 1, value.length) : 0 };
  if (path.has(value) || path.size >= nativeBudgetLimits.depth) return oversized;
  const cached = memo.get(value);
  if (cached) return cached;
  const staticCost = staticRoots.get(value);
  if (staticCost) return staticCost;
  const total: Cost = { nodes: 1, depth: 1,
    elements: (value as any).type === 'element' ? 1 : 0, utf16: 0 };
  path.add(value);
  if (Array.isArray(value)) {
    if (value.length > nativeBudgetLimits.nodes) Object.assign(total, oversized);
    else for (let i = 0; i < value.length && !exceeds(total); i++) appendCost(total, value[i], 0, memo, path);
  } else {
    // Do not allocate Object.entries on an already oversized host object.
    for (const key in value) {
      if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
      appendCost(total, (value as any)[key], key.length, memo, path);
      if (exceeds(total)) break;
    }
  }
  // Each loop stops at the first exceeded metric, so intermediate sums stay
  // bounded. Saturate once per object instead of once per scalar field.
  if (exceeds(total)) {
    total.nodes = Math.min(total.nodes, nativeBudgetLimits.nodes + 1);
    total.depth = Math.min(total.depth, nativeBudgetLimits.depth + 1);
    total.elements = Math.min(total.elements, nativeBudgetLimits.elements + 1);
    total.utf16 = Math.min(total.utf16, nativeBudgetLimits.utf16 + 1);
  }
  path.delete(value); memo.set(value, total); return total;
}
function inspect(value: unknown, state: Scope, fresh = false): Cost {
  const measured = cost(value, fresh ? new WeakMap() : state.memo);
  if (exceeds(measured)) fail(state, 'output');
  return measured;
}

export function runBudget<T>(body: () => T): BudgetOutcome<T> {
  const previous = active, state = previous ?? scope();
  active = state;
  try {
    if (state.reason) throw limit;
    const value = body();
    if (state.reason) throw limit;
    // A fresh final pass also sees any in-place changes made by a host callback.
    inspect(value, state, true);
    return { value, limitExceeded: false, work: state.work };
  } catch (error) {
    if (!isNativeBudgetError(error)) throw error;
    return { value: null, limitExceeded: true, work: state.work };
  } finally { active = previous; }
}
export function reserveWork(amount = 1): void {
  if (!active) return;
  if (active.reason) throw limit;
  active.work = add(active.work, Math.max(0, amount), nativeBudgetLimits.work);
  if (active.work > nativeBudgetLimits.work) fail(active, 'work');
}
export function enterBudget(): Scope | undefined {
  const state = active;
  if (!state) return undefined;
  if (state.reason) throw limit;
  // This hot path consumes exactly one unit. A live scope cannot already be
  // over the limit, so the first rejection is 100001 without bulk arithmetic.
  if (++state.work > nativeBudgetLimits.work) fail(state, 'work');
  if (++state.depth > nativeBudgetLimits.depth) {
    state.depth--; fail(state, 'depth');
  }
  return state;
}
export function leaveBudget(state: Scope | undefined): void { if (state) state.depth--; }
export function budgetFrame<T>(body: () => T, context?: any): T {
  if (!active) {
    const outcome = runBudget(() => budgetFrame(body, context));
    if (outcome.limitExceeded) context?.reportNativeLimit?.();
    return outcome.value as T;
  }
  const state = enterBudget()!;
  try {
    const value = body();
    if (state.reason) throw limit;
    return value;
  } finally { leaveBudget(state); }
}
export function budgetBuiltin(name: string, fn: (args: any) => unknown, args: any): unknown {
  if (active) {
    const measured = inspect(args, active);
    reserveWork(measured.nodes);
    if (name === 'Sort' && Array.isArray(args.array))
      reserveWork(args.array.length * Math.ceil(Math.log2(Math.max(1, args.array.length))));
  }
  return fn(args);
}
export function budgetLiteral<T>(value: unknown, body: () => T): T {
  // Literal AST conversion allocates nodes and key/value containers per value.
  if (active) reserveWork(inspect(value, active).nodes * 3);
  return body();
}
export function budgetInput(value: unknown): void {
  if (active && object(value)) inspect(value, active);
}
export function budgetConcat(left: unknown, right: unknown): string {
  budgetInput(left); budgetInput(right);
  const a = String(left ?? ''), b = String(right ?? '');
  if (active && a.length + b.length > nativeBudgetLimits.utf16) fail(active, 'output');
  reserveWork(Math.ceil((a.length + b.length) / 64));
  return a + b;
}

function materializationFailure(ctx: any): void {
  if (ctx.nativeLimit) return;
  ctx.nativeLimit = true;
  ctx.errors.push({ source: 'parser', code: 'parse-exception',
    message: 'Native materialization or output budget exceeded.', statementId: ctx.currentStatementId });
}
export function materializationEvaluation<T>(ctx: any, body: () => T, fallback: T): T {
  if (ctx.nativeLimit) return fallback;
  let state = materializationScopes.get(ctx);
  if (!state) materializationScopes.set(ctx, state = scope());
  // All state defaults in this parse share the materializer's remaining work.
  // An evaluator here has no host callback; convert its private failure back
  // into this context before recordResult crosses the native boundary.
  const previous = active;
  active = state;
  try {
    const outcome = runBudget(body);
    if (outcome.limitExceeded || ctx.nativeLimit) {
      materializationFailure(ctx); return fallback;
    }
    return outcome.value as T;
  } finally { active = previous; }
}
export function materializationBudget<T>(ctx: any, body: () => T, fallback: T): T {
  if (ctx.nativeLimit) return fallback;
  let state = materializationScopes.get(ctx);
  if (!state) materializationScopes.set(ctx, state = scope());
  state.work++;
  if (++state.depth > nativeBudgetLimits.depth || state.work > nativeBudgetLimits.work) {
    state.depth--; materializationFailure(ctx); return fallback;
  }
  try {
    const value = body();
    if (ctx.nativeLimit || (object(value) && exceeds(cost(value, state.memo)))) {
      materializationFailure(ctx); return fallback;
    }
    return value;
  } finally { state.depth--; }
}
export function materializationReference<T>(ctx: any, value: T, fallback: T): T {
  if (ctx.nativeLimit) return fallback;
  const state = materializationScopes.get(ctx);
  if (!state || !object(value)) return value;
  // A memoized reference is cheap to resolve, but consumers such as validation
  // and dynamic-prop discovery may scan its expanded contents again. Charge
  // that occurrence before returning it to those consumers, not after a large
  // outer collection has already scanned the same shared subtree many times.
  const measured = cost(value, state.memo);
  state.work = add(state.work, measured.nodes, nativeBudgetLimits.work);
  if (exceeds(measured) || state.work > nativeBudgetLimits.work) {
    materializationFailure(ctx); return fallback;
  }
  return value;
}
export function recordParseBudget(result: any, ctx: any): boolean {
  // Before Swift's lazy root, state-default or AST projections touch this graph.
  const memo = new WeakMap<object, Cost>();
  if (!ctx.nativeLimit && exceeds(cost(result, memo))) materializationFailure(ctx);
  if (!ctx.nativeLimit && result.root?.hasDynamicProps === false) {
    const measured = memo.get(result.root);
    if (measured) staticRoots.set(result.root, measured);
  }
  if (!ctx.nativeLimit) return false;
  markBudgetExceeded(result); return true;
}

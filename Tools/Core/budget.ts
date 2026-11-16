// Native execution limits. They are host metadata, never Lang values or fields.
// One synchronous operation shares its work counter across recursive calls.
import { T, type Token } from '@openui/core-source/parser/tokens';
export const nativeBudgetLimits = Object.freeze({
  work: 100_000, nodes: 100_000, depth: 256, elements: 4_096, utf16: 1_048_576,
});
type Cost = { nodes: number; depth: number; elements: number; utf16: number };
type Reason = 'work' | 'depth' | 'output';
type Failure = Reason | { error: unknown };
type Scope = { work: number; maximumWork: number; depth: number; failure?: Failure;
  memo: WeakMap<object, Cost>; diagnostics?: Cost };
export type BudgetOutcome<T> = { value: T | null; limitExceeded: boolean; work: number };
type ParseBudgetError = { source: string; code: string; message: string; hint?: string; statementId?: string };
const failedValues = new WeakMap<object, ParseBudgetError | undefined>();
const materializationScopes = new WeakMap<object, Scope>();
// Only parser-owned static root snapshots are reusable across operations.
// Values supplied by state/tool/custom-function callbacks always use a local memo.
const staticRoots = new WeakMap<object, Cost>();
const limit = Object.freeze({ nativeBudget: true });
let active: Scope | undefined;
const scope = (maximumWork: number = nativeBudgetLimits.work): Scope => ({
  work: 0, depth: 0, memo: new WeakMap(),
  maximumWork: Number.isFinite(maximumWork)
    ? Math.max(0, Math.min(nativeBudgetLimits.work, Math.floor(maximumWork))) : 0,
});
const object = (value: unknown): value is object => value !== null && typeof value === 'object';
const add = (a: number, b: number, max: number) => Math.min(max + 1, a + b);
const oversized: Cost = { nodes: nativeBudgetLimits.nodes + 1, depth: nativeBudgetLimits.depth + 1,
  elements: nativeBudgetLimits.elements + 1, utf16: nativeBudgetLimits.utf16 + 1 };

export function nativeBudgetExceeded(value: unknown): boolean {
  return object(value) && failedValues.has(value);
}
export function markBudgetExceeded<T extends object>(value: T, error?: ParseBudgetError): T {
  failedValues.set(value, error); return value;
}
export function parseBudgetError(value: object): ParseBudgetError {
  const error = failedValues.get(value);
  if (error && !exceeds(cost(error, new WeakMap()))) return error;
  return { source: 'parser', code: 'parse-exception',
    message: 'Native materialization or output budget exceeded.',
    hint: 'The last valid prefix remains readable but is not executable. Replace or reset this document to resume.' };
}
export function isNativeBudgetError(error: unknown): boolean { return error === limit; }
// Native callbacks obtain the private token without throwing through the
// bridge's call/assert boundary, then install it as the JSContext exception.
// Also poison the active scope so swallowing the exception cannot resume work.
export function nativeInputFailure(): object {
  if (active) active.failure ??= 'output';
  return limit;
}
function throwFailure(state: Scope): never {
  if (typeof state.failure === 'object') throw state.failure.error;
  throw limit;
}

// Only an exception that escaped a native execution boundary is terminal.
// Ordinary prop/function diagnostics already handled by the core stay local.
// Poison an outer scope too: a native callback may inspect an inner outcome
// without throwing it, but that must not let the outer operation continue.
export function nativeExecutionFailure(error: unknown) {
  if (typeof active?.failure === 'object') error = active.failure.error;
  const budgetFailure = () => {
    if (active) active.failure ??= 'output';
    return { value: null, limitExceeded: true as const, work: active?.work ?? 0 };
  };
  if (isNativeBudgetError(error) || typeof active?.failure === 'string') return budgetFailure();
  const message = error instanceof Error && typeof error.message === 'string' ? error.message
    : typeof error === 'string' ? error : 'Unknown shared-core execution error.';
  const prefix = 'Native execution failed: ';
  const hint = 'The last valid prefix remains readable but is not executable. Replace or reset this document to resume.';
  // Check before constructing/crossing the diagnostic envelope, including its
  // fixed keys/metadata. An exception is not an unlimited output channel.
  if (message.length + prefix.length + hint.length + 64 > nativeBudgetLimits.utf16) return budgetFailure();
  if (active) active.failure ??= { error };
  return { error: { source: 'runtime', code: 'runtime-error', message: prefix + message, hint } };
}
export function nativeExecution<T>(body: () => T): T | ReturnType<typeof nativeExecutionFailure> {
  try { return body(); }
  catch (error) { return nativeExecutionFailure(error); }
}
export function hasActiveBudget(): boolean { return active !== undefined; }
const sourceOpenings = new Set([T.LParen, T.LBrack, T.LBrace]);
const sourceClosings = new Set([T.RParen, T.RBrack, T.RBrace]);
const sourceOperators = new Set([T.Plus, T.Minus, T.Star, T.Slash, T.Percent, T.Not,
  T.And, T.Or, T.EqEq, T.NotEq, T.Greater, T.Less, T.GreaterEq, T.LessEq, T.Question, T.Dot]);

// Use the official parser's tokens before Pratt recursion. Completed streaming
// statements have already passed this check; their occurrence counts are kept
// by that parser, including declarations later overwritten by the same ID.
// No second tokenize/preprocess/split pass is needed for a growing source.
export function checkSourceStatements(statements: readonly { tokens: Token[] }[],
  previousTokens = 0, previousStatements = 0, tokenComplete?: (token: Token) => boolean): number {
  if (previousStatements + statements.length > 4_096) throw nativeInputFailure();
  let total = previousTokens;
  for (const statement of statements) {
    let depth = 0, operators = 0;
    for (const token of statement.tokens) {
      const closing = sourceClosings.has(token.t);
      // autoClose adds advisory closing tokens to a pending tail. They are
      // parsed as before, but do not count as tokens received on the wire.
      if ((!closing || !tokenComplete || tokenComplete(token)) && ++total > 100_000)
        throw nativeInputFailure();
      if (sourceOpenings.has(token.t)) depth++;
      else if (closing) depth = Math.max(0, depth - 1);
      else if (sourceOperators.has(token.t)) operators++;
      if (depth > 128 || operators > 256) throw nativeInputFailure();
    }
  }
  return total;
}

export function parseWithSourceBudget<T extends { meta: { errors: unknown[] } }>(body: () => T, empty: () => T): T {
  try { return body(); }
  catch (error) {
    if (!isNativeBudgetError(error)) throw error;
    const result = empty();
    const diagnostic = { source: 'parser', code: 'parse-exception',
      message: 'Native input budget exceeded (100,000 tokens, 4,096 statements, 128 nesting levels or 256 operators per expression).',
      hint: 'The last valid prefix remains readable but is not executable. Replace or reset this document to resume.' };
    result.meta.errors.push(diagnostic);
    return markBudgetExceeded(result, diagnostic);
  }
}
function fail(state: Scope, reason: Reason): never {
  state.failure ??= reason; throwFailure(state);
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

export function budgetDiagnostic<T>(value: T): T {
  if (!active) return value;
  const measured = inspect(value, active, true);
  const total = active.diagnostics ??= { nodes: 1, depth: 1, elements: 0, utf16: 0 };
  total.nodes += measured.nodes;
  total.depth = Math.max(total.depth, measured.depth + 1);
  total.elements += measured.elements;
  total.utf16 += measured.utf16;
  if (exceeds(total)) fail(active, 'output');
  reserveWork(measured.nodes + Math.ceil(measured.utf16 / 64));
  return value;
}

export function runBudget<T>(body: () => T, maximumWork?: number): BudgetOutcome<T> {
  // Native action batches can lend their remaining allowance to this call.
  // Recursive/nested calls keep the active counter and cannot reset its cap.
  const previous = active, state = previous ?? scope(maximumWork);
  active = state;
  try {
    if (state.failure) throwFailure(state);
    const value = body();
    if (state.failure) throwFailure(state);
    // A fresh final pass also sees any in-place changes made by a host callback.
    inspect(value, state, true);
    return { value, limitExceeded: false, work: state.work };
  } catch (error) {
    if (!isNativeBudgetError(error)) throw error;
    if (typeof state.failure === 'object') throw state.failure.error;
    return { value: null, limitExceeded: true, work: state.work };
  } finally { active = previous; }
}
export function reserveWork(amount = 1): void {
  if (!active) return;
  if (active.failure) throwFailure(active);
  active.work = add(active.work, Math.max(0, amount), active.maximumWork);
  if (active.work > active.maximumWork) fail(active, 'work');
}
export function enterBudget(): Scope | undefined {
  const state = active;
  if (!state) return undefined;
  if (state.failure) throwFailure(state);
  // This hot path consumes exactly one unit. A live scope cannot already be
  // over the limit, so the first rejection is cap + 1 without bulk arithmetic.
  if (++state.work > state.maximumWork) fail(state, 'work');
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
    if (state.failure) throwFailure(state);
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
function budgetCoercion(value: unknown): void {
  if (!active || !object(value)) return;
  // String/abstract-equality conversion can expand a compact shared array even
  // when the final value is only a boolean. Charge every conversion, including
  // repeated calls in Each/Filter/Sort, before JavaScript starts that work.
  // A host callback may have changed this object since an earlier conversion.
  const measured = inspect(value, active, true);
  reserveWork(measured.nodes + Math.ceil(measured.utf16 / 64));
}
export function budgetString(value: unknown): string {
  budgetCoercion(value);
  const result = String(value);
  if (active && result.length > nativeBudgetLimits.utf16) fail(active, 'output');
  return result;
}
export function budgetEqual(left: unknown, right: unknown): boolean {
  // Object/object comparisons use identity; null/undefined do not coerce an
  // object either. Leave those cheap upstream comparisons untouched.
  if (object(left) && right != null && !object(right) && typeof right !== 'function') budgetCoercion(left);
  if (object(right) && left != null && !object(left) && typeof left !== 'function') budgetCoercion(right);
  return left == right;
}
export function budgetConcat(left: unknown, right: unknown): string {
  const a = budgetString(left ?? ''), b = budgetString(right ?? '');
  if (active && a.length + b.length > nativeBudgetLimits.utf16) fail(active, 'output');
  reserveWork(Math.ceil((a.length + b.length) / 64));
  return a + b;
}

function materializationFailure(ctx: any): void {
  if (ctx.nativeLimit) return;
  ctx.nativeLimit = true;
  const diagnostic = { source: 'parser', code: 'parse-exception',
    message: 'Native materialization or output budget exceeded.', statementId: ctx.currentStatementId };
  ctx.errors.push(diagnostic);
  markBudgetExceeded(ctx, diagnostic);
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
  markBudgetExceeded(result, failedValues.get(ctx)); return true;
}

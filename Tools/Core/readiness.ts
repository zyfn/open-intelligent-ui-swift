// Native presentation metadata. Syntax marks live only on parser-owned ASTs;
// evaluated values use a WeakMap so application data (including frozen values)
// gains no properties. Neither channel is part of the OpenUI protocol.
import { getCallDefs } from '@openui/core-source/parser/builtins';
import { recordParseBudget } from './budget';
const syntax = Symbol('native.source.syntax');
const closedSyntax = new WeakMap<object, boolean>();
// Only completed, parser-owned ASTs are registered. A closed tree without
// symbol/state/runtime references has context-independent closure and no Query
// dependencies. Cache that syntax fact, never a materialized Lang value.
const closedLocalDepth = new WeakMap<object, number>();
export function registerCompletedSyntax(node: any): void {
  const inspect = (value: any, depth: number): number | undefined => {
    if (!value || typeof value !== 'object') return 0;
    if (depth > 256) return undefined;
    if (Array.isArray(value)) {
      let maximum = 0;
      for (const item of value) {
        const height = inspect(item, depth);
        if (height === undefined) return undefined;
        maximum = Math.max(maximum, height);
      }
      return maximum;
    }
    const known = closedLocalDepth.get(value);
    if (known !== undefined) return known;
    if (value[syntax] === false || ['Ref', 'StateRef', 'RuntimeRef', 'Ph'].includes(value.k)) return undefined;
    if (typeof value.k !== 'string') return undefined;
    let maximum = 0;
    for (const child of Object.values(value)) {
      const height = inspect(child, depth + 1);
      if (height === undefined) return undefined;
      maximum = Math.max(maximum, height);
    }
    const height = maximum + 1;
    closedLocalDepth.set(value, height);
    return height;
  };
  inspect(node, 0);
}
type Placeholder = { name: string; id?: string; props: Record<string, string | number | boolean> };
type Presentation = { complete: boolean; closed: boolean; count?: number; queries?: string[]; observed?: boolean; children?: Record<string, Presentation>; slots?: (number | null)[]; pending?: Record<string, Presentation>; placeholder?: Placeholder };
// Most settled leaves have exactly these two bits. Share immutable metadata,
// never a Lang value: the native bridge can recognize it without projecting a
// dozen absent fields for every stable sibling on every streaming update.
const closedPresentation: Presentation = Object.freeze({ complete: true, closed: true });
const openPresentation: Presentation = Object.freeze({ complete: false, closed: false });
const presentationDefaults = Object.freeze([closedPresentation, openPresentation]);
export const sourcePresentationDefaults = (): readonly Presentation[] => presentationDefaults;
const defaultPresentation = (complete: boolean): Presentation => complete ? closedPresentation : openPresentation;
const presentation = new WeakMap<object, Presentation>();
const ready = new WeakMap<object, boolean>();
const nativeValues = new WeakMap<object, boolean>();
// Parser/native metadata belongs to the immutable value. Evaluation can use the
// same value in a different source context without rewriting that baseline.
// The native bridge keeps this opaque snapshot only while projecting its result.
type SourceSnapshot = {
  parent?: SourceSnapshot;
  ready: WeakMap<object, boolean>;
  presentation: WeakMap<object, Presentation>;
  descendants: WeakMap<object, SourceScope>;
  scopes: Map<string, SourceScope>;
};
type SourceConstraint = { pending: boolean; queries: string[] };
type SourceScope = SourceConstraint & { snapshot: SourceSnapshot };
type SourceContext = SourceSnapshot | SourceScope;
const snapshotOf = (context: SourceContext): SourceSnapshot => 'snapshot' in context ? context.snapshot : context;
const scopeOf = (context?: SourceContext): SourceScope | undefined => context && 'snapshot' in context ? context : undefined;
function sourceRecord<K extends 'ready' | 'presentation' | 'descendants'>(snapshot: SourceSnapshot | undefined, kind: K, value: object): ReturnType<SourceSnapshot[K]['get']> {
  for (let current = snapshot; current; current = current.parent) {
    const found = current[kind].get(value);
    if (found !== undefined) return found as ReturnType<SourceSnapshot[K]['get']>;
  }
  return undefined as ReturnType<SourceSnapshot[K]['get']>;
}
function newSourceSnapshot(parent?: SourceSnapshot): SourceSnapshot {
  return { parent, ready: new WeakMap(), presentation: new WeakMap(),
    descendants: new WeakMap(), scopes: new Map() };
}
let evaluating: SourceSnapshot | undefined;
export const currentSourceSnapshot = (): SourceSnapshot | undefined => evaluating;
export function sourceEvaluation<T extends object>(body: () => T): T & { sourceSnapshot: SourceSnapshot } {
  const previous = evaluating;
  const sourceSnapshot = newSourceSnapshot();
  evaluating = sourceSnapshot;
  try { return Object.assign(body(), { sourceSnapshot }); }
  finally { evaluating = previous; }
}
export function evaluateSource<T>(node: any, body: () => T): T {
  const parent = evaluating;
  if (!parent || node.k !== 'Comp' || node.name !== 'Each') return body();
  // Template evaluation can itself return an unfinished shared native value.
  // Keep those writes local too, before adding the loop's descendant constraint.
  const snapshot = newSourceSnapshot(parent);
  evaluating = snapshot;
  let value: T;
  try { value = body(); }
  finally { evaluating = parent; }
  if (value && typeof value === 'object') {
    const complete = sourceComplete(value, snapshot), details = sourcePresentation(value, snapshot);
    parent.ready.set(value, complete); parent.presentation.set(value, details);
    parent.descendants.set(value, { snapshot, pending: !complete, queries: details.queries ?? [] });
  }
  return value;
}
const memo = Symbol('native.source.memo');
const path = Symbol('native.source.path');
// This memo belongs to a materialization context, never to a protocol value.
const materialized = Symbol('native.presentation.materialized');
const emptyScope: ReadonlySet<string> = new Set();
const layoutProps = new Set(['height', 'imageSize', 'size', 'iconSize', 'variant', 'appearance', 'layout', 'direction', 'gap', 'align', 'justify', 'wrap', 'id', 'key', 'resourceId', 'category', 'name']);

export function tokenComplete(token: any): boolean { return token?.[syntax] !== false; }
export function tagSyntax<T extends object>(value: T, complete: boolean): T {
  if (!closedSyntax.has(value)) closedSyntax.set(value, complete);
  (value as any)[syntax] = complete; return value;
}
export function tagReady<T>(value: T, complete: boolean): T {
  if (value && typeof value === 'object') ready.set(value as object, complete);
  return value;
}
export function tagNativeSource<T extends object>(value: T, complete: boolean, details?: Presentation): T {
  if (details) presentation.set(value, details);
  nativeValues.set(value, complete); return tagReady(value, complete);
}
export function sourceComplete(value: any, context?: SourceContext): boolean {
  if (scopeOf(context)?.pending) return false;
  const snapshot = context && snapshotOf(context);
  return (value && typeof value === 'object' ? sourceRecord(snapshot, 'ready', value) ?? ready.get(value) : undefined)
    ?? value?.[syntax] ?? !value?.partial;
}

// Advisory source boundaries only. Kept out of enumerable values, AST/wire
// serialization and schema validation. Unknown expressions remain conservative.
export function sourcePresentation(value: any, context?: SourceContext): Presentation {
  const snapshot = context && snapshotOf(context), scope = scopeOf(context);
  const own = (value && typeof value === 'object' ? sourceRecord(snapshot, 'presentation', value) ?? presentation.get(value) : undefined)
    ?? defaultPresentation(sourceComplete(value, context));
  const queries = scope?.queries.length ? [...new Set([...(own.queries ?? []), ...scope.queries])] : own.queries;
  if (scope?.pending) return { complete: false, closed: false, queries,
    observed: scope.queries.length ? true : own.observed };
  return queries === own.queries ? own : { ...own, queries, observed: true };
}

/// Descendant constraints belong to an output occurrence, not a shared Lang
/// value. Each creates its own outer array; entering that array carries its
/// dependency scope without changing siblings that reuse the same child/plan.
/// Equal scopes are interned so shared subgraphs still project once per scope.
export function sourceChildSnapshot(value: any, context?: SourceContext): SourceContext | undefined {
  if (!context || !value || typeof value !== 'object') return context;
  const boundary = sourceRecord(snapshotOf(context), 'descendants', value);
  if (!boundary) return context;
  const snapshot = boundary.snapshot;
  const inherited = scopeOf(context);
  const pending = !!inherited?.pending || boundary.pending;
  const queries = [...new Set([...(inherited?.queries ?? []), ...boundary.queries])];
  if (!pending && !queries.length) return snapshot;
  const key = JSON.stringify([pending, queries]);
  let scope = snapshot.scopes.get(key);
  if (!scope) snapshot.scopes.set(key, scope = { snapshot, pending, queries });
  return scope;
}

/// The core maps prop arrays while evaluating their elements. Carry the
/// occurrence boundary onto that existing copy; never clone a Lang value just
/// to attach presentation metadata or change its identity inside evaluation.
export function copyEvaluationSource<T>(from: any, to: T): T {
  if (evaluating && from && typeof from === 'object' && to && typeof to === 'object') {
    const boundary = sourceRecord(evaluating, 'descendants', from);
    if (boundary) evaluating.descendants.set(to, boundary);
    const complete = sourceRecord(evaluating, 'ready', from), details = sourceRecord(evaluating, 'presentation', from);
    if (complete !== undefined) evaluating.ready.set(to, complete);
    if (details) evaluating.presentation.set(to, details);
  }
  return to;
}
export function copyPresentation<T>(from: any, to: T, observed?: Set<string>): T {
  // Materializer copies omit observed; evaluator copies always supply a Set.
  // A synchronous host callback can parse another document inside evaluation.
  const snapshot = observed === undefined ? undefined : evaluating;
  const previous = sourcePresentation(from, snapshot);
  const details = observed ? { ...previous,
    queries: [...new Set([...(previous.observed ? previous.queries ?? [] : []), ...observed])], observed: true } : previous;
  if (to && typeof to === 'object') {
    if (observed === undefined) {
      presentation.set(to as object, details);
      tagReady(to, sourceComplete(from));
    } else {
      snapshot?.presentation.set(to as object, details);
      snapshot?.ready.set(to as object, sourceComplete(from, snapshot));
    }
  }
  return to;
}
export function observeQueries(source: any, context: any): { context: any; queries: Set<string> } {
  const candidates = new Set(sourcePresentation(source).queries ?? []);
  if (source?.k === 'RuntimeRef' && source.refType === 'query') candidates.add(source.n);
  const queries = new Set<string>();
  if (!candidates.size) return { context, queries };
  return { queries, context: { ...context, resolveRef: (name: any) => {
    if (typeof name === 'string' && candidates.has(name)) queries.add(name);
    return context.resolveRef(name);
  } } };
}
export function finishMaterialization(node: any, ctx: any, value: any, scope: ReadonlySet<string> = emptyScope): any {
  const records: WeakMap<object, any> = ctx[materialized] ??= new WeakMap();
  if (node && typeof node === 'object') records.set(node, value);
  tagReady(value, astComplete(node, ctx, scope));
  if (!value || typeof value !== 'object') return value;
  presentation.set(value, describeSource(node, ctx, value, scope));
  return value;
}

export function recordResult(result: any, ctx: any, node: any, id?: string): any {
  if (recordParseBudget(result, ctx)) {
    presentation.set(result, openPresentation);
    return result;
  }
  if (result.root) presentation.set(result, sourcePresentation(result.root));
  else if (node && ctx[materialized]?.has(node) && ctx[materialized].get(node) === null) {
    const details = describeSource(node, ctx, null);
    if (details.placeholder && id) details.placeholder = { ...details.placeholder, id };
    presentation.set(result, details);
  }
  return result;
}

function describeSource(node: any, ctx: any, value: any, scope: ReadonlySet<string> = emptyScope): Presentation {
  const records: WeakMap<object, any> = ctx[materialized];
  let budget = 0;
  const seen = new Set<any>();
  const pending = openPresentation;
  const shape = (n: any, v: any): Presentation => {
    if (!n || typeof n !== 'object') return pending;
    if (++budget > 100000 || seen.size > 256 || seen.has(n) || ctx.nativeLimit) return pending;
    const complete = astComplete(n, ctx, scope);
    seen.add(n);
    try {
      if ((n.k === 'Ref' || n.k === 'StateRef') && ctx.syms?.has(n.n)) {
        if (n[syntax] === false) return pending;
        const target = shape(ctx.syms.get(n.n), v);
        return target.placeholder && n.k === 'Ref'
          ? { ...target, placeholder: { ...target.placeholder, id: n.n } } : target;
      }
      const component = n.k === 'Comp' && !getCallDefs(ctx.cat).has(n.name) ? ctx.cat?.get(n.name) : undefined;
      const omitted = n.k === 'Arr' && Array.isArray(v) && n.els.length !== v.length;
      if (complete && !omitted && !(component && v === null)) return closedPresentation;
      const result: Presentation = { complete, closed: complete || closedSyntax.get(n) === true };
      const children: Record<string, Presentation> = Object.create(null);
      if (n.k === 'Arr') {
        result.count = n.els.length;
        // Observe the already performed materialization; never evaluate a
        // missing node again, repair the Lang array or suppress diagnostics.
        const drops = n.els.map((child: any) => child.k === 'Ph'
          || (['Comp', 'Ref'].includes(child.k) && records.has(child) && records.get(child) === null));
        const known = n.els.every((child: any) => child.k === 'Ph' || records.has(child));
        if (Array.isArray(v) && known && drops.filter((drop: boolean) => !drop).length === v.length) {
          const slots: (number | null)[] = [];
          const missing: Record<string, Presentation> = Object.create(null);
          let index = 0;
          n.els.forEach((child: any, sourceIndex: number) => {
            if (drops[sourceIndex]) {
              slots.push(null);
              const detail = shape(child, null);
              if (detail.placeholder) missing[String(sourceIndex)] = detail;
            } else {
              slots.push(index);
              children[String(index)] = shape(child, v[index]);
              index++;
            }
          });
          if (omitted) result.slots = slots;
          if (Object.keys(missing).length) result.pending = missing;
        } else if (Array.isArray(v) && v.length === n.els.length) {
          n.els.forEach((child: any, i: number) => { children[String(i)] = shape(child, v[i]); });
        }
      } else if (n.k === 'Obj') {
        for (const [key, child] of n.entries) children[key] = shape(child, v?.[key]);
      } else if (component && (v?.type === 'element' || v === null)) {
        const props: Record<string, string | number | boolean> = Object.create(null);
        component.params.forEach((param: any, i: number) => {
          const supplied = i < n.args.length;
          const actual = v?.type === 'element' ? v.props?.[param.name]
            : supplied ? records.get(n.args[i]) : param.defaultValue;
          children[param.name] = supplied ? shape(n.args[i], actual)
            : defaultPresentation(result.closed);
          if (layoutProps.has(param.name) && children[param.name].complete
            && (typeof actual === 'string' || typeof actual === 'boolean' || (typeof actual === 'number' && Number.isFinite(actual)))) props[param.name] = actual;
        });
        if (v === null) {
          result.placeholder = { name: n.name, props };
          result.queries = queryDependencies(n, ctx, scope);
        }
      }
      if (Object.keys(children).length) result.children = children;
      return result;
    } finally { seen.delete(n); }
  };
  const result = shape(node, value);
  const queries = queryDependencies(node, ctx, scope);
  return queries.length ? { ...result, queries } : result;
}

function queryDependencies(node: any, ctx: any, scope: ReadonlySet<string> = emptyScope): string[] {
  if (node && typeof node === 'object' && closedLocalDepth.has(node)) return [];
  const queries = new Set<string>();
  const visited = new Set<any>();
  const collect = (n: any, local: ReadonlySet<string>, depth = 0) => {
    if (!n || typeof n !== 'object' || depth > 256 || visited.has(n) || visited.size >= 100000) return;
    // References can lead to completed, reference-free syntax too. Reuse the
    // same closure fact as the entry point without caching materialized values.
    if (closedLocalDepth.has(n)) return;
    visited.add(n);
    if (n.k === 'RuntimeRef') { if (n.refType === 'query') queries.add(n.n); return; }
    if (n.k === 'Ref' && !local.has(n.n)) {
      const target = ctx.syms?.get(n.n);
      if (target?.k === 'Comp' && target.name === 'Query') queries.add(n.n);
      else collect(target, local, depth + 1);
      return;
    }
    if (n.k === 'Comp') {
      const call = getCallDefs(ctx.cat).get(n.name);
      // A deferred action can retry a failed Query. It is not a dependency of
      // the currently displayed data and must not turn its owner into loading.
      if (call?.kind === 'action') return;
      const def = call ?? ctx.cat?.get(n.name);
      const variable = n.args?.[1];
      const name = variable?.k === 'Str' ? variable.v : variable?.k === 'Ref' ? variable.n : undefined;
      const nested = call?.lazy && name ? new Set([...local, name]) : local;
      (def ? n.args.slice(0, def.params.length) : []).forEach((arg: any, index: number) => {
        if (!(call?.lazy && index === 1)) collect(arg, index > 1 ? nested : local, depth + 1);
      });
      return;
    }
    for (const child of Object.values(n)) {
      if (Array.isArray(child)) child.forEach(v => Array.isArray(v) ? v.forEach(x => collect(x, local, depth + 1)) : collect(v, local, depth + 1));
      else if (child && typeof child === 'object' && 'k' in child) collect(child, local, depth + 1);
    }
  };
  collect(node, scope);
  return [...queries];
}

function astComplete(node: any, ctx: any, scope: ReadonlySet<string> = emptyScope, seen: Set<any> = ctx[path] ??= new Set()): boolean {
  if (!node || typeof node !== 'object') return true;
  if (seen.size > 256 || ctx.nativeLimit) return false;
  if (node[syntax] === false || node.k === 'Ph') return false;
  const localDepth = closedLocalDepth.get(node);
  // A deep alias path must not use this shortcut to cross the existing limit.
  if (localDepth !== undefined && seen.size + localDepth <= 257) return true;
  const key = scope.size ? [...scope].sort().join('\0') : '';
  const groups: Map<string, WeakMap<object, boolean>> = ctx[memo] ??= new Map();
  let cache = groups.get(key);
  if (!cache) groups.set(key, cache = new WeakMap());
  const known = cache.get(node);
  if (known !== undefined) return known;
  if (seen.has(node)) return false;
  seen.add(node);
  const child = (value: any, local = scope): boolean => astComplete(value, ctx, local, seen);
  let result = true;
  if (node.k === 'Ref' || node.k === 'StateRef') {
    // Opaque native captures and a control's injected $value are already bound.
    if (typeof node.n !== 'string' || scope.has(node.n) || node.n === '$value') result = true;
    else if (node.k === 'StateRef' && !ctx.syms?.has(node.n)) result = true;
    else result = ctx.syms ? ctx.syms.has(node.n) && child(ctx.syms.get(node.n)) : true;
  } else if (node.k === 'Comp') {
    const call = getCallDefs(ctx.cat).get(node.name);
    const definition = call ?? ctx.cat?.get(node.name);
    const lazy = call?.lazy;
    const variable = node.args?.[1];
    const name = variable?.k === 'Str' ? variable.v : variable?.k === 'Ref' ? variable.n : undefined;
    const nested = lazy && name ? new Set([...scope, name]) : scope;
    // Validation drops unsupported calls and excess arguments. Their unused
    // data must not become an unrelated control's readiness dependency.
    const args = definition ? node.args.slice(0, definition.params.length) : [];
    result = args.every((value: any, index: number) => lazy && name && index === 1 ? true : child(value, index > 1 ? nested : scope));
  } else {
    const visit = (value: any): boolean => Array.isArray(value)
      ? value.every(visit) : value && typeof value === 'object' && typeof value.k === 'string' ? child(value) : true;
    result = Object.values(node).every(visit);
  }
  seen.delete(node);
  cache.set(node, result);
  return result;
}

export function finishEvaluation(node: any, value: any, observed?: Set<string>): any {
  const complete = sourceComplete(node) && (value && typeof value === 'object' ? nativeValues.get(value) ?? true : true);
  const snapshot = evaluating;
  // Unscoped internal query evaluation only computes Lang data. Presentation
  // is projected by boundedEvaluate/boundedRoot with an explicit snapshot.
  if (!snapshot) return value;
  if (value && typeof value === 'object') {
    snapshot.ready.set(value, complete);
    const known = sourcePresentation(node);
    const queries = observed ? [...observed] : known.queries;
    snapshot.presentation.set(value, complete ? { complete: true, closed: true, queries, observed: observed !== undefined }
      : { ...known, complete: false, queries, observed: observed !== undefined });
  }
  return value;
}

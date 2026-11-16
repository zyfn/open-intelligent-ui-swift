import { capture, hasCapture, capturedValue, nativePlan, isNativePlan, isRuntimePlan, evaluationContext } from './captures';
export { capture, hasCapture, capturedValue, nativePlan, isRuntimePlan };
import { runBudget } from './budget';
import { sourceEvaluation } from './readiness';
export { nativeBudgetExceeded, nativeInputFailure } from './budget';
export { sourceComplete, sourcePresentation, tagNativeSource, currentSourceSnapshot } from './readiness';
import * as core from '@openui/core-source';
import { isASTNode } from '@openui/core-source/parser/ast';
import {
  stripFences,
  nativePreprocess,
} from '@openui/core-source/parser/parser';
import { URL, URLSearchParams } from 'whatwg-url';
Object.assign(globalThis, { URL, URLSearchParams });
const ids = new WeakMap<object, number>();
let next = 0;
export const identity = (value: object) => {
  let id = ids.get(value);
  if (!id) ids.set(value, (id = ++next));
  return id;
};
export const keys = Object.keys;
export const isAST = isASTNode;
export const api = core;
export const fences = stripFences;
export const library = (schema: any, bindings: Record<string, string[]>) => ({
  components: Object.fromEntries(
    Object.entries(schema.$defs ?? {}).map(([name, def]: [string, any]) => [
      name,
      {
        props: {
          shape: Object.fromEntries(
            Object.keys(def.properties ?? {}).map((k) => {
              const prop = {};
              if (bindings[name]?.includes(k)) core.markReactive(prop);
              return [k, prop];
            }),
          ),
        },
      },
    ]),
  ),
  toJSONSchema: () => schema,
});
export const store = core.createStore;
// Preserve missing versus explicitly undefined without copying every state key
// and value across the bridge for each lookup.
export function storeRead(store: any, name: string): { found: boolean, value?: unknown } {
  return Object.prototype.hasOwnProperty.call(store.getSnapshot(), name)
    ? { found: true, value: store.get(name) } : { found: false };
}
export const boundedEvaluate = (node: any, ctx: any, lib: any) =>
  sourceEvaluation(() => runBudget(() => core.evaluate(node, evaluationContext(ctx), { library: lib })));
export const evaluate = (node: any, ctx: any, lib: any) => boundedEvaluate(node, ctx, lib).value;
export const boundedRoot = (
  result: any,
  ctx: any,
  lib: any,
  store: any,
  errors: any[],
) => sourceEvaluation(() => runBudget(() => core.evaluateRoot(result, { ctx: evaluationContext(ctx), library: lib, store, errors })));
export const root = (result: any, ctx: any, lib: any, store: any, errors: any[]) =>
  boundedRoot(result, ctx, lib, store, errors).value;
// Invalid rule data must not leave an uncaught exception in the shared realm.
// Normal validation, unknown-rule leniency and first-error order stay upstream.
export function validate(value: unknown, rules: any[]): string | undefined {
  try { return core.validate(value, rules); }
  catch { return 'Validation could not complete: invalid rule or value.'; }
}
export const numberText = (value: number) => String(value);
export const truth = (value: any) => !!value;
export const equal = (a: any, b: any) => a == b;
export const queryManager = core.createQueryManager;
export const evaluateQueryStatements = (manager: any, statements: any, ctx: any) =>
  manager.evaluateStatements(statements, evaluationContext(ctx));
export const promise = (start: (resolve: any, reject: any) => void) =>
  new Promise(start);
export const error = (message: string) => new Error(message);
export const toolError = (name: string, available: string[]) =>
  new core.ToolNotFoundError(name, available);
export const mcpError = (message: string) => new core.McpToolError(message);
import { toNumber } from '@openui/core-source/parser/builtins';
export const dslNumber = toNumber;
export const stringValue = (value: any) => String(value);
export const preprocess = nativePreprocess;
// Lang 1.1 uses the parser's statement spans for merging. Keep native editing
// on that same algorithm, including multiline ternaries and comments.
export const splitSource = (source: string) =>
  core.split(core.tokenize(source)).map(statement =>
    source.slice(statement.start, statement.end).trimEnd());

export const merge = core.mergeStatements;
export const object = () => ({});
export const define = (object: any, key: string, value: any) =>
  Object.defineProperty(object, key, {
    value,
    writable: true,
    enumerable: true,
    configurable: true,
  });
export function extract(result: any) {
  try {
    return { value: core.extractToolResult(result) };
  } catch (error) {
    if (error instanceof core.McpToolError)
      return { error: error.toolErrorText };
    throw error;
  }
}
import { toLiteralAST } from '@openui/core-source/parser/ast';
function serializable(value: any): any {
  if (!value || typeof value !== 'object') return value;
  if (hasCapture(value)) {
    const valueAST = serializable(capturedValue(value));
    return isASTNode(valueAST) ? valueAST : toLiteralAST(valueAST);
  }
  if (nativeKinds.get(value) !== 'object' && core.isReactiveAssign(value))
    return value.expr?.k === 'StateRef' && value.expr.n === '$value'
      ? { k: 'StateRef', n: value.target }
      : { k: 'Assign', target: value.target, value: value.expr };
  if (nativeKinds.get(value) !== 'object' && isRuntimePlan(value)) {
    const steps = value.steps.map((step: any) => {
      let name: string, args: any[];
      switch (step.type) {
        case 'reset':
          name = 'Reset';
          args = step.targets.map((n: string) => ({ k: 'StateRef', n }));
          break;
        case 'set':
          name = 'Set';
          args = [{ k: 'StateRef', n: step.target }, step.valueAST];
          break;
        case 'run':
          name = 'Run';
          args = [
            { k: 'RuntimeRef', n: step.statementId, refType: step.refType },
          ];
          break;
        case 'open_url':
          name = 'OpenUrl';
          args = [toLiteralAST(step.url)];
          break;
        case 'continue_conversation':
          name = 'ToAssistant';
          args = [
            toLiteralAST(step.message),
            ...(step.context == null ? [] : [toLiteralAST(step.context)]),
          ];
          break;
        default:
          name = step.name;
          args = Object.values(step.params ?? {}).map(toLiteralAST);
      }
      return { k: 'Comp', name, args };
    });
    return steps.length === 1
      ? steps[0]
      : { k: 'Comp', name: 'Action', args: [{ k: 'Arr', els: steps }] };
  }
  if (Array.isArray(value)) return value.map(serializable);
  return Object.fromEntries(
    Object.entries(value).map(([key, v]) => [key, serializable(v)]),
  );
}
export const serialize = (tree: any, library: any, options: any) =>
  core.jsonToOpenUI(serializable(tree), library, {
    ...options,
    stateDeclarations: serializable(options.stateDeclarations),
  });

const nativeKinds = new WeakMap<object, string>();
export const tag = (value: object, kind: string) => {
  nativeKinds.set(value, kind);
  return value;
};
export const kind = (value: object) => nativeKinds.get(value);

import { ownSteps } from '@openui/core-source/runtime/evaluator';
export const actionSteps = (plan: any) =>
  isNativePlan(plan) ? plan.steps : ownSteps(plan).steps;

export { nativeAuthoring, nativeCompileSchema } from './authoring';

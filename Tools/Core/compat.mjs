// Explicit dependency export compatibility, shared-core corrections and budgets.
// Every replacement is checked against the pinned source; upgrades must review it.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

export const zodJSONSchemaCompatibility = Object.freeze({
  package: 'zod',
  version: '4.6.7',
  module: 'v4/core/to-json-schema.js',
  sourceSHA256: '85b883eb8f05e9f060c71a39fce7df9345b566af29d5bc9c8fa477fe616a051d',
  transformedSHA256: '38c767e92b86e8c6808531ca3c43f58075284af2eb6ca5503f02a0ef1efb26ec',
  reason: 'Preserve established anyOf union spelling, nesting and key order; Zod parsing, validation and collection security limits are unchanged.',
});

// Zod 4.6.7 introduced a final JSON Schema compaction pass after its public
// override callback. Disabling just that pass retains the existing schema
// contract, including nested/nullable unions, without attempting a lossy
// type-array rewrite or changing the security-fixed validators.
export function zodJSONSchemaCompatibilityPlugin() {
  const digest = source => createHash('sha256').update(source).digest('hex');
  let loaded = 0;
  return {
    name: 'native-zod-json-schema-unions',
    setup(build) {
      build.onStart(() => { loaded = 0; });
      build.onLoad({ filter: /\/zod\/v4\/core\/to-json-schema\.js$/, namespace: 'file' }, args => {
        const version = JSON.parse(readFileSync(join(dirname(args.path), '../../package.json'), 'utf8')).version;
        const source = readFileSync(args.path, 'utf8');
        if (version !== zodJSONSchemaCompatibility.version || digest(source) !== zodJSONSchemaCompatibility.sourceSHA256)
          throw Error('Review the pinned Zod JSON Schema export compatibility before upgrading');
        const contents = replaceOnce(source,
          `        if (ctx.target !== "openapi-3.0") {
            for (const entry of ctx.seen.entries()) {
                compactTypeUnion(entry[1].def ?? entry[1].schema);
            }
        }`,
          '        // Preserve the established native JSON Schema union representation.');
        if (digest(contents) !== zodJSONSchemaCompatibility.transformedSHA256)
          throw Error('Zod JSON Schema compatibility transform differs from its reviewed digest');
        loaded++;
        return { contents, loader: 'js' };
      });
      build.onEnd(result => {
        if (!result.errors.length && loaded !== 1)
          return { errors: [{ text: `Expected exactly one pinned Zod JSON Schema emitter, found ${loaded}` }] };
      });
    },
  };
}

export function replaceOnce(source, before, after) {
  if (source.split(before).length !== 2)
    throw Error(
      'Pinned compatibility patch no longer matches: ' + before.slice(0, 90),
    );
  return source.replace(before, after);
}
export function serializer(source) {
  const patches = [
    ['_side: "left" | "right",', 'side: "left" | "right",'],
    [
      'if (child.k !== "BinOp") return inner;',
      'if (child.k === "Ternary" || child.k === "Assign") return `(${inner})`;\n  if (child.k !== "BinOp") return inner;',
    ],
    [
      'if (childPrec < parentPrec) return `(${inner})`;',
      'if (childPrec < parentPrec || (side === "right" && childPrec === parentPrec)) return `(${inner})`;',
    ],
    [
      'return `${node.op}${serializeASTNode(node.operand, calls)}`;',
      'return `${node.op}${tight(node.operand, calls)}`;',
    ],
    [
      'return `${serializeASTNode(node.cond, calls)} ? ${serializeASTNode(node.then, calls)} : ${serializeASTNode(node.else, calls)}`;',
      'return `${node.cond.k === "Ternary" || node.cond.k === "Assign" ? "(" + serializeASTNode(node.cond, calls) + ")" : serializeASTNode(node.cond, calls)} ? ${serializeASTNode(node.then, calls)} : ${serializeASTNode(node.else, calls)}`;',
    ],
    [
      'return `${serializeASTNode(node.obj, calls)}.${node.field}`;',
      'return `${tight(node.obj, calls)}[${JSON.stringify(node.field)}]`;',
    ],
    [
      'return `${serializeASTNode(node.obj, calls)}[${serializeASTNode(node.index, calls)}]`;',
      'return `${tight(node.obj, calls)}[${serializeASTNode(node.index, calls)}]`;',
    ],
    [
      '`${k}: ${serializeASTNode(v, calls)}`',
      '`${key(k)}: ${serializeASTNode(v, calls)}`',
    ],
    [
      '`${k}: ${serializeValue(v, paramMap, collector)}`',
      '`${key(k)}: ${serializeValue(v, paramMap, collector)}`',
    ],
  ];
  for (const [before, after] of patches)
    source = replaceOnce(source, before, after);
  return (
    source +
    '\nfunction key(k:string){return /^[A-Za-z_][A-Za-z0-9_]*$/.test(k)?k:JSON.stringify(k);}\nfunction tight(n:ASTNode,c:ReadonlyMap<string,CallDef>){const text=serializeASTNode(n,c);return ["BinOp","UnaryOp","Ternary","Assign"].includes(n.k)?"("+text+")":text;}\n'
  );
}
export function materializer(source, budgetPath) {
  source = replaceOnce(source,
    'return scopedRefs.has(node.n) ? node : (resolveRef(node.n, ctx, "expr") as ASTNode);',
    'return scopedRefs.has(node.n) ? node : nativeReferenceBudget(ctx,resolveRef(node.n,ctx,"expr") as ASTNode,{k:"Null"});');
  source = replaceOnce(source, 'return resolveRef(node.n, ctx, "value");',
    'return nativeReferenceBudget(ctx,resolveRef(node.n,ctx,"value"),null);');
  source = replaceOnce(
    source,
    'export function materializeValue(node: ASTNode, ctx: MaterializeCtx): unknown {',
    `export function materializeValue(node: ASTNode, ctx: MaterializeCtx): unknown {
  return nativeBudget(ctx,()=>nativeMaterializeValue(node,ctx),null);
}
function nativeMaterializeValue(node: ASTNode, ctx: MaterializeCtx): unknown {`,
  );
  source = replaceOnce(
    source,
    `): ASTNode {
  switch (node.k) {`,
    `): ASTNode {
  return nativeBudget(ctx,()=>nativeMaterializeExpr(node,ctx,scopedRefs),{k:"Null"});
}
function nativeMaterializeExpr(node:ASTNode,ctx:MaterializeCtx,scopedRefs:ReadonlySet<string>):ASTNode {
  switch (node.k) {`,
  );
  return `import {materializationBudget as nativeBudget,materializationReference as nativeReferenceBudget} from ${JSON.stringify(budgetPath)};\n` + source;
}

// Bounded work wraps the official implementations; successful values and
// query scheduling still come from the pinned core. Exhaustion is a private
// signal, caught before a native bridge call or asynchronous reader returns.
export function evaluationBudget(source, kind, path) {
  const imports = `import {budgetFrame as nativeBudgetFrame,enterBudget as nativeEnterBudget,leaveBudget as nativeLeaveBudget,reserveWork as nativeReserveWork,budgetBuiltin as nativeBudgetBuiltin,budgetLiteral as nativeBudgetLiteral,budgetConcat as nativeBudgetConcat,budgetInput as nativeBudgetInput,isNativeBudgetError,hasActiveBudget as nativeHasBudget,runBudget as nativeRunBudget,nativeBudgetExceeded,markBudgetExceeded as nativeMarkBudgetExceeded,materializationEvaluation as nativeMaterializationEvaluation} from ${JSON.stringify(path)};\n`;
  if (kind === 'parser') {
    source = replaceOnce(source, 'function extractStatements(', `function extractStatements(stmts:Statement[],ctx:MaterializeCtx,partialRef?:PartialRef) {
  return nativeMaterializationEvaluation(ctx,()=>nativeExtractStatements(stmts,ctx,partialRef),{
    stateDeclarations:{},queryStatements:[],mutationStatements:[],
  });
}
function nativeExtractStatements(`);
    source = replaceOnce(source, 'function stateDefault(value: unknown, declared: Record<string, unknown>): unknown {', `function stateDefault(value: unknown, declared: Record<string, unknown>): unknown {
  const nativeScope=nativeEnterBudget();
  try {`);
    source = replaceOnce(source, '  return value;\n}\n\n/** True when every call', '  return value;\n  } finally { nativeLeaveBudget(nativeScope); }\n}\n\n/** True when every call');
    source = replaceOnce(source, '  if (Array.isArray(value)) return value.map((item) => stateDefault(item, declared));', '  if (Array.isArray(value)) { nativeReserveWork(value.length); return value.map((item) => stateDefault(item, declared)); }');
    source = replaceOnce(source, '    if (current.k === "Comp" && BUILTIN_CALLS.get(current.name)?.kind !== "function") ok = false;', '    nativeReserveWork();\n    if (current.k === "Comp" && BUILTIN_CALLS.get(current.name)?.kind !== "function") ok = false;');
  } else if (kind === 'evaluator') {
    source = replaceOnce(source, '): unknown {\n  switch (node.k) {', `): unknown {
  return nativeBudgetFrame(()=>nativeBudgetEvaluate(node,context,schemaCtx),context);
}
function nativeBudgetEvaluate(node:ASTNode,context:EvaluationContext,schemaCtx?:SchemaContext): unknown {
  switch (node.k) {`);
    source = replaceOnce(source, '): ElementNode {\n  if (el.hasDynamicProps === false) return el;', `): ElementNode {
  const nativeScope=nativeEnterBudget();
  try {
  if (el.hasDynamicProps === false) return el;`);
    source = replaceOnce(source, '  return { ...el, props: evaluated };\n}\n\n/**\n * Evaluate a single prop value', '  return { ...el, props: evaluated };\n  } finally { nativeLeaveBudget(nativeScope); }\n}\n\n/**\n * Evaluate a single prop value');
    source = replaceOnce(source, 'function substituteRef(node: ASTNode, varName: string, value: unknown): ASTNode {', `function substituteRef(node: ASTNode, varName: string, value: unknown): ASTNode {
  const nativeScope=nativeEnterBudget();
  try {`);
    source = replaceOnce(source, '  }\n}\n\nfunction mapValues(', '  }\n  } finally { nativeLeaveBudget(nativeScope); }\n}\n\nfunction mapValues(');
    source = replaceOnce(source, 'return node.n === varName ? toLiteralAST(value) : node;', 'return node.n === varName ? nativeBudgetLiteral(value,()=>toLiteralAST(value)) : node;');
    source = replaceOnce(source, '    return arr.map((item, _idx) => {', '    nativeReserveWork(arr.length);\n    return arr.map((item, _idx) => {');
    source = replaceOnce(source, '      return node.els.map((el) => evaluate(el, context));', '      nativeReserveWork(node.els.length);\n      return node.els.map((el) => evaluate(el, context));');
    source = replaceOnce(source, '      return Object.fromEntries(node.entries.map(([k, v]) => [k, evaluate(v, context)]));', '      nativeReserveWork(node.entries.length);\n      return Object.fromEntries(node.entries.map(([k, v]) => [k, evaluate(v, context)]));');
    source = replaceOnce(source, '              props[key] = val.map((item) =>', '              nativeReserveWork(val.length);\n              props[key] = val.map((item) =>');
    source = replaceOnce(source, '        return obj.map((item: any) => item?.[node.field] ?? null);', '        nativeReserveWork(obj.length);\n        return obj.map((item: any) => item?.[node.field] ?? null);');
    source = replaceOnce(source, 'return builtin.fn!(evaluateArgs(node, context));', 'return nativeBudgetBuiltin(node.name,builtin.fn!,evaluateArgs(node,context));');
    source = replaceOnce(source, 'return String(left ?? "") + String(right ?? "");', 'return nativeBudgetConcat(left,right);');
    source = replaceOnce(source, '  const ctx = { errors: [], partial: false } as unknown as MaterializeCtx;', '  nativeBudgetInput(value);\n  const ctx = { errors: [], partial: false } as unknown as MaterializeCtx;');
    source = replaceOnce(source, '  } catch (e) {\n    context.reportError?', '  } catch (e) {\n    if (isNativeBudgetError(e)) throw e;\n    context.reportError?');
  } else if (kind === 'evaluate-tree') {
    source = replaceOnce(source, 'export function evaluateElementProps(el: ElementNode, evalCtx: EvalContext): ElementNode {', `export function evaluateElementProps(el: ElementNode, evalCtx: EvalContext): ElementNode {
  return nativeBudgetFrame(()=>nativeBudgetElementProps(el,evalCtx),evalCtx.ctx);
}
function nativeBudgetElementProps(el: ElementNode, evalCtx: EvalContext): ElementNode {`);
    source = replaceOnce(source, '    } catch (e) {\n      // Use raw value', '    } catch (e) {\n      if (isNativeBudgetError(e)) throw e;\n      // Use raw value');
  } else if (kind === 'evaluate-prop') {
    source = replaceOnce(source, '  const result = evaluatePropValue(value, context, schemaCtx, reactiveSchema, callbacks);', `  const nativeScope=nativeEnterBudget();
  try {
  const result = evaluatePropValue(value, context, schemaCtx, reactiveSchema, callbacks);`);
    source = replaceOnce(source, '  return isActionPlan(result) ? ownSteps(result) : result;\n}', '  return isActionPlan(result) ? ownSteps(result) : result;\n  } finally { nativeLeaveBudget(nativeScope); }\n}');
    source = replaceOnce(source, '      return result.map((item) =>', '      nativeReserveWork(result.length);\n      return result.map((item) =>');
    source = replaceOnce(source, '    return value.map((v) => callbacks.recurse(v, reactiveSchema));', '    nativeReserveWork(value.length);\n    return value.map((v) => callbacks.recurse(v, reactiveSchema));');
  } else if (kind === 'query-manager') {
    source = replaceOnce(source, '): QueryNode {\n  const toolName', `): QueryNode {
  const outcome=nativeRunBudget(()=>nativeBudgetQueryNode(statement,context,extraDeps));
  if (!outcome.limitExceeded) return outcome.value as QueryNode;
  if (!nativeHasBudget()) (context as EvaluationContext & {reportNativeLimit?:()=>void}).reportNativeLimit?.();
  return nativeMarkBudgetExceeded({statementId:statement.statementId,toolName:"",args:null,defaults:null,deps:null,complete:false});
}
function nativeBudgetQueryNode(statement:QueryStatementInfo,context:EvaluationContext,extraDeps?: (toolName:string)=>Record<string,unknown>|undefined):QueryNode {
  const toolName`);
    source = replaceOnce(source, '  let disposed = false;', '  let disposed = false;\n  let nativeReportLimit: (()=>void) | undefined;');
    source = replaceOnce(source, '    statements = next;', '    statements = next;\n    nativeReportLimit=()=> (context as EvaluationContext & {reportNativeLimit?:()=>void}).reportNativeLimit?.();');
    source = replaceOnce(source, '    applyNodes(next.map(buildNode));', `    const nativeNodes=nativeBuildNodes(()=>next.map(statement=>{
      const node=buildNode(statement); nativeReserveWork(); return node;
    }));
    if (!nativeNodes) return;
    applyNodes(nativeNodes);`);
    source = replaceOnce(source, '      applyNodes(statements.map((s) => (stale.has(s) ? buildNode(s) : nodes.get(s.statementId)!)));', `      const nativeNodes=nativeBuildNodes(()=>statements.map(s=>{
        const node=stale.has(s)?buildNode(s):nodes.get(s.statementId)!;
        nativeReserveWork(); return node;
      }));
      if (!nativeNodes) return;
      applyNodes(nativeNodes);`);
    source = replaceOnce(source, '  function applyNodes(queryNodes: QueryNode[]) {', `  function nativeBuildNodes(build:()=>QueryNode[]):QueryNode[]|null {
    const outcome=nativeRunBudget(build);
    if (outcome.limitExceeded) { nativeReportLimit?.(); dispose(); return null; }
    return outcome.value;
  }

  function applyNodes(queryNodes: QueryNode[]) {`);
    source = replaceOnce(source, '  function applyNodes(queryNodes: QueryNode[]) {\n    if (disposed) return;', `  function applyNodes(queryNodes: QueryNode[]) {
    if (disposed) return;
    if (queryNodes.some(nativeBudgetExceeded)) { dispose(); return; }`);
  } else throw Error('Unknown evaluation budget module: ' + kind);
  return imports + source;
}

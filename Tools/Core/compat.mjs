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

export function sourcePreprocessing(source, path) {
  const start = source.indexOf('/** Text that starts an OpenUI Lang statement');
  const end = source.indexOf('/**\n * Parse a complete openui-lang string');
  if (start < 0 || end <= start) throw Error('Review pinned parser preprocessing boundaries');
  // Replace the old batch helpers, rather than retaining a second normalizer.
  // Public stripFences and nativePreprocess use the same line rules as streaming.
  source = replaceOnce(source, source.slice(start, end),
    `import {SourcePreprocessor,preprocess} from ${JSON.stringify(path)};\nexport {stripFences} from ${JSON.stringify(path)};\n\n`);
  source = replaceOnce(source, '  let buf = ""; // raw accumulated input (kept for set() diffing)',
    '  let buf = ""; // raw accumulated input (kept for set() diffing)\n  let preprocessing = new SourcePreprocessor();');
  source = replaceOnce(source,
    '    const next = preprocess(buf);\n    if (!next.startsWith(cleaned.slice(0, completedEnd))) {',
    '    const next = preprocessing.read();\n    if (next.changedFrom < completedEnd) {');
  source = replaceOnce(source, '    cleaned = next;', '    cleaned = next.text;');
  source = replaceOnce(source, '    buf = "";\n    cleaned = "";',
    '    buf = "";\n    preprocessing = new SourcePreprocessor();\n    cleaned = "";');
  source = replaceOnce(source, '      buf += chunk;\n      return currentResult(complete);',
    '      buf += chunk;\n      preprocessing.append(chunk);\n      return currentResult(complete);');
  source = replaceOnce(source, '      if (delta) buf += delta;',
    '      if (delta) { buf += delta; preprocessing.append(delta); }');
  source = replaceOnce(source,
    '  // Recompute `cleaned` from `buf`. If the already-completed prefix is no longer\n  // a prefix of the new cleaned text (e.g. an opening ```fence``` just appeared\n  // and shifted the stripped output), the watermark + cache are stale, so reset\n  // and re-scan. When the prefix is stable (the common streaming case) the cache\n  // is kept; pending text is overlaid on a copy when building the current result.',
    '  // The preprocessor consumes completed lines once. A changed fence selection\n  // or unfinished line can revise the output; only invalidate completed ASTs\n  // when that revision reaches their prefix. No full-prefix comparison is needed.');
  return source;
}

// Bounded work wraps the official implementations; successful values and
// query scheduling still come from the pinned core. Exhaustion is a private
// signal, caught before a native bridge call or asynchronous reader returns.
export function evaluationBudget(source, kind, path) {
  const imports = `import {budgetFrame as nativeBudgetFrame,enterBudget as nativeEnterBudget,leaveBudget as nativeLeaveBudget,reserveWork as nativeReserveWork,budgetBuiltin as nativeBudgetBuiltin,budgetLiteral as nativeBudgetLiteral,budgetConcat as nativeBudgetConcat,budgetInput as nativeBudgetInput,budgetString as nativeBudgetString,budgetEqual as nativeBudgetEqual,budgetDiagnostic as nativeBudgetDiagnostic,isNativeBudgetError,hasActiveBudget as nativeHasBudget,runBudget as nativeRunBudget,nativeBudgetExceeded,markBudgetExceeded as nativeMarkBudgetExceeded,materializationEvaluation as nativeMaterializationEvaluation,nativeExecutionFailure} from ${JSON.stringify(path)};\n`;
  if (kind === 'lexer') {
    // Raw source size is checked before the merge enters the lexer. One charge
    // per outer iteration bounds token allocation and otherwise ignored input;
    // long strings/comments/whitespace were already charged by UTF-16 size.
    source = replaceOnce(source, '  const n = src.length;', '  const n = src.length;\n  const nativeBudgeted = nativeHasBudget();');
    source = replaceOnce(source, '\n  while (i < n) {', '\n  while (i < n) {\n    if (nativeBudgeted) nativeReserveWork();');
  } else if (kind === 'expressions') {
    source = replaceOnce(source, 'export function parseExpression(tokens: Token[]): ASTNode {',
      'export function parseExpression(tokens: Token[]): ASTNode {\n  const nativeBudgeted = nativeHasBudget();');
    source = replaceOnce(source, '  function parseExpr(minPrec: number = 0): ASTNode {',
      '  function parseExpr(minPrec: number = 0): ASTNode {\n    const nativeScope = nativeBudgeted ? nativeEnterBudget() : undefined;\n    try {');
    source = replaceOnce(source, '  }\n\n  // ── Prefix / atoms',
      '    } finally { if (nativeScope) nativeLeaveBudget(nativeScope); }\n  }\n\n  // ── Prefix / atoms');
  } else if (kind === 'statements') {
    source = replaceOnce(source, 'export function split(tokens: Token[]): RawStmt[] {',
      'export function split(tokens: Token[]): RawStmt[] {\n  nativeReserveWork(tokens.length);\n  let nativeNextNonNewline = 0;');
    // A run of newlines before a ternary operator used to be rescanned from
    // every newline. Reuse the same endpoint inside this one split operation.
    source = replaceOnce(source, '        let peek = pos + 1;', '        let peek = Math.max(pos + 1, nativeNextNonNewline);');
    source = replaceOnce(source, '        while (peek < tokens.length && tokens[peek].t === T.Newline) peek++;',
      '        while (peek < tokens.length && tokens[peek].t === T.Newline) peek++;\n        nativeNextNonNewline = peek;');
  } else if (kind === 'merge') {
    source = replaceOnce(source, '  return split(tokenize(input)).map((stmt) => ({',
      '  const statements = split(tokenize(input));\n  nativeReserveWork(statements.length);\n  return statements.map((stmt) => ({');
    source = replaceOnce(source, 'function collectRefs(node: ASTNode, out: Set<string>): void {',
      'function collectRefs(node: ASTNode, out: Set<string>): void {\n  nativeBudgetInput(node);');
    source = replaceOnce(source, '  walkAST(node, (current) => {', '  walkAST(node, (current) => {\n    nativeReserveWork();');
    for (const header of [
      '  while (queue.length > 0) {',
      '    for (const ref of refs) {',
      '  for (const id of order) {',
      '  for (let i = order.length - 1; i >= 0; i--) {',
      '  for (const stmt of existingStmts) {',
      '  for (const stmt of patchStmts) {',
    ]) source = replaceOnce(source, header, header + '\n    nativeReserveWork();');
    source = replaceOnce(source, '      order.splice(i, 1);',
      '      nativeReserveWork(order.length - i - 1);\n      order.splice(i, 1);');
    // indexOf scans a prefix, then splice shifts its suffix. Their combined
    // work is bounded by this full order length, including a missing ID.
    source = replaceOnce(source, '      const idx = order.indexOf(stmt.id);',
      '      nativeReserveWork(order.length);\n      const idx = order.indexOf(stmt.id);');
    source = replaceOnce(source, '  return order\n', '  nativeReserveWork(order.length * 2);\n  return order\n');
  } else if (kind === 'parser') {
    source = `import {checkSourceStatements as nativeCheckSourceStatements,parseWithSourceBudget as nativeParseWithSourceBudget} from ${JSON.stringify(path)};\n` + source;
    source = replaceOnce(source, 'export function parse(input: string, cat: ParamMap, rootName?: string): ParseResult {',
      `export function parse(input: string, cat: ParamMap, rootName?: string): ParseResult {
  return nativeParseWithSourceBudget(()=>nativeParseSource(input,cat,rootName),()=>nativeTagReady(emptyResult(true),false));
}
function nativeParseSource(input:string,cat:ParamMap,rootName?:string):ParseResult {`);
    source = replaceOnce(source, '  const stmts = split(tokenize(text));',
      '  const stmts = split(tokenize(text));\n  nativeCheckSourceStatements(stmts,0,0,nativeTokenComplete);');
    source = replaceOnce(source, '  let completedCount = 0;',
      '  let completedCount = 0;\n  let nativeCompletedTokens = 0;');
    source = replaceOnce(source, '    for (const s of split(tokenize(t))) {',
      `    const nativeStatements = split(tokenize(t));
    nativeCompletedTokens = nativeCheckSourceStatements(nativeStatements,nativeCompletedTokens,completedCount);
    for (const s of nativeStatements) {`);
    source = replaceOnce(source, '      completedCount = 0;',
      '      completedCount = 0;\n      nativeCompletedTokens = 0;');
    source = replaceOnce(source, '    completedCount = 0;\n  }',
      '    completedCount = 0;\n    nativeCompletedTokens = 0;\n  }');
    source = replaceOnce(source, '  function currentResult(complete = false): ParseResult {',
      `  function currentResult(complete = false): ParseResult {
    return nativeParseWithSourceBudget(()=>nativeCurrentResult(complete),()=>nativeTagReady(emptyResult(true),false));
  }
  function nativeCurrentResult(complete = false): ParseResult {`);
    source = replaceOnce(source, '    const stmts = split(tokenize(closed));',
      '    const stmts = split(tokenize(closed));\n    nativeCheckSourceStatements(stmts,nativeCompletedTokens,completedCount,nativeTokenComplete);');
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
  } else if (kind === 'builtins') {
    source = replaceOnce(source, '      const f = String(field ?? "");\n      const desc = String(direction ?? "asc") === "desc";',
      '      const f = nativeBudgetString(field ?? "");\n      const desc = nativeBudgetString(direction ?? "asc") === "desc";');
    source = replaceOnce(source, '      const f = String(field ?? "");\n      const o = String(operator ?? "==");',
      '      const f = nativeBudgetString(field ?? "");\n      const o = nativeBudgetString(operator ?? "==");');
    source = replaceOnce(source, 'String(av ?? "").localeCompare(String(bv ?? ""))', 'nativeBudgetString(av ?? "").localeCompare(nativeBudgetString(bv ?? ""))');
    source = replaceOnce(source, 'String(v ?? "").includes(String(value ?? ""))', 'nativeBudgetString(v ?? "").includes(nativeBudgetString(value ?? ""))');
    source = replaceOnce(source, 'return v == value;', 'return nativeBudgetEqual(v,value);');
    source = replaceOnce(source, 'return v != value;', 'return !nativeBudgetEqual(v,value);');
    source = replaceOnce(source, 'message: String(message ?? ""),', 'message: nativeBudgetString(message ?? ""),');
    source = replaceOnce(source, 'url: String(url ?? "")', 'url: nativeBudgetString(url ?? "")');
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
    source = replaceOnce(source, 'return left == right;', 'return nativeBudgetEqual(left,right);');
    source = replaceOnce(source, 'return left != right;', 'return !nativeBudgetEqual(left,right);');
    source = replaceOnce(source, 'return obj[String(idx)];', 'return obj[nativeBudgetString(idx)];');
    source = replaceOnce(source, 'e instanceof Error ? e.message : String(e)', 'e instanceof Error ? e.message : nativeBudgetString(e)');
    source = replaceOnce(source, '  const ctx = { errors: [], partial: false } as unknown as MaterializeCtx;', '  nativeBudgetInput(value);\n  const ctx = { errors: [], partial: false } as unknown as MaterializeCtx;');
    source = replaceOnce(source, '  } catch (e) {\n    context.reportError?', '  } catch (e) {\n    if (isNativeBudgetError(e)) throw e;\n    context.reportError?');
  } else if (kind === 'evaluate-tree') {
    source = replaceOnce(source, '\n    evalCtx.errors?.push({', '\n    evalCtx.errors?.push(nativeBudgetDiagnostic({');
    source = replaceOnce(source, '      hint: `Check the expression used for prop "${key}"`,\n    });',
      '      hint: `Check the expression used for prop "${key}"`,\n    }));');
    source = replaceOnce(source, '\n  evalCtx.errors?.push({', '\n  evalCtx.errors?.push(nativeBudgetDiagnostic({');
    source = replaceOnce(source, '    message: "root does not evaluate to a component",\n  });',
      '    message: "root does not evaluate to a component",\n  }));');
    source = replaceOnce(source, 'export function evaluateElementProps(el: ElementNode, evalCtx: EvalContext): ElementNode {', `export function evaluateElementProps(el: ElementNode, evalCtx: EvalContext): ElementNode {
  return nativeBudgetFrame(()=>nativeBudgetElementProps(el,evalCtx),evalCtx.ctx);
}
function nativeBudgetElementProps(el: ElementNode, evalCtx: EvalContext): ElementNode {`);
    source = replaceOnce(source, '    } catch (e) {\n      // Use raw value', '    } catch (e) {\n      if (isNativeBudgetError(e)) throw e;\n      // Use raw value');
    source = replaceOnce(source, 'e instanceof Error ? e.message : String(e)', 'e instanceof Error ? e.message : nativeBudgetString(e)');
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
    source = replaceOnce(source, '  let disposed = false;', '  let disposed = false;\n  let nativeReportLimit: (()=>void) | undefined;\n  let nativeReportFailure: ((error:unknown)=>void) | undefined;');
    source = replaceOnce(source, '    statements = next;', '    statements = next;\n    nativeReportLimit=()=> (context as EvaluationContext & {reportNativeLimit?:()=>void}).reportNativeLimit?.();\n    nativeReportFailure=error=> (context as EvaluationContext & {reportNativeFailure?:(error:unknown)=>void}).reportNativeFailure?.(error);');
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
    try {
      const outcome=nativeRunBudget(build);
      if (outcome.limitExceeded) { nativeReportLimit?.(); dispose(); return null; }
      return outcome.value;
    } catch (error) {
      const failure=nativeExecutionFailure(error);
      if ('error' in failure) nativeReportFailure?.(failure.error);
      else nativeReportLimit?.();
      dispose();
      return null;
    }
  }

  function applyNodes(queryNodes: QueryNode[]) {`);
    source = replaceOnce(source, '  function applyNodes(queryNodes: QueryNode[]) {\n    if (disposed) return;', `  function applyNodes(queryNodes: QueryNode[]) {
    if (disposed) return;
    if (queryNodes.some(nativeBudgetExceeded)) { dispose(); return; }`);
  } else throw Error('Unknown evaluation budget module: ' + kind);
  return imports + source;
}

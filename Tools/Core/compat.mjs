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
  const imports = `import {budgetFrame as nativeBudgetFrame,enterBudget as nativeEnterBudget,leaveBudget as nativeLeaveBudget,reserveWork as nativeReserveWork,budgetBuiltin as nativeBudgetBuiltin,budgetLiteral as nativeBudgetLiteral,budgetConcat as nativeBudgetConcat,budgetInput as nativeBudgetInput,budgetString as nativeBudgetString,budgetEqual as nativeBudgetEqual,isNativeBudgetError,hasActiveBudget as nativeHasBudget,runBudget as nativeRunBudget,nativeBudgetExceeded,markBudgetExceeded as nativeMarkBudgetExceeded,materializationEvaluation as nativeMaterializationEvaluation} from ${JSON.stringify(path)};\n`;
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
    // A request belongs to its existing cache entry. Its first statement can
    // disappear while another statement still consumes the same request; a
    // newly created entry with the same key must never receive old completion.
    source = replaceOnce(source, '    q.loading = true;\n    rebuildSnapshot();', `    const isCurrent = () => {
      if (disposed || cache.get(fetchKey) !== entry) return false;
      if (queries.get(statementId) === q && q.cacheKey === fetchKey) return true;
      for (const current of queries.values()) if (current.cacheKey === fetchKey) return true;
      return false;
    };
    for (const current of queries.values()) if (current.cacheKey === fetchKey) current.loading = true;
    rebuildSnapshot();`);
    source = replaceOnce(source,
      'const data = await toolProvider.callTool(toolName, (args as Record<string, unknown>) ?? {});',
      `const data = await (toolProvider.callTool as any)(toolName, (args as Record<string, unknown>) ?? {},
        isCurrent);`);
    source = replaceOnce(source, `      if (disposed) return;
      // Stale: the query was removed or its key changed
      const current = queries.get(statementId);
      if (!current || current.cacheKey !== fetchKey) {
        entry.inFlight = false;
        return;
      }

      entry.data = data ?? null;
      entry.failed = false;
      current.everFetched = true;
      for (const q of queries.values()) if (q.cacheKey === fetchKey) q.error = undefined;

      // Clear prevCacheKey first so cleanup does not see it as in use
      if (current.prevCacheKey && current.prevCacheKey !== fetchKey) {
        const prevKey = current.prevCacheKey;
        current.prevCacheKey = undefined;
        cleanupCacheEntry(prevKey);
      }`, `      if (!isCurrent()) return;
      entry.data = data ?? null;
      entry.failed = false;
      const previousKeys = new Set<string>();
      for (const current of queries.values()) {
        if (current.cacheKey !== fetchKey) continue;
        const previousKey = acceptCacheResult(current);
        if (previousKey) previousKeys.add(previousKey);
      }
      for (const key of previousKeys) cleanupCacheEntry(key);`);
    source = replaceOnce(source, '    } catch (err) {\n      const failure =',
      '    } catch (err) {\n      if (!isCurrent()) return;\n      const failure =');
    source = replaceOnce(source, `    } finally {
      entry.inFlight = false;
      const current = queries.get(statementId);
      if (current && current.cacheKey === fetchKey) {
        current.loading = false;
        if (rebuildSnapshot()) notify();
        if (current.needsRefetch) {
          current.needsRefetch = false;
          executeFetch(current.cacheKey, statementId);
        }
      } else {
        if (rebuildSnapshot()) notify();
      }
      reevaluateReaders();
    }`, `    } finally {
      entry.inFlight = false;
      if (!isCurrent()) return;
      let refetch = false;
      for (const current of queries.values()) {
        if (current.cacheKey !== fetchKey) continue;
        current.loading = false;
        refetch ||= current.needsRefetch;
        current.needsRefetch = false;
      }
      if (rebuildSnapshot()) notify();
      // A synchronous listener can retire this entry or start its refresh.
      if (!isCurrent()) return;
      if (refetch && !entry.inFlight) {
        for (const [sid, current] of queries) {
          if (current.cacheKey !== fetchKey) continue;
          executeFetch(fetchKey, sid);
          break;
        }
      }
      reevaluateReaders();
    }`);
    source = replaceOnce(source, '  /** Remove a cache entry if no query references it. */', `  /** Accept current data, whether a request just finished or the key was cached. */
  function acceptCacheResult(q: QueryEntry): string | undefined {
    q.everFetched = true;
    q.error = undefined;
    const previousKey = q.prevCacheKey;
    q.prevCacheKey = undefined;
    return previousKey && previousKey !== q.cacheKey ? previousKey : undefined;
  }

  /** Remove a cache entry if no query references it. */`);
    // A later node in the same patch can adopt a released key. Decide whether
    // it is unused only after all current/previous key references are updated.
    source = replaceOnce(source,
      '    const activeIds = new Set(queryNodes.map((n) => n.statementId));',
      '    const activeIds = new Set(queryNodes.map((n) => n.statementId));\n    const cacheKeysToClean = new Set<string>();');
    source = replaceOnce(source, `        queries.delete(sid);
        cleanupCacheEntry(q.cacheKey);
        if (q.prevCacheKey) cleanupCacheEntry(q.prevCacheKey);`, `        queries.delete(sid);
        cacheKeysToClean.add(q.cacheKey);
        if (q.prevCacheKey) cacheKeysToClean.add(q.prevCacheKey);`);
    source = replaceOnce(source, `        if (existing.cacheKey !== cacheKey) {
          existing.prevCacheKey = existing.cacheKey;`, `        if (existing.cacheKey !== cacheKey) {
          if (existing.prevCacheKey) cacheKeysToClean.add(existing.prevCacheKey);
          existing.prevCacheKey = existing.cacheKey;`);
    source = replaceOnce(source, `      q.waiting = node.waitFor?.some((dep) => getData(dep) === undefined) ?? false;
      if (q.waiting) continue;

      const entry = cache.get(cacheKey);`, `      q.waiting = node.waitFor?.some((dep) => getData(dep) === undefined) ?? false;
      const entry = cache.get(cacheKey);
      q.loading = entry?.inFlight ?? false;
      if (entry?.data !== undefined && !entry.failed) {
        const previousKey = acceptCacheResult(q);
        if (previousKey) cacheKeysToClean.add(previousKey);
      }
      if (q.waiting) continue;`);
    source = replaceOnce(source, `        q.refreshInterval = newInterval;
      }
    }

    if (rebuildSnapshot()) notify();`, `        q.refreshInterval = newInterval;
      }
    }

    for (const key of cacheKeysToClean) cleanupCacheEntry(key);
    if (rebuildSnapshot()) notify();`);
    // dispose owns its terminal snapshot; it must not rely on a retired
    // request's finally to make getSnapshot agree with isLoading.
    source = replaceOnce(source, '    mutations.clear();\n  }\n\n  return {',
      '    mutations.clear();\n    rebuildSnapshot();\n  }\n\n  return {');
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

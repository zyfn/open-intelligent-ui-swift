import { replaceOnce } from './compat.mjs';
export function readiness(source, kind, path) {
  const imports = `import {tokenComplete as nativeTokenComplete,tagSyntax as nativeTagSyntax,tagReady as nativeTagReady,registerCompletedSyntax as nativeRegisterCompletedSyntax,evaluateSource as nativeEvaluateSource,finishEvaluation as nativeFinishEvaluation,finishMaterialization as nativeFinishMaterialization,copyPresentation as nativeCopyPresentation,copyEvaluationSource as nativeCopyEvaluationSource,recordResult as nativeRecordResult,observeQueries as nativeObserveQueries} from ${JSON.stringify(path)};\n`;
  if (kind === 'lexer') {
    source = replaceOnce(source, 'tokenize(src: string): Token[]', 'tokenize(src: string, sourceLength = src.length, sourceEnded = true): Token[]');
    source = source.replaceAll('tokens.push(', 'nativePush(');
    source = replaceOnce(source, '  const n = src.length;', `  const n = src.length;
  const nativePush = (token:Token) => {
    const closing = [T.RParen,T.RBrack,T.RBrace].includes(token.t);
    nativeTagSyntax(token, closing ? i < sourceLength : token.t === T.Str ? i <= sourceLength && (sourceEnded || i < sourceLength) : sourceEnded || i < sourceLength);
    tokens.push(token);
  };`);
  } else if (kind === 'expressions') {
    source = replaceOnce(source, '  let pos = 0;', `  let pos = 0;
  const nativeIncomplete = [0];
  for (const token of tokens) nativeIncomplete.push(nativeIncomplete[nativeIncomplete.length-1] + (nativeTokenComplete(token) ? 0 : 1));`);
    source = replaceOnce(source, 'function parseExpr(minPrec: number = 0): ASTNode {', 'function parseExpr(minPrec: number = 0): ASTNode {\n    const nativeStart = pos;');
    source = replaceOnce(source, '    return left;\n  }\n\n  // ── Prefix', '    return nativeTagSyntax(left, nativeIncomplete[Math.min(nativeStart,tokens.length)] === nativeIncomplete[Math.min(pos,tokens.length)]);\n  }\n\n  // ── Prefix');
  } else if (kind === 'parser') {
    source = replaceOnce(source, '      const stmt = classifyStatement(s, expr);\n      completedStmtMap.set(s.id, stmt);',
      '      const stmt = classifyStatement(s, expr);\n      nativeRegisterCompletedSyntax(expr);\n      completedStmtMap.set(s.id, stmt);');
    source = replaceOnce(source, '  return {\n    root,\n', '  return nativeRecordResult({\n    root,\n');
    source = replaceOnce(source, '    mutationStatements,\n  };\n}', '    mutationStatements,\n  }, ctx, entry ? syms.get(entry.id) : undefined, entry?.id);\n}');
    source = replaceOnce(source, 'split(tokenize(text))', 'split(tokenize(text, trimmed.length, !wasIncomplete))');
    source = replaceOnce(source, 'split(tokenize(closed))', 'split(tokenize(closed, pendingText.length, complete && !wasIncomplete))');
    // The last statement may remain in the streaming parser's pending buffer
    // after all of its real delimiters have arrived. Its token/AST markers
    // already distinguish received syntax from auto-closed preview syntax;
    // stream termination must not override a closed component's readiness.
  } else if (kind === 'materialize') {
    source = replaceOnce(source, 'return nativeBudget(ctx,()=>nativeMaterializeValue(node,ctx),null);', 'return nativeFinishMaterialization(node,ctx,nativeBudget(ctx,()=>nativeMaterializeValue(node,ctx),null));');
    source = replaceOnce(source, 'return nativeBudget(ctx,()=>nativeMaterializeExpr(node,ctx,scopedRefs),{k:"Null"});', 'return nativeFinishMaterialization(node,ctx,nativeBudget(ctx,()=>nativeMaterializeExpr(node,ctx,scopedRefs),{k:"Null"}),scopedRefs);');
    // Lang 1.1 copies a memoized element when an alias gives it a different
    // statement ID. Preserve host-only readiness across that official copy.
    source = replaceOnce(source, '  return { ...el, statementId: id };', '  return nativeCopyPresentation(el, { ...el, statementId: id });');
  } else if (kind === 'evaluator') {
    source = replaceOnce(source, '): unknown {\n  switch (node.k) {', '): unknown {\n  const observation = nativeObserveQueries(node,context);\n  return nativeEvaluateSource(node,()=>nativeFinishEvaluation(node, nativeSourceEvaluate(node,observation.context,schemaCtx),observation.queries));\n}\nfunction nativeSourceEvaluate(node:ASTNode,context:EvaluationContext,schemaCtx?:SchemaContext):unknown {\n  switch (node.k) {');
    source = replaceOnce(source, '  if (el.hasDynamicProps === false) return el;', '  if (el.hasDynamicProps === false) return el;\n  const observation = nativeObserveQueries(el,context);\n  context = observation.context;');
    source = replaceOnce(source, '  return { ...el, props: evaluated };', '  return nativeCopyPresentation(el, { ...el, props: evaluated }, observation.queries);');
  } else if (kind === 'evaluate-tree') {
    source = replaceOnce(source, '  if (el.hasDynamicProps === false) return el;', '  if (el.hasDynamicProps === false) return el;\n  const observation = nativeObserveQueries(el,evalCtx.ctx);\n  evalCtx = {...evalCtx,ctx:observation.context};');
    source = replaceOnce(source, '  return { ...el, props: evaluated };', '  return nativeCopyPresentation(el, { ...el, props: evaluated }, observation.queries);');
  } else if (kind === 'evaluate-prop') {
    source = replaceOnce(source, `      return result.map((item) =>
        isElementNode(item) ? callbacks.recurseElement(item as ElementNode) : item,
      );`, `      return nativeCopyEvaluationSource(result, result.map((item) =>
        isElementNode(item) ? callbacks.recurseElement(item as ElementNode) : item,
      ));`);
    source = replaceOnce(source, '    return value.map((v) => callbacks.recurse(v, reactiveSchema));',
      '    return nativeCopyEvaluationSource(value, value.map((v) => callbacks.recurse(v, reactiveSchema)));');
  }
  return imports + source;
}

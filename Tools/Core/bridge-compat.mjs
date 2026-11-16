// Explicit, source-checked fixes at the native bridge boundary. The original
// core remains the oracle for ordinary values, action contents and validation.
import { replaceOnce } from './compat.mjs';

// The Swift transport probe identifies the first real frame outside raw Lang
// strings/comments. Keep the official selection algorithm, but do not let it
// reinterpret markers inside that protected prefix. The public message API
// calls the same implementation with its original unrestricted boundary.
export function messageBoundary(source) {
  source = replaceOnce(source,
    'export function parseMessage(raw: string, { streaming }: ParseMessageOptions = {}): ParsedMessage {',
    `export function parseMessage(raw: string, options: ParseMessageOptions = {}): ParsedMessage {
  return nativeParseMessage(raw, options);
}

export function nativeParseMessage(raw: string, { streaming }: ParseMessageOptions = {}, protectedPrefix = 0): ParsedMessage {`);
  source = replaceOnce(source,
    'const held = streaming && last !== "" && PREFIX.startsWith(last);',
    'const held = streaming && nl + 1 >= protectedPrefix && last !== "" && PREFIX.startsWith(last);');
  source = replaceOnce(source,
    '  let text = raw.replace(RETRY, "$1\\n");',
    `  // Include exactly one preceding unit so a mid-line first content frame
  // keeps the official retry newline, without scanning the protected prefix.
  const retryStart = Math.max(0, protectedPrefix - 1);
  let text = raw.slice(0, retryStart) + raw.slice(retryStart).replace(RETRY, "$1\\n");`);
  source = replaceOnce(source,
    'if (cut && `${PREFIX}content`.startsWith(cut[1]))',
    'if (cut && cut.index + 1 >= protectedPrefix && `${PREFIX}content`.startsWith(cut[1]))');
  source = replaceOnce(source,
    'const held = streaming && last !== "" && (last.startsWith(PREFIX) || PREFIX.startsWith(last));',
    'const held = streaming && text.lastIndexOf("\\n") + 1 >= protectedPrefix && last !== "" && (last.startsWith(PREFIX) || PREFIX.startsWith(last));');
  source = replaceOnce(source,
    '  for (const [i, line] of lines.entries()) {\n    const match = MARKER.exec(line.replace(/\\r$/, ""));',
    `  let lineOffset = 0;
  for (const [i, line] of lines.entries()) {
    const match = lineOffset >= protectedPrefix ? MARKER.exec(line.replace(/\\r$/, "")) : null;
    lineOffset += line.length + 1;`);
  return source;
}

export function actionProvenance(source, capturesPath) {
  source = replaceOnce(source,
    'if (isStep(node.name)) return evaluateActionCall(node, context);',
    'if (isStep(node.name)) return nativeCorePlan(evaluateActionCall(node, context));');
  source = replaceOnce(source,
    'if (missesRequired(args, def.params)) return { steps: [] };',
    'if (missesRequired(args, def.params)) return nativeCorePlan({ steps: [] });');
  source = replaceOnce(source,
    'if (params === INVALID) return { steps: [] };',
    'if (params === INVALID) return nativeCorePlan({ steps: [] });');
  source = replaceOnce(source,
    '        return { steps: [step] };',
    '        return nativeCorePlan({ steps: [step] });');
  source = replaceOnce(source,
    '  return plan.steps.every(own) ? plan : { ...plan, steps: plan.steps.filter(own) };',
    '  return nativeCopyCorePlan(plan, plan.steps.every(own) ? plan : { ...plan, steps: plan.steps.filter(own) });');
  return `import { corePlan as nativeCorePlan, copyCorePlan as nativeCopyCorePlan } from ${JSON.stringify(capturesPath)};\n` + source;
}

export function propActionProvenance(source, capturesPath) {
  // Data is allowed to contain a `steps` field, including business records that
  // happen to resemble action steps. Only evaluated calls/native plans take the
  // deferred-action path. Explicit DSL Action(...) still applies ownSteps.
  source = replaceOnce(source,
    '  return isActionPlan(result) ? ownSteps(result) : result;',
    '  return nativeIsRuntimePlan(result) && !nativeIsNativePlan(result) ? ownSteps(result) : result;');
  source = replaceOnce(source,
    '  if (isActionPlan(value)) return value;',
    '  if (nativeIsRuntimePlan(value)) return value;');
  return `import { isRuntimePlan as nativeIsRuntimePlan, isNativePlan as nativeIsNativePlan } from ${JSON.stringify(capturesPath)};\n` + source;
}

export function validationOwnKeys(source) {
  return replaceOnce(source,
    '    const validator = customValidators?.[rule.type] ?? builtInValidators[rule.type];',
    `    const custom = customValidators && Object.prototype.hasOwnProperty.call(customValidators, rule.type)
      ? customValidators[rule.type] : undefined;
    const validator = custom ?? (Object.prototype.hasOwnProperty.call(builtInValidators, rule.type)
      ? builtInValidators[rule.type] : undefined);`);
}

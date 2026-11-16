// Explicit, source-checked fixes at the native bridge boundary. The original
// core remains the oracle for ordinary values, action contents and validation.
import { replaceOnce } from './compat.mjs';

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

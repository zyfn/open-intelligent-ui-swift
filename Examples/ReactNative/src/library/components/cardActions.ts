import { ACTION_STEPS, BuiltinActionType, type ActionPlan } from '@openuidev/react-lang';
import { record } from './contentUtils';

/** Pinned OpenUI card semantics: ToAssistant receives a serialized item context. */
export function withCardItemContext(action: unknown, item: Record<string, unknown>) {
  const context = Object.fromEntries(Object.entries(item).filter(([, value]) => value !== undefined));
  const supplied = record(action);
  if (Array.isArray(supplied.steps)) {
    const plan = action as ActionPlan;
    const selected = `Selected item: ${JSON.stringify(context)}`;
    return { ...plan, steps: plan.steps.map(step => {
      if (step.type !== ACTION_STEPS.ToAssistant) return step;
      const existing = step.context == null ? '' : typeof step.context === 'string' ? step.context : JSON.stringify(step.context);
      return { ...step, context: existing ? `${existing}\n${selected}` : selected };
    }) };
  }
  return { type: typeof supplied.type === 'string' ? supplied.type : BuiltinActionType.ContinueConversation,
    params: { ...record(supplied.params), ...(supplied.url !== undefined ? { url: supplied.url } : {}),
      ...(supplied.context ? { context: supplied.context } : {}), ...context } };
}

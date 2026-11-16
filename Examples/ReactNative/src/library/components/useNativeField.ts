import { createContext, useCallback, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import {
  isReactiveAssign, parseStructuredRules, useFormName, useFormValidation, useIsStreaming, useSetFieldValue, useStateField, validate,
} from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';

export const FieldPresentationContext = createContext<{ label: string; labelId: string; hint?: string } | null>(null);
const unchanged = (value: unknown) => value;
const text = (value: unknown) => typeof value === 'string' ? value : '';

/** Native callbacks belong to a committed field, even when React reuses its view. */
export function useFieldGuard(identity: string, disabled = false): () => boolean {
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const token = useMemo(() => ({}), [identity]);
  const mounted = useRef(true);
  const committed = useRef({ token, disabled: disabled || streaming });
  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  useLayoutEffect(() => { committed.current = { token, disabled: disabled || streaming }; },
    [token, disabled, streaming]);
  return useCallback(() => mounted.current && committed.current.token === token
    && !committed.current.disabled && canInteract(), [token, canInteract]);
}

/** Presentation and validation only; all values remain in the official Store. */
export function useNativeField(props: Record<string, unknown>, options: {
  fallback?: unknown;
  hydrateDefault?: string;
  validateOnChange?: boolean;
  validationValue?: (value: unknown) => unknown;
  identity?: string;
} = {}) {
  const name = text(props.name);
  const formName = useFormName();
  const form = useFormValidation();
  const field = useStateField(name, props.value);
  const setFieldValue = useSetFieldValue();
  const streaming = useIsStreaming();
  const document = useDocumentInteraction();
  const presentation = useContext(FieldPresentationContext);
  const binding = isReactiveAssign(props.value) ? [props.value.target, props.value.expr] : null;
  const identity = JSON.stringify([formName ?? null, name, binding, props.rules ?? null, options.identity ?? null]);
  const canInteract = useFieldGuard(identity);
  const value = field.value ?? options.fallback;
  const valueRef = useRef(value);
  const [touchedIdentity, setTouchedIdentity] = useState<string>();
  const touched = touchedIdentity === identity;
  const rulesKey = JSON.stringify(props.rules ?? {});
  const rules = useMemo(() => parseStructuredRules(JSON.parse(rulesKey)), [rulesKey]);
  const validationValue = options.validationValue ?? unchanged;
  const register = form?.registerField;
  const unregister = form?.unregisterField;
  useLayoutEffect(() => { valueRef.current = value; }, [value, identity]);
  useEffect(() => {
    if (streaming || !rules.length || !register || !unregister) return;
    register(name, rules, () => validationValue(valueRef.current));
    return () => unregister(name);
  }, [name, identity, rules, register, unregister, streaming, validationValue]);
  useEffect(() => {
    if (options.hydrateDefault && !field.isReactive && field.value === undefined
      && options.fallback !== undefined && canInteract()) {
      // Match official default hydration: initialState is applied by the parent
      // Renderer after child effects, so a mount default must not overwrite the
      // host's saved snapshot before that restoration has run.
      setFieldValue(formName, options.hydrateDefault, name, options.fallback, false);
    }
  }, [options.hydrateDefault, options.fallback, field, canInteract, setFieldValue, formName, name]);

  const setValue = (next: unknown): boolean => {
    if (!canInteract()) return false;
    valueRef.current = next;
    // Capture this field's setter. Forwarding through a latest-field ref could
    // redirect an old native event to an entirely different binding.
    field.setValue(next);
    if (!canInteract()) return true;
    if (options.validateOnChange !== false || touched || form?.errors[name]) {
      setTouchedIdentity(identity);
      form?.validateField(name, validationValue(next), rules);
    }
    return true;
  };
  const touch = () => {
    if (!canInteract()) return;
    setTouchedIdentity(identity);
    form?.validateField(name, validationValue(valueRef.current), rules);
  };
  const clearError = () => { if (canInteract()) form?.clearFieldError(name); };
  const error = form ? form.errors[name] : touched ? validate(validationValue(value), rules) : undefined;
  return {
    name, identity, value, getValue: () => valueRef.current, setValue, touch, clearError, canInteract,
    disabled: streaming || !document.canInteract(), error, inlineError: presentation && form ? undefined : error,
    required: rules.some(rule => rule.type === 'required'),
    label: presentation?.label || text(props.label) || text(props.placeholder) || name || '输入内容',
    labelledBy: presentation?.labelId,
    hint: [rules.some(rule => rule.type === 'required') ? '必填' : '', presentation?.hint].filter(Boolean).join('，') || undefined,
  };
}

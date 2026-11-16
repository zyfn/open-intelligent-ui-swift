import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Platform, Text, TextInput, View, type KeyboardTypeOptions } from 'react-native';
import {
  parseStructuredRules, useFormValidation, useIsStreaming, useStateField, validate,
  type ComponentRenderer,
} from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme } from '../theme';

const asString = (value: unknown) => typeof value === 'string' ? value : '';

export const Input: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const name = asString(props.name);
  const field = useStateField(name, props.value);
  const form = useFormValidation();
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const disabled = streaming || !canInteract();
  const [focused, setFocused] = useState(false);
  const [touchedName, setTouchedName] = useState<string>();
  const touched = touchedName === name;
  const mounted = useRef(true);
  const current = useRef({ field, disabled });
  const value = asString(field.value);
  const valueRef = useRef(value);
  // Runtime projections may recreate the object while its nine rule fields stay identical.
  const rulesKey = JSON.stringify(props.rules ?? {});
  const rules = useMemo(() => parseStructuredRules(JSON.parse(rulesKey)), [rulesKey]);
  const register = form?.registerField;
  const unregister = form?.unregisterField;
  const hasForm = form !== null;
  const localError = useMemo(() => !hasForm && touched ? validate(value, rules) : undefined,
    [hasForm, touched, value, rules]);
  const error = form ? form.errors[name] : localError;
  const id = useId();
  const type = asString(props.type) || 'text';
  const placeholder = asString(props.placeholder);
  const label = placeholder.trim() || name || '输入内容';
  const required = rules.some(rule => rule.type === 'required');

  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  useLayoutEffect(() => {
    current.current = { field, disabled };
    valueRef.current = value;
  }, [field, disabled, value]);
  useEffect(() => {
    if (streaming || !rules.length || !register || !unregister) return;
    register(name, rules, () => valueRef.current);
    return () => unregister(name);
  }, [name, rules, register, unregister, streaming]);

  const keyboardType: KeyboardTypeOptions = type === 'email' ? 'email-address'
    : type === 'url' ? 'url'
    : type === 'number' ? Platform.OS === 'ios' ? 'numbers-and-punctuation' : 'numeric'
    : 'default';

  return (
    <View style={{ gap: 6, minWidth: 0, flexShrink: 1 }}>
      <TextInput
        nativeID={`openui-field-${id}`}
        accessibilityLabel={label}
        accessibilityHint={error || (required ? '必填' : undefined)}
        accessibilityState={{ disabled }}
        editable={!disabled}
        value={value}
        onChangeText={next => {
          if (!mounted.current || current.current.disabled || !canInteract()) return;
          valueRef.current = next;
          current.current.field.setValue(next);
          if (touched || form?.errors[name]) form?.validateField(name, next, rules);
        }}
        onFocus={() => {
          if (!mounted.current || current.current.disabled || !canInteract()) return;
          setFocused(true);
          form?.clearFieldError(name);
        }}
        onBlur={() => {
          if (!mounted.current) return;
          setFocused(false);
          if (current.current.disabled || !canInteract()) return;
          setTouchedName(name);
          form?.validateField(name, valueRef.current, rules);
        }}
        placeholder={placeholder}
        placeholderTextColor={theme.muted}
        selectionColor={theme.accent}
        secureTextEntry={type === 'password'}
        autoCapitalize={type === 'text' ? 'sentences' : 'none'}
        autoCorrect={type === 'text'}
        spellCheck={type === 'text'}
        autoComplete={type === 'email' ? 'email' : 'off'}
        textContentType={type === 'email' ? 'emailAddress' : type === 'url' ? 'URL' : 'none'}
        keyboardType={keyboardType}
        returnKeyType="done"
        submitBehavior="blurAndSubmit"
        underlineColorAndroid="transparent"
        style={{ minHeight: theme.controlMinHeight, minWidth: 0, borderWidth: 1.5,
          borderColor: error ? theme.destructive : focused && !disabled ? theme.focus : theme.muted,
          borderRadius: 12, paddingHorizontal: 14, paddingVertical: 12,
          fontSize: 16, color: theme.ink, backgroundColor: disabled ? theme.surfaceMuted : theme.surface }}
      />
      {error ? <Text nativeID={`openui-error-${id}`} accessibilityLiveRegion="polite"
        style={{ color: theme.destructive, fontSize: 13, lineHeight: 20 }}>{error}</Text> : null}
    </View>
  );
};

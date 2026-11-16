import { useEffect, useId, useState } from 'react';
import { Platform, Text, TextInput, View, type KeyboardTypeOptions } from 'react-native';
import type { ComponentRenderer } from '@openuidev/react-lang';
import { useOpenUITheme } from '../theme';
import { useNativeField } from './useNativeField';

const asString = (value: unknown) => typeof value === 'string' ? value : '';

export function NativeTextField({ props, multiline = false }: { props: Record<string, unknown>; multiline?: boolean }) {
  const theme = useOpenUITheme();
  const field = useNativeField(props, { validateOnChange: false, identity: JSON.stringify([multiline, props.type]) });
  const { disabled, error, required, label } = field;
  const [focused, setFocused] = useState(false);
  useEffect(() => { if (disabled) setFocused(false); }, [disabled]);
  const value = asString(field.value);
  const id = useId();
  const type = asString(props.type) || 'text';
  const placeholder = asString(props.placeholder);
  const rows = typeof props.rows === 'number' && Number.isFinite(props.rows)
    ? Math.max(1, Math.min(16, Math.round(props.rows))) : 4;

  const keyboardType: KeyboardTypeOptions = type === 'email' ? 'email-address'
    : type === 'url' ? 'url'
    : type === 'number' ? Platform.OS === 'ios' ? 'numbers-and-punctuation' : 'numeric'
    : 'default';

  return (
    <View style={{ gap: 6, minWidth: 0, flexShrink: 1 }}>
      <TextInput
        nativeID={`openui-field-${id}`}
        accessibilityLabel={label}
        accessibilityLabelledBy={field.labelledBy}
        accessibilityHint={error || field.hint || (required ? '必填' : undefined)}
        accessibilityState={{ disabled }}
        editable={!disabled}
        value={value}
        onChangeText={next => { field.setValue(next); }}
        onFocus={() => {
          if (!field.canInteract()) return;
          setFocused(true);
          field.clearError();
        }}
        onBlur={() => {
          if (!field.canInteract()) return;
          setFocused(false);
          field.touch();
        }}
        placeholder={placeholder}
        placeholderTextColor={theme.muted}
        selectionColor={theme.accent}
        multiline={multiline}
        numberOfLines={multiline ? rows : 1}
        textAlignVertical={multiline ? 'top' : 'center'}
        secureTextEntry={!multiline && type === 'password'}
        autoCapitalize={type === 'text' ? 'sentences' : 'none'}
        autoCorrect={type === 'text'}
        spellCheck={type === 'text'}
        autoComplete={type === 'email' ? 'email' : 'off'}
        textContentType={type === 'email' ? 'emailAddress' : type === 'url' ? 'URL' : 'none'}
        keyboardType={keyboardType}
        returnKeyType={multiline ? 'default' : 'done'}
        submitBehavior={multiline ? 'newline' : 'blurAndSubmit'}
        underlineColorAndroid="transparent"
        style={{ minHeight: multiline ? Math.max(theme.controlMinHeight, rows * 24 + 24) : theme.controlMinHeight,
          minWidth: 0, borderWidth: 1.5,
          borderColor: error ? theme.destructive : focused && !disabled ? theme.focus : theme.muted,
          borderRadius: 12, paddingHorizontal: 14, paddingVertical: 12,
          fontSize: 16, color: theme.ink, backgroundColor: disabled ? theme.surfaceMuted : theme.surface }}
      />
      {field.inlineError ? <Text nativeID={`openui-error-${id}`} accessibilityLiveRegion="polite"
        style={{ color: theme.destructive, fontSize: 13, lineHeight: 20 }}>{field.inlineError}</Text> : null}
    </View>
  );
}

export const Input: ComponentRenderer = ({ props }) => <NativeTextField props={props} />;

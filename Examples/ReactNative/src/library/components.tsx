import { Children } from 'react';
import { StyleSheet, Text, View, type ViewStyle } from 'react-native';
import { ACTION_STEPS, useFormName, useFormValidation, type ActionPlan, type ComponentRenderer } from '@openuidev/react-lang';
import ActionButton from '../platform/ActionButton';
import { useDocumentInteraction } from '../runtime/interaction';
import { Input } from './components/Input';
import { TextContent } from './components/TextContent';
import { Image } from './components/NativeImage';
import { useNativeAction } from './components/useNativeAction';
import { useOpenUITheme } from './theme';

const string = (value: unknown, fallback = '') => typeof value === 'string' ? value : fallback;
const align: Record<string, ViewStyle['alignItems']> = {
  start: 'flex-start', center: 'center', end: 'flex-end', stretch: 'stretch', baseline: 'baseline',
};
const justify: Record<string, ViewStyle['justifyContent']> = {
  start: 'flex-start', center: 'center', end: 'flex-end',
  between: 'space-between', around: 'space-around', evenly: 'space-evenly',
};

const Stack: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const gap = theme.gap[string(props.gap, 'm') as keyof typeof theme.gap] ?? theme.gap.m;
  return (
    <View style={{ gap, minWidth: 0, flexShrink: 1, flexDirection: props.direction === 'row' ? 'row' : 'column',
      alignItems: align[string(props.align)] ?? 'stretch',
      justifyContent: justify[string(props.justify)] ?? 'flex-start',
      flexWrap: props.wrap === true ? 'wrap' : 'nowrap' }}>
      {Children.map(renderNode(props.children), child =>
        typeof child === 'string' || typeof child === 'number'
          ? <Text selectable style={{ color: theme.ink, fontSize: 16, lineHeight: 24,
            minWidth: 0, flexShrink: 1 }}>{child}</Text> : child)}
    </View>
  );
};

const CardHeader: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const title = string(props.title);
  const subtitle = string(props.subtitle);
  if (!title && !subtitle) return null;
  return (
    <View style={{ gap: 6, minWidth: 0, flexShrink: 1 }}>
      {title ? <Text accessibilityRole="header" selectable style={{ color: theme.ink, fontSize: 24,
        fontWeight: '600', lineHeight: 32 }}>{title}</Text> : null}
      {subtitle ? <Text selectable style={{ color: theme.muted, fontSize: 14, lineHeight: 22 }}>
        {subtitle}</Text> : null}
    </View>
  );
};

const Separator: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const decorative = props.decorative !== false;
  const vertical = props.orientation === 'vertical';
  return <View accessible={!decorative} role={decorative ? undefined : 'separator'}
    accessibilityElementsHidden={decorative} importantForAccessibility={decorative ? 'no' : 'yes'}
    accessibilityLabel={decorative ? undefined : vertical ? '垂直分隔线' : '分隔线'}
    style={{ backgroundColor: theme.border, alignSelf: 'stretch', flexShrink: 0,
      ...(vertical ? { width: StyleSheet.hairlineWidth, minHeight: 24 }
        : { height: StyleSheet.hairlineWidth }) }} />;
};

const Button: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const { invoke, disabled, pending, error } = useNativeAction();
  const { canInteract } = useDocumentInteraction();
  const formName = useFormName();
  const validation = useFormValidation();
  const label = string(props.label);
  const variant = string(props.variant, 'primary');
  return <View style={{ gap: 6, minWidth: 0, flexShrink: 1 }}>
    <ActionButton label={label} disabled={disabled || !label.trim()} busy={pending}
      variant={variant} type={string(props.type, 'normal')} size={string(props.size, 'medium')}
      onPress={() => {
        if (disabled || !canInteract()) return;
        const action = props.action as ActionPlan | undefined;
        // Match the pinned OpenUI Button contract; no form is invented for a Stack.
        const needsValidation = !action?.steps || action.steps.some(step =>
          step.type === ACTION_STEPS.ToAssistant || step.type === 'custom_action' ||
          (step.type === ACTION_STEPS.Run && step.refType === 'mutation'));
        if (formName && variant === 'primary' && validation && needsValidation && !validation.validateForm()) return;
        void invoke(label, action, formName);
      }} />
    {error ? <Text accessibilityLiveRegion="polite" style={{ color: theme.destructive,
      fontSize: 13, lineHeight: 20 }}>{error}</Text> : null}
  </View>;
};

export const renderers: Record<string, ComponentRenderer> = { Stack, TextContent, CardHeader, Separator, Input, Button, Image };

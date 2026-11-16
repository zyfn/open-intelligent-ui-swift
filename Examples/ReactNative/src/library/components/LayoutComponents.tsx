import { Children, useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { KeyboardAvoidingView, Modal as NativeModal, Platform, Pressable, ScrollView, Text, View,
  type ViewStyle } from 'react-native';
import { useIsStreaming, useStateField, type ComponentRenderer } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme } from '../theme';
import { useNativeAction } from './useNativeAction';
import { NativeIcon } from './NativeIcon';

type Element = { type: 'element'; typeName: string; props: Record<string, unknown>; partial?: boolean };
const string = (value: unknown, fallback = '') => typeof value === 'string' ? value : fallback;
const elements = (value: unknown, name: string): Element[] => Array.isArray(value)
  ? value.filter((item): item is Element => !!item && item.type === 'element' && item.typeName === name) : [];
const aligns: Record<string, ViewStyle['alignItems']> = { start: 'flex-start', center: 'center',
  end: 'flex-end', stretch: 'stretch', baseline: 'baseline' };
const justifies: Record<string, ViewStyle['justifyContent']> = { start: 'flex-start', center: 'center',
  end: 'flex-end', between: 'space-between', around: 'space-around', evenly: 'space-evenly' };

function useActivation() {
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const current = useRef({ mounted: true, streaming, canInteract });
  useLayoutEffect(() => {
    current.current = { mounted: true, streaming, canInteract };
    return () => { current.current.mounted = false; };
  }, [streaming, canInteract]);
  return { disabled: streaming || !canInteract(), active: () => {
    const state = current.current;
    return state.mounted && !state.streaming && state.canInteract();
  } };
}

function Content({ children }: { children: ReactNode }) {
  const theme = useOpenUITheme();
  return <>{Children.map(children, child => typeof child === 'string' || typeof child === 'number'
    ? <Text selectable style={{ color: theme.ink, fontSize: 16, lineHeight: 24, flexShrink: 1 }}>{child}</Text>
    : child)}</>;
}

const Card: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const variant = string(props.variant, 'card');
  return <View style={{ minWidth: 0, flexShrink: 1, flexGrow: 1, padding: variant === 'clear' ? 0 : 16,
    borderRadius: 16, borderWidth: variant === 'card' ? 1 : 0, borderColor: theme.border,
    backgroundColor: variant === 'clear' ? 'transparent' : variant === 'sunk' ? theme.surfaceMuted : theme.surface,
    flexDirection: props.direction === 'row' ? 'row' : 'column',
    flexWrap: props.wrap === true ? 'wrap' : 'nowrap',
    alignItems: aligns[string(props.align)] ?? 'stretch', justifyContent: justifies[string(props.justify)] ?? 'flex-start',
    gap: theme.gap[string(props.gap, 'm') as keyof typeof theme.gap] ?? theme.gap.m }}>
    <Content>{renderNode(props.children)}</Content>
  </View>;
};

const Buttons: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  return <View style={{ flexDirection: props.direction === 'column' ? 'column' : 'row',
    flexWrap: 'wrap', minWidth: 0, gap: theme.gap.s }}><Content>{renderNode(props.buttons)}</Content></View>;
};

const IconButton: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const label = string(props.name);
  const { invoke, disabled, pending, error } = useNativeAction(JSON.stringify([label, props.action]));
  const { active } = useActivation();
  const primary = props.variant !== 'secondary' && props.variant !== 'tertiary';
  const icon = elements([props.icon], 'Icon')[0];
  const size = props.size === 'large' ? 56 : theme.controlMinHeight;
  return <View style={{ gap: 6, alignSelf: 'flex-start' }}>
    <Pressable accessibilityRole="button" accessibilityLabel={label} disabled={disabled || !label}
      accessibilityState={{ disabled: disabled || !label, busy: pending }}
      onPress={() => { if (active()) void invoke(label, props.action as Parameters<typeof invoke>[1]); }}
      style={({ pressed }) => ({ minWidth: size, minHeight: size, padding: 12,
        borderRadius: props.shape === 'circle' ? size / 2 : Platform.OS === 'ios' ? 12 : 24,
        justifyContent: 'center', alignItems: 'center', opacity: disabled ? 0.5 : pressed ? 0.7 : 1,
        borderColor: primary ? theme.accent : theme.border, borderWidth: 1,
        backgroundColor: primary ? theme.accent : props.variant === 'secondary' ? theme.surfaceMuted : theme.surface })}>
      <View pointerEvents="none" accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
        {icon ? <NativeIcon name={string(icon.props.name)} category={string(icon.props.category)}
          color={primary ? theme.onAccent : theme.accent} size={props.size === 'large' ? 24 : 20} /> : renderNode(props.icon)}
      </View>
    </Pressable>
    {error ? <Text accessibilityRole="alert" style={{ color: theme.destructive, fontSize: 13 }}>{error}</Text> : null}
  </View>;
};

const Tabs: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const items = elements(props.items, 'TabItem');
  const [selection, setSelection] = useState(() => string(items[0]?.props.value));
  const currentItems = useRef(items);
  useLayoutEffect(() => { currentItems.current = items; }, [items]);
  const selected = items.some(item => item.props.value === selection) ? selection : string(items[0]?.props.value);
  useEffect(() => { if (selected !== selection) setSelection(selected); }, [selected, selection]);
  const { disabled, active } = useActivation();
  return <View style={{ gap: theme.gap.m, minWidth: 0, flexShrink: 1 }}>
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}
      keyboardShouldPersistTaps="handled">
      {items.map((item, index) => {
        const value = string(item.props.value);
        const chosen = value === selected;
        return <Pressable key={`${value}:${index}`} accessibilityRole="tab" accessibilityLabel={string(item.props.trigger)}
          accessibilityState={{ selected: chosen, disabled }} disabled={disabled}
          onPress={() => { if (active() && currentItems.current.some(candidate => candidate.props.value === value)) setSelection(value); }}
          style={({ pressed }) => ({ minHeight: theme.controlMinHeight, paddingHorizontal: 16, paddingVertical: 10,
            justifyContent: 'center', borderBottomWidth: 2, borderBottomColor: chosen ? theme.accent : 'transparent',
            opacity: pressed ? 0.65 : 1 })}>
          <Text style={{ color: chosen ? theme.accent : theme.muted, fontSize: 15, fontWeight: chosen ? '600' : '400' }}>
            {string(item.props.trigger)}
          </Text>
        </Pressable>;
      })}
    </ScrollView>
    {items.map((item, index) => {
      const hidden = item.props.value !== selected;
      return <View key={`${string(item.props.value)}:${index}`} style={{ display: hidden ? 'none' : 'flex', gap: theme.gap.m }}
        accessibilityElementsHidden={hidden} importantForAccessibility={hidden ? 'no-hide-descendants' : 'auto'}>
        <Content>{renderNode(item.props.content)}</Content>
      </View>;
    })}
  </View>;
};

const Accordion: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const items = elements(props.items, 'AccordionItem');
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(() => new Set());
  const { disabled, active } = useActivation();
  return <View style={{ minWidth: 0, flexShrink: 1 }}>{items.map((item, index) => {
    const value = string(item.props.value);
    const open = expanded.has(value);
    return <View key={`${value}:${index}`} style={{ borderBottomColor: theme.border, borderBottomWidth: 1 }}>
      <Pressable accessibilityRole="button" accessibilityLabel={string(item.props.trigger)}
        accessibilityState={{ expanded: open, disabled }} disabled={disabled}
        onPress={() => { if (active()) setExpanded(previous => {
          const next = new Set(previous); if (next.has(value)) next.delete(value); else next.add(value); return next;
        }); }}
        style={({ pressed }) => ({ minHeight: theme.controlMinHeight, flexDirection: 'row', gap: 12,
          alignItems: 'center', paddingVertical: 12, opacity: pressed ? 0.65 : 1 })}>
        <Text style={{ flex: 1, color: theme.ink, fontSize: 16, fontWeight: '500' }}>{string(item.props.trigger)}</Text>
        <Text accessible={false} style={{ color: theme.muted, fontSize: 18 }}>{open ? '−' : '+'}</Text>
      </Pressable>
      <View style={{ display: open ? 'flex' : 'none', gap: theme.gap.m, paddingBottom: 16 }}
        accessibilityElementsHidden={!open} importantForAccessibility={open ? 'auto' : 'no-hide-descendants'}>
        <Content>{renderNode(item.props.content)}</Content>
      </View>
    </View>;
  })}</View>;
};

const Steps: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const items = elements(props.items, 'StepsItem');
  return <View style={{ gap: 16, minWidth: 0 }}>{items.map((item, index) =>
    <View key={index} style={{ flexDirection: 'row', gap: 12, alignItems: 'flex-start' }}>
      <View style={{ width: 28, height: 28, borderRadius: 14, backgroundColor: theme.surfaceMuted,
        alignItems: 'center', justifyContent: 'center' }}><Text style={{ color: theme.accent }}>{index + 1}</Text></View>
      <View style={{ flex: 1, gap: 4 }}>
        <Text accessibilityRole="header" style={{ color: theme.ink, fontSize: 16, lineHeight: 24, fontWeight: '600' }}>
          {string(item.props.title)}</Text>
        <Text selectable style={{ color: theme.muted, fontSize: 14, lineHeight: 22 }}>{string(item.props.details)}</Text>
      </View>
    </View>)}</View>;
};

const Carousel: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const slides = Array.isArray(props.children) ? props.children : [];
  const [width, setWidth] = useState(320);
  const [page, setPage] = useState(0);
  const scroll = useRef<ScrollView>(null);
  const { disabled, active } = useActivation();
  const selected = Math.min(page, Math.max(0, slides.length - 1));
  const move = (offset: number) => {
    if (!active()) return;
    const next = Math.max(0, Math.min(slides.length - 1, selected + offset));
    setPage(next); scroll.current?.scrollTo({ x: next * width, animated: true });
  };
  return <View style={{ minWidth: 0, gap: 8 }} onLayout={event => {
    const measured = event.nativeEvent.layout.width;
    if (Number.isFinite(measured) && measured > 0 && measured !== width) setWidth(measured);
  }}>
    <ScrollView ref={scroll} horizontal pagingEnabled showsHorizontalScrollIndicator={false}
      keyboardShouldPersistTaps="handled" onMomentumScrollEnd={event => {
        if (active()) setPage(Math.max(0, Math.min(slides.length - 1, Math.round(event.nativeEvent.contentOffset.x / width))));
      }}>
      {slides.map((slide, index) => <View key={index} accessibilityLabel={`第 ${index + 1} 页，共 ${slides.length} 页`}
        style={{ width, minWidth: 0, padding: 16, gap: theme.gap.m, borderRadius: 16,
          backgroundColor: props.variant === 'sunk' ? theme.surfaceMuted : theme.surface }}>
        <Content>{renderNode(slide)}</Content>
      </View>)}
    </ScrollView>
    {slides.length > 1 ? <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 12 }}>
      <Pressable accessibilityRole="button" accessibilityLabel="上一页" disabled={disabled || selected === 0}
        accessibilityState={{ disabled: disabled || selected === 0 }} onPress={() => move(-1)}
        style={{ minWidth: 48, minHeight: 48, justifyContent: 'center', alignItems: 'center' }}>
        <Text style={{ color: selected === 0 ? theme.border : theme.accent, fontSize: 22 }}>‹</Text>
      </Pressable>
      <Text accessibilityLiveRegion="polite" style={{ color: theme.muted, fontSize: 12 }}>{selected + 1} / {slides.length}</Text>
      <Pressable accessibilityRole="button" accessibilityLabel="下一页" disabled={disabled || selected >= slides.length - 1}
        accessibilityState={{ disabled: disabled || selected >= slides.length - 1 }} onPress={() => move(1)}
        style={{ minWidth: 48, minHeight: 48, justifyContent: 'center', alignItems: 'center' }}>
        <Text style={{ color: selected >= slides.length - 1 ? theme.border : theme.accent, fontSize: 22 }}>›</Text>
      </Pressable>
    </View> : null}
  </View>;
};

const Modal: ComponentRenderer = ({ props, renderNode, statementId }) => {
  const theme = useOpenUITheme();
  const id = useId();
  const field = useStateField(statementId ?? `modal-${id}`, props.open ?? false);
  const { disabled, active } = useActivation();
  const bindingKey = JSON.stringify(props.open ?? false);
  const identity = useMemo(() => ({}), [bindingKey, statementId]);
  const committedIdentity = useRef(identity);
  useLayoutEffect(() => { committedIdentity.current = identity; }, [identity]);
  const close = () => { if (active() && committedIdentity.current === identity) field.setValue(false); };
  return <NativeModal visible={field.value === true} transparent animationType="fade"
    onRequestClose={close} accessibilityViewIsModal>
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <Pressable accessibilityLabel="关闭弹窗" onPress={close} disabled={disabled}
        style={{ flex: 1, justifyContent: 'center', alignItems: 'center', padding: 20, backgroundColor: '#00000070' }}>
        <Pressable onPress={event => event.stopPropagation()} style={{ width: '100%', maxWidth: props.size === 'sm' ? 360
          : props.size === 'lg' ? 720 : 520, maxHeight: '90%', borderRadius: 20, padding: 20, gap: 16,
          backgroundColor: theme.surface }}>
          <View style={{ flexDirection: 'row', gap: 16, alignItems: 'center' }}>
            <Text accessibilityRole="header" style={{ flex: 1, color: theme.ink, fontSize: 20,
              lineHeight: 28, fontWeight: '600' }}>{string(props.title)}</Text>
            <Pressable accessibilityRole="button" accessibilityLabel="关闭弹窗" onPress={close} disabled={disabled}
              accessibilityState={{ disabled }} style={{ minWidth: 48, minHeight: 48, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={{ color: theme.muted, fontSize: 24 }}>×</Text>
            </Pressable>
          </View>
          <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ gap: theme.gap.m }}>
            <Content>{renderNode(props.children)}</Content>
          </ScrollView>
        </Pressable>
      </Pressable>
    </KeyboardAvoidingView>
  </NativeModal>;
};

const DataItem: ComponentRenderer = () => null;
export const layoutRenderers: Record<string, ComponentRenderer> = {
  Card, Buttons, IconButton, Tabs, TabItem: DataItem, Accordion, AccordionItem: DataItem,
  Steps, StepsItem: DataItem, Carousel, Modal,
};

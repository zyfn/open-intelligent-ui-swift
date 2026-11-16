import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text as NativeText, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { isReactiveAssign, useIsStreaming, useStateField, type ComponentRenderer } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme, type NativeTheme } from '../theme';
import { NativeIcon } from './NativeIcon';
import { NativeCode } from './NativeCode';
import { NativeImage } from './NativeImage';
import { TextContent } from './TextContent';
import { elements, finiteNumber, nodeProps, record, text } from './contentUtils';
import { useNativeAction } from './useNativeAction';

const inkFor = (variant: unknown, theme: NativeTheme) => variant === 'danger' || variant === 'error'
  ? theme.destructive : variant === 'neutral' || !variant ? theme.ink : theme.accent;

const MarkDownRenderer: ComponentRenderer = ({ props, ...renderer }) => {
  const theme = useOpenUITheme();
  const boxed = props.variant === 'card' || props.variant === 'sunk';
  return <View style={{ minWidth: 0, flexShrink: 1, ...(boxed ? {
    borderRadius: 12, padding: 16, backgroundColor: props.variant === 'sunk' ? theme.surfaceMuted : theme.surface,
    borderWidth: props.variant === 'card' ? StyleSheet.hairlineWidth : 0, borderColor: theme.border,
  } : {}) }}>
    <TextContent {...renderer} props={{ text: text(props.textMarkdown) }} />
  </View>;
};

function QuietCallout({ variant, title, description, renderNode }: {
  variant?: unknown; title: string; description: string; renderNode: (value: unknown) => React.ReactNode;
}) {
  const theme = useOpenUITheme();
  const color = inkFor(variant, theme);
  const icon = variant === 'success' ? 'circle-check' : variant === 'warning' ? 'triangle-alert'
    : variant === 'error' || variant === 'danger' ? 'circle-alert' : 'info';
  if (!title && !description) return null;
  return <View style={{ minWidth: 0, flexShrink: 1, flexDirection: 'row', alignItems: 'flex-start',
    gap: 10, padding: 12, borderRadius: 12, backgroundColor: theme.surfaceMuted }}>
    <View style={{ paddingTop: 2 }}><NativeIcon name={icon} size={18} color={color} /></View>
    <View style={{ minWidth: 0, flex: 1, gap: 4 }}>
      {title ? <NativeText selectable style={{ color, fontSize: 14, fontWeight: '600', lineHeight: 21 }}>{title}</NativeText> : null}
      {description ? <TextContent props={{ text: description, size: 'small' }} renderNode={renderNode} /> : null}
    </View>
  </View>;
}

const TextCallout: ComponentRenderer = ({ props, renderNode }) => <QuietCallout variant={props.variant}
  title={text(props.title)} description={text(props.description)} renderNode={renderNode} />;

const Callout: ComponentRenderer = ({ props, renderNode }) => {
  const field = useStateField('visible', props.visible);
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const binding = isReactiveAssign(props.visible) ? props.visible.target : field.name;
  const visible = !field.isReactive || field.value === true || field.value === 'true';
  const current = useRef({ binding, field, canInteract });
  useLayoutEffect(() => { current.current = { binding, field, canInteract }; }, [binding, field, canInteract]);
  useEffect(() => {
    if (!field.isReactive || !visible || streaming || !canInteract()) return;
    const timeout = setTimeout(() => {
      const latest = current.current;
      if (latest.binding === binding && latest.canInteract()) latest.field.setValue(false);
    }, 3000);
    return () => clearTimeout(timeout);
  }, [field.isReactive, binding, visible, streaming, canInteract]);
  return visible ? <QuietCallout variant={props.variant} title={text(props.title)}
    description={text(props.description)} renderNode={renderNode} /> : null;
};

const ImageBlock: ComponentRenderer = ({ props }) => <NativeImage source={text(props.src)} alt={text(props.alt)} />;

const ImageGallery: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const images = Array.isArray(props.images) ? props.images.map(record).filter(item => text(item.src)) : [];
  const [selected, setSelected] = useState<{ source: string; index: number }>();
  const index = selected?.index ?? -1;
  const active = images[index]?.src === selected?.source ? images[index] : undefined;
  const available = !streaming && canInteract();
  return <View style={{ minWidth: 0, flexShrink: 1 }}>
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, minWidth: 0 }}>
      {images.map((image, i) => <View key={`${text(image.src)}:${i}`} style={{ flexBasis: '46%', flexGrow: 1, minWidth: 0 }}>
        <NativeImage source={text(image.src)} alt={text(image.alt)} compact aspectRatio={1} resizeMode="cover"
          onPress={() => { if (available && canInteract()) setSelected({ source: text(image.src), index: i }); }} />
      </View>)}
    </View>
    <Modal visible={Boolean(active) && available} transparent animationType="fade" onRequestClose={() => setSelected(undefined)}>
      <SafeAreaView style={{ flex: 1, backgroundColor: theme.background }} accessibilityViewIsModal>
        <View style={{ flexDirection: 'row', justifyContent: 'flex-end', paddingHorizontal: 12 }}>
          <Pressable accessibilityRole="button" accessibilityLabel="关闭图片预览" onPress={() => setSelected(undefined)}
            style={{ minHeight: theme.controlMinHeight, minWidth: theme.controlMinHeight, alignItems: 'center', justifyContent: 'center' }}>
            <NativeIcon name="x" />
          </Pressable>
        </View>
        <ScrollView contentContainerStyle={{ padding: 16, gap: 12, flexGrow: 1, justifyContent: 'center' }}>
          {active ? <NativeImage source={text(active.src)} alt={text(active.alt)} /> : null}
          {active && text(active.details) ? <NativeText selectable style={{ color: theme.muted, fontSize: 14, lineHeight: 21 }}>
            {text(active.details)}</NativeText> : null}
        </ScrollView>
        {images.length > 1 ? <View style={{ flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 16 }}>
          {[{ label: '上一张', next: index - 1 }, { label: '下一张', next: index + 1 }].map(({ label, next }) => {
            const disabled = next < 0 || next >= images.length || !available;
            return <Pressable key={label} accessibilityRole="button" accessibilityLabel={label} disabled={disabled}
              accessibilityState={{ disabled }} onPress={() => { if (!disabled && canInteract()) setSelected({ source: text(images[next].src), index: next }); }}
              style={{ minHeight: theme.controlMinHeight, paddingHorizontal: 12, justifyContent: 'center', opacity: disabled ? 0.4 : 1 }}>
              <NativeText style={{ color: theme.accent, fontSize: 14 }}>{label}</NativeText>
            </Pressable>;
          })}
        </View> : null}
      </SafeAreaView>
    </Modal>
  </View>;
};

const CodeBlock: ComponentRenderer = ({ props }) => <NativeCode code={text(props.codeString)} language={text(props.language)} />;

const InlineHeader: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  return <View style={{ gap: 4, minWidth: 0, flexShrink: 1 }}>
    <NativeText selectable accessibilityRole="header" style={{ color: theme.ink, fontSize: 16, fontWeight: '600', lineHeight: 24 }}>
      {text(props.heading)}</NativeText>
    {text(props.description) ? <NativeText selectable style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{text(props.description)}</NativeText> : null}
  </View>;
};

const Icon: ComponentRenderer = ({ props }) => <NativeIcon name={text(props.name)} category={text(props.category)}
  accessibilityLabel={text(props.name)} />;

const Tag: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const icon = nodeProps(props.icon);
  const color = inkFor(props.variant, theme);
  const fontSize = props.size === 'lg' ? 14 : props.size === 'sm' ? 12 : 13;
  return <View accessible accessibilityLabel={text(props.text)} style={{ alignSelf: 'flex-start', maxWidth: '100%',
    minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: theme.surfaceMuted,
    paddingHorizontal: props.size === 'sm' ? 7 : 9, paddingVertical: props.size === 'lg' ? 6 : 4, borderRadius: 8 }}>
    {text(icon.name) ? <NativeIcon name={text(icon.name)} category={text(icon.category)} color={color} size={fontSize + 1} /> : null}
    <NativeText style={{ color, fontSize, lineHeight: Math.ceil(fontSize * 1.5), minWidth: 0, flexShrink: 1 }}>{text(props.text)}</NativeText>
  </View>;
};

const TagBlock: ComponentRenderer = ({ props, ...renderer }) => <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6, minWidth: 0 }}>
  {(Array.isArray(props.tags) ? props.tags : []).filter(item => typeof item === 'string').map((tag, index) =>
    <Tag key={index} {...renderer} props={{ text: tag, size: props.size }} />)}
</View>;

function TextLine({ props, bold = false }: { props: Record<string, unknown>; bold?: boolean }) {
  const theme = useOpenUITheme();
  const fontSize = { xs: 13, sm: 14, md: 16, lg: 18 }[text(props.size)] ?? 14;
  const subtext = text(props.subtext);
  const subtextColor = props.subtextVariant === 'metric' && /^[+-]/.test(subtext.trim())
    ? subtext.trim().startsWith('-') ? theme.destructive : theme.accent : theme.muted;
  return <View style={{ minWidth: 0, flexShrink: 1, gap: 3 }}>
    <NativeText selectable style={{ color: theme.ink, fontSize, lineHeight: Math.ceil(fontSize * 1.5), fontWeight: bold ? '600' : '400',
      fontVariant: props.variant === 'number' ? ['tabular-nums'] : undefined }}>{text(props.value)}</NativeText>
    {subtext ? <NativeText selectable style={{ color: subtextColor, fontSize: Math.max(12, fontSize - 2),
      lineHeight: Math.ceil(Math.max(12, fontSize - 2) * 1.5), fontVariant: props.subtextVariant === 'number' || props.subtextVariant === 'metric'
        ? ['tabular-nums'] : undefined }}>{subtext}</NativeText> : null}
  </View>;
}

const Text: ComponentRenderer = ({ props }) => <TextLine props={props} />;
const BoldText: ComponentRenderer = ({ props }) => <TextLine props={props} bold />;

const IconText: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const icon = nodeProps(props.icon);
  const vertical = props.layout === 'vertical';
  const size = { xs: 16, s: 18, sm: 18, m: 20, md: 20, l: 24, lg: 24, xl: 28 }[text(props.iconSize)] ?? 20;
  const inverted = props.iconVariant === 'inverted' || props.iconVariant === 'filled';
  return <View style={{ minWidth: 0, flexShrink: 1, flexDirection: vertical ? 'column' : 'row', alignItems: vertical ? 'flex-start' : 'center', gap: 10 }}>
    <View style={{ padding: 8, borderRadius: 10, backgroundColor: inverted ? theme.accent : theme.surfaceMuted }}>
      <NativeIcon name={text(icon.name)} category={text(icon.category)} size={size}
        color={inverted ? theme.onAccent : inkFor(props.iconVariant, theme)} />
    </View>
    <View style={{ minWidth: 0, flexShrink: 1, ...(vertical ? {} : { flex: 1 }) }}>
      <TextLine props={{ value: props.title, subtext: props.subtitle, size: 'sm' }} bold={props.bold === true} />
    </View>
  </View>;
};

const ImageText: ComponentRenderer = ({ props }) => {
  const vertical = props.layout === 'vertical';
  const imageSize = Math.max(24, Math.min(160, finiteNumber(props.imageSize, 40)));
  return <View style={{ minWidth: 0, flexShrink: 1, flexDirection: vertical ? 'column' : 'row', alignItems: vertical ? 'flex-start' : 'center', gap: 10 }}>
    <View style={{ width: imageSize, maxWidth: '100%', flexShrink: 0 }}>
      <NativeImage source={text(props.src)} alt={text(props.alt)} compact aspectRatio={1} resizeMode="cover" />
    </View>
    <View style={{ minWidth: 0, flexShrink: 1, ...(vertical ? {} : { flex: 1 }) }}>
      <TextLine props={{ value: props.title, subtext: props.subtitle, size: 'sm' }} bold={props.bold === true} />
    </View>
  </View>;
};

const ImageTextLarge: ComponentRenderer = ({ props }) => <View style={{ minWidth: 0, flexShrink: 1, gap: 10 }}>
  <NativeImage source={text(props.src)} alt={text(props.alt)} compact aspectRatio={16 / 9} resizeMode="cover" />
  <TextLine props={{ value: props.title, subtext: props.subtitle, size: 'sm' }} bold={props.bold === true} />
</View>;

function Metric({ props, previous = false }: { props: Record<string, unknown>; previous?: boolean }) {
  const theme = useOpenUITheme();
  const trend = record(props.trend);
  const hasTrend = (trend.direction === 'up' || trend.direction === 'down') && typeof trend.value === 'number' && Number.isFinite(trend.value);
  const down = trend.direction === 'down';
  const subtext = text(props.subtext);
  return <View style={{ minWidth: 0, flexShrink: 1, gap: 3 }}>
    <View style={{ minWidth: 0, flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap', columnGap: 8, rowGap: 3 }}>
      <NativeText selectable style={{ color: theme.ink, fontSize: 18, lineHeight: 27, fontWeight: '600', fontVariant: ['tabular-nums'], flexShrink: 1 }}>
        {text(props.value)}</NativeText>
      {previous && text(props.previousValue) ? <NativeText selectable style={{ color: theme.muted, fontSize: 13,
        lineHeight: 20, textDecorationLine: 'line-through', fontVariant: ['tabular-nums'] }}>{text(props.previousValue)}</NativeText> : null}
      {hasTrend ? <NativeText accessibilityLabel={`${down ? '下降' : '上升'} ${Math.abs(trend.value as number)}%`}
        style={{ color: down ? theme.destructive : theme.accent, fontSize: 13, lineHeight: 20, fontVariant: ['tabular-nums'] }}>
        {down ? '−' : '+'}{Math.abs(trend.value as number)}%</NativeText> : null}
      {!previous && subtext ? <NativeText selectable style={{ color: theme.muted, fontSize: 13, lineHeight: 20, flexShrink: 1 }}>{subtext}</NativeText> : null}
    </View>
    {previous && subtext ? <NativeText selectable style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{subtext}</NativeText> : null}
  </View>;
}

const MetricIndicatorInline: ComponentRenderer = ({ props }) => <Metric props={props} />;
const MetricIndicatorWithStrikethrough: ComponentRenderer = ({ props }) => <Metric props={props} previous />;

const EntityList: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const small = props.size === 'small';
  const rows = (Array.isArray(props.rows) ? props.rows : []).map(record);
  const row = (item: Record<string, unknown>, key: string, strong = false) => <View key={key} style={{
    flexDirection: 'row', gap: 12, paddingVertical: small ? 6 : 9, minWidth: 0,
    borderBottomWidth: strong ? StyleSheet.hairlineWidth : 0, borderColor: theme.border }}>
    <NativeText selectable style={{ color: strong ? theme.ink : theme.muted, fontSize: small ? 13 : 14,
      lineHeight: small ? 20 : 21, fontWeight: strong ? '600' : '400', minWidth: 0, flex: 1 }}>{text(item.left)}</NativeText>
    <NativeText selectable style={{ color: theme.ink, fontSize: small ? 13 : 14, lineHeight: small ? 20 : 21,
      fontWeight: strong ? '600' : '400', fontVariant: item.rightVariant === 'number' ? ['tabular-nums'] : undefined,
      textAlign: 'right', minWidth: 0, flex: 1 }}>{text(item.right)}</NativeText>
  </View>;
  return <View style={{ minWidth: 0, flexShrink: 1 }}>
    {!small && props.header ? row(record(props.header), 'header', true) : null}
    {rows.map((item, index) => row(item, `row:${index}`))}
    {!small && props.footer ? row(record(props.footer), 'footer', true) : null}
  </View>;
};

function ListRow({ item, index, variant, small }: { item: Record<string, unknown>; index: number; variant: unknown; small: boolean }) {
  const theme = useOpenUITheme();
  const { invoke, disabled, pending, error } = useNativeAction(JSON.stringify([item.title, item.action]));
  const action = item.action as Parameters<typeof invoke>[1];
  const hasAction = Boolean(action);
  const title = text(item.title);
  const image = record(item.image);
  return <View style={{ minWidth: 0, flexShrink: 1 }}>
    <Pressable accessible={hasAction} accessibilityRole={hasAction ? 'button' : undefined} accessibilityLabel={title}
      accessibilityHint={text(item.actionLabel) || undefined} accessibilityState={{ disabled: hasAction && disabled, busy: pending }}
      disabled={!hasAction || disabled} onPress={() => { if (hasAction && !disabled) void invoke(title, action); }}
      style={({ pressed }) => ({ minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10,
        paddingVertical: small ? 6 : 10, minHeight: hasAction ? theme.controlMinHeight : undefined,
        opacity: pressed || hasAction && disabled ? 0.6 : 1 })}>
      {variant === 'image' ? text(image.src) ? <View style={{ width: small ? 32 : 40 }}>
        <NativeImage source={text(image.src)} alt={text(image.alt)} compact aspectRatio={1} resizeMode="cover" />
      </View> : null : <NativeText style={{ color: theme.muted, fontSize: small ? 13 : 14, minWidth: 18 }}>{index + 1}.</NativeText>}
      <View style={{ flex: 1, minWidth: 0, gap: 3 }}>
        <NativeText selectable={!hasAction} style={{ color: theme.ink, fontSize: small ? 13 : 14, lineHeight: 21 }}>{title}</NativeText>
        {text(item.subtitle) ? <NativeText selectable={!hasAction} style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{text(item.subtitle)}</NativeText> : null}
        {hasAction && text(item.actionLabel) ? <NativeText style={{ color: theme.accent, fontSize: 13, lineHeight: 20 }}>{text(item.actionLabel)}</NativeText> : null}
      </View>
    </Pressable>
    {error ? <NativeText accessibilityLiveRegion="polite" style={{ color: theme.destructive, fontSize: 13, lineHeight: 20 }}>{error}</NativeText> : null}
  </View>;
}

const ListBlock: ComponentRenderer = ({ props }) => <View style={{ minWidth: 0, flexShrink: 1 }}>
  {elements(props.items).map((item, index) => <ListRow key={index} item={item.props} index={index}
    variant={props.variant} small={props.size === 'small'} />)}
</View>;

function FollowUp({ label }: { label: string }) {
  const theme = useOpenUITheme();
  const { invoke, disabled, pending, error } = useNativeAction(label);
  return <View style={{ minWidth: 0, flexShrink: 1 }}>
    <Pressable accessibilityRole="button" accessibilityLabel={label} accessibilityState={{ disabled, busy: pending }}
      disabled={disabled} onPress={() => { if (!disabled) void invoke(label); }}
      style={({ pressed }) => ({ minHeight: theme.controlMinHeight, minWidth: 0, justifyContent: 'center', paddingVertical: 10,
        borderBottomWidth: StyleSheet.hairlineWidth, borderColor: theme.border, opacity: disabled || pressed ? 0.6 : 1 })}>
      <NativeText style={{ color: theme.accent, fontSize: 14, lineHeight: 21 }}>{label}</NativeText>
    </Pressable>
    {error ? <NativeText accessibilityLiveRegion="polite" style={{ color: theme.destructive, fontSize: 13, lineHeight: 20 }}>{error}</NativeText> : null}
  </View>;
}

const FollowUpBlock: ComponentRenderer = ({ props }) => <View style={{ minWidth: 0, flexShrink: 1 }}>
  {elements(props.items).map((item, index) => <FollowUp key={index} label={text(item.props.text)} />)}
</View>;

// The official catalog models these as data-only children consumed by their block.
const DataItem: ComponentRenderer = () => null;

export const contentRenderers: Record<string, ComponentRenderer> = {
  MarkDownRenderer, Callout, TextCallout, ImageBlock, ImageGallery, CodeBlock, InlineHeader,
  Tag, TagBlock, Icon, EntityList, ListBlock, ListItem: DataItem, FollowUpBlock, FollowUpItem: DataItem,
  Text, BoldText, IconText, ImageText, ImageTextLarge, MetricIndicatorInline, MetricIndicatorWithStrikethrough,
};

import { Fragment, useState, type ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { useFormName, type ComponentRenderer, type ElementNode } from '@openuidev/react-lang';
import { useOpenUITheme } from '../theme';
import { NativeImage } from './NativeImage';
import { elements, finiteNumber, nodeProps, record, text } from './contentUtils';
import { withCardItemContext } from './cardActions';
import { useNativeAction } from './useNativeAction';

type Family = 'Snippet' | 'Overview' | 'Context' | 'Composite' | 'Visual';
type RenderNode = (value: unknown) => ReactNode;
const override = (node: unknown, props: Record<string, unknown>) => ({ ...record(node), props: { ...nodeProps(node), ...props } });
const optionalText = (value: unknown) => typeof value === 'string' ? value : undefined;

function itemContext(family: Family, item: Record<string, unknown>, index: number) {
  const common = { itemIndex: index, itemId: item.id };
  if (family === 'Snippet') {
    const lhs = nodeProps(item.lhs);
    return { label: text(lhs.title) || text(item.id) || `Snippet card ${index + 1}`,
      context: { ...common, itemTitle: lhs.title, itemSubtitle: lhs.subtitle, itemValue: nodeProps(item.rhs).value } };
  }
  if (family === 'Overview') {
    const top = nodeProps(item.top);
    const title = optionalText(top.title) ?? optionalText(top.value);
    return { label: title ?? text(item.id, `Overview card ${index + 1}`), context: { ...common,
      itemTitle: title, itemSubtitle: optionalText(top.subtitle) ?? optionalText(top.subtext), itemMetricValue: nodeProps(item.bottom).value } };
  }
  if (family === 'Context') {
    const title = typeof item.title === 'string' ? item.title : text(nodeProps(item.title).text);
    return { label: title || text(item.id) || `Context card ${index + 1}`, context: { ...common,
      itemTitle: title, itemBody: item.body, itemBgColor: item.bgColor, itemBgImageSrc: item.bgImageSrc, itemBgImageAlt: item.bgImageAlt } };
  }
  if (family === 'Composite') {
    const header = nodeProps(item.header);
    const footer = record(item.footer);
    const title = optionalText(header.title) ?? optionalText(header.value);
    return { label: title || text(header.alt) || text(item.id) || `Composite card ${index + 1}`, context: { ...common,
      itemHeaderTitle: title, itemHeaderSubtitle: optionalText(header.subtitle) ?? optionalText(header.subtext), itemHeaderAlt: header.alt,
      itemBodyCount: Array.isArray(item.body) ? item.body.length : 0, itemFooterPrice: nodeProps(footer.price).value,
      itemFooterButtonLabel: nodeProps(footer.button).label } };
  }
  const body = nodeProps(item.body);
  const tag = nodeProps(item.tag);
  return { label: text(body.value) || text(tag.text) || text(item.id) || `Visual card ${index + 1}`, context: { ...common,
    itemTag: tag.text, itemBody: body.value, itemBodySubtext: body.subtext, itemBgImageSrc: item.bgImageSrc, itemBgImageAlt: item.bgImageAlt } };
}

function compactNode(node: unknown, renderNode: RenderNode, footer = false) {
  const name = text(record(node).typeName);
  if (!footer && (name === 'Text' || name === 'BoldText')) return renderNode(override(node, { size: 'xs' }));
  if (name === 'ListBlock') return renderNode(override(node, { size: 'small' }));
  if (name === 'EntityList') return renderNode(override(node, { size: 'small', header: undefined, footer: undefined }));
  if (name === 'TagBlock') return renderNode(override(node, { size: 'sm' }));
  if (name === 'Button') return renderNode(override(node, { size: 'small' }));
  return renderNode(node);
}

function CardBody({ family, item, renderNode }: { family: Family; item: Record<string, unknown>; renderNode: RenderNode }) {
  const theme = useOpenUITheme();
  if (family === 'Snippet') return <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, minWidth: 0 }}>
    <View style={{ flex: 1, minWidth: 0 }}>{renderNode(item.lhs)}</View>
    {item.rhs ? <View style={{ maxWidth: '40%', minWidth: 0 }}>{renderNode(override(item.rhs, { size: 'xs' }))}</View> : null}
  </View>;
  if (family === 'Overview') return <View style={{ minWidth: 0, gap: 14 }}>
    {renderNode(item.top)}{item.bottom ? renderNode(item.bottom) : null}
  </View>;
  if (family === 'Context') return <View style={{ minWidth: 0, gap: 10 }}>
    {typeof item.title === 'string' ? <Text selectable style={{ color: theme.ink, fontSize: 14, lineHeight: 21 }}>{item.title}</Text> : renderNode(item.title)}
    {text(item.body) ? <Text selectable style={{ color: theme.ink, fontSize: 16, lineHeight: 24, fontWeight: '600' }}>{text(item.body)}</Text> : null}
  </View>;
  if (family === 'Composite') return <View style={{ minWidth: 0, gap: 12 }}>
    {item.header ? renderNode(item.header) : null}
    {(Array.isArray(item.body) ? item.body : []).map((node, index) => <Fragment key={index}>{compactNode(node, renderNode)}</Fragment>)}
  </View>;
  return <View style={{ minWidth: 0, minHeight: text(item.bgImageSrc) ? undefined : 160, justifyContent: 'space-between', gap: 24 }}>
    {!text(item.bgImageSrc) && item.tag ? renderNode(item.tag) : null}
    <View style={{ minWidth: 0, borderRadius: 10, backgroundColor: theme.surface, padding: 12 }}>{renderNode(item.body)}</View>
  </View>;
}

function NativeCard({ family, node, index, action, renderNode }: {
  family: Family; node: ElementNode; index: number; action: unknown; renderNode: RenderNode;
}) {
  const theme = useOpenUITheme();
  const formName = useFormName();
  const item = node.props;
  const hasAction = Boolean(action);
  const { label, context } = itemContext(family, item, index);
  const { invoke, disabled, pending, error } = useNativeAction(JSON.stringify([family, label, action, context, formName]));
  const footer = family === 'Composite' ? record(item.footer) : {};
  const source = family === 'Context' || family === 'Visual' ? text(item.bgImageSrc) : '';
  // A normal image child keeps its retry hit target reachable. Text can overlap
  // the photo's lower edge without a full-card overlay intercepting the image.
  const content = <View style={{ minWidth: 0, flex: 1 }}>
    {source ? <View style={{ height: family === 'Visual' ? 180 : 96 }}>
      <NativeImage source={source} alt={text(item.bgImageAlt)} compact fill resizeMode="cover" />
    </View> : null}
    {source && family === 'Visual' && item.tag ? <View pointerEvents="none"
      style={{ position: 'absolute', top: 14, left: 14, right: 14 }}>{renderNode(item.tag)}</View> : null}
    <View style={{ minWidth: 0, padding: 14, marginTop: source && family === 'Visual' ? -38 : 0 }}>
      <CardBody family={family} item={item} renderNode={renderNode} />
    </View>
  </View>;
  return <View style={{ minWidth: 0, flex: 1, borderRadius: 14, overflow: 'hidden', backgroundColor:
    family === 'Context' && item.bgColor === 'gray' ? theme.surfaceMuted : theme.surface,
    borderWidth: StyleSheet.hairlineWidth, borderColor: theme.border }}>
    {hasAction ? <Pressable accessibilityRole="button" accessibilityLabel={label} accessibilityState={{ disabled, busy: pending }}
      disabled={disabled} onPress={() => { if (!disabled) void invoke(label, withCardItemContext(action, context), formName); }}
      style={({ pressed }) => ({ minWidth: 0, flex: 1, opacity: disabled || pressed ? 0.6 : 1 })}>
      {content}
    </Pressable> : content}
    {footer.price || footer.button ? <View style={{ paddingHorizontal: 14, paddingBottom: 14, minWidth: 0,
      flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 10 }}>
      {footer.price ? <View style={{ flexGrow: 1, minWidth: 0, flexShrink: 1 }}>{compactNode(footer.price, renderNode, true)}</View> : null}
      {footer.button ? <View style={{ minWidth: 0, flexShrink: 1 }}>{compactNode(footer.button, renderNode, true)}</View> : null}
    </View> : null}
    {error ? <Text accessibilityLiveRegion="polite" style={{ color: theme.destructive, fontSize: 13, lineHeight: 20,
      paddingHorizontal: 14, paddingBottom: 10, backgroundColor: theme.surface }}>{error}</Text> : null}
  </View>;
}

function spacing(value: unknown, fallback: number) {
  if (typeof value === 'number') return Math.max(0, Math.min(96, finiteNumber(value, fallback)));
  const match = typeof value === 'string' ? /^\s*(\d+(?:\.\d+)?)\s*(px|rem)?\s*$/.exec(value) : null;
  return match ? Math.min(96, Number(match[1]) * (match[2] === 'rem' ? 16 : 1)) : fallback;
}

function makeBlock(family: Family): ComponentRenderer {
  return function CardBlock({ props, renderNode }) {
    const theme = useOpenUITheme();
    const window = useWindowDimensions();
    const [measured, setMeasured] = useState(0);
    const items = elements(props.items);
    const available = measured || Math.max(0, window.width - 32);
    const gap = spacing(props.gap, theme.gap.m);
    const carousel = props.layout === 'carousel';
    const columns = props.responsive === false ? 2 : available >= 480 * Math.min(window.fontScale, 1.6) ? 2 : 1;
    const width = carousel ? Math.min(340, available * 0.86) : Math.max(0, (available - gap * (columns - 1)) / columns);
    const cards = items.map((node, index) => <View key={`${text(node.props.id, String(index))}:${index}`}
      style={{ width, minWidth: 0, flexShrink: 0 }}>
      <NativeCard family={family} node={node} index={index} action={props.action} renderNode={renderNode} />
    </View>);
    return <View onLayout={event => {
      const next = event.nativeEvent.layout.width;
      if (Number.isFinite(next) && next >= 0 && Math.abs(next - measured) > 0.5) setMeasured(next);
    }} style={{ minWidth: 0, flexShrink: 1 }}>
      {carousel ? <ScrollView horizontal nestedScrollEnabled accessibilityLabel="卡片，可横向滚动"
        showsHorizontalScrollIndicator contentContainerStyle={{ gap, alignItems: 'stretch' }}>{cards}</ScrollView>
        : <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap, alignItems: 'stretch', minWidth: 0 }}>{cards}</View>}
    </View>;
  };
}

const DataItem: ComponentRenderer = () => null;
export const cardRenderers: Record<string, ComponentRenderer> = {
  SnippetCardItem: DataItem, SnippetCardBlock: makeBlock('Snippet'),
  OverviewCardItem: DataItem, OverviewCardBlock: makeBlock('Overview'),
  ContextCardItem: DataItem, ContextCardBlock: makeBlock('Context'),
  CompositeCardItem: DataItem, CompositeCardBlock: makeBlock('Composite'),
  VisualCardItem: DataItem, VisualCardBlock: makeBlock('Visual'),
};

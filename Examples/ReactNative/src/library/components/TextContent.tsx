import { useEffect, useMemo, useRef, type ReactNode } from 'react';
import { Platform, ScrollView, StyleSheet, Text, View, type TextStyle } from 'react-native';
import { BuiltinActionType, type ComponentRenderer } from '@openuidev/react-lang';
import { decodeHTMLStrict } from 'entities';
import type { Token, Tokens } from 'marked';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme, type NativeTheme } from '../theme';
import { contentLink, useNativeContentPolicy } from './contentPolicy';
import { NativeImage } from './NativeImage';
import { NativeCode } from './NativeCode';
import { parseNativeMarkdown, splitInlineImages } from './markdown';
import { useNativeAction } from './useNativeAction';

type Presentation = { theme: NativeTheme; text: TextStyle; fontSize: number };
const mono = Platform.OS === 'ios' ? 'Menlo' : 'monospace';
const children = (token: Token): Token[] => 'tokens' in token && Array.isArray(token.tokens) ? token.tokens : [];
const textOf = (token: Token): string => 'text' in token && typeof token.text === 'string' ? token.text : token.raw;
const plainText = (tokens: Token[]): string => tokens.map(token => {
  if (token.type === 'br') return '\n';
  const nested = children(token);
  if (nested.length) return plainText(nested);
  if (token.type === 'codespan' || token.type === 'escape' || token.type === 'html') return textOf(token);
  return decodeHTMLStrict(textOf(token));
}).join('');

function MarkdownLink({ href, label, children: content }: { href: string; label: string; children: ReactNode }) {
  const theme = useOpenUITheme();
  const url = contentLink(href);
  const { invoke, disabled, pending, error } = useNativeAction(JSON.stringify([url, label]));
  if (!url) return <Text>{content}</Text>;
  return <Text accessibilityRole="link" accessibilityLabel={label || url}
    accessibilityHint={error || '由应用处理外部链接'} accessibilityState={{ disabled, busy: pending }}
    onPress={() => { if (!disabled) void invoke(label || url, { type: BuiltinActionType.OpenUrl, params: { url } }); }}
    style={{ color: theme.accent, textDecorationLine: 'underline', opacity: disabled ? 0.6 : 1 }}>
    {content}{error ? <Text accessibilityLiveRegion="polite">（打开失败，请重试）</Text> : null}
  </Text>;
}

function inline(tokens: Token[], presentation: Presentation): ReactNode[] {
  return tokens.map((token, index) => {
    const key = `${index}:${token.type}`;
    switch (token.type) {
      case 'strong': return <Text key={key} style={{ fontWeight: '700' }}>{inline(children(token), presentation)}</Text>;
      case 'em': return <Text key={key} style={{ fontStyle: 'italic' }}>{inline(children(token), presentation)}</Text>;
      case 'del': return <Text key={key} style={{ textDecorationLine: 'line-through' }}>{inline(children(token), presentation)}</Text>;
      case 'codespan': return <Text key={key} style={{ fontFamily: mono,
        fontSize: Math.max(12, presentation.fontSize - 1), backgroundColor: presentation.theme.code }}>
        {textOf(token)}</Text>;
      case 'br': return '\n';
      case 'checkbox': return null; // The list marker presents task state accessibly.
      case 'link': {
        const link = token as Tokens.Link;
        // GFM autolinks are literal; explicit Markdown links resolve character references.
        const href = link.autolink ? link.href : decodeHTMLStrict(link.href);
        return <MarkdownLink key={`${key}:${href}`} href={href}
          label={link.autolink ? link.text : plainText(link.tokens)}>
          {link.autolink ? link.text : inline(link.tokens, presentation)}
        </MarkdownLink>;
      }
      case 'escape':
      case 'html': return <Text key={key}>{textOf(token)}</Text>;
      case 'text': return children(token).length
        ? <Text key={key}>{inline(children(token), presentation)}</Text>
        : <Text key={key}>{decodeHTMLStrict(textOf(token))}</Text>;
      default: return <Text key={key}>{textOf(token)}</Text>;
    }
  });
}

function paragraph(tokens: Token[], presentation: Presentation, key: string, heading?: number): ReactNode {
  const headingSize = heading ? presentation.fontSize * [1.75, 1.5, 1.25, 1.125, 1, 1][heading - 1] : undefined;
  const style: TextStyle = heading ? { ...presentation.text, fontSize: headingSize,
    lineHeight: Math.ceil(headingSize! * 1.4), fontWeight: '700' } : presentation.text;
  const parts = splitInlineImages(tokens);
  return <View key={key} style={{ minWidth: 0, flexShrink: 1, gap: presentation.theme.gap.m }}>
    {parts.map((part, index) => {
      if (part.kind === 'text') return <Text key={index} selectable
        accessibilityRole={heading ? 'header' : undefined} style={style}>{inline(part.tokens, presentation)}</Text>;
      const alt = part.image.tokens?.length ? plainText(part.image.tokens) : decodeHTMLStrict(part.image.text);
      return <View key={index} style={{ minWidth: 0, flexShrink: 1, gap: 6 }}>
        <NativeImage source={decodeHTMLStrict(part.image.href)} alt={alt} />
        {part.link ? <Text style={presentation.text}>
          <MarkdownLink href={part.link.autolink ? part.link.href : decodeHTMLStrict(part.link.href)}
            label={alt || '打开图片链接'}>{alt || '打开图片链接'}</MarkdownLink>
        </Text> : null}
      </View>;
    })}
  </View>;
}

function table(token: Tokens.Table, presentation: Presentation, key: string): ReactNode {
  const { theme } = presentation;
  return <ScrollView key={key} horizontal nestedScrollEnabled
    accessibilityLabel="表格，可横向滚动" showsHorizontalScrollIndicator
    style={{ minWidth: 0, flexShrink: 1, maxWidth: '100%' }}>
    <View style={{ borderWidth: StyleSheet.hairlineWidth, borderColor: theme.border, borderRadius: 8, overflow: 'hidden' }}>
      {[token.header, ...token.rows].map((row, rowIndex) => <View key={rowIndex}
        style={{ flexDirection: 'row', alignItems: 'stretch', backgroundColor: rowIndex === 0 ? theme.surfaceMuted : theme.surface }}>
        {row.map((cell, columnIndex) => <View key={columnIndex} style={{ width: 180, padding: 12,
          borderRightWidth: columnIndex === row.length - 1 ? 0 : StyleSheet.hairlineWidth,
          borderBottomWidth: rowIndex === token.rows.length ? 0 : StyleSheet.hairlineWidth,
          borderColor: theme.border }}>
          {paragraph(cell.tokens, { ...presentation, text: { ...presentation.text,
            textAlign: token.align[columnIndex] ?? 'left', fontWeight: rowIndex === 0 ? '600' : presentation.text.fontWeight } }, `cell-${columnIndex}`)}
        </View>)}
      </View>)}
    </View>
  </ScrollView>;
}

function blocks(tokens: Token[], presentation: Presentation): ReactNode[] {
  const { theme } = presentation;
  return tokens.map((token, index) => {
    const key = `${index}:${token.type}`;
    switch (token.type) {
      case 'space':
      case 'def':
      case 'checkbox': return null;
      case 'heading': return paragraph(children(token), presentation, key, (token as Tokens.Heading).depth);
      case 'paragraph':
      case 'text': return paragraph(children(token).length ? children(token) : [token], presentation, key);
      case 'code': {
        const code = token as Tokens.Code;
        return <NativeCode key={key} code={code.text} language={code.lang} fontSize={Math.max(12, presentation.fontSize - 1)} />;
      }
      case 'blockquote': return <View key={key} style={{ minWidth: 0, flexShrink: 1,
        borderLeftWidth: 3, borderLeftColor: theme.accent, paddingLeft: 14, gap: theme.gap.m }}>
        {blocks(children(token), { ...presentation, text: { ...presentation.text, color: theme.muted } })}
      </View>;
      case 'list': {
        const list = token as Tokens.List;
        return <View key={key} style={{ minWidth: 0, flexShrink: 1, gap: list.loose ? theme.gap.m : theme.gap.s }}>
          {list.items.map((item, itemIndex) => {
            const marker = item.task ? item.checked ? '☑' : '☐'
              : list.ordered ? `${Number(list.start) + itemIndex}.` : '•';
            return <View key={itemIndex} style={{ minWidth: 0, flexDirection: 'row', alignItems: 'flex-start', gap: 8 }}>
              <Text accessibilityLabel={item.task ? item.checked ? '已完成' : '未完成' : undefined}
                style={[presentation.text, { minWidth: 20, flexShrink: 0 }]}>{marker}</Text>
              <View style={{ minWidth: 0, flex: 1, gap: theme.gap.s }}>{blocks(item.tokens, presentation)}</View>
            </View>;
          })}
        </View>;
      }
      case 'table': return table(token as Tokens.Table, presentation, key);
      case 'hr': return <View key={key} accessible={false} importantForAccessibility="no"
        style={{ height: StyleSheet.hairlineWidth, backgroundColor: theme.border }} />;
      // HTML is displayed as inert text. No DOM, WebView or HTML execution is involved.
      default: return <Text key={key} selectable style={presentation.text}>{textOf(token)}</Text>;
    }
  });
}

export const TextContent: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const { isCurrent } = useDocumentInteraction();
  const { onError } = useNativeContentPolicy();
  const source = typeof props.text === 'string' ? props.text : '';
  const size = typeof props.size === 'string' ? props.size : 'default';
  const parsed = useMemo(() => parseNativeMarkdown(source), [source]);
  const content = useMemo(() => {
    const fontSize = size.startsWith('small') ? 13 : size.startsWith('large') ? 19 : 16;
    const presentation: Presentation = { theme, fontSize, text: { color: theme.ink, fontSize,
      lineHeight: Math.ceil(fontSize * 1.55), fontWeight: size.endsWith('heavy') ? '600' : '400',
      minWidth: 0, flexShrink: 1 } };
    // The official Store context updates on unrelated field edits. Reuse the
    // reading tree; links/images still subscribe to their own live contexts.
    return parsed.kind === 'plain' ? <Text selectable style={presentation.text}>{parsed.text}</Text>
      : blocks(parsed.tokens, presentation);
  }, [parsed, size, theme]);
  const parseError = parsed.kind === 'plain' ? parsed.error : undefined;
  const reportedParseError = useRef<Error | undefined>(undefined);
  useEffect(() => {
    if (!parseError) { reportedParseError.current = undefined; return; }
    if (parseError && isCurrent()) {
      if (reportedParseError.current === parseError) return;
      reportedParseError.current = parseError;
      try { onError?.(parseError); } catch { /* Reporting must not break content. */ }
    }
  }, [parseError, onError, isCurrent]);
  if (!source) return null;
  return <View style={{ minWidth: 0, flexShrink: 1, gap: theme.gap.m }}>
    {content}
  </View>;
};

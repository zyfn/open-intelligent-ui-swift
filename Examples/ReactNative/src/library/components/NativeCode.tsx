import { useEffect, useMemo, useRef } from 'react';
import { Platform, ScrollView, Text, View } from 'react-native';
import Prism from 'prismjs';
import 'prismjs/components/prism-typescript';
import 'prismjs/components/prism-json';
import 'prismjs/components/prism-python';
import 'prismjs/components/prism-bash';
import { normalizeError } from '../../runtime/errors';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme } from '../theme';
import { useNativeContentPolicy } from './contentPolicy';

type Run = { text: string; type: string };
type Highlight = { runs: Run[]; error?: Error };
const aliases: Record<string, string> = { js: 'javascript', ts: 'typescript', sh: 'bash', shell: 'bash', html: 'markup', xml: 'markup' };

function highlight(code: string, language: string): Highlight {
  const plain = { runs: [{ text: code, type: '' }] };
  const name = language.toLowerCase().trim().split(/\s/)[0];
  const key = Object.hasOwn(aliases, name) ? aliases[name] : name;
  // Unknown languages and oversized code remain complete, selectable plain text.
  if (code.length > 65_536 || !Object.hasOwn(Prism.languages, key)) return plain;
  const grammar = Prism.languages[key];
  if (!grammar || typeof grammar !== 'object') return plain;
  try {
    const tokens = Prism.tokenize(code, grammar);
    const stack: { value: string | Prism.Token | (string | Prism.Token)[]; type: string; depth: number }[] = [
      { value: tokens, type: '', depth: 0 },
    ];
    const runs: Run[] = [];
    let count = 0;
    while (stack.length) {
      const item = stack.pop()!;
      if (++count > 4_096 || item.depth > 24) return plain;
      if (typeof item.value === 'string') runs.push({ text: item.value, type: item.type });
      else if (Array.isArray(item.value)) {
        if (count + item.value.length > 4_096) return plain;
        for (let index = item.value.length - 1; index >= 0; index--) {
          stack.push({ value: item.value[index], type: item.type, depth: item.depth + 1 });
        }
      } else stack.push({ value: item.value.content, type: item.value.type, depth: item.depth + 1 });
    }
    return { runs };
  } catch (cause) { return { ...plain, error: normalizeError(cause) }; }
}

/** Prism only tokenizes. All display stays selectable native text, with no HTML. */
export function NativeCode({ code, language = '', fontSize = 14 }: { code: string; language?: string; fontSize?: number }) {
  const theme = useOpenUITheme();
  const { isCurrent } = useDocumentInteraction();
  const { onError } = useNativeContentPolicy();
  const reported = useRef<Error | undefined>(undefined);
  const highlighted = useMemo(() => highlight(code, language), [code, language]);
  useEffect(() => {
    if (highlighted.error && highlighted.error !== reported.current && isCurrent()) {
      reported.current = highlighted.error;
      try { onError?.(highlighted.error); } catch { /* Host reporting cannot replace readable code. */ }
    }
  }, [highlighted, onError, isCurrent]);
  const content = useMemo(() => highlighted.runs.map((run, index) => {
    const comment = /^(comment|prolog|doctype|cdata)$/.test(run.type);
    const accent = /^(keyword|boolean|number|string|char|builtin|function|class-name|attr-value)$/.test(run.type);
    return <Text key={index} style={{ color: comment ? theme.muted : accent ? theme.accent : theme.ink,
      fontStyle: comment ? 'italic' : 'normal', fontWeight: run.type === 'keyword' ? '600' : '400' }}>{run.text}</Text>;
  }), [highlighted, theme]);
  return <View style={{ minWidth: 0, flexShrink: 1, borderRadius: 10, backgroundColor: theme.code, paddingVertical: 12, gap: 6 }}>
    {language ? <Text style={{ color: theme.muted, fontSize: 12, paddingHorizontal: 14 }}>{language}</Text> : null}
    <ScrollView horizontal nestedScrollEnabled accessibilityLabel="代码块，可横向滚动" contentContainerStyle={{ paddingHorizontal: 14 }}>
      <Text selectable style={{ color: theme.ink, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
        fontSize, lineHeight: Math.ceil(fontSize * 1.5) }}>{content}</Text>
    </ScrollView>
  </View>;
}

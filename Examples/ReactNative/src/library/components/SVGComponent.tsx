import { Component, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { ActivityIndicator, Modal, Pressable, ScrollView, Text, useWindowDimensions, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { SvgXml } from 'react-native-svg';
import { useIsStreaming, type ComponentRenderer } from '@openuidev/react-lang';
import { normalizeError } from '../../runtime/errors';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme } from '../theme';
import { NativeIcon } from './NativeIcon';
import { contentImage, contentLink, useNativeContentPolicy } from './contentPolicy';
import { text } from './contentUtils';
import { readSvgResponse, validateNativeSvg, type ValidSvg } from './svgSource';

type SvgState = { kind: 'loading' } | { kind: 'ready'; svg: ValidSvg } | { kind: 'error'; error: Error; report?: boolean };

class SvgBoundary extends Component<{ children: ReactNode; fallback: ReactNode; onFailure: (error: Error) => void }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch(error: Error) { this.props.onFailure(error); }
  render() { return this.state.failed ? this.props.fallback : this.props.children; }
}

function SvgFailure({ alt, disabled, retry }: { alt: string; disabled: boolean; retry: () => void }) {
  const theme = useOpenUITheme();
  return <Pressable accessibilityRole="button" accessibilityLabel="重新加载图形" accessibilityHint={alt || 'SVG 图形'}
    accessibilityState={{ disabled }} disabled={disabled} onPress={event => { event?.stopPropagation?.(); retry(); }}
    style={({ pressed }) => ({ width: '100%', aspectRatio: 16 / 9, minHeight: theme.controlMinHeight,
      minWidth: 0, borderRadius: 12, backgroundColor: theme.surfaceMuted, padding: 16,
      justifyContent: 'center', alignItems: 'center', opacity: disabled ? 0.5 : pressed ? 0.7 : 1 })}>
    <Text style={{ color: theme.accent, fontSize: 14 }}>点击重试</Text>
  </Pressable>;
}

function SvgLoading({ alt, active }: { alt: string; active: boolean }) {
  const theme = useOpenUITheme();
  return <View accessible accessibilityRole="image" accessibilityLabel={`${alt || 'SVG 图形'}，${active ? '正在加载' : '尚未完成'}`}
    style={{ width: '100%', aspectRatio: 16 / 9, minWidth: 0, borderRadius: 12,
      backgroundColor: theme.surfaceMuted, alignItems: 'center', justifyContent: 'center' }}>
    {active ? <ActivityIndicator color={theme.accent} /> : <Text style={{ color: theme.muted, fontSize: 13 }}>图形尚未完成</Text>}
  </View>;
}

function SvgResource({ content, source, alt }: { content: string; source: string; alt: string }) {
  const theme = useOpenUITheme();
  const dimensions = useWindowDimensions();
  const streaming = useIsStreaming();
  const { canInteract, isCurrent } = useDocumentInteraction();
  const { resolveImage, onError } = useNativeContentPolicy();
  const mounted = useRef(true);
  const reported = useRef<Error | undefined>(undefined);
  const [attempt, setAttempt] = useState(0);
  const [expanded, setExpanded] = useState(false);
  const [remote, setRemote] = useState<SvgState>({ kind: 'loading' });
  useLayoutEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const available = !streaming && canInteract();
  const local = useMemo<SvgState | { kind: 'remote' }>(() => {
    if (!content.trim() && !source.trim()) return { kind: 'error', report: false,
      // The official Store may initialize a referenced source just after mount.
      // Empty data stays a quiet placeholder; it is not a host transport failure.
      error: new Error('SVG content or src is unavailable') };
    if (content.trim() && source.trim()) return { kind: 'error', error: new Error('SVG requires exactly one content or src') };
    if (source.trim()) return { kind: 'remote' };
    try { return { kind: 'ready', svg: validateNativeSvg(content) }; }
    catch (cause) { return { kind: 'error', error: normalizeError(cause) }; }
  }, [content, source, attempt]);

  useEffect(() => {
    if (local.kind !== 'remote' || streaming || !canInteract()) return;
    let active = true;
    let timedOut = false;
    const request = new AbortController();
    const timeoutError = new Error('SVG request timed out');
    const current = () => active && mounted.current && canInteract();
    setRemote({ kind: 'loading' });
    const timeout = setTimeout(() => {
      timedOut = true;
      request.abort();
      if (current()) setRemote({ kind: 'error', error: timeoutError });
    }, 15_000);
    void (async () => {
      try {
        const mapped = contentImage(source, { resolveImage });
        const candidate = Array.isArray(mapped) ? mapped[0] : mapped;
        if (!candidate || typeof candidate === 'number' || !candidate.uri
          || !contentLink(candidate.uri)?.startsWith('https:')) throw new Error('SVG source must resolve to an HTTPS resource');
        // Expo's native fetch exposes a streaming body, so the 1 MiB bound is
        // checked before a complete remote response is buffered in JavaScript.
        // Keep the native transport lazy without requiring an ESM VM in host tests.
        const { fetch } = require('expo/fetch') as typeof import('expo/fetch');
        if (!current() || request.signal.aborted) return;
        const response = await fetch(candidate.uri, { headers: candidate.headers, signal: request.signal,
          credentials: 'omit', redirect: 'error' });
        const xml = await readSvgResponse(response, request.signal);
        if (!current() || request.signal.aborted) return;
        const svg = validateNativeSvg(xml);
        if (current() && !request.signal.aborted) setRemote({ kind: 'ready', svg });
      } catch (cause) {
        if (current()) setRemote({ kind: 'error', error: timedOut ? timeoutError : normalizeError(cause) });
        request.abort();
      } finally { clearTimeout(timeout); }
    })();
    return () => { active = false; clearTimeout(timeout); request.abort(); };
  }, [local, source, resolveImage, attempt, streaming, canInteract]);

  const report = useCallback((error: Error) => {
    if (!mounted.current || streaming || !isCurrent() || reported.current === error) return;
    reported.current = error;
    try { onError?.(error); } catch { /* Diagnostics cannot replace the diagram. */ }
  }, [streaming, isCurrent, onError]);
  const state = local.kind === 'remote' ? remote : local;
  useEffect(() => { if (state.kind === 'error' && state.report !== false) report(state.error); }, [state, report]);
  const retry = () => {
    if (mounted.current && available && canInteract()) {
      setExpanded(false);
      setAttempt(value => value + 1);
    }
  };
  if (state.kind === 'error') return streaming ? <SvgLoading alt={alt} active={isCurrent()} />
    : <SvgFailure alt={alt} disabled={!available} retry={retry} />;
  if (state.kind === 'loading') return <SvgLoading alt={alt} active={isCurrent()} />;

  const drawing = (modal: boolean) => <SvgBoundary key={`${attempt}:${modal}`} onFailure={report}
    fallback={<SvgFailure alt={alt} disabled={!available} retry={retry} />}>
    <View style={{ width: '100%', minWidth: 0, aspectRatio: state.svg.aspectRatio,
      minHeight: 48, maxHeight: modal ? Math.max(160, dimensions.height - 140) : 480 }}>
      <SvgXml xml={state.svg.xml} width="100%" height="100%" accessible={modal}
        accessibilityRole="image" accessibilityLabel={alt || 'SVG 图形'}
        onError={cause => { throw normalizeError(cause); }} />
    </View>
  </SvgBoundary>;
  return <View style={{ minWidth: 0, flexShrink: 1 }}>
    <Pressable accessibilityRole="button" accessibilityLabel={alt || 'SVG 图形'} accessibilityHint="查看图形"
      accessibilityState={{ disabled: !available }} disabled={!available}
      onPress={event => { event?.stopPropagation?.(); if (mounted.current && available && canInteract()) setExpanded(true); }}>
      {drawing(false)}
    </Pressable>
    <Modal visible={expanded && available} transparent animationType="fade" onRequestClose={() => setExpanded(false)}>
      <SafeAreaView style={{ flex: 1, backgroundColor: theme.background }} accessibilityViewIsModal>
        <View style={{ alignItems: 'flex-end', paddingHorizontal: 12 }}>
          <Pressable accessibilityRole="button" accessibilityLabel="关闭图形预览" onPress={() => setExpanded(false)}
            style={{ minWidth: theme.controlMinHeight, minHeight: theme.controlMinHeight,
              justifyContent: 'center', alignItems: 'center' }}><NativeIcon name="x" /></Pressable>
        </View>
        <ScrollView contentContainerStyle={{ flexGrow: 1, padding: 16, justifyContent: 'center' }}>{drawing(true)}</ScrollView>
      </SafeAreaView>
    </Modal>
  </View>;
}

const SVG: ComponentRenderer = ({ props }) => {
  const content = text(props.content);
  const source = text(props.src);
  const target = useMemo(() => JSON.stringify([content, source]), [content, source]);
  return <SvgResource key={target} content={content} source={source} alt={text(props.alt)} />;
};

export const svgRenderers: Record<string, ComponentRenderer> = { SVG };

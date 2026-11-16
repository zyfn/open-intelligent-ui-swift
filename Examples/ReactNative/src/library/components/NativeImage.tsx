import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator, Image as NativeImageView, Pressable, StyleSheet, Text, View,
  type ImageSourcePropType,
} from 'react-native';
import { useIsStreaming, type ComponentRenderer } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme } from '../theme';
import { contentImage, useNativeContentPolicy } from './contentPolicy';

type NativeImageProps = { source: string; alt: string };

/** Shared native image presentation for the catalog Image and Markdown images. */
export function NativeImage({ source, alt }: NativeImageProps) {
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const { resolveImage, onError } = useNativeContentPolicy();
  const reportedResolutionError = useRef<string | undefined>(undefined);
  // A partial streamed URL must not start a request. Host resolvers are pure mappings.
  const resolved = useMemo(() => {
    if (streaming || !source) return {};
    try { return { image: contentImage(source, { resolveImage }) }; }
    catch (cause) { return { error: cause instanceof Error ? cause : new Error(String(cause)) }; }
  }, [source, streaming, resolveImage]);
  useEffect(() => {
    if (!resolved.error) { reportedResolutionError.current = undefined; return; }
    if (resolved.error && canInteract()) {
      const key = JSON.stringify([source, resolved.error.name, resolved.error.message]);
      if (reportedResolutionError.current === key) return;
      reportedResolutionError.current = key;
      try { onError?.(resolved.error); } catch { /* Reporting must not break content. */ }
    }
  }, [resolved.error, onError, canInteract, source]);

  if (!resolved.image) return <ImagePlaceholder alt={alt}
    message={streaming ? '内容生成完成后加载图片' : '图片不可用'} />;
  // Changing URL, host mapping or headers creates a fresh request boundary. An old
  // native onLoad/onError callback cannot change the replacement image's state.
  return <ImageRequest key={JSON.stringify(resolved.image)} source={resolved.image} alt={alt} />;
}

function ImagePlaceholder({ alt, message }: { alt: string; message: string }) {
  const theme = useOpenUITheme();
  return <View accessible accessibilityRole="image" accessibilityLabel={`${alt || '图片'}，${message}`}
    style={{ minWidth: 0, flexShrink: 1, borderRadius: 12, padding: 20,
      minHeight: 120, justifyContent: 'center', backgroundColor: theme.surfaceMuted, gap: 6 }}>
    <Text style={{ color: theme.ink, fontSize: 15, lineHeight: 22 }}>{alt || '图片'}</Text>
    <Text style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{message}</Text>
  </View>;
}

function ImageRequest({ source, alt }: { source: ImageSourcePropType; alt: string }) {
  const [attempt, setAttempt] = useState(0);
  return <ImageAttempt key={attempt} source={source} alt={alt}
    retry={() => setAttempt(value => value + 1)} />;
}

function ImageAttempt({ source, alt, retry }: {
  source: ImageSourcePropType; alt: string; retry: () => void;
}) {
  const theme = useOpenUITheme();
  const { onError } = useNativeContentPolicy();
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const mounted = useRef(true);
  const settled = useRef(false);
  const [status, setStatus] = useState<'loading' | 'loaded' | 'error'>('loading');
  const [aspectRatio, setAspectRatio] = useState(16 / 9);
  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  const disabled = streaming || !canInteract();

  if (status === 'error') return <View style={{ minWidth: 0, flexShrink: 1, borderRadius: 12,
    padding: 16, backgroundColor: theme.surfaceMuted, gap: 6 }}>
    <Text accessibilityLiveRegion="polite" style={{ color: theme.ink, fontSize: 15,
      lineHeight: 22 }}>{alt || '图片'}：图片未能加载</Text>
    <Pressable accessibilityRole="button" accessibilityLabel="重新加载图片"
      accessibilityState={{ disabled }} disabled={disabled}
      onPress={() => { if (mounted.current && !streaming && canInteract()) retry(); }}
      style={({ pressed }) => ({ minHeight: theme.controlMinHeight, paddingHorizontal: 16,
        paddingVertical: 12, justifyContent: 'center', alignSelf: 'flex-start',
        opacity: disabled ? 0.5 : pressed ? 0.7 : 1 })}>
      <Text style={{ color: theme.accent, fontSize: 14, textDecorationLine: 'underline' }}>重新加载图片</Text>
    </Pressable>
  </View>;

  return <View style={{ minWidth: 0, width: '100%', flexShrink: 1, gap: 6 }}>
    <View style={{ width: '100%', aspectRatio, borderRadius: 12, overflow: 'hidden',
      backgroundColor: theme.surfaceMuted }}>
      <NativeImageView source={source} resizeMode="contain"
        accessible={status === 'loaded'} accessibilityRole="image" accessibilityLabel={alt || '图片'}
        style={StyleSheet.absoluteFill}
        onLoad={event => {
          if (!mounted.current || !canInteract() || settled.current) return;
          settled.current = true;
          const { width, height } = event.nativeEvent.source;
          if (Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0) {
            // Keep unusually tall/wide resources usable; contain preserves the full image.
            setAspectRatio(Math.max(0.5, Math.min(3, width / height)));
          }
          setStatus('loaded');
        }}
        onError={event => {
          if (!mounted.current || !canInteract() || settled.current) return;
          settled.current = true;
          setStatus('error');
          try { onError?.(new Error(event.nativeEvent.error || 'Image failed to load')); }
          catch { /* Reporting must not break content. */ }
        }} />
      {status === 'loading' ? <View accessible accessibilityRole="image"
        accessibilityLabel={`${alt || '图片'}，正在加载`}
        style={[StyleSheet.absoluteFill, { justifyContent: 'center', alignItems: 'center', padding: 16 }]}>
        <ActivityIndicator color={theme.accent} />
      </View> : null}
    </View>
    {status === 'loading' ? <Text accessible={false} importantForAccessibility="no"
      accessibilityElementsHidden style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>
      {alt || '正在加载图片'}</Text> : null}
  </View>;
}

export const Image: ComponentRenderer = ({ props }) => <NativeImage
  source={typeof props.src === 'string' ? props.src : ''}
  alt={typeof props.alt === 'string' ? props.alt : ''} />;

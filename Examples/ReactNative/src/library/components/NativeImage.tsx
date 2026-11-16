import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator, Image as NativeImageView, Pressable, StyleSheet, Text, View,
  type ImageResizeMode, type ImageSourcePropType,
} from 'react-native';
import { useIsStreaming, type ComponentRenderer } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { normalizeError } from '../../runtime/errors';
import { useOpenUITheme } from '../theme';
import { contentImage, useNativeContentPolicy } from './contentPolicy';

type ImagePresentation = { compact?: boolean; aspectRatio?: number; resizeMode?: ImageResizeMode; onPress?: () => void; fill?: boolean };
type NativeImageProps = { source: string; alt: string } & ImagePresentation;

/** Shared native image presentation for the catalog Image and Markdown images. */
export function NativeImage({ source, ...props }: NativeImageProps) {
  return <ResolvedImage key={source} source={source} {...props} />;
}

function ResolvedImage({ source, alt, ...presentation }: NativeImageProps) {
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const { resolveImage, onError } = useNativeContentPolicy();
  const [attempt, setAttempt] = useState(0);
  const mounted = useRef(true);
  const reportedResolutionError = useRef<string | undefined>(undefined);
  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  const retry = () => {
    if (mounted.current && !streaming && canInteract()) setAttempt(value => value + 1);
  };
  // A partial streamed URL must not start a request. Host resolvers are pure mappings.
  const resolved = useMemo(() => {
    if (streaming || !source) return {};
    try { return { image: contentImage(source, { resolveImage }) }; }
    catch (cause) { return { error: normalizeError(cause) }; }
  }, [source, streaming, resolveImage, attempt]);
  useEffect(() => {
    if (!resolved.error) { reportedResolutionError.current = undefined; return; }
    if (resolved.error && canInteract()) {
      const key = JSON.stringify([source, attempt, resolved.error.name, resolved.error.message]);
      if (reportedResolutionError.current === key) return;
      reportedResolutionError.current = key;
      try { onError?.(resolved.error); } catch { /* Reporting must not break content. */ }
    }
  }, [resolved.error, onError, canInteract, source, attempt]);

  if (resolved.error) return <ImageFailure alt={alt} retry={retry} {...presentation}
    disabled={streaming || !canInteract()} />;
  if (!resolved.image) return <ImagePlaceholder alt={alt} {...presentation}
    message={streaming ? '内容生成完成后加载图片' : '图片不可用'} />;
  // Changing URL, host mapping or headers creates a fresh request boundary. An old
  // native onLoad/onError callback cannot change the replacement image's state.
  return <ImageAttempt key={`${attempt}:${JSON.stringify(resolved.image)}`}
    source={resolved.image} alt={alt} retry={retry} {...presentation} />;
}

function ImagePlaceholder({ alt, message, compact, aspectRatio, fill }: { alt: string; message: string } & ImagePresentation) {
  const theme = useOpenUITheme();
  return <View accessible accessibilityRole="image" accessibilityLabel={`${alt || '图片'}，${message}`}
    style={{ minWidth: 0, flexShrink: 1, borderRadius: 12, padding: 20,
      minHeight: compact ? 0 : 120, aspectRatio: fill ? undefined : aspectRatio, width: '100%',
      height: fill ? '100%' : undefined, justifyContent: 'center',
      backgroundColor: theme.surfaceMuted, gap: 6, ...(compact ? { padding: 6 } : {}) }}>
    <Text style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{compact ? '图片' : message}</Text>
  </View>;
}

function ImageFailure({ alt, retry, disabled, compact, fill, aspectRatio = 16 / 9 }: {
  alt: string; retry: () => void; disabled: boolean;
} & ImagePresentation) {
  const theme = useOpenUITheme();
  return <Pressable accessibilityRole="button" accessibilityLabel="重新加载图片"
    accessibilityHint={`${alt || '图片'}，加载失败`} accessibilityLiveRegion="polite"
    hitSlop={compact ? 12 : undefined}
    accessibilityState={{ disabled }} disabled={disabled} onPress={event => { event?.stopPropagation?.(); retry(); }}
    style={({ pressed }) => ({ width: '100%', aspectRatio: fill ? undefined : aspectRatio,
      height: fill ? '100%' : undefined, minHeight: compact ? 0 : theme.controlMinHeight,
      minWidth: 0, flexShrink: 1, borderRadius: 12, padding: compact ? 6 : 16,
      backgroundColor: theme.surfaceMuted, justifyContent: 'center', alignItems: 'center',
      opacity: disabled ? 0.5 : pressed ? 0.7 : 1 })}>
    <Text style={{ color: theme.accent, fontSize: 14 }}>{compact ? '重试' : '点击重试'}</Text>
  </Pressable>;
}

function ImageAttempt({ source, alt, retry, compact, fill, aspectRatio: fixedRatio, resizeMode = 'contain', onPress }: {
  source: ImageSourcePropType; alt: string; retry: () => void;
} & ImagePresentation) {
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

  if (status === 'error') return <ImageFailure alt={alt} disabled={disabled} compact={compact} fill={fill} aspectRatio={fixedRatio ?? aspectRatio}
    retry={() => { if (mounted.current && !streaming && canInteract()) retry(); }} />;

  return <View style={{ minWidth: 0, width: '100%', height: fill ? '100%' : undefined, flexShrink: 1, gap: 6 }}>
    <Pressable accessible={Boolean(onPress) && status === 'loaded'} accessibilityRole="button"
      accessibilityLabel={`查看${alt || '图片'}`} disabled={!onPress || status !== 'loaded' || disabled}
      onPress={event => { event?.stopPropagation?.(); if (!disabled && canInteract()) onPress?.(); }}
      style={{ width: '100%', aspectRatio: fill ? undefined : fixedRatio ?? aspectRatio,
        height: fill ? '100%' : undefined, borderRadius: 12, overflow: 'hidden',
      backgroundColor: theme.surfaceMuted }}>
      <NativeImageView source={source} resizeMode={resizeMode}
        accessible={status === 'loaded' && !onPress} accessibilityRole="image" accessibilityLabel={alt || '图片'}
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
    </Pressable>
    {status === 'loading' && !compact ? <Text accessible={false} importantForAccessibility="no"
      accessibilityElementsHidden style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>
      {alt || '正在加载图片'}</Text> : null}
  </View>;
}

export const Image: ComponentRenderer = ({ props }) => <NativeImage
  source={typeof props.src === 'string' ? props.src : ''}
  alt={typeof props.alt === 'string' ? props.alt : ''} />;

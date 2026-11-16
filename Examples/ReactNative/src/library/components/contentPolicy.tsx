import { createContext, useContext, useMemo, type ReactNode } from 'react';
import type { ImageSourcePropType } from 'react-native';

export type NativeContentPolicy = {
  /** Return a trusted native source, rewrite the URL, or return undefined to omit it. */
  resolveImage?: (source: string) => ImageSourcePropType | undefined;
  onError?: (error: Error) => void;
};

const ContentPolicy = createContext<NativeContentPolicy>({});

export function NativeContentProvider({ children, resolveImage, onError }: NativeContentPolicy & { children: ReactNode }) {
  const policy = useMemo(() => ({ resolveImage, onError }), [resolveImage, onError]);
  return <ContentPolicy.Provider value={policy}>{children}</ContentPolicy.Provider>;
}

export function useNativeContentPolicy(): NativeContentPolicy {
  return useContext(ContentPolicy);
}

/** Only intents that the host can review; this function never opens a URL. */
export function contentLink(source: string): string | undefined {
  if (!source || source.length > 8192 || /[\u0000-\u0020\u007f-\u009f]/.test(source)) return;
  try {
    if (/[\u0000-\u001f\u007f-\u009f]/.test(decodeURIComponent(source))) return;
    const url = new URL(source);
    if (url.username || url.password) return;
    if ((url.protocol === 'https:' || url.protocol === 'http:') && url.hostname) return url.href;
    if (url.protocol === 'mailto:' && url.pathname) return url.href;
  } catch { /* A partial streamed URL remains inert until it is valid. */ }
}

export function contentImage(source: string, policy: NativeContentPolicy): ImageSourcePropType | undefined {
  const resolved = policy.resolveImage
    ? policy.resolveImage(source)
    : contentLink(source)?.startsWith('https:') ? { uri: source } : undefined;
  // Numeric asset IDs only originate in the host's resolver, never in model text.
  if (typeof resolved === 'number') return Number.isInteger(resolved) && resolved > 0 ? resolved : undefined;
  if (!resolved) return;
  const sources = Array.isArray(resolved) ? resolved : [resolved];
  if (!sources.length || sources.some(item => !item.uri || !/^https?:/.test(contentLink(item.uri) ?? ''))) return;
  return resolved;
}

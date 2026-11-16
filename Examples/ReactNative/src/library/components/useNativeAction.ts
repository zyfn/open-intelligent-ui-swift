import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useIsStreaming, useTriggerAction } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { normalizeError } from '../../runtime/errors';
import { useNativeContentPolicy } from './contentPolicy';

type Action = Parameters<ReturnType<typeof useTriggerAction>>[2];

/** Presentation pending/error state only. The official runtime still executes actions. */
export function useNativeAction(identity?: string) {
  const trigger = useTriggerAction();
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const { onError } = useNativeContentPolicy();
  // A committed A → B → A change must not revive a native callback from the first A.
  const token = useMemo(() => ({}), [identity]);
  const mounted = useRef(true);
  const inFlight = useRef<object | null>(null);
  const current = useRef({ token, trigger, streaming, canInteract, onError });
  const [status, setStatus] = useState<{ token: object; pending: boolean; error?: string }>({ token, pending: false });

  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  useLayoutEffect(() => { current.current = { token, trigger, streaming, canInteract, onError }; },
    [token, trigger, streaming, canInteract, onError]);

  const isCurrent = useCallback(() => {
    const state = current.current;
    return mounted.current && state.token === token && !state.streaming && state.canInteract();
  }, [token]);
  const canInvoke = useCallback(() => isCurrent() && inFlight.current !== token, [isCurrent, token]);

  const invoke = useCallback(async (label: string, action?: Action, formName?: string) => {
    const state = current.current;
    if (!canInvoke()) return false;
    inFlight.current = token;
    setStatus({ token, pending: true });
    try {
      await state.trigger(label, formName, action);
      return isCurrent();
    } catch (cause) {
      if (isCurrent()) {
        const error = normalizeError(cause);
        if (isCurrent()) {
          setStatus({ token, pending: false, error: '操作暂时未完成，请重试。' });
          try { current.current.onError?.(error); } catch { /* Host reporting cannot break a control. */ }
        }
      }
      return false;
    } finally {
      if (inFlight.current === token) inFlight.current = null;
      if (mounted.current && current.current.token === token) {
        setStatus(previous => previous.token === token ? { ...previous, pending: false } : previous);
      }
    }
  }, [canInvoke, isCurrent, token]);

  const pending = status.token === token && status.pending;
  const error = status.token === token ? status.error : undefined;
  return { invoke, canInvoke, pending, error, disabled: streaming || pending || !canInteract() };
}

import { useCallback, useLayoutEffect, useRef, useState } from 'react';
import { useIsStreaming, useTriggerAction } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useNativeContentPolicy } from './contentPolicy';

type Action = Parameters<ReturnType<typeof useTriggerAction>>[2];

/** Presentation pending/error state only. The official runtime still executes actions. */
export function useNativeAction() {
  const trigger = useTriggerAction();
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const { onError } = useNativeContentPolicy();
  const mounted = useRef(true);
  const inFlight = useRef(false);
  const current = useRef({ trigger, streaming, canInteract, onError });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string>();

  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  useLayoutEffect(() => { current.current = { trigger, streaming, canInteract, onError }; },
    [trigger, streaming, canInteract, onError]);

  const invoke = useCallback(async (label: string, action?: Action, formName?: string) => {
    const state = current.current;
    if (!mounted.current || state.streaming || !state.canInteract() || inFlight.current) return;
    inFlight.current = true;
    setPending(true);
    setError(undefined);
    try {
      await state.trigger(label, formName, action);
    } catch (cause) {
      if (mounted.current && current.current.canInteract()) {
        setError('操作暂时未完成，请重试。');
        try { current.current.onError?.(cause instanceof Error ? cause : new Error(String(cause))); } catch { /* Host reporting cannot break a control. */ }
      }
    } finally {
      inFlight.current = false;
      if (mounted.current) setPending(false);
    }
  }, []);

  return { invoke, pending, error, disabled: streaming || pending || !canInteract() };
}

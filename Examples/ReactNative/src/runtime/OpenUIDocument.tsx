import { Component, useCallback, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore,
  type ReactNode } from 'react';
import { Renderer, type RendererProps } from '@openuidev/react-lang';
import type { MessageController, MessageHandle, MessageSnapshot } from './message';
import { DocumentInteractionContext } from './interaction';

type Props = {
  message: MessageController;
  library: RendererProps['library'];
  onAction?: RendererProps['onAction'];
  onError?: RendererProps['onError'];
  onPersistenceError?: (error: Error) => void;
};

const identities = new WeakMap<object, number>();
let nextIdentity = 0;
function identity(value: object): number {
  let id = identities.get(value);
  if (id === undefined) { id = ++nextIdentity; identities.set(value, id); }
  return id;
}

// Official component boundaries handle individual render failures. This catches
// failures above them (for example a failing library) without losing the host UI.
class DocumentBoundary extends Component<{
  children: ReactNode; onFailure: (error: Error) => void;
}, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch(cause: unknown) {
    this.props.onFailure(cause instanceof Error ? cause : new Error(String(cause)));
  }
  render() { return this.state.failed ? null : this.props.children; }
}

export function OpenUIDocument(props: Props) {
  const { message } = props;
  const snapshot = useSyncExternalStore(message.subscribe, message.getSnapshot, message.getSnapshot);
  const handle = message.getHandle();
  // Message IDs can be reused by different controllers. Library changes must
  // also retire the old Renderer, whose Store and memoized nodes belong to it.
  return <DocumentEpoch key={`${identity(handle)}:${identity(props.library)}`} {...props}
    snapshot={snapshot} handle={handle} />;
}

function DocumentEpoch({ message, library, snapshot, handle, onAction, onError, onPersistenceError }:
  Props & { snapshot: MessageSnapshot; handle: MessageHandle }) {
  // Read once per mount. Feeding every state callback back into initialState
  // would reinitialize the official Store and can overwrite an active edit.
  const [initialState] = useState(() => message.getSavedFields(handle));
  const mounted = useRef(true);
  const callbacks = useRef({ onAction, onError, onPersistenceError });
  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  useLayoutEffect(() => { callbacks.current = { onAction, onError, onPersistenceError }; },
    [onAction, onError, onPersistenceError]);

  const current = useCallback(() => mounted.current && message.isCurrent(handle), [message, handle]);
  const canInteract = useCallback(() => current() && message.getSnapshot().phase === 'complete',
    [current, message]);
  const interaction = useMemo(() => ({ isCurrent: current, canInteract }), [current, canInteract]);
  const saveFields = useCallback((fields: Record<string, unknown>) => {
    if (!canInteract()) return;
    if (!message.saveFields(handle, fields) && canInteract()) {
      callbacks.current.onPersistenceError?.(message.getError() ?? new Error('Unable to save message fields'));
    }
  }, [message, handle, canInteract]);
  const reportFailure = useCallback((reason: Error) => {
    if (!current() || !message.fail(handle, reason)) return;
    // fail() notifies subscribers synchronously; a subscriber may retire or
    // dispose the message before the diagnostic is forwarded to the host.
    if (mounted.current && message.getHandle() === handle && message.getError() === reason) {
      callbacks.current.onError?.([{ source: 'runtime', code: 'render-error', message: reason.message }]);
    }
  }, [current, message, handle]);

  return (
    <DocumentInteractionContext.Provider value={interaction}>
      <DocumentBoundary onFailure={reportFailure}>
        <Renderer
          library={library}
          response={snapshot.source}
          // A stopped/truncated source must not be finalized as a complete program.
          // Components disable interactions while this preview is incomplete.
          isStreaming={snapshot.phase !== 'complete'}
          initialState={initialState}
          onStateUpdate={saveFields}
          onAction={event => { if (canInteract()) callbacks.current.onAction?.(event); }}
          onError={errors => { if (current()) callbacks.current.onError?.(errors); }}
          publishObservability={false}
        />
      </DocumentBoundary>
    </DocumentInteractionContext.Provider>
  );
}

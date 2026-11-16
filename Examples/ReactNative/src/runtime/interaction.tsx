import { createContext, useContext } from 'react';

type DocumentInteraction = { isCurrent: () => boolean; canInteract: () => boolean };

// A library can also be used directly with the official Renderer. Its components
// must still respect useIsStreaming; this context adds host lifecycle checks.
export const DocumentInteractionContext = createContext<DocumentInteraction>({
  isCurrent: () => true, canInteract: () => true,
});

export function useDocumentInteraction(): DocumentInteraction {
  return useContext(DocumentInteractionContext);
}

import type { MessageController } from '../runtime/message';

/** The Gallery host owns transport; leaving a virtualized row does not stop it. */
export function replayMessage(message: MessageController, source: string): () => void {
  const handle = message.begin();
  if (!source) { message.complete(handle); return () => {}; }
  const chunkSize = Math.max(8, Math.ceil(source.length / 120));
  let offset = 0;
  let active = true;
  const timer = setInterval(() => {
    if (!message.append(handle, source.slice(offset, offset + chunkSize))) {
      active = false; clearInterval(timer); return;
    }
    offset += chunkSize;
    if (offset >= source.length) {
      active = false; clearInterval(timer); message.complete(handle);
    }
  }, 32);
  return () => {
    if (!active) return;
    active = false; clearInterval(timer); message.interrupt(handle);
  };
}

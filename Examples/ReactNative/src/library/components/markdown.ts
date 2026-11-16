import { Lexer, type Token, type Tokens } from 'marked';

const inlineChildren = (token: Token): Token[] =>
  'tokens' in token && Array.isArray(token.tokens) ? token.tokens : [];

export type NativeMarkdown =
  | { kind: 'markdown'; tokens: Token[] }
  | { kind: 'plain'; text: string; error?: Error };

/** Marked owns Markdown syntax; this only bounds work before native presentation. */
export function parseNativeMarkdown(text: string): NativeMarkdown {
  if (text.length > 65_536) return { kind: 'plain', text };
  try {
    const tokens = Lexer.lex(text, { gfm: true, breaks: false });
    // Keep existing arrays by reference. Check the budget before enqueueing, never
    // spread/flatten an unbounded child list just to discover it exceeds the cap.
    const queue: Array<{ tokens: Token[]; depth: number }> = [];
    let count = 0;
    const reserve = (amount: number) => { count += amount; return count <= 4_096; };
    const enqueue = (items: Token[], depth: number) => {
      if (!items.length) return true;
      if (depth > 24 || !reserve(items.length)) return false;
      queue.push({ tokens: items, depth });
      return true;
    };
    if (!enqueue(tokens, 0)) return { kind: 'plain', text };
    while (queue.length) {
      const group = queue.pop()!;
      for (const token of group.tokens) {
        if (!enqueue(inlineChildren(token), group.depth + 1)) return { kind: 'plain', text };
        if (token.type === 'list') {
          if (!enqueue((token as Tokens.List).items, group.depth + 1)) return { kind: 'plain', text };
        } else if (token.type === 'table') {
          const table = token as Tokens.Table;
          // Empty cells and rows still create native views, so count those too.
          if (!reserve(1 + table.rows.length + table.header.length)) return { kind: 'plain', text };
          for (const cell of table.header) {
            if (!enqueue(cell.tokens, group.depth + 1)) return { kind: 'plain', text };
          }
          for (const row of table.rows) {
            if (!reserve(row.length)) return { kind: 'plain', text };
            for (const cell of row) {
              if (!enqueue(cell.tokens, group.depth + 1)) return { kind: 'plain', text };
            }
          }
        }
      }
    }
    return { kind: 'markdown', tokens };
  } catch (cause) {
    return { kind: 'plain', text, error: cause instanceof Error ? cause : new Error(String(cause)) };
  }
}

export type InlinePart = { kind: 'text'; tokens: Token[] }
  | { kind: 'image'; image: Tokens.Image; link?: Tokens.Link };

/** RN Text cannot contain a native View. Split images without losing inline styles. */
export function splitInlineImages(tokens: Token[]): InlinePart[] {
  const result: InlinePart[] = [];
  let text: Token[] = [];
  const flush = () => {
    if (text.length) result.push({ kind: 'text', tokens: text });
    text = [];
  };
  for (const token of tokens) {
    if (token.type === 'image') {
      flush();
      result.push({ kind: 'image', image: token as Tokens.Image });
    } else if (inlineChildren(token).length && ['strong', 'em', 'del', 'link', 'text'].includes(token.type)) {
      for (const part of splitInlineImages(inlineChildren(token))) {
        if (part.kind === 'text') text.push({ ...token, tokens: part.tokens });
        else {
          flush();
          result.push({ ...part, link: token.type === 'link' ? token as Tokens.Link : part.link });
        }
      }
    } else text.push(token);
  }
  flush();
  return result;
}

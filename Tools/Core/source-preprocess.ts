// The pinned parser's fence selection and comment rules, shared by batch and
// streaming input. Completed lines are consumed once; only the unfinished line
// is previewed again. No AST, Lang value or execution state lives here.
const statementStart = /^\s*\$?[A-Za-z_]\w*\s*=(?!=)/;
const fenceLine = /^[ \t]*```[ \t]*([\w.+-]*)[ \t]*(.*?)[ \t]*\r?$/;

class Text {
  raw = '';
  clean = '';
  quote: false | '"' | "'" = false;

  copy(): Text { return Object.assign(new Text(), this); }

  append(line: string, separator: boolean): void {
    let end = line.length;
    for (let index = 0; index < line.length; index++) {
      const character = line[index];
      if (this.quote) {
        if (character === '\\' && index + 1 < line.length) index++;
        else if (character === this.quote) this.quote = false;
      } else if (character === '"' || character === "'") this.quote = character;
      else if (character === '#' || (character === '/' && line[index + 1] === '/')) {
        end = line.slice(0, index).trimEnd().length;
        break;
      }
    }
    const prefix = separator ? '\n' : '';
    this.raw += prefix + line;
    const addition = prefix + line.slice(0, end);
    // preprocess trims its result. Discard only leading output whitespace here
    // so every later read need not rescan a long leading run of blank comments.
    this.clean += this.clean ? addition : addition.trimStart();
  }
}

type Body = {
  text: Text;
  script: boolean;
  lines: number;
  prelude: boolean;
  program: boolean;
  nonempty: boolean;
};

class Fences {
  outside = new Text();
  blocks = new Text();
  outsideLines = 0;
  outsideProgram = false;
  blockCount = 0;
  blockProgram = false;
  blockNonempty = false;
  body: Body | null = null;
  open = false;
  depth = 0;

  copy(): Fences {
    const next = Object.assign(new Fences(), this);
    next.outside = this.outside.copy();
    next.blocks = this.blocks.copy();
    next.body = this.body && { ...this.body, text: this.body.text.copy() };
    return next;
  }

  private appendBody(line: string): void {
    const body = this.body!;
    body.text.append(line, body.lines++ > 0);
    body.nonempty ||= line.trim().length > 0;
    // startsProgram skips leading blank/comment lines. A last comment line is
    // still not a program; the next line can make that leading comment complete.
    if (body.prelude && line.trim() && !/^\s*(\/\/|#)/.test(line)) {
      body.program = statementStart.test(line);
      body.prelude = false;
    }
  }

  consume(line: string): void {
    const fence = this.open ? null : fenceLine.exec(line);
    if (!fence) {
      if (this.body?.script) return;
      if (this.body) this.appendBody(line);
      else {
        this.outside.append(line, this.outsideLines++ > 0);
        this.outsideProgram ||= statementStart.test(line);
      }
      // The official fence scanner tracks double-quoted code strings. Its
      // separate comment pass also accepts single quotes; do not conflate them.
      if (this.open || this.depth > 0 || this.body !== null || statementStart.test(line)) {
        for (let index = 0; index < line.length; index++) {
          const character = line[index];
          if (this.open) {
            if (character === '\\') index++;
            else if (character === '"') this.open = false;
          } else if (character === '"') this.open = true;
          else if (character === '(' || character === '[' || character === '{') this.depth++;
          else if ((character === ')' || character === ']' || character === '}') && this.depth > 0) this.depth--;
        }
      }
      return;
    }

    this.depth = 0;
    const [, tag = '', rest = ''] = fence;
    if (this.body) {
      if (!this.body.script) {
        this.blocks = this.body.text;
        this.blockCount++;
        this.blockProgram ||= this.body.program;
        this.blockNonempty ||= this.body.nonempty;
      }
      this.body = null;
      return;
    }
    if (rest.includes('```')) return;
    const code = statementStart.test(rest) ? rest
      : tag && /^=(?!=)/.test(rest) ? tag + ' ' + rest : null;
    const text = this.blocks.copy();
    if (this.blockCount) text.append('', true);
    this.body = { text, script: tag.toLowerCase() === 'openui-js', lines: 0,
      prelude: true, program: false, nonempty: false };
    if (code !== null && !this.body.script) this.appendBody(code);
  }

  selection(): { channel: 'outside' | 'blocks'; text: Text } {
    const active = this.body && !this.body.script ? this.body : null;
    const program = this.blockProgram || active?.program;
    const nonempty = this.blockNonempty || active?.nonempty;
    const outside = !program && (this.outsideProgram || !nonempty);
    return outside ? { channel: 'outside', text: this.outside }
      : { channel: 'blocks', text: active?.text ?? this.blocks };
  }
}

class SourceLines {
  private state = new Fences();
  private pending = '';

  append(text: string): void {
    let start = 0;
    for (let end = text.indexOf('\n'); end !== -1; end = text.indexOf('\n', start)) {
      this.state.consume(this.pending + text.slice(start, end));
      this.pending = '';
      start = end + 1;
    }
    this.pending += text.slice(start);
  }

  read(): { channel: 'outside' | 'blocks'; text: Text; stable: number } {
    const preview = this.state.copy();
    preview.consume(this.pending);
    const selected = preview.selection();
    // Completed text on each selection channel is append-only. The unfinished
    // line may turn into a fence/comment, and a new code block can switch the
    // selected channel, so neither is treated as an immutable output prefix.
    const stable = selected.channel === 'outside' ? this.state.outside
      : this.state.body && !this.state.body.script ? this.state.body.text : this.state.blocks;
    return { ...selected, stable: stable.clean.length };
  }
}

export class SourcePreprocessor {
  private lines = new SourceLines();
  private leading = true;
  private whitespace = '';
  private previous = { text: '', stable: 0, channel: 'outside' as 'outside' | 'blocks' };
  private changed = false;

  append(chunk: string): void {
    // Match input.trim() without repeatedly scanning whitespace already seen.
    // A trailing run is held until another non-whitespace unit arrives.
    if (this.leading) {
      chunk = chunk.trimStart();
      if (!chunk) return;
      this.leading = false;
    }
    const content = chunk.trimEnd();
    if (!content) { this.whitespace += chunk; return; }
    this.lines.append(this.whitespace + content);
    this.whitespace = chunk.slice(content.length);
    this.changed = true;
  }

  read(): { text: string; changedFrom: number } {
    if (!this.changed) return { text: this.previous.text, changedFrom: this.previous.text.length };
    const selected = this.lines.read();
    const text = selected.text.clean.trimEnd();
    const stable = Math.min(selected.stable, text.length);
    let changedFrom = selected.channel === this.previous.channel
      ? Math.min(stable, this.previous.stable) : 0;
    const end = Math.min(text.length, this.previous.text.length);
    while (changedFrom < end && text.charCodeAt(changedFrom) === this.previous.text.charCodeAt(changedFrom)) changedFrom++;
    this.previous = { text, stable, channel: selected.channel };
    this.changed = false;
    return { text, changedFrom };
  }
}

export function preprocess(input: string): string {
  const source = new SourcePreprocessor();
  source.append(input);
  return source.read().text;
}

export function stripFences(input: string): string {
  if (!input.includes('```')) return input;
  const source = new SourceLines();
  source.append(input);
  return source.read().text.raw;
}

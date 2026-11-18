// Independent test-only oracle copied from MIT-licensed OpenUI parser/parser.ts
// at 39a4e3f6493673fdf2de04681240374c8d6f6be8, with TypeScript types erased.
// Keep this fixed when changing the production preprocessor; do not import it
// from source-preprocess.ts or regenerate it as part of a resource build.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import { createNativeRuntime } from './native-test-runtime.mjs';
import {transform} from 'esbuild';

const compiled = await transform(readFileSync(new URL('./source-preprocess.ts', import.meta.url), 'utf8'), {loader:'ts',format:'esm'});
const candidate = await import('data:text/javascript;base64,' + Buffer.from(compiled.code).toString('base64'));
const realm = createNativeRuntime({}, {});
const bridge = realm.SwiftCore;

const STATEMENT_START = /^\s*\$?[A-Za-z_]\w*\s*=(?!=)/;
const FENCE_LINE = /^[ \t]*```[ \t]*([\w.+-]*)[ \t]*(.*?)[ \t]*\r?$/;
function openerCode(tag, rest) {
  if (STATEMENT_START.test(rest)) return rest;
  if (tag && /^=(?!=)/.test(rest)) return tag + " " + rest;
  return null;
}
function scanCode(line, state) {
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (state.open) {
      if (c === "\\") i++;
      else if (c === '"') state.open = false;
    } else if (c === '"') state.open = true;
    else if (c === "(" || c === "[" || c === "{") state.depth++;
    else if ((c === ")" || c === "]" || c === "}") && state.depth > 0) state.depth--;
  }
}
function startsProgram(block) {
  return STATEMENT_START.test(block.replace(/^(\s*(\/\/|#)[^\n]*\n)+/, ""));
}
function stripFences(input) {
  if (!input.includes("```")) return input;
  const blocks = [];
  const outside = [];
  let body = null;
  let script = false;
  const scan = { open: false, depth: 0 };
  for (const line of input.split("\n")) {
    const fence = scan.open ? null : FENCE_LINE.exec(line);
    if (!fence) {
      if (script) continue;
      (body ?? outside).push(line);
      if (scan.open || scan.depth > 0 || body !== null || STATEMENT_START.test(line)) {
        scanCode(line, scan);
      }
      continue;
    }
    scan.depth = 0;
    const [, tag = "", rest = ""] = fence;
    if (body !== null) {
      if (!script) blocks.push(body.join("\n"));
      body = null;
      script = false;
      continue;
    }
    if (rest.includes("```")) continue;
    const code = openerCode(tag, rest);
    script = tag.toLowerCase() === "openui-js";
    body = code === null ? [] : [code];
  }
  if (body !== null && !script) blocks.push(body.join("\n"));
  if (blocks.some(startsProgram)) return blocks.join("\n");
  const unfenced = outside.some((l) => STATEMENT_START.test(l));
  return unfenced || blocks.every((b) => b.trim() === "") ? outside.join("\n") : blocks.join("\n");
}
function stripComments(input) {
  let inStr = false;
  return input.split("\n").map((line) => {
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (inStr) {
        if (c === "\\" && i + 1 < line.length) {
          i++;
          continue;
        }
        if (c === inStr) inStr = false;
        continue;
      }
      if (c === '"' || c === "'") {
        inStr = c;
        continue;
      }
      if (c === "/" && line[i + 1] === "/") {
        return line.substring(0, i).trimEnd();
      }
      if (c === "#") {
        return line.substring(0, i).trimEnd();
      }
    }
    return line;
  }).join("\n");
}
function preprocess(input) {
  return stripComments(stripFences(input.trim())).trim();
}

const cases = [
  "",
  "  \n\r\t",
  "root=Box(\"ok\")",
  "  root=Box(\"ok\") \n\n",
  "root=Box(\"A\n//str\n#str\") #comment\na=2",
  "Header\n```openui\nroot=Box(\"ready\")\n```\nFooter",
  "```openui\n// comment\nroot=Box(\"value\")\n```\nroot=Box(\"outside\")",
  "```txt\nhello\n```\n```openui\nroot=Box(\"ok\")\n```",
  "```openui-js\nroot=Box(\"hidden\")\n```\nroot=Box(\"out\")",
  "root=Box(\"```\n#x\")\n```\nfooter",
  "```root=Box(\"inline\")\n```",
  "```openui root=Box(\"inline\")\n```",
  "before\n```js\nhello\n```\nafter",
  "```openui\nroot=Box(\"\\\ntext\")\n```",
  "\r\n```openui\r\nroot=Box(\"ok\")\r\n```\r\n",
  "root=Box(\"😀\\uD800é\") # c\n",
  "root=Box(\"𐀀𐏿\")\n// end",
  "root=Box('// string # text') # comment\nroot=Box(\"done\")",
  "```openui\nroot=Box(\"one\")\n```\n```\n```\n```other\nlast=2\n```",
  "intro\n```one\n// only a comment\n```\n```two\n#comment\nroot=Box(\"program\")\n```\nfooter",
  "root=Box(\"outside\")\n```unknown\ntext\n```\n```openui-js\nroot=Box(\"ignored\")\n```",
  "```openui root=Box(\"inline\") ```\nroot=Box(\"outside\")",
  "root=Box(1) // quote \"\n```\nroot=Box(\"string according to fence scanner\")\n```",
  "﻿ root=Box(\"value\")  ﻿",
  "```openui\nroot=Box(\"\\\"escaped\")\n```\n# footer"
];

function comparePrefixes(text, widths) {
  for (const width of widths) {
    const stream = new candidate.SourcePreprocessor();
    let prefix = '', previous = '';
    for (let offset = 0; offset < text.length; offset += width) {
      const chunk = text.slice(offset, offset + width);
      prefix += chunk; stream.append(chunk);
      const result = stream.read(), expected = preprocess(prefix);
      assert.equal(result.text, expected, 'stream prefix ' + JSON.stringify(prefix));
      assert.equal(candidate.preprocess(prefix), expected, 'batch prefix ' + JSON.stringify(prefix));
      assert.equal(candidate.stripFences(prefix), stripFences(prefix), 'fence prefix ' + JSON.stringify(prefix));
      assert.equal(bridge.preprocess(prefix), expected, 'shipped preprocess prefix ' + JSON.stringify(prefix));
      assert.equal(bridge.fences(prefix), stripFences(prefix), 'shipped fences prefix ' + JSON.stringify(prefix));
      assert.equal(previous.slice(0, result.changedFrom), result.text.slice(0, result.changedFrom), 'retained prefix');
      if (result.changedFrom < Math.min(previous.length, result.text.length))
        assert.notEqual(previous.charCodeAt(result.changedFrom), result.text.charCodeAt(result.changedFrom), 'first change');
      assert.deepEqual(stream.read(), {text:result.text,changedFrom:result.text.length}, 'unchanged read');
      previous = result.text;
    }
  }
}

test('batch and incremental preprocessing match the fixed official oracle at every UTF16 prefix', () => {
  assert.equal(candidate.preprocess(''), preprocess(''));
  for (const source of cases) comparePrefixes(source, [1,2,3,7,13]);
});

test('short mixed lexical fragments preserve the independent preprocessing oracle', () => {
  let seed = 0x2a42f0;
  const fragments = ['root=', 'Box(', ')', 'true', '\n', '\r', '\t', ' ', '#', '/', '//', '\\', '"', "'", String.fromCharCode(96), 'openui', 'openui-js', 'a=', '😀', '\ud800', '[]', '{}'];
  for (let sample = 0; sample < 160; sample++) {
    let source = '';
    for (let index = 0; index < 22; index++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      source += fragments[seed % fragments.length];
    }
    comparePrefixes(source, [1,7]);
  }
});

test('only the unfinished line is rescanned while a large stable prefix grows', () => {
  const stream = new candidate.SourcePreprocessor();
  const names = Array.from({length:600}, (_, index) => 'f' + index);
  stream.append('root=Stack([' + names.join(',') + ',tail])\n'
    + names.map(name => name + '=Box("stable")\n').join('') + 'tail=Box("');
  stream.read();
  // Count the actual line-consumer input, not a cache-hit or timing proxy.
  const prototype = Object.getPrototypeOf(stream.lines.state);
  const consume = prototype.consume;
  let calls = 0, units = 0;
  prototype.consume = function(line) { calls++; units += line.length; return consume.call(this,line); };
  try {
    for (let index = 0; index < 50; index++) { stream.append('abc'); stream.read(); }
  } finally { prototype.consume = consume; }
  assert.equal(calls, 50, 'one unfinished-line preview per append, no completed-line replay');
  assert(units < 10000, 'completed source must not dominate incremental scanning');
});

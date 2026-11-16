import { XMLParser, XMLValidator } from 'fast-xml-parser';

export const MAX_SVG_BYTES = 1_048_576;
const MAX_NODES = 4_096;
const MAX_DEPTH = 32;
const tags = new Set(['svg', 'g', 'defs', 'symbol', 'use', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon',
  'text', 'tspan', 'title', 'desc', 'linearGradient', 'radialGradient', 'stop', 'clipPath', 'mask', 'pattern', 'marker']);
const attributes = new Set(['id', 'xmlns', 'xmlns:xlink', 'version', 'viewBox', 'preserveAspectRatio', 'width', 'height',
  'x', 'y', 'x1', 'y1', 'x2', 'y2', 'cx', 'cy', 'r', 'rx', 'ry', 'd', 'points', 'dx', 'dy', 'rotate', 'pathLength',
  'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity', 'stroke-dasharray', 'stroke-dashoffset',
  'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'clip-path', 'clip-rule', 'opacity', 'transform', 'color',
  'font-family', 'font-size', 'font-weight', 'font-style', 'text-anchor', 'dominant-baseline', 'alignment-baseline',
  'letter-spacing', 'word-spacing', 'text-decoration', 'textLength', 'lengthAdjust', 'style',
  'gradientUnits', 'gradientTransform', 'spreadMethod', 'offset', 'stop-color', 'stop-opacity', 'fx', 'fy', 'fr',
  'href', 'xlink:href', 'marker-start', 'marker-mid', 'marker-end', 'markerWidth', 'markerHeight', 'refX', 'refY',
  'orient', 'markerUnits', 'mask', 'maskUnits', 'maskContentUnits', 'clipPathUnits', 'patternUnits', 'patternContentUnits',
  'patternTransform']);
const styleProperties = new Set(['fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity',
  'stroke-dasharray', 'stroke-dashoffset', 'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'clip-path',
  'clip-rule', 'opacity', 'color', 'font-family', 'font-size', 'font-weight', 'font-style', 'text-anchor',
  'dominant-baseline', 'letter-spacing', 'word-spacing', 'text-decoration', 'stop-color', 'stop-opacity', 'mask',
  'marker-start', 'marker-mid', 'marker-end']);
const idPattern = /^[A-Za-z_][\w:.-]*$/;
const localUrl = /^url\(\s*['"]?#([A-Za-z_][\w:.-]*)['"]?\s*\)$/i;
const parser = new XMLParser({ preserveOrder: true, ignoreAttributes: false, attributeNamePrefix: '',
  parseTagValue: false, parseAttributeValue: false, trimValues: false, processEntities: false, ignoreDeclaration: true });

export type ValidSvg = { xml: string; aspectRatio: number };
type XmlNode = Record<string, unknown>;
type SvgNode = { name: string; children: number[]; references: string[] };
const failure = (reason: string): never => { throw new Error(`Unsupported SVG: ${reason}`); };

function utf8Bytes(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code < 0x80) bytes++;
    else if (code < 0x800) bytes += 2;
    else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length
      && value.charCodeAt(index + 1) >= 0xdc00 && value.charCodeAt(index + 1) <= 0xdfff) { bytes += 4; index++; }
    else bytes += 3;
    if (bytes > MAX_SVG_BYTES) return bytes;
  }
  return bytes;
}

/** A bounded native SVG subset. XML syntax and the native renderer remain library-owned. */
export function validateNativeSvg(source: string): ValidSvg {
  if (!source.trim() || source.length > MAX_SVG_BYTES || utf8Bytes(source) > MAX_SVG_BYTES) failure('source size');
  if (/<!\s*(?:DOCTYPE|ENTITY)|<!\[CDATA\[|<\?(?!xml(?:\s|\?>))/i.test(source)) failure('declarations');
  // Predefined XML escapes and numeric character references are text, never an
  // entity definition. Custom entities are rejected before the XML parser runs.
  if (/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)/.test(source)) failure('entity reference');
  if (XMLValidator.validate(source, { allowBooleanAttributes: false }) !== true) failure('invalid XML');
  const tree = parser.parse(source) as XmlNode[];
  const roots = tree.filter(node => Object.keys(node).some(key => key !== ':@' && key !== '#text'));
  if (roots.length !== 1 || !Array.isArray(roots[0].svg)) failure('one svg root is required');
  const rootAttributes = roots[0][':@'] as Record<string, string> | undefined;
  const box = (rootAttributes?.viewBox ?? '').trim().split(/[\s,]+/).map(Number);
  if (box.length !== 4 || box.some(value => !Number.isFinite(value) || Math.abs(value) > 10_000_000) || box[2] < 0.000001 || box[3] < 0.000001
    || !Number.isFinite(box[2] / box[3]) || box[2] / box[3] <= 0) failure('valid viewBox is required');

  const nodes: SvgNode[] = [];
  const ids = new Map<string, number>();
  const queue: { entry: XmlNode; parent?: number; depth: number }[] = [{ entry: roots[0], depth: 0 }];
  let coordinates = 0;
  while (queue.length) {
    const { entry, parent, depth } = queue.pop()!;
    if (depth > MAX_DEPTH || nodes.length >= MAX_NODES) failure('node or depth budget');
    const name = Object.keys(entry).find(key => key !== ':@') ?? '';
    if (name === '#text') {
      if (String(entry[name]).trim() && (parent === undefined || !['text', 'tspan', 'title', 'desc'].includes(nodes[parent].name))) failure('text location');
      continue;
    }
    if (!tags.has(name)) failure(`element ${name}`);
    const index = nodes.length;
    const node: SvgNode = { name, children: [], references: [] };
    nodes.push(node);
    if (parent !== undefined) nodes[parent].children.push(index);
    const validateValue = (attribute: string, value: string) => {
      if (/[&\\\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)
        || /(?:javascript|data|file|https?|ftp):|expression\s*\(/i.test(value)) failure(`attribute ${attribute}`);
      if (attribute === 'href' || attribute === 'xlink:href') {
        if (!['use', 'linearGradient', 'radialGradient'].includes(name) || !value.startsWith('#') || !idPattern.test(value.slice(1))) failure('external reference');
        node.references.push(value.slice(1));
      }
      if (/url\s*\(/i.test(value)) {
        const match = localUrl.exec(value);
        if (!match) failure('external CSS URL');
        node.references.push(match![1]);
      }
      for (const number of value.matchAll(/[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/gi)) {
        if (!Number.isFinite(Number(number[0])) || Math.abs(Number(number[0])) > 10_000_000 || ++coordinates > 65_536) failure('coordinate budget');
      }
    };
    for (const [attribute, raw] of Object.entries((entry[':@'] ?? {}) as Record<string, unknown>)) {
      if (!attributes.has(attribute) || typeof raw !== 'string') failure(`attribute ${attribute}`);
      const value = raw as string;
      if (attribute === 'xmlns' || attribute === 'xmlns:xlink') {
        if (value !== (attribute === 'xmlns' ? 'http://www.w3.org/2000/svg' : 'http://www.w3.org/1999/xlink')) failure('namespace');
      } else if (attribute === 'id') {
        if (!idPattern.test(value) || ids.has(value)) failure('duplicate or invalid id');
        ids.set(value, index);
      } else if (attribute === 'style') {
        if (/[{}@\\&]/.test(value)) failure('CSS syntax');
        for (const declaration of value.split(';').filter(part => part.trim())) {
          const colon = declaration.indexOf(':');
          const property = declaration.slice(0, colon).trim();
          if (colon <= 0 || !styleProperties.has(property)) failure('CSS property');
          validateValue(property, declaration.slice(colon + 1).trim());
        }
      } else validateValue(attribute, value);
    }
    const children: XmlNode[] = Array.isArray(entry[name]) ? entry[name] as XmlNode[] : failure('invalid children');
    if (nodes.length + queue.length + children.length > MAX_NODES) failure('node budget');
    for (let child = children.length - 1; child >= 0; child--) queue.push({ entry: children[child], parent: index, depth: depth + 1 });
  }
  // Local use/paint references cannot create cycles or exponential native work.
  const active = new Set<number>();
  const work = [{ index: 0, exit: false, depth: 0 }];
  let expanded = 0;
  while (work.length) {
    const step = work.pop()!;
    if (step.exit) { active.delete(step.index); continue; }
    if (active.has(step.index) || ++expanded > MAX_NODES || step.depth > MAX_DEPTH) failure('reference budget');
    active.add(step.index);
    work.push({ ...step, exit: true });
    const node = nodes[step.index];
    for (const reference of node.references) {
      const target = ids.get(reference);
      if (target === undefined) failure('missing local reference');
      work.push({ index: target!, exit: false, depth: step.depth + 1 });
    }
    for (const child of node.children) work.push({ index: child, exit: false, depth: step.depth + 1 });
  }
  return { xml: source, aspectRatio: box[2] / box[3] };
}

type SvgResponse = { ok: boolean; headers: { get: (name: string) => string | null };
  body: { getReader: () => { read: () => Promise<{ done: boolean; value?: Uint8Array }>;
    cancel: () => Promise<unknown>; releaseLock: () => void } } | null };

/** Enforce the response budget while reading, before decoding or retaining an oversized body. */
export async function readSvgResponse(response: SvgResponse, signal: AbortSignal): Promise<string> {
  if (!response.ok) throw new Error('SVG request failed');
  const declared = Number(response.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > MAX_SVG_BYTES) throw new Error('SVG response exceeds the size limit');
  if (!response.body) throw new Error('SVG streaming response is unavailable');
  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const parts: string[] = [];
  let bytes = 0;
  let complete = false;
  const cancel = () => { void reader.cancel().catch(() => undefined); };
  signal.addEventListener('abort', cancel);
  try {
    while (true) {
      if (signal.aborted) throw new Error('SVG request was cancelled');
      const chunk = await reader.read();
      if (signal.aborted) throw new Error('SVG request was cancelled');
      if (chunk.done) { complete = true; break; }
      if (!chunk.value) continue;
      bytes += chunk.value.byteLength;
      if (bytes > MAX_SVG_BYTES) throw new Error('SVG response exceeds the size limit');
      parts.push(decoder.decode(chunk.value, { stream: true }));
    }
    parts.push(decoder.decode());
    return parts.join('');
  } finally {
    signal.removeEventListener('abort', cancel);
    if (!complete) cancel();
    reader.releaseLock();
  }
}

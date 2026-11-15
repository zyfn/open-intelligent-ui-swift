import { upstreamFile } from "../../upstream.mjs";
// Project the pinned upstream icon artwork into drawing commands. Runtime Swift
// only draws these commands; it neither parses SVG nor maps names to substitutes.
import {readFileSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {resolve, dirname} from 'node:path';
import assert from 'node:assert/strict';
const here = dirname(fileURLToPath(import.meta.url));
const moduleArgument = process.argv.slice(2).find(arg => !arg.startsWith('--'));
const modules = moduleArgument ? resolve(moduleArgument) : resolve(here, 'node_modules');
const require = createRequire(resolve(modules, '_generator.cjs'));
const svgpath = require('svgpath');
const lucide = resolve(modules, 'lucide-react');
const revision = '9823ec05d4b29bc78d101676dc16b44fe17f1830';
const version = JSON.parse(readFileSync(resolve(lucide, 'package.json'))).version;
if (version !== '0.562.0') throw Error('Unexpected Lucide version');
const imports = readFileSync(resolve(lucide, 'dist/esm/dynamicIconImports.js'), 'utf8');
const icons = {};
for (const match of imports.matchAll(/"([^"]+)":\s*\(\)\s*=>\s*import\('\.\/icons\/([^']+)'\)/g)) {
  const [, name, file] = match;
  let source = readFileSync(resolve(lucide, 'dist/esm/icons', file), 'utf8');
  // Alias files re-export a canonical icon; use the exact same artwork.
  if (!source.includes('const __iconNode')) {
    const alias = source.match(/from ['"]\.\/([^'"]+)['"]/);
    if (!alias) throw Error('Unresolved icon alias: ' + name);
    source = readFileSync(resolve(lucide, 'dist/esm/icons', alias[1]), 'utf8');
  }
  const literal = source.match(/const __iconNode = (\[[\s\S]*?\]);/)[1];
  // Icon nodes are JSON-compatible literals with unquoted attribute names.
  const nodes = JSON.parse(literal.replace(/([{,]\s*)([a-zA-Z][\w-]*):/g, '$1"$2":'));
  icons[name] = nodes.map(([type, attributes]) => {
    const a = Object.fromEntries(Object.entries(attributes).filter(([key]) => key !== 'key'));
    const numeric = key => Number(a[key] ?? 0);
    switch (type) {
      case 'path': {
        const path = svgpath(a.d).abs().unarc().unshort();
        if (path.err) throw Error(name + ': ' + path.err);
        let x = 0, y = 0, startX = 0, startY = 0;
        const commands = path.segments.map(([op, ...values]) => {
          if (op === 'H') { x = values[0]; return ['L', x, y]; }
          if (op === 'V') { y = values[0]; return ['L', x, y]; }
          if (op !== 'Z') { x = values.at(-2); y = values.at(-1); }
          if (op === 'M') { startX = x; startY = y; }
          if (op === 'Z') { x = startX; y = startY; }
          if (!['M','L','C','Q','Z'].includes(op)) throw Error('Unsupported path command: ' + op);
          return [op, ...values];
        });
        return {commands};
      }
      case 'circle': return {ellipse: [numeric('cx')-numeric('r'), numeric('cy')-numeric('r'), numeric('r')*2, numeric('r')*2]};
      case 'ellipse': return {ellipse: [numeric('cx')-numeric('rx'), numeric('cy')-numeric('ry'), numeric('rx')*2, numeric('ry')*2]};
      case 'rect': return {rect: [numeric('x'), numeric('y'), numeric('width'), numeric('height'), Number(a.rx ?? a.ry ?? 0), Number(a.ry ?? a.rx ?? 0)]};
      case 'line': return {commands: [['M',numeric('x1'),numeric('y1')],['L',numeric('x2'),numeric('y2')]]};
      case 'polygon': case 'polyline': {
        const points = a.points.trim().split(/[\s,]+/).map(Number);
        const commands = [];
        for(let i=0;i<points.length;i+=2) commands.push([i ? 'L' : 'M',points[i],points[i+1]]);
        if(type==='polygon') commands.push(['Z']);
        return {commands};
      }
      default: throw Error('Unsupported icon primitive: ' + type);
    }
  }).map((primitive, index) => {
    const fill = nodes[index][1].fill;
    if (fill && !['none', 'currentColor'].includes(fill)) throw Error('Unexpected icon fill: ' + fill);
    return {...primitive, fill: fill === 'currentColor'};
  });
}
if (Object.keys(icons).length < 1500) throw Error('Incomplete dynamic icon catalog');
const fallbackSource = upstreamFile(revision, 'packages/react-ui/src/components/_shared/icons/categoryFallbacks.ts');
const fallbacks = Object.fromEntries([...fallbackSource.split('};')[0].matchAll(/^\s*(?:"([^"]+)"|(\w+)):\s*"([^"]+)"/gm)].map(m=>[m[1]??m[2],m[3]]));
for(const name of [...Object.values(fallbacks),'circle-dot']) if(!icons[name]) throw Error('Missing fallback: '+name);
// SVG arc conversion uses platform transcendental math. Its final binary
// digits are not portable across Node/CPU/libm implementations. Check geometry
// with an explicitly tiny scale-relative rounding budget, while requiring exact
// names, order, commands, flags, metadata, lengths and all non-geometry values.
// Never rewrite the committed artwork merely to fit a new build platform.
function compareArtwork(expected, actual) {
  let roundedCoordinates = 0, maximumAbsoluteDifference = 0;
  function visit(a, b, path) {
    if (Object.is(a, b)) return;
    if (typeof a === 'number' && typeof b === 'number' && path[0] === 'icons') {
      assert.ok(Number.isFinite(a) && Number.isFinite(b), `Non-finite coordinate: ${path.join('.')}`);
      const difference = Math.abs(a - b);
      const roundingBudget = Math.min(1e-10, 16 * Number.EPSILON * Math.max(1, Math.abs(a), Math.abs(b)));
      assert.ok(difference <= roundingBudget,
        `Artwork geometry changed: ${path.join('.')} (${a} -> ${b}; delta ${difference}, budget ${roundingBudget})`);
      roundedCoordinates++;
      maximumAbsoluteDifference = Math.max(maximumAbsoluteDifference, difference);
      return;
    }
    assert.equal(typeof b, typeof a, `Type changed: ${path.join('.')}`);
    if (a === null || b === null || typeof a !== 'object') {
      assert.deepEqual(b, a, `Value changed: ${path.join('.')}`);
      return;
    }
    assert.equal(Array.isArray(b), Array.isArray(a), `Structure changed: ${path.join('.')}`);
    assert.deepEqual(Object.keys(b), Object.keys(a), `Keys/order/length changed: ${path.join('.')}`);
    for (const key of Object.keys(a)) visit(a[key], b[key], [...path, key]);
  }
  visit(expected, actual, []);
  return {roundedCoordinates, maximumAbsoluteDifference};
}
// Negative controls prove that portability does not permit changed topology,
// labels, fills, revisions, missing aliases, or visible geometric drift.
const control = {version: 'pinned', revision: 'fixed', fallbacks: {place: 'pin'},
  icons: {pin: [{commands: [['M', 6.11856720214702, 12]], fill: false}]}};
for (const mutate of [
  x => { x.version = 'different'; },
  x => { x.fallbacks.place = 'other'; },
  x => { x.icons.pin[0].commands[0][0] = 'L'; },
  x => { x.icons.pin[0].fill = true; },
  x => { x.icons.pin[0].commands[0][1] += 0.000001; },
  x => { x.icons.pin[0].commands[0].push(1); },
  x => { delete x.icons.pin; },
  x => { x.icons.pin[0].commands[0][1] = NaN; },
]) {
  const changed = structuredClone(control); mutate(changed);
  assert.throws(() => compareArtwork(control, changed));
}
const rounded = structuredClone(control);
rounded.icons.pin[0].commands[0][1] = 6.1185672021470205;
assert.equal(compareArtwork(control, rounded).roundedCoordinates, 1);
assert.equal(compareArtwork(control, structuredClone(control)).roundedCoordinates, 0);
const target = resolve(here,'../../../Sources/SwiftOpenUI/Resources');
for (const [name, data] of [
  ['lucide-icons.json', JSON.stringify({version,revision,fallbacks,icons})+'\n'],
  ['Lucide-LICENSE.txt', readFileSync(resolve(lucide,'LICENSE'),'utf8')],
]) {
  if (process.argv.includes('--check')) {
    const expected = readFileSync(resolve(target,name),'utf8');
    if (name === 'lucide-icons.json') {
      const result = compareArtwork(JSON.parse(expected), JSON.parse(data));
      console.log(JSON.stringify({resource: name, byteIdentical: expected === data,
        ...result, policy: 'exact structure and metadata; geometry <= min(1e-10, 16*EPSILON*scale)'}));
    } else assert.equal(data, expected, `Generated resource differs: ${name}`);
  } else writeFileSync(resolve(target,name), data);
}
console.log(`Lucide ${version}: ${Object.keys(icons).length} names, ${Object.keys(fallbacks).length} category fallbacks`);

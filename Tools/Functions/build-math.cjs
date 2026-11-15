// Reproduce the standalone MathML engine from the same audited npm lock as
// the function generator. Application startup uses these committed bytes.
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const check = process.argv.includes('--check');
if (process.argv.slice(2).some(value => value !== '--check')) {
  throw new Error('Usage: node Tools/Functions/build-math.cjs [--check]');
}
const here = __dirname;
const resources = path.resolve(here, '../../Sources/SwiftIntelligentUI/Resources');
const read = file => fs.readFileSync(file);
const sha256 = value => createHash('sha256').update(value).digest('hex');
const packageBytes = read(path.join(here, 'package.json'));
const lockBytes = read(path.join(here, 'package-lock.json'));
const spec = JSON.parse(packageBytes);
const lock = JSON.parse(lockBytes);
const installed = path.join(here, 'node_modules/katex');
const installedSpec = JSON.parse(read(path.join(installed, 'package.json')));
const version = spec.dependencies.katex;
assert.match(version, /^\d+\.\d+\.\d+$/, 'KaTeX must use an exact reviewed version');
assert.equal(lock.packages[''].dependencies.katex, version);
const locked = lock.packages['node_modules/katex'];
assert.equal(locked.version, version);
assert.equal(installedSpec.version, version, 'Run npm ci before building Math');
assert.equal(locked.resolved, `https://registry.npmjs.org/katex/-/katex-${version}.tgz`);
assert.match(locked.integrity, /^sha512-/);

const script = read(path.join(installed, 'dist/katex.min.js'));
const license = read(path.join(installed, 'LICENSE'));
const noticePath = path.join(resources, 'THIRD-PARTY-NOTICES.txt');
const previousNotices = read(noticePath).toString('utf8');
const sections = [...previousNotices.matchAll(/^KaTeX [^\n]+\n/gm)];
assert.equal(sections.length, 1, 'Expected one KaTeX license section');
const sectionStart = sections[0].index;
const priorSection = previousNotices.slice(sectionStart).match(
  /^KaTeX [^\n]+\nThe MIT License \(MIT\)\n[\s\S]*?\nSOFTWARE\.(?:\n|$)/,
);
assert.ok(priorSection, 'Unrecognized KaTeX license section; inspect before changing notices');
const notices = previousNotices.slice(0, sectionStart)
  + `KaTeX ${version}\n${license.toString('utf8').trimEnd()}\n`
  + previousNotices.slice(sectionStart + priorSection[0].length);
const manifest = {
  package: 'katex',
  version,
  resolved: locked.resolved,
  integrity: locked.integrity,
  packageSHA256: sha256(packageBytes),
  lockSHA256: sha256(lockBytes),
  builderSHA256: sha256(read(__filename)),
  sourceScript: 'dist/katex.min.js',
  resource: 'katex.min.js',
  scriptSHA256: sha256(script),
  scriptBytes: script.length,
  sourceLicense: 'LICENSE',
  licenseSHA256: sha256(license),
  notice: 'THIRD-PARTY-NOTICES.txt',
  noticeSection: `KaTeX ${version}`,
  noticesSHA256: sha256(notices),
  output: 'mathml',
  stylesheetAndFonts: 'not required by the native MathML renderer',
};
const outputs = new Map([
  ['katex.min.js', script],
  ['THIRD-PARTY-NOTICES.txt', Buffer.from(notices)],
  ['katex-manifest.json', Buffer.from(JSON.stringify(manifest, null, 2) + '\n')],
]);
for (const [name, bytes] of outputs) {
  const file = path.join(resources, name);
  if (check) assert.ok(read(file).equals(bytes), `Generated Math resource drift: ${name}`);
  else fs.writeFileSync(file, bytes);
}
console.log(`KaTeX ${version}: ${script.length} bytes; ${check ? 'verified' : 'generated'} offline MathML resource`);

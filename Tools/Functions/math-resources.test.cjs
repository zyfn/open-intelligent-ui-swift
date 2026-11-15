// Exercise committed runtime bytes, including GHSA-238p-pmpm-9mq7 in an
// isolated realm. Prototype changes cannot escape into the Node test runner.
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const repository = path.resolve(__dirname, '../..');
const intelligent = path.join(repository, 'Sources/SwiftIntelligentUI/Resources');
const standard = path.join(repository, 'Sources/SwiftOpenUI/Resources');
const sha256 = value => createHash('sha256').update(value).digest('hex');
function realm(file) {
  const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
  vm.runInContext(fs.readFileSync(file, 'utf8'), context, { timeout: 5000 });
  return context;
}
function evaluate(context, source) {
  return vm.runInContext(source, context, { timeout: 5000 });
}
function assertUntrusted(output) {
  assert.doesNotMatch(output, /\bhref\s*=\s*["']\s*javascript:/i);
  assert.doesNotMatch(output, /\bsrc\s*=\s*["']\s*https:\/\/example\.invalid\//i);
}

test('standalone Math bundle and license match their locked provenance', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(intelligent, 'katex-manifest.json')));
  const script = fs.readFileSync(path.join(intelligent, 'katex.min.js'));
  assert.equal(sha256(script), manifest.scriptSHA256);
  assert.equal(script.length, manifest.scriptBytes);
  assert.equal(sha256(fs.readFileSync(path.join(__dirname, 'package-lock.json'))), manifest.lockSHA256);
  assert.equal(sha256(fs.readFileSync(path.join(intelligent, 'THIRD-PARTY-NOTICES.txt'))), manifest.noticesSHA256);
  assert.equal(evaluate(realm(path.join(intelligent, 'katex.min.js')), 'katex.version'), manifest.version);
});

test('Intelligent Math preserves offline MathML and explicit rendering options', () => {
  const context = realm(path.join(intelligent, 'katex.min.js'));
  const output = evaluate(context, String.raw`katex.renderToString('\\frac{a}{b}', {
    output: 'mathml', displayMode: true, throwOnError: true, trust: false,
    strict: 'error', maxExpand: 1000, maxSize: 10,
  })`);
  assert.match(output, /<math\b/);
  assert.match(output, /<mfrac>/);
  assert.doesNotMatch(output, /class="katex-html"/);
  assert.throws(() => evaluate(context, String.raw`katex.renderToString('\\invalidExpression', {throwOnError: true, trust: false})`));
});

test('KaTeX ignores polluted prototype trust and inherited renderer options', () => {
  const context = realm(path.join(intelligent, 'katex.min.js'));
  for (const options of [
    `Object.prototype.trust = true; return { throwOnError: false };`,
    `return Object.assign(Object.create({ trust: true }), { throwOnError: false });`,
  ]) {
    for (const expression of [String.raw`\href{javascript:alert(1)}{x}`, String.raw`\includegraphics{https://example.invalid/blocked.png}`]) {
      const output = evaluate(context, `(() => {
        try { const options = (() => { ${options} })(); return katex.renderToString(${JSON.stringify(expression)}, options); }
        finally { delete Object.prototype.trust; }
      })()`);
      assertUntrusted(output);
    }
  }
});

test('standard rich text retains math extraction and embeds all fonts offline', () => {
  const context = realm(path.join(standard, 'rich-text.js'));
  const markdown = evaluate(context, `NativeRichText.prepare('Inline $$x^2$$ formula', 'textContent')`);
  assert.match(markdown, /openui-math:\/\/equation/);
  const output = evaluate(context, String.raw`NativeRichText.math('\\frac{a}{b}', true)`);
  assert.match(output, /<mfrac>/);
  assert.doesNotMatch(output, /katex-error/);
  const manifest = JSON.parse(fs.readFileSync(path.join(standard, 'rich-text-manifest.json')));
  const css = fs.readFileSync(path.join(standard, 'rich-math.css'));
  assert.equal(manifest.versions.katex, '0.18.2');
  assert.equal(sha256(fs.readFileSync(path.join(standard, 'rich-text.js'))), manifest.scriptSHA256);
  assert.equal(sha256(css), manifest.cssSHA256);
  assert.ok(manifest.offlineFonts && manifest.embeddedFontCount > 0);
  assert.doesNotMatch(css.toString('utf8'), /url\((?!data:)/);
});

test('standard rich text keeps untrusted links and images blocked under prototype pollution', () => {
  const context = realm(path.join(standard, 'rich-text.js'));
  for (const expression of [String.raw`\href{javascript:alert(1)}{x}`, String.raw`\includegraphics{https://example.invalid/blocked.png}`]) {
    const output = evaluate(context, `(() => {
      Object.prototype.trust = true;
      try { return NativeRichText.math(${JSON.stringify(expression)}, false); }
      finally { delete Object.prototype.trust; }
    })()`);
    assertUntrusted(output);
  }
});

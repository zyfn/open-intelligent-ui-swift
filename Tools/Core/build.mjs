import { build } from 'esbuild';
import { prepareCoreSource, lock } from '../upstream.mjs';
import { readiness } from './readiness-compat.mjs';
import { actionProvenance, propActionProvenance, validationOwnKeys, messageBoundary } from './bridge-compat.mjs';
import {
  serializer,
  replaceOnce,
  materializer,
  evaluationBudget,
  zodJSONSchemaCompatibility,
  zodJSONSchemaCompatibilityPlugin,
} from './compat.mjs';
import { readFileSync, writeFileSync, mkdirSync, cpSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname, join } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
const here = dirname(fileURLToPath(import.meta.url)),
  root = prepareCoreSource();
// The pinned checkout adds the positional-omittability rule to the signature
// printer plus its regression test; parser/runtime sources are unchanged.
// The tree pin also records the repository-formatted regression test.
const pin = lock.core.adaptedTree;
if (
  execFileSync('git', ['rev-parse', 'HEAD:packages/lang-core'], {
    cwd: root,
    encoding: 'utf8',
  }).trim() !== pin
)
  throw Error('Review upstream source pin');
execFileSync('git', ['diff', '--quiet', 'HEAD', '--', 'packages/lang-core'], {
  cwd: root,
});
// Preserve the original module graph's relative paths. esbuild uses module
// paths when assigning minified identifiers, so mere relocation otherwise
// changes the shipped resource despite identical language/runtime semantics.
// Only a temporary build workspace is materialized; no upstream checkout or
// node_modules directory is required by a SwiftPM consumer.
const bridge = join(root, 'packages/swift-lang/scripts');
mkdirSync(bridge, { recursive: true });
cpSync(join(here, 'package.json'), join(bridge, 'package.json'));
for (const file of ['entry.ts', 'captures.ts', 'authoring.ts', 'readiness.ts', 'budget.ts']) {
  const source = readFileSync(join(here, file), 'utf8')
    .replaceAll("'@openui/core-source'", "'../../lang-core/src/index'")
    .replaceAll("'@openui/core-source/", "'../../lang-core/src/");
  writeFileSync(join(bridge, file), source);
}
cpSync(join(here, 'node_modules'), join(bridge, 'node_modules'), { recursive: true });
const banner = `globalThis.TextEncoder=class{encode(s){return Uint8Array.from(__utf8Encode(String(s)))}};globalThis.TextDecoder=class{decode(bytes){return __utf8Decode(bytes)}};globalThis.console={warn(){},error(){},log(){}};`;
const result = await build({
  absWorkingDir: root,
  tsconfig: join(root, 'tsconfig.json'),
  entryPoints: ['packages/swift-lang/scripts/entry.ts'],
  bundle: true,
  write: false,
  format: 'iife',
  globalName: 'SwiftCore',
  platform: 'neutral',
  mainFields: ['module', 'main'],
  target: ['safari15'],
  minify: true,
  legalComments: 'eof',
  nodePaths: [join(bridge, 'node_modules')],
  banner: { js: banner },
  metafile: true,
  plugins: [
    zodJSONSchemaCompatibilityPlugin(),
    {
      name: 'native-compatibility',
      setup(b) {
        b.onLoad({ filter: /\/lang-core\/src\/message\.ts$/ }, (args) => ({
          contents: messageBoundary(readFileSync(args.path, 'utf8')),
          loader: 'ts',
        }));
        b.onLoad({ filter: /\/parser\/materialize\.ts$/ }, (args) => ({
          contents: readiness(materializer(readFileSync(args.path, 'utf8'), join(bridge, 'budget.ts')), 'materialize', join(bridge, 'readiness.ts')),
          loader: 'ts',
        }));
        b.onLoad({ filter: /\/utils\/validation\.ts$/ }, (args) => ({
          contents: validationOwnKeys(replaceOnce(
            readFileSync(args.path, 'utf8'),
            'return new RegExp(arg).test(value) ? undefined : \"Invalid format\";',
            'const outcome=__nativePattern(arg,value);return outcome===\"resourceError\"?\"Validation could not complete: regular expression resource limit exceeded.\":outcome===\"matches\"||outcome===\"invalidPattern\"?undefined:\"Invalid format\";',
          )),
          loader: 'ts',
        }));
        b.onLoad({ filter: /\/parser\/serialize\.ts$/ }, (args) => ({
          contents: serializer(readFileSync(args.path, 'utf8')),
          loader: 'ts',
        }));
        for (const [kind, filter] of [
          ['lexer', /\/parser\/lexer\.ts$/],
          ['expressions', /\/parser\/expressions\.ts$/],
          ['evaluator', /\/runtime\/evaluator\.ts$/],
          ['evaluate-tree', /\/runtime\/evaluate-tree\.ts$/],
        ]) b.onLoad({filter}, (args) => {
          let source = readFileSync(args.path, 'utf8');
          if (kind === 'evaluator' || kind === 'evaluate-tree')
            source = evaluationBudget(source, kind, join(bridge, 'budget.ts'));
          if (kind === 'evaluator') source = actionProvenance(source, join(bridge, 'captures.ts'));
          source = readiness(source, kind, join(bridge, 'readiness.ts'));
          if (kind === 'lexer' || kind === 'expressions')
            source = evaluationBudget(source, kind, join(bridge, 'budget.ts'));
          return { contents: source, loader: 'ts' };
        });
        for (const [kind, filter] of [
          ['builtins', /\/parser\/builtins\.ts$/],
          ['statements', /\/parser\/statements\.ts$/],
          ['merge', /\/parser\/merge\.ts$/],
          ['evaluate-prop', /\/runtime\/evaluate-prop\.ts$/],
          ['query-manager', /\/runtime\/queryManager\.ts$/],
        ]) b.onLoad({filter}, args => {
          let source = evaluationBudget(readFileSync(args.path, 'utf8'), kind, join(bridge, 'budget.ts'));
          if (kind === 'evaluate-prop') source = readiness(propActionProvenance(source, join(bridge, 'captures.ts')),
            kind, join(bridge, 'readiness.ts'));
          return { contents: source, loader: 'ts' };
        });
      },
    },
    {
      name: 'native-helper-exports',
      setup(b) {
        b.onLoad({ filter: /\/parser\/parser\.ts$/ }, (args) => ({
          contents:
            readiness(evaluationBudget(readFileSync(args.path, 'utf8'), 'parser', join(bridge, 'budget.ts')), 'parser', join(bridge, 'readiness.ts')) +
            '\nexport {preprocess as nativePreprocess};',
          loader: 'ts',
        }));
      },
    },
    {
      name: 'no-native-telemetry',
      setup(b) {
        b.onLoad({ filter: /\/telemetry\/runtime\.ts$/ }, () => ({
          contents:
            'export const prepareParserParseTelemetry=()=>undefined;export const captureParserParseResult=()=>{};export const captureParserParseException=()=>{};export const recordSystemPromptGeneration=()=>{};',
          loader: 'ts',
        }));
      },
    },
  ],
});
const imports = Object.values(result.metafile.outputs).flatMap(
  (x) => x.imports,
);
if (imports.length) throw Error('Unexpected external runtime imports');
const out = join(here, '../../Sources/SwiftLang/Resources');
mkdirSync(out, { recursive: true });
const data = Buffer.from(
  result.outputFiles[0].text
    .split('\n')
    .map((line) => line.trimEnd())
    .join('\n'),
);
writeFileSync(join(out, 'lang-core.js'), data);
const licenses = [
  'Upstream OpenUI (MIT)',
  readFileSync(join(root, 'LICENSE'), 'utf8'),
  'Bounded native pattern backend',
  readFileSync(join(here, '../../Sources/COpenUIRegExp/vendor/LICENSE'), 'utf8'),
];
for (const name of [
  'zod',
  'whatwg-url',
  'webidl-conversions',
  'tr46',
  'punycode',
]) {
  const d = join(here, 'node_modules', name);
  let text;
  for (const file of [
    'LICENSE',
    'LICENSE.md',
    'LICENSE.txt',
    'LICENSE-MIT.txt',
  ])
    try {
      text = readFileSync(join(d, file), 'utf8');
      break;
    } catch {}
  if (!text) throw Error('Missing license ' + name);
  licenses.push(name + '\n' + text);
}
writeFileSync(
  join(out, 'THIRD-PARTY-NOTICES.txt'),
  licenses
    .join('\n\n')
    .split('\n')
    .map((line) => line.trimEnd())
    .join('\n'),
);
writeFileSync(
  join(out, 'core-manifest.json'),
  JSON.stringify(
    {
      upstream: lock.core.revision,
      dependencyRepository: lock.repository,
      dependencyPackage: lock.core.package,
      dependencyVersion: lock.core.version,
      originalSourceTree: lock.core.originalTree,
      sourcePatchSHA256: lock.core.sourcePatchSHA256,
      sourceTree: pin,
      dependencyTransforms: [zodJSONSchemaCompatibility],
      sha256: createHash('sha256').update(data).digest('hex'),
      bytes: data.length,
      lockSha256: createHash('sha256')
        .update(readFileSync(join(here, 'package-lock.json')))
        .digest('hex'),
      adapterSha256: createHash('sha256')
        .update(
          ['entry.ts', 'captures.ts', 'authoring.ts', 'compat.mjs', 'bridge-compat.mjs', 'budget.ts', 'readiness.ts', 'readiness-compat.mjs', 'adaptations.json', 'patches/serializer-roundtrip.patch', 'build.mjs', '../upstream.mjs', '../upstream.json', 'patches/positional-omittability.patch']
            .map((name) => readFileSync(join(here, name), 'utf8'))
            .join('\n'),
        )
        .digest('hex'),
      telemetry:
        'excluded at build time: native host has no process, fetch or install telemetry',
      bridge: 'opaque captures resolve through upstream EvaluationContext.resolveRef; core-created ActionPlan objects retain provenance; host-authored plans execute at the native boundary',
      authoring: {
        rules: ['lang-core createLibrary', 'lang-core library.extend', 'lang-core compileSchema', 'lang-core schemaSignature/buildSignature'],
        transport: 'Pinned Zod fromJSONSchema plus JSON/Zod reference identity. LibrarySpec and signatures come directly from the shared core.',
        removedNativeRules: ['component/call naming and parameter-order checks', 'namespace/group validation copies', 'JSON Schema compiler and action-ref inlining', 'slot add/remove/override algorithms', 'signature type rendering', 'static action schema copies'],
      },
      hostCapabilities: [
        'UTF-8 encoding for WHATWG URL',
        'timers and tool Promise callbacks',
        'bounded no-flag ECMAScript pattern validation',
      ],
      compatibility: [
        'serializer precedence and lossless keys',
        'materialization depth/node budgets',
        'shared evaluation work and expanded-output budgets',
        'source limits reuse parser tokens; merge raw-input and cumulative-work limits; linear multiline-ternary lookahead',
        'native pre-encode budgets for tool/context values, Evaluator ASTs and high-level State inputs; conservative non-data metadata/AST costs',
      ],
      adaptations: JSON.parse(readFileSync(join(here, 'adaptations.json'), 'utf8')),
      retainedPatches: [
        {
          module: 'message.ts',
          reason: 'The private Lang content entry protects its raw quote/comment prefix; the same message parser still handles frames and retries, while public parseMessage remains unchanged.',
          removal: 'Equivalent upstream distinction between raw Lang content and transport headers.',
        },
        {
          module: 'parser/lexer.ts, parser/expressions.ts, parser/statements.ts, parser/merge.ts, parser/parser.ts',
          reason: 'Source checks reuse parser tokens and completed-statement counts; raw merge inputs and all merge work share one limit. Same-run newline lookahead avoids quadratic rescanning.',
          removal: 'Equivalent upstream source and merge limits with explicit rejection, and linear statement lookahead.',
        },
        {
          module: 'parser/serialize.ts',
          reason: 'Pinned serializer loses grouping and fails to quote nonidentifier keys during editing round trips.',
          removal: 'Adopt an upstream release with equivalent verified round-trip fixes.',
        },
        {
          module: 'parser/materialize.ts, parser/parser.ts',
          reason: 'Bound materialization, shared state-default evaluation and projected alias occurrences; report exhaustion through private metadata before native projection.',
          removal: 'Equivalent shared-core or host execution bounds verified on Apple runtimes.',
        },
        {
          module: 'parser/builtins.ts, runtime/evaluator.ts, runtime/evaluate-tree.ts, runtime/evaluate-prop.ts, runtime/queryManager.ts',
          reason: 'Bound synchronous work, implicit primitive conversions, projected values and element occurrences before native rendering or tool dispatch, including automatic query readers.',
          removal: 'Equivalent shared-core budgets verified against normal official results and bounded expansion regressions.',
        },
        {
          module: 'utils/validation.ts',
          reason: 'Delegate pattern execution to the existing bounded native backend; stock JSC RegExp has no portable per-call budget.',
          removal: 'Equivalent bounded pattern execution in the shared core or host runtime.',
        },
        {
          module: 'runtime/queryManager.ts',
          reason: 'Use the existing cache entry identity and live consumers for request validity across native preflight, success, failure and finalization; preserve shared requests and reject retired completions.',
          removal: 'Equivalent upstream shared-query lifecycle and native request validity verified across asynchronous preflight and completion.',
        },
        {
          module: 'parser/lexer.ts, parser/expressions.ts, parser/parser.ts, parser/materialize.ts, runtime/evaluator.ts, runtime/evaluate-tree.ts, runtime/evaluate-prop.ts',
          reason: 'Readiness source provenance is private native metadata; per-evaluation snapshots and output-occurrence scopes isolate shared values and retain old projections. The pinned core has no equivalent complete-control/dependency API.',
          removal: 'Equivalent source/dependency readiness supplied by upstream and verified against strict intermediate snapshots.',
        },
      ],
      removedSemanticOverrides: [
        'raw message context API compatibility',
        'batch parsing on streaming finalization and implicit stream reset',
        'legacy schema spelling, ordered-wire and signature projection',
        'Store shallow-object identity replacement',
        'merge duplicate-ID normalization',
        'extra slot, branch, template and argument validation',
        'Query/Mutation statement-reference expansion',
        'query retry suppression and skipInitialFetch',
        'evaluator capture dispatch and native-plan provenance exemption',
      ],
    },
    null,
    2,
  ) + '\n',
);
console.log(readFileSync(join(out, 'core-manifest.json'), 'utf8'));

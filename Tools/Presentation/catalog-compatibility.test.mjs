// The expectations below were verified against the shipped pre-upgrade core.
// Exercise native authoring itself so catalog-only formatting cannot conceal
// drift in the runtime used by Library.toSchema() and Library.toSpec().
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import vm from 'node:vm';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const script = readFileSync(resolve(root, 'Sources/OpenUILang/Resources/lang-core.js'), 'utf8');
const catalog = JSON.parse(readFileSync(resolve(root, 'Sources/OpenSwiftUI/Resources/upstream-catalog.json')));
const schemas = {
  stringNumber: { anyOf: [{ type: 'string' }, { type: 'number' }] },
  numberString: { anyOf: [{ type: 'number' }, { type: 'string' }] },
  nullable: { anyOf: [{ type: 'string' }, { type: 'null' }] },
  typeArray: { type: ['string', 'number'] },
  defaulted: { anyOf: [{ type: 'number' }, { type: 'string' }], default: 4 },
  constrained: { anyOf: [{ type: 'number', minimum: 0 }, { type: 'string', enum: ['sm', 'lg'] }] },
  nested: { type: 'array', items: { anyOf: [{ type: 'string' }, { type: 'number' }] } },
};
const input = {
  components: [{
    name: 'Probe',
    description: 'Compatibility probe',
    params: Object.entries(schemas).map(([name, schema]) => ({
      name, schema, required: true, hasDefault: Object.hasOwn(schema, 'default'),
      defaultValue: schema.default ?? null, isBindable: false,
    })),
  }],
  functions: [], actions: [], root: 'Probe',
};
function authoring(definition = input) {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
    input: JSON.stringify(definition),
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  const result = JSON.parse(vm.runInContext(
    'JSON.stringify(SwiftCore.nativeAuthoring(JSON.parse(input)))', realm, { timeout: 5000 },
  ));
  assert.equal(result.error, undefined);
  return { realm, value: result.value };
}

// Match the existing native reference test's singleton enum/const equivalence.
// Default values and other data payloads remain opaque to schema comparison.
function canonicalSchema(value) {
  if (!value || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(canonicalSchema);
  const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key, ['default', 'const', 'enum', 'examples'].includes(key) ? item : canonicalSchema(item),
  ]));
  if (Array.isArray(result.enum) && result.enum.length === 1) {
    result.const = result.enum[0];
    delete result.enum;
  }
  return result;
}

test('native authoring preserves historical scalar union schemas and parameter order', () => {
  const { value } = authoring();
  const definition = value.spec.schema.$defs.Probe;
  assert.deepEqual(definition.properties, {
    stringNumber: { anyOf: [{ type: 'string' }, { type: 'number' }] },
    numberString: { anyOf: [{ type: 'number' }, { type: 'string' }] },
    nullable: { anyOf: [{ type: 'string' }, { type: 'null' }] },
    typeArray: { anyOf: [{ type: 'string' }, { type: 'number' }] },
    defaulted: { default: 4, anyOf: [{ type: 'number' }, { type: 'string' }] },
    constrained: { anyOf: [{ type: 'number', minimum: 0 }, { type: 'string', enum: ['sm', 'lg'] }] },
    nested: { type: 'array', items: { anyOf: [{ type: 'string' }, { type: 'number' }] } },
  });
  assert.deepEqual(Object.keys(definition.properties), Object.keys(schemas));
  assert.deepEqual(value.components[0].params.map(parameter => parameter.name), Object.keys(schemas));
  assert.deepEqual(definition.required, ['stringNumber', 'numberString', 'nullable', 'typeArray', 'constrained', 'nested']);
  assert.equal(definition.additionalProperties, false);
  assert.equal(definition.description, 'Compatibility probe');
  assert.equal(value.components[0].params.find(parameter => parameter.name === 'defaulted').hasDefault, true);
  assert.equal(value.components[0].params.find(parameter => parameter.name === 'defaulted').defaultValue, 4);
});

test('nested nullable unions and mixed literals retain their distinct historical shapes', () => {
  const { value } = authoring({
    ...input,
    components: [{ ...input.components[0], params: [
      { name: 'nullable', required: true, schema: {
        anyOf: [{ anyOf: [{ type: 'string' }, { type: 'number' }] }, { type: 'null' }],
      } },
      { name: 'literal', required: true, schema: { enum: ['one', 1, true, null] } },
    ] }],
  });
  assert.deepEqual(value.spec.schema.$defs.Probe.properties, {
    nullable: { anyOf: [{ anyOf: [{ type: 'string' }, { type: 'number' }] }, { type: 'null' }] },
    literal: { anyOf: [
      { type: 'string', const: 'one' }, { type: 'number', const: 1 },
      { type: 'boolean', const: true }, { type: 'null', const: null },
    ] },
  });
});

test('preserved union schemas retain the historical parser outcomes', () => {
  const { realm, value } = authoring();
  realm.schema = JSON.stringify(value.spec.schema);
  const errors = source => {
    realm.source = source;
    return JSON.parse(vm.runInContext(
      'JSON.stringify(SwiftCore.api.createParser(JSON.parse(schema)).parse(source).meta.errors)',
      realm, { timeout: 5000 },
    ));
  };
  assert.deepEqual(errors('root=Probe("text",1,"nullable",2,4,"sm",["text",2])'), []);
  // Required-position null handling is a Lang rule; do not change it while
  // preserving the JSON Schema spelling emitted by the security upgrade.
  const requiredNull = errors('root=Probe("text",1,null,2,4,"sm",["text",2])');
  assert.deepEqual(requiredNull.map(({ code, component, path }) => ({ code, component, path })), [
    { code: 'null-required', component: 'Probe', path: '/nullable' },
  ]);
});

test('standard record bindings retain their original schema, signature and reactive identity', () => {
  const { realm, value } = authoring({
    components: catalog.components, functions: [], actions: [],
    root: catalog.root, componentGroups: catalog.componentGroups,
  });
  realm.schema = JSON.stringify(value.spec.schema);
  realm.spec = JSON.stringify(value.spec);
  const compiled = JSON.parse(vm.runInContext(
    'JSON.stringify(SwiftCore.nativeCompileSchema(JSON.parse(schema), JSON.parse(spec)))',
    realm, { timeout: 5000 },
  ));
  const expectedSchema = {
    type: 'object', propertyNames: { type: 'string' }, additionalProperties: { type: 'boolean' },
  };
  for (const name of ['CheckBoxGroup', 'SwitchGroup']) {
    const parameter = value.components.find(component => component.name === name).params.find(parameter => parameter.name === 'value');
    assert.deepEqual(parameter.schema, expectedSchema, `${name}.value authoring schema`);
    assert.deepEqual(value.spec.schema.$defs[name].properties.value, expectedSchema, `${name}.value exported schema`);
    assert.equal(parameter.isBindable, true, `${name}.value authoring identity`);
    assert.equal(compiled.components[name].find(parameter => parameter.name === 'value').isBindable, true, `${name}.value compiled identity`);
    assert.equal(value.spec.components[name].signature, catalog.spec.components[name].signature);
    assert.match(value.spec.components[name].signature, /value\?: \$binding<Record<string, boolean>>\)$/);
  }
});

test('all 84 pinned components retain every parameter and full signature through native authoring', () => {
  const { value } = authoring({
    components: catalog.components, functions: [], actions: [],
    root: catalog.root, componentGroups: catalog.componentGroups,
  });
  assert.equal(catalog.components.length, 84);
  assert.deepEqual(value.components.map(component => component.name), catalog.components.map(component => component.name));
  let parameters = 0;
  for (let index = 0; index < catalog.components.length; index++) {
    const actual = value.components[index];
    const expected = catalog.components[index];
    assert.equal(actual.description, expected.description, expected.name);
    assert.deepEqual(actual.params.map(parameter => parameter.name), expected.params.map(parameter => parameter.name), expected.name);
    for (let parameterIndex = 0; parameterIndex < expected.params.length; parameterIndex++) {
      const a = actual.params[parameterIndex];
      const b = expected.params[parameterIndex];
      const name = `${expected.name}.${b.name}`;
      assert.deepEqual(canonicalSchema(a.schema), canonicalSchema(b.schema), `${name} schema`);
      assert.equal(Boolean(a.required) && !a.hasDefault, Boolean(b.required) && !b.hasDefault, `${name} requiredness`);
      assert.equal(a.hasDefault, b.hasDefault, `${name} default presence`);
      assert.deepEqual(a.defaultValue, b.defaultValue, `${name} default value`);
      assert.equal(a.isBindable, b.isBindable, `${name} binding identity`);
      parameters++;
    }
    assert.equal(value.spec.components[expected.name].signature, catalog.spec.components[expected.name].signature, expected.name);
  }
  assert.equal(parameters, 304);
});

test('record parsing retains object values, rejects nonobjects and preserves state-reference targets', () => {
  const { realm, value } = authoring({
    components: [{ name: 'Toggle', description: '', params: [{
      name: 'value', required: true, isBindable: true,
      // This is the native record spelling; the adapter supplies string keys.
      schema: { type: 'object', additionalProperties: { type: 'boolean' } },
    }] }],
    functions: [], actions: [], root: 'Toggle',
  });
  realm.schema = JSON.stringify(value.spec.schema);
  const parse = source => {
    realm.source = source;
    return JSON.parse(vm.runInContext(
      'JSON.stringify(SwiftCore.api.createParser(JSON.parse(schema)).parse(source))',
      realm, { timeout: 5000 },
    ));
  };
  const object = parse('root=Toggle({enabled:true,disabled:false})');
  assert.deepEqual(object.meta.errors, []);
  assert.deepEqual(object.root.props.value, { enabled: true, disabled: false });
  for (const source of ['root=Toggle("wrong")', 'root=Toggle([true,false])']) {
    const result = parse(source);
    assert.equal(result.root, null);
    assert.deepEqual(result.meta.errors.map(({ code, component, path }) => ({ code, component, path })), [
      { code: 'type-mismatch', component: 'Toggle', path: '/value' },
    ]);
  }
  for (const target of ['$first', '$second']) {
    const bound = parse(`${target}={enabled:true}\nroot=Toggle(${target})`);
    assert.deepEqual(bound.meta.errors, []);
    assert.deepEqual(bound.root.props.value, { k: 'StateRef', n: target });
    assert.equal(bound.root.hasDynamicProps, true);
  }
});

test('record compatibility retains current Zod guards on the actual linked authoring props', async () => {
  const coreTools = resolve(root, 'Tools/Core');
  const [{ build }, { prepareCoreSource, coreSourcePlugin }, { zodJSONSchemaCompatibilityPlugin }] = await Promise.all([
    import(pathToFileURL(resolve(coreTools, 'node_modules/esbuild/lib/main.js'))),
    import(pathToFileURL(resolve(coreTools, '../upstream.mjs'))),
    import(pathToFileURL(resolve(coreTools, 'compat.mjs'))),
  ]);
  const authoringPath = resolve(coreTools, 'authoring.ts');
  // Test-only access to the real private `parts` function. No implementation
  // is copied, no production export is added, and each assertion runs the
  // actual Zod parser produced by the native adapter's link operation.
  const built = await build({
    stdin: { contents: `export { partsForGuardTest } from ${JSON.stringify(authoringPath)};`, resolveDir: root },
    bundle: true, write: false, platform: 'node', format: 'esm', target: 'node20',
    nodePaths: [resolve(coreTools, 'node_modules')], external: ['ci-info'],
    plugins: [
      { name: 'actual-authoring-guard-test', setup(builder) {
        builder.onLoad({ filter: /\/authoring\.ts$/ }, args => {
          if (args.path !== authoringPath) return;
          return { contents: readFileSync(args.path, 'utf8') + '\nexport { parts as partsForGuardTest };\n', loader: 'ts' };
        });
      } },
      coreSourcePlugin(prepareCoreSource()),
      zodJSONSchemaCompatibilityPlugin(),
    ],
    logLevel: 'silent',
  });
  const { partsForGuardTest } = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
  const cases = [
    {
      name: 'plain record values',
      schema: { type: 'object', additionalProperties: { type: 'boolean' } },
      accepted: [{ enabled: true, disabled: false }],
      rejected: [{ enabled: 'wrong' }, 'wrong', [true, false]],
    },
    {
      name: 'minimum and maximum own-property counts',
      schema: { type: 'object', propertyNames: { type: 'string' }, additionalProperties: { type: 'boolean' }, minProperties: 2, maxProperties: 2 },
      accepted: [{ first: true, second: false }],
      rejected: [{}, { first: true }, { first: true, second: false, third: true }],
    },
    {
      name: 'property-name constraint without an explicit type',
      schema: { type: 'object', propertyNames: { pattern: '^[a-z]+$' }, additionalProperties: { type: 'boolean' } },
      accepted: [{ enabled: true }],
      rejected: [{ 'bad-key': true }, { UPPER: true }],
    },
    {
      name: 'fixed fields and additional property types',
      schema: { type: 'object', properties: { fixed: { type: 'string' } }, required: ['fixed'], propertyNames: { type: 'string' }, additionalProperties: { type: 'boolean' } },
      accepted: [{ fixed: 'kept', enabled: true }],
      rejected: [{ fixed: false }, { fixed: 'kept', enabled: 'wrong' }, { enabled: true }],
    },
    {
      name: 'pattern properties and forbidden unmatched keys',
      schema: { type: 'object', patternProperties: { '^flag_': { type: 'boolean' } }, propertyNames: { type: 'string' }, additionalProperties: false },
      accepted: [{ flag_enabled: true }, {}],
      rejected: [{ flag_enabled: 'wrong' }, { unmatched: true }],
    },
  ];
  for (const entry of cases) {
    const linked = partsForGuardTest({
      components: [{ name: 'GuardProbe', description: '', params: [{ name: 'value', required: true, isBindable: true, schema: entry.schema }] }],
      functions: [], actions: [], root: 'GuardProbe',
    }).components[0].props;
    for (const value of entry.accepted) assert.equal(linked.safeParse({ value }).success, true, `${entry.name}: accepted ${JSON.stringify(value)}`);
    for (const value of entry.rejected) assert.equal(linked.safeParse({ value }).success, false, `${entry.name}: rejected ${JSON.stringify(value)}`);
  }
});

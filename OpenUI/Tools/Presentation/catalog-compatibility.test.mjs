// The expectations below were verified against the shipped pre-upgrade core.
// Exercise native authoring itself so catalog-only formatting cannot conceal
// drift in the runtime used by Library.toSchema() and Library.toSpec().
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import vm from 'node:vm';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const script = readFileSync(resolve(root, 'Sources/OpenUILang/Resources/lang-core.js'), 'utf8');
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

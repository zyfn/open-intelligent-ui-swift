import test from 'node:test';
import assert from 'node:assert/strict';
import {preserveSchemaEmission} from './schema-emission.mjs';

test('type-array unions retain legacy wire spelling and branch order', () => {
  assert.deepEqual(preserveSchemaEmission({type:['number','string'],description:'value'}),
    {anyOf:[{type:'number'},{type:'string'}],description:'value'});
});
test('nested parameters and return schemas are converted without changing field order', () => {
  const source={functions:{f:{params:{type:'object',properties:{second:{type:['string','null']},first:{type:'number'}},required:['second','first']},returns:{type:['number','null']}}}};
  const result=preserveSchemaEmission(source);
  assert.deepEqual(Object.keys(result.functions.f.params.properties),['second','first']);
  assert.deepEqual(result.functions.f.params.required,['second','first']);
  assert.deepEqual(result.functions.f.returns,{anyOf:[{type:'number'},{type:'null'}]});
});
test('business defaults, enum values, const and extension metadata remain source data', () => {
  const data={type:['actual','business'],anyOf:[1,2]};
  const schema={type:'object',default:data,const:data,enum:[data],examples:[data],'x-host':data};
  assert.deepEqual(preserveSchemaEmission(schema),schema);
});
test('existing anyOf constraints cannot be overwritten by an additional type constraint', () => {
  const schema={type:['number','string'],anyOf:[{minimum:2},{maxLength:3}]};
  assert.deepEqual(preserveSchemaEmission(schema),schema);
});
test('exclusive unions and their overlapping integer/number semantics are preserved', () => {
  const schema={oneOf:[{type:'integer'},{type:'number'}]};
  assert.deepEqual(preserveSchemaEmission(schema),schema);
});
test('a business property named type is a schema value, not a type-array instruction', () => {
  const schema={type:'object',properties:{type:{type:'array',items:{type:'string'}}}};
  assert.deepEqual(preserveSchemaEmission(schema),schema);
});

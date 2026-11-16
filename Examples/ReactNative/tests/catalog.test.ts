import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { URL } from 'node:url';
import { createParser, createStreamingParser } from '@openuidev/lang-core';
import { catalog } from '../src/library/schema';
import { createContract } from '../src/library/contract';
import { fixture } from '../src/fixture';
import { samples } from '../src/demo/samples';
import { contentSamples, cardSamples } from '../src/demo/contentSamples';
import { formSamples } from '../src/demo/formSamples';
import { dataSamples } from '../src/demo/dataSamples';
import { componentSamples } from '../src/demo/componentSamples';

const library = createContract();

// Zod 4.6 emits { type: ['string', 'number'] } for the exact union that the
// exported catalog represents as anyOf. Normalize that standard encoding only;
// required/default, bounds, enums, references and every other constraint remain.
function schemaEncoding(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(schemaEncoding);
  if (!value || typeof value !== 'object') return value;
  const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, schemaEncoding(item)]));
  if (Array.isArray(result.type)) {
    result.anyOf = result.type.map(type => ({ type }));
    delete result.type;
  }
  return result;
}

test('RN transport preserves each canonical component signature and complete JSON schema', () => {
  const upstream = JSON.parse(readFileSync(new URL('../../../Tests/SwiftOpenUITests/Fixtures/AgentCasesContract/test-library-spec.json', import.meta.url), 'utf8'));
  const actual = library.toSpec();
  const schema = library.toJSONSchema();
  assert.deepEqual(Object.keys(actual.components), Object.keys(upstream.components));
  assert.ok(schema.$defs, 'The registered library must expose its component definitions');
  for (const definition of catalog.components) {
    assert.deepEqual(actual.components[definition.name], upstream.components[definition.name], definition.name);
    assert.deepEqual(schemaEncoding(schema.$defs[definition.name]),
      schemaEncoding(upstream.schema.$defs[definition.name]), definition.name);
  }
});

for (const sample of [...samples, ...contentSamples, ...cardSamples, ...formSamples, ...dataSamples]) test(`Gallery ${sample.id} preserves its program across irregular stream boundaries`, () => {
  const expected = createParser(library.toJSONSchema()).parse(sample.source);
  assert.deepEqual(expected.meta.errors, []);
  assert.deepEqual(expected.meta.unresolved, []);
  assert.equal(expected.root?.typeName, 'Stack');
  const parser = createStreamingParser(library.toJSONSchema(), library.root);
  for (let offset = 0, step = 1; offset < sample.source.length; step = step % 47 + 1) {
    parser.push(sample.source.slice(offset, offset + step));
    offset += step;
  }
  // Finalize only what push() received. Resubmitting the full source here
  // would silently repair dropped or corrupted chunks and mask a regression.
  const completed = parser.getResult(true);
  assert.deepEqual(completed.root, expected.root);
  assert.deepEqual(completed.stateDeclarations, expected.stateDeclarations);
  assert.deepEqual(completed.meta.errors, []);
  assert.deepEqual(completed.meta.unresolved, []);
});

test('all unchanged OpenUI Gallery component programs accept exactly their received chunks', () => {
  for (const sample of componentSamples) {
    const expected = createParser(library.toJSONSchema()).parse(sample.source);
    assert.deepEqual(expected.meta.errors, [], sample.label);
    assert.deepEqual(expected.meta.unresolved, [], sample.label);
    const parser = createStreamingParser(library.toJSONSchema(), library.root);
    for (let offset = 0; offset < sample.source.length; offset += 17) parser.push(sample.source.slice(offset, offset + 17));
    const actual = parser.getResult(true);
    assert.deepEqual(actual.root, expected.root, sample.label);
    assert.deepEqual(actual.stateDeclarations, expected.stateDeclarations, sample.label);
    assert.deepEqual(actual.meta.errors, [], sample.label);
    assert.deepEqual(actual.meta.unresolved, [], sample.label);
  }
});

test('the same fixture finishes identically with single-unit and irregular transport chunks', () => {
  const expected = createParser(library.toJSONSchema()).parse(fixture);
  assert.deepEqual(expected.meta.errors, []);
  assert.deepEqual(expected.meta.unresolved, []);
  assert.equal(expected.root?.typeName, 'Stack');
  for (const size of [1, 7, 31]) {
    const parser = createStreamingParser(library.toJSONSchema(), library.root);
    for (let offset = 0; offset < fixture.length; offset += size) parser.push(fixture.slice(offset, offset + size));
    const completed = parser.getResult(true);
    assert.deepEqual(completed.root, expected.root);
    assert.deepEqual(completed.stateDeclarations, expected.stateDeclarations);
    assert.deepEqual(completed.meta.errors, []);
    assert.deepEqual(completed.meta.unresolved, []);
  }
});

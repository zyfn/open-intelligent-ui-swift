import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { URL } from 'node:url';
import { createParser, createStreamingParser } from '@openuidev/lang-core';
import { catalog } from '../src/library/schema';
import { createContract } from '../src/library/contract';
import { fixture } from '../src/fixture';
import { samples } from '../src/demo/samples';

const library = createContract();

test('RN transport preserves each canonical component signature and complete JSON schema', () => {
  const upstream = JSON.parse(readFileSync(new URL('../../../Sources/SwiftOpenUI/Resources/upstream-catalog.json', import.meta.url), 'utf8'));
  const actual = library.toSpec();
  const schema = library.toJSONSchema();
  assert.ok(schema.$defs, 'The registered library must expose its component definitions');
  for (const definition of catalog.components) {
    assert.deepEqual(actual.components[definition.name], upstream.spec.components[definition.name]);
    assert.deepEqual(schema.$defs[definition.name], upstream.spec.schema.$defs[definition.name]);
  }
});

for (const sample of samples) test(`Gallery ${sample.id} preserves its program across irregular stream boundaries`, () => {
  const expected = createParser(library.toJSONSchema()).parse(sample.source);
  assert.deepEqual(expected.meta.errors, []);
  assert.deepEqual(expected.meta.unresolved, []);
  assert.equal(expected.root?.typeName, 'Stack');
  const parser = createStreamingParser(library.toJSONSchema(), library.root);
  for (let offset = 0, step = 1; offset < sample.source.length; step = step % 47 + 1) {
    parser.push(sample.source.slice(offset, offset + step));
    offset += step;
  }
  const completed = parser.set(sample.source, true);
  assert.deepEqual(completed.root, expected.root);
  assert.deepEqual(completed.stateDeclarations, expected.stateDeclarations);
  assert.deepEqual(completed.meta.errors, []);
});

test('the same fixture finishes identically with single-unit and irregular transport chunks', () => {
  const expected = createParser(library.toJSONSchema()).parse(fixture);
  assert.deepEqual(expected.meta.errors, []);
  assert.deepEqual(expected.meta.unresolved, []);
  assert.equal(expected.root?.typeName, 'Stack');
  for (const size of [1, 7, 31]) {
    const parser = createStreamingParser(library.toJSONSchema(), library.root);
    for (let offset = 0; offset < fixture.length; offset += size) parser.push(fixture.slice(offset, offset + size));
    const completed = parser.set(fixture, true);
    assert.deepEqual(completed.root, expected.root);
    assert.deepEqual(completed.stateDeclarations, expected.stateDeclarations);
    assert.deepEqual(completed.meta.errors, []);
  }
});

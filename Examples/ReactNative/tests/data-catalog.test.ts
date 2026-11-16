import assert from 'node:assert/strict';
import test from 'node:test';
import { createParser, createStreamingParser } from '@openuidev/lang-core';
import { createContract } from '../src/library/contract';
import { dataSamples } from '../src/demo/dataSamples';

const library = createContract();

for (const sample of dataSamples) test(`data Gallery ${sample.id} preserves every streamed statement`, () => {
  const expected = createParser(library.toJSONSchema()).parse(sample.source);
  assert.deepEqual(expected.meta.errors, []);
  assert.deepEqual(expected.meta.unresolved, []);
  const parser = createStreamingParser(library.toJSONSchema(), library.root);
  for (let offset = 0, size = 1; offset < sample.source.length; size = size % 29 + 1) {
    parser.push(sample.source.slice(offset, offset + size));
    offset += size;
  }
  const actual = parser.getResult(true);
  assert.deepEqual(actual.meta.errors, []);
  assert.deepEqual(actual.meta.unresolved, []);
  assert.deepEqual(actual.root, expected.root);
  assert.deepEqual(actual.stateDeclarations, expected.stateDeclarations);
});

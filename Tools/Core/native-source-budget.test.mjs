// Source limits run on the shared parser's existing statement tokens. These
// cases check accumulated occurrences and resets, not a replacement lexer.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: { Box: { type: 'object', properties: { value: {} }, required: ['value'] } },
  properties: { Box: { $ref: '#/$defs/Box' } },
};
function runtime() {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
  });
  vm.runInContext(script, realm, { timeout: 5000 });
  return realm.SwiftCore;
}
const prefix = 'root=Box("ready")\nunused=';
function accepted(bridge, result) {
  assert.equal(bridge.nativeBudgetExceeded(result), false);
  assert.equal(result.root?.props.value, 'ready');
}
function rejected(bridge, result) {
  assert.equal(bridge.nativeBudgetExceeded(result), true);
  assert.equal(result.meta.incomplete, true);
  assert(result.meta.errors.some(error => error.code === 'parse-exception'));
  assert.equal(bridge.sourceComplete(result), false);
}

test('batch and streaming enforce the same 128 nesting and 256 operator boundaries before recursion', () => {
  const bridge = runtime();
  for (const [allowed, denied] of [
    [Array(257).fill('1').join('+'), Array(258).fill('1').join('+')],
    ['['.repeat(128) + '1' + ']'.repeat(128), '['.repeat(129) + '1'],
  ]) {
    const batch = bridge.api.createParser(schema);
    accepted(bridge, batch.parse(prefix + allowed));
    rejected(bridge, batch.parse(prefix + denied));
    const stream = bridge.api.createStreamingParser(schema);
    accepted(bridge, stream.set(prefix + allowed, true));
    rejected(bridge, stream.set(prefix + denied, false));
    accepted(bridge, stream.set('root=Box("ready")', true));
  }
});

test('4096 declaration occurrences include duplicate IDs and repeated getResult does not recount them', () => {
  const bridge = runtime();
  const source = 'root=Box("ready")\n' + 'same=0\n'.repeat(4095);
  accepted(bridge, bridge.api.createParser(schema).parse(source));
  rejected(bridge, bridge.api.createParser(schema).parse(source + 'same=1\n'));
  const parser = bridge.api.createStreamingParser(schema);
  accepted(bridge, parser.set(source, true));
  for (let i = 0; i < 8; i++) accepted(bridge, parser.getResult(i % 2 === 0));
  rejected(bridge, parser.push('same=1\n'));
  accepted(bridge, parser.set('root=Box("ready")\n', true));
  accepted(bridge, parser.push('same=1', true));
});

test('100000 expression tokens include overwritten declarations and the pending tail exactly once', () => {
  const bridge = runtime();
  const list = size => '[' + Array(size).fill('0').join(',') + ']';
  // Box("ready") has 4 tokens, each 200-value array has 401; the last
  // 73-value array adds 147. All values are unreferenced, so this isolates
  // source work from the distinct materialization/output-size limits.
  const source = 'root=Box("ready")\n' + ('same=' + list(200) + '\n').repeat(249) + 'same=' + list(73);
  accepted(bridge, bridge.api.createParser(schema).parse(source));
  rejected(bridge, bridge.api.createParser(schema).parse(source + '\nextra=0'));
  const parser = bridge.api.createStreamingParser(schema);
  accepted(bridge, parser.set(source.slice(0, -1)));
  for (let i = 0; i < 4; i++) accepted(bridge, parser.getResult());
  accepted(bridge, parser.push(']', true));
  rejected(bridge, parser.push('\nextra=0', true));
});

test('a fence changing the selected prefix resets completed token and declaration counts', () => {
  const bridge = runtime(), parser = bridge.api.createStreamingParser(schema);
  accepted(bridge, parser.push('root=Box("ready")\n' + 'old=0\n'.repeat(4094)));
  accepted(bridge, parser.push('```openui\nroot=Box("ready")\n'));
  accepted(bridge, parser.push('new=0\n'.repeat(4095)));
  rejected(bridge, parser.push('new=1\n'));
  accepted(bridge, parser.set('```openui\nroot=Box("ready")\n```', true));
});

test('chunked comments, quoted punctuation and Unicode keep the same final program', () => {
  const bridge = runtime();
  const text = '上海 😀 ' + '([+'.repeat(300) + '\nquoted # // marker';
  const source = '// ' + '[+'.repeat(300) + '\nroot=Box(' + JSON.stringify(text) + ') # ' + '+'.repeat(300);
  const batch = bridge.api.createParser(schema).parse(source);
  assert.equal(bridge.nativeBudgetExceeded(batch), false);
  assert.equal(batch.root.props.value, text);
  for (const width of [1, 7, 24, 128]) {
    const parser = bridge.api.createStreamingParser(schema);
    for (let offset = 0; offset < source.length; offset += width) {
      assert.equal(bridge.nativeBudgetExceeded(parser.push(source.slice(offset, offset + width))), false);
    }
    const result = parser.getResult(true);
    assert.equal(bridge.nativeBudgetExceeded(result), false);
    assert.equal(result.root.props.value, text);
  }
});

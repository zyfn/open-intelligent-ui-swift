import assert from 'node:assert/strict';
import test from 'node:test';
import { createNativeRuntime } from './native-test-runtime.mjs';

const realm = createNativeRuntime({ setInterval, clearInterval });
const bridge = realm.SwiftCore;

// These exercise the shipped message algorithm with the UTF-16 boundary from
// the native transport probe. Swift tests separately exercise boundary detection
// and the batch/stream/State entry points; this is not a native XCTest substitute.
const prefixes = [
  'root=Box("😀 上海\n]]>openui:content\nkept")\n',
  'root=Box("kept")\r\n// ]]>openui:content\r\n',
  'root=Box("first\n]]>openui:context\n{not context}\n]]>openui:end\nlast")\n',
];

for (const [index, prefix] of prefixes.entries()) {
  test(`real context/end preserves raw marker text ${index + 1}`, () => {
    const expected = prefix.replace(/\r?\n$/, '');
    for (const suffix of [']]>openui:context\r\n{"attempt":1}\r\n]]>openui:end', ']]>openui:end\r\n']) {
      assert.equal(bridge.messageContent(prefix + suffix, false, prefix.length), expected);
      for (let length = 1; length <= suffix.length; length++) {
        assert.equal(bridge.messageContent(prefix + suffix.slice(0, length), true, prefix.length),
          expected, JSON.stringify(suffix.slice(0, length)));
      }
      assert.equal(bridge.messageContent(prefix + suffix + '\n]]>openui:content\nroot=Box("new")',
        false, prefix.length), 'root=Box("new")');
    }
  });
}

test('first mid-line content retry keeps the protected prefix out of protocol selection', () => {
  const prefix = prefixes[0].replace(/\n$/, '');
  const suffix = ']]>openui:content?attempt=2\r\nroot=Box("new")';
  assert.equal(bridge.messageContent(prefix + suffix, false, prefix.length), 'root=Box("new")');
  for (const partial of [']]>open', ']]>openui:', ']]>openui:con']) {
    assert.equal(bridge.messageContent(prefix + partial, true, prefix.length), prefix);
  }
});

test('public message extraction remains unrestricted and uses the same algorithm', () => {
  const inputs = [
    'root=Box("kept")\n// ]]>openui:content',
    ...prefixes,
    ']]>openui:content?v=1\r\nroot=Box("old]]>openui:content?v=2\r\nroot=Box("new")\r\n]]>openui:context\r\n{"attempt":2}\r\n]]>openui:end',
    ']]>openui:context\n{"old":true}\n]]>openui:content\nroot=Box("new")\n]]>openui:end',
  ];
  for (const input of inputs) {
    for (const streaming of [false, true]) {
      for (let length = 0; length <= input.length; length++) {
        const prefix = input.slice(0, length);
        assert.equal(bridge.messageContent(prefix, streaming, 0),
          bridge.api.parseMessage(prefix, { streaming }).content);
      }
    }
  }
});

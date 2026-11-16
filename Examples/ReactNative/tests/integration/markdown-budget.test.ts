import { parseNativeMarkdown } from '../../src/library/components/markdown';

function expectCompletePlainText(source: string) {
  expect(parseNativeMarkdown(source)).toEqual({ kind: 'plain', text: source });
}

test('a compact table with thousands of empty cells falls back before native presentation', () => {
  const row = (cell: string) => `|${Array.from({ length: 100 }, () => cell).join('|')}|\n`;
  const source = row('column') + row('---') + row(' ').repeat(50);
  expect(source.length).toBeLessThan(65_536);
  expectCompletePlainText(source);
});

test('many inline nodes are bounded even when the Markdown source is small', () => {
  const source = '**b** '.repeat(1_600);
  expect(source.length).toBeLessThan(65_536);
  expectCompletePlainText(source);
});

test('deep block quotes fall back without dropping their original markers', () => {
  expectCompletePlainText('> '.repeat(30) + 'leaf');
});

test('source beyond the character budget remains complete, including its Unicode tail', () => {
  const source = 'a'.repeat(65_536) + '🙂 未截断';
  expectCompletePlainText(source);
});

test.each(['**还未闭合', '```ts\nconst value = '])(
  'an ordinary unfinished stream stays on the Markdown path: %s', source => {
    expect(parseNativeMarkdown(source).kind).toBe('markdown');
  },
);

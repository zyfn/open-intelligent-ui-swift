import { StyleSheet } from 'react-native';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { library, NativeThemeProvider } from '../../src/library';
import * as markdown from '../../src/library/components/markdown';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from '../../src/runtime/message';

const controllers = new Set<MessageController>();
afterEach(() => {
  for (const controller of controllers) controller.dispose();
  controllers.clear();
});
function document(source: string, completed = true) {
  const message = createMessageController('markdown-rendering');
  controllers.add(message);
  const handle = message.begin(source);
  if (completed) message.complete(handle);
  return { message, handle };
}

test('unrelated field edits preserve the native Markdown tree, while theme changes rebuild its presentation', () => {
  const parse = jest.spyOn(markdown, 'parseNativeMarkdown');
  const split = jest.spyOn(markdown, 'splitInlineImages');
  const source = `root = Stack([field, reading])
$name = ""
field = Input("name", "Name", "text", null, $name)
reading = TextContent("# Stable heading\\n\\nUnchanged **reading** content.")`;
  const { message } = document(source);
  const result = render(<NativeThemeProvider colorScheme="light">
    <OpenUIDocument message={message} library={library} />
  </NativeThemeProvider>);
  const originalColor = StyleSheet.flatten(screen.getByRole('header', { name: 'Stable heading' }).props.style).color;
  const parseCount = parse.mock.calls.length;
  const splitCount = split.mock.calls.length;
  for (let i = 0; i < 10; i++) fireEvent.changeText(screen.getByLabelText('Name'), `Edit ${i}`);
  expect(screen.getByLabelText('Name')).toHaveDisplayValue('Edit 9');
  expect(parse).toHaveBeenCalledTimes(parseCount);
  expect(split).toHaveBeenCalledTimes(splitCount);

  result.rerender(<NativeThemeProvider colorScheme="dark">
    <OpenUIDocument message={message} library={library} />
  </NativeThemeProvider>);
  expect(split.mock.calls.length).toBeGreaterThan(splitCount);
  expect(StyleSheet.flatten(screen.getByRole('header', { name: 'Stable heading' }).props.style).color).not.toBe(originalColor);
  expect(screen.getByLabelText('Name')).toHaveDisplayValue('Edit 9');
});

test('memoized Markdown links still react to streaming completion and reject a retired epoch', async () => {
  const source = 'root = Stack([TextContent("[Docs](https://example.com/docs)")])';
  const { message, handle } = document(source, false);
  const onAction = jest.fn();
  render(<OpenUIDocument message={message} library={library} onAction={onAction} />);
  expect(screen.getByRole('link', { name: 'Docs' })).toBeDisabled();
  act(() => { message.complete(handle); });
  const link = screen.getByRole('link', { name: 'Docs' });
  expect(link).toBeEnabled();
  await act(async () => { fireEvent.press(link); });
  expect(onAction).toHaveBeenCalledTimes(1);
  const retiredPress = screen.getByRole('link', { name: 'Docs' }).props.onPress;
  await act(async () => {
    const next = message.begin(source);
    retiredPress();
    message.complete(next);
  });
  expect(onAction).toHaveBeenCalledTimes(1);
  await act(async () => { fireEvent.press(screen.getByRole('link', { name: 'Docs' })); });
  expect(onAction).toHaveBeenCalledTimes(2);
});

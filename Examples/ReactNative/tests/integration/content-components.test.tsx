import { StyleSheet } from 'react-native';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { Renderer } from '@openuidev/react-lang';
import { contentSamples, cardSamples } from '../../src/demo/contentSamples';
import { NativeContentProvider } from '../../src/library/components/contentPolicy';
import { NativeThemeProvider, theme } from '../../src/library/theme';
import { NativeIcon } from '../../src/library/components/NativeIcon';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from '../../src/runtime/message';
import { library as contentTestLibrary } from '../../src/library';

const controllers = new Set<MessageController>();
afterEach(() => { controllers.forEach(controller => controller.dispose()); controllers.clear(); jest.useRealTimers(); });

function show(source: string, complete = true, onAction = jest.fn()) {
  const message = createMessageController('content-components');
  controllers.add(message);
  const handle = message.begin(source);
  if (complete) message.complete(handle);
  const onError = jest.fn();
  const result = render(<NativeThemeProvider colorScheme="light"><NativeContentProvider resolveImage={() => 1}>
    <OpenUIDocument message={message} library={contentTestLibrary} onAction={onAction} onError={onError} />
  </NativeContentProvider></NativeThemeProvider>);
  return { message, handle, result, onError, onAction };
}

test.each([...contentSamples, ...cardSamples])('the $id sample uses the real catalog without parse or renderer errors', sample => {
  const { message, onError } = show(sample.source);
  expect(onError.mock.calls.flatMap(call => call[0])).toEqual([]);
  expect(message.getSnapshot().phase).toBe('complete');
  expect(screen.toJSON()).not.toBeNull();
});

test('Callout starts its three-second binding timer after completion, independent of unrelated field changes', async () => {
  jest.useFakeTimers();
  const { message, handle } = show(`root = Stack([notice, field, state])
$visible = true
$name = ""
notice = Callout("success", "Saved", "Ready", $visible)
field = Input("name", "Name", "text", null, $name)
state = TextContent($visible ? "shown" : "hidden")`, false);
  act(() => { jest.advanceTimersByTime(4000); });
  expect(screen.getByText('Saved')).toBeOnTheScreen();
  act(() => { message.complete(handle); });
  act(() => { jest.advanceTimersByTime(1000); });
  fireEvent.changeText(screen.getByLabelText('Name'), 'Edited');
  act(() => { jest.advanceTimersByTime(1999); });
  expect(screen.getByText('Saved')).toBeOnTheScreen();
  act(() => { jest.advanceTimersByTime(1); });
  expect(screen.queryByText('Saved')).not.toBeOnTheScreen();
  expect(screen.getByText('hidden')).toBeOnTheScreen();
  expect(message.getSavedFields(handle)).toEqual(expect.objectContaining({ $visible: false, $name: 'Edited' }));
});

test('retiring a Callout document before its timer runs prevents stale state writes', () => {
  jest.useFakeTimers();
  const { message } = show('root = Stack([Callout("info", "Old", "Notice", $visible)])\n$visible = true');
  const save = jest.spyOn(message, 'saveFields');
  act(() => { message.begin('root = Stack([TextContent("Replacement")])'); jest.advanceTimersByTime(3001); });
  expect(save).not.toHaveBeenCalled();
});

test('list actions and followups use official action events and disable during streaming', async () => {
  const { message, handle, onAction } = show(`root = Stack([list, followups])
list = ListBlock([ListItem("Read", "Details", null, "Open", @ToAssistant("list message"))])
followups = FollowUpBlock([FollowUpItem("Tell me more")])`, false);
  expect(screen.getByRole('button', { name: 'Read' })).toBeDisabled();
  expect(screen.getByRole('button', { name: 'Tell me more' })).toBeDisabled();
  act(() => { message.complete(handle); });
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Read' })); });
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Tell me more' })); });
  expect(onAction.mock.calls.map(call => call[0].humanFriendlyMessage)).toEqual(['list message', 'Tell me more']);
});

test('card actions preserve upstream item context and a composite footer fires only its own action', async () => {
  const sample = cardSamples.find(item => item.id === 'cards-composite')!;
  const { onAction } = show(sample.source);
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: '湖边一日' })); });
  expect(onAction).toHaveBeenCalledTimes(1);
  const event = onAction.mock.calls[0][0];
  expect(event.humanFriendlyMessage).toBe('查看详情');
  expect(event.params.context).toBe('Selected item: {"itemIndex":0,"itemId":"lake","itemHeaderTitle":"湖边一日","itemHeaderSubtitle":"给周末留一点空闲","itemHeaderAlt":"西湖","itemBodyCount":2,"itemFooterPrice":"¥128","itemFooterButtonLabel":"选择湖边"}');
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: '选择湖边' })); });
  expect(onAction).toHaveBeenCalledTimes(2);
  expect(onAction.mock.calls[1][0].humanFriendlyMessage).toBe('选择湖边一日');
  expect(onAction.mock.calls[1][0].params.context).toBeUndefined();
});

test('gallery previews duplicate sources independently and navigation/close remain native controls', () => {
  show('root = Stack([ImageGallery([{src:"asset://same",alt:"First",details:"first details"},{src:"asset://same",alt:"Second",details:"second details"}])])');
  fireEvent(screen.getByLabelText('Second'), 'load', { nativeEvent: { source: { width: 100, height: 100 } } });
  fireEvent.press(screen.getByRole('button', { name: '查看Second' }));
  expect(screen.getByText('second details')).toBeOnTheScreen();
  expect(screen.getByRole('button', { name: '下一张' })).toBeDisabled();
  fireEvent.press(screen.getByRole('button', { name: '上一张' }));
  expect(screen.getByText('first details')).toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '关闭图片预览' }));
  expect(screen.queryByText('first details')).not.toBeOnTheScreen();
});

test('native code highlights tokens and retains literal markup and unknown languages as text', () => {
  show('root = Stack([CodeBlock("typescript", "const value = 42;"), CodeBlock("unknown", "<script>alert(1)</script>")])');
  expect(StyleSheet.flatten(screen.getByText('const').props.style).color).toBe(theme.accent);
  expect(screen.getByText('<script>alert(1)</script>')).toBeOnTheScreen();
});

test('unknown icon names use the pinned topical fallback', () => {
  const known = render(<NativeIcon name="map-pin" />).toJSON();
  const fallback = render(<NativeIcon name="not-a-real-icon" category="navigation" />).toJSON();
  expect(fallback).toEqual(known);
  const generic = render(<NativeIcon name="circle-help" />).toJSON();
  const inheritedName = render(<NativeIcon name="constructor" category="__proto__" />).toJSON();
  expect(inheritedName).toEqual(generic);
});

test.each([
  { name: 'FollowUp', role: 'button' as const,
    content: 'content = FollowUpBlock([FollowUpItem($mode ? "Second" : "First")])' },
  { name: 'ListItem', role: 'button' as const,
    content: 'content = ListBlock([ListItem($mode ? "Second" : "First", null, null, "Open", @ToAssistant($mode ? "second" : "first"))])' },
  { name: 'CardItem', role: 'button' as const,
    content: 'content = SnippetCardBlock([SnippetCardItem("stable", IconText(Icon("info"), "neutral", "m", $mode ? "Second" : "First")), SnippetCardItem("spare", IconText(Icon("info"), "neutral", "m", "Spare"))], "grid", true, @ToAssistant("card choice"))' },
  { name: 'MarkdownLink', role: 'link' as const,
    content: 'content = TextContent($mode ? "[Second](https://example.com/same)" : "[First](https://example.com/same)")' },
])('$name retires an old native callback when its semantic target changes in the same document', async ({ name, role, content }) => {
  const { message, handle, onAction } = show(`root = Stack([content, swap])
$mode = false
${content}
swap = Button("Swap", @Set($mode, true))`);
  let instance = screen.getByRole(role, { name: 'First' });
  while (instance && typeof instance.props.onPress !== 'function') instance = instance.parent!;
  const oldPress = instance.props.onPress as () => void;
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Swap' })); });
  expect(message.getHandle()).toBe(handle);
  expect(screen.getByRole(role, { name: 'Second' })).toBeOnTheScreen();
  await act(async () => { oldPress(); });
  expect(onAction).not.toHaveBeenCalled();
  await act(async () => { fireEvent.press(screen.getByRole(role, { name: 'Second' })); });
  expect(onAction).toHaveBeenCalledTimes(1);
  if (name === 'CardItem') expect(onAction.mock.calls[0][0].params.context).toContain('"itemTitle":"Second"');
});

test('an unchanged card action remains current across unrelated field edits and uses the latest form payload', async () => {
  const { onAction } = show(`root = Stack([field, cards])
$name = ""
field = Input("name", "Name", "text", null, $name)
cards = SnippetCardBlock([SnippetCardItem("first", IconText(Icon("info"), "neutral", "m", "Stable")), SnippetCardItem("second", IconText(Icon("info"), "neutral", "m", "Other"))], "grid", true, @ToAssistant("choose"))`);
  let instance = screen.getByRole('button', { name: 'Stable' });
  while (instance && typeof instance.props.onPress !== 'function') instance = instance.parent!;
  const stablePress = instance.props.onPress as () => void;
  for (let index = 0; index < 5; index++) fireEvent.changeText(screen.getByLabelText('Name'), `Edit ${index}`);
  await act(async () => { stablePress(); });
  expect(onAction).toHaveBeenCalledTimes(1);
  expect(onAction.mock.calls[0][0].formState).toEqual(expect.objectContaining({ $name: 'Edit 4' }));
});

test.each([false, true])('a real Mutation keeps pending across edits and an old completion cannot change its replacement (old host throws: %s)', async oldHostThrows => {
  const completions = new Map<string, (value: unknown) => void>();
  const save = jest.fn((args: Record<string, unknown>) => new Promise(resolve => {
    completions.set(String(args.target), resolve);
  }));
  const onContentError = jest.fn();
  const onRendererError = jest.fn();
  const onAction = jest.fn(event => {
    if (oldHostThrows && event.humanFriendlyMessage === 'done A') throw new Error('old host failure');
  });
  const source = `root = Stack([field, list, swap])
$mode = false
$name = ""
saveA = Mutation("save", {target: "A"})
saveB = Mutation("save", {target: "B"})
field = Input("name", "Name", "text", null, $name)
list = ListBlock([ListItem($mode ? "Save B" : "Save A", null, null, "Save", $mode ? Action([@Run(saveB), @ToAssistant("done B")]) : Action([@Run(saveA), @ToAssistant("done A")]))])
swap = Button("Switch target", @Set($mode, true))`;
  // Direct Renderer exercises its public asynchronous tool boundary. The
  // OpenUIDocument host adapter intentionally does not expose toolProvider.
  render(<NativeContentProvider onError={onContentError}>
    <Renderer response={source} library={contentTestLibrary} isStreaming={false}
      toolProvider={{ save }} onAction={onAction} onError={onRendererError} publishObservability={false} />
  </NativeContentProvider>);
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Save A' })); });
  expect(save).toHaveBeenCalledTimes(1);
  expect(screen.getByRole('button', { name: 'Save A' })).toBeDisabled();
  expect(screen.getByRole('button', { name: 'Save A' }).props.accessibilityState.busy).toBe(true);
  fireEvent.changeText(screen.getByLabelText('Name'), 'unrelated edit');
  expect(screen.getByRole('button', { name: 'Save A' }).props.accessibilityState.busy).toBe(true);
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Switch target' })); });
  expect(screen.getByRole('button', { name: 'Save B' })).toBeEnabled();
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Save B' })); });
  expect(save).toHaveBeenCalledTimes(2);
  await act(async () => { completions.get('A')!({ saved: 'A' }); });
  expect(screen.getByRole('button', { name: 'Save B' })).toBeDisabled();
  expect(screen.getByRole('button', { name: 'Save B' }).props.accessibilityState.busy).toBe(true);
  expect(onContentError).not.toHaveBeenCalled();
  expect(screen.queryByText('操作暂时未完成，请重试。')).not.toBeOnTheScreen();
  await act(async () => { completions.get('B')!({ saved: 'B' }); });
  expect(screen.getByRole('button', { name: 'Save B' })).toBeEnabled();
  expect(screen.getByRole('button', { name: 'Save B' }).props.accessibilityState.busy).toBe(false);
  expect(onRendererError.mock.calls.flatMap(call => call[0])).toEqual([]);
});

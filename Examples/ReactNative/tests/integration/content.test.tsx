import { Linking } from 'react-native';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { BuiltinActionType } from '@openuidev/react-lang';
import { library } from '../../src/library';
import { NativeContentProvider } from '../../src/library/components/contentPolicy';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from '../../src/runtime/message';

const controllers = new Set<MessageController>();

afterEach(() => {
  for (const controller of controllers) controller.dispose();
  controllers.clear();
});

function document(source: string, completed = true) {
  const controller = createMessageController('content');
  controllers.add(controller);
  const handle = controller.begin(source);
  if (completed) controller.complete(handle);
  return { controller, handle };
}

test('Markdown renders native reading content and routes an allowed link through the host exactly once', async () => {
  const markdown = '# 阅读标题\n\n**重点** 与 *强调*，访问 [文档](https://example.com/guide?a=1&amp;b=2)。\n\n'
    + '- [x] 已完成任务\n\n> 引用说明\n\n'
    + '```ts\nconst answer = 42;\n```\n\n'
    + '| 字段 | 内容 |\n| --- | --- |\n| 名称 | 示例 |\n\n'
    + '![案例图片](https://example.com/image.png)\n\n'
    + '[不可执行链接](javascript:alert(1))';
  const { controller } = document(`root = Stack([TextContent(${JSON.stringify(markdown)})])`);
  const onAction = jest.fn();
  const openURL = jest.spyOn(Linking, 'openURL');
  render(<OpenUIDocument message={controller} library={library} onAction={onAction} />);

  expect(screen.getByRole('header', { name: '阅读标题' })).toBeOnTheScreen();
  expect(screen.getByText('重点')).toBeOnTheScreen();
  expect(screen.getByText('强调')).toBeOnTheScreen();
  expect(screen.getByText('引用说明')).toBeOnTheScreen();
  expect(screen.getByText('const answer = 42;')).toBeOnTheScreen();
  expect(screen.getByText('字段')).toBeOnTheScreen();
  expect(screen.getByText('示例')).toBeOnTheScreen();
  expect(screen.getAllByLabelText('已完成')).toHaveLength(1);
  expect(screen.getByRole('image', { name: '案例图片，正在加载' })).toBeOnTheScreen();
  expect(screen.getByText('不可执行链接')).toBeOnTheScreen();
  expect(screen.queryByRole('link', { name: '不可执行链接' })).not.toBeOnTheScreen();

  await act(async () => { fireEvent.press(screen.getByRole('link', { name: '文档' })); });
  expect(onAction).toHaveBeenCalledTimes(1);
  expect(onAction).toHaveBeenCalledWith(expect.objectContaining({
    type: BuiltinActionType.OpenUrl,
    params: { url: 'https://example.com/guide?a=1&b=2' },
  }));
  expect(openURL).not.toHaveBeenCalled();
});

test('streaming images remain placeholders until completion makes the host mapping eligible', () => {
  const { controller, handle } = document('root = Stack([Image("Preview", "asset:preview")])', false);
  const resolveImage = jest.fn(() => ({ uri: 'https://example.com/preview.png' }));
  render(<NativeContentProvider resolveImage={resolveImage}>
    <OpenUIDocument message={controller} library={library} />
  </NativeContentProvider>);

  expect(resolveImage).not.toHaveBeenCalled();
  expect(screen.getByRole('image', { name: 'Preview，内容生成完成后加载图片' })).toBeOnTheScreen();
  act(() => { controller.complete(handle); });
  expect(resolveImage).toHaveBeenCalledWith('asset:preview');
  expect(screen.getByRole('image', { name: 'Preview，正在加载' })).toBeOnTheScreen();
});

test('a native image error can retry and callbacks from the failed attempt cannot corrupt the new one', () => {
  const { controller } = document('root = Stack([Image("Preview", "https://example.com/preview.png")])');
  const onContentError = jest.fn();
  render(<NativeContentProvider onError={onContentError}>
    <OpenUIDocument message={controller} library={library} />
  </NativeContentProvider>);
  const firstImage = screen.getByLabelText('Preview');
  const oldError = firstImage.props.onError;
  const oldLoad = firstImage.props.onLoad;
  fireEvent(firstImage, 'error', { nativeEvent: { error: 'offline' } });
  expect(screen.getByRole('button', { name: '重新加载图片' })).toBeOnTheScreen();
  expect(screen.getByText('点击重试')).toBeOnTheScreen();
  expect(onContentError).toHaveBeenCalledTimes(1);

  fireEvent.press(screen.getByRole('button', { name: '重新加载图片' }));
  expect(screen.getByRole('image', { name: 'Preview，正在加载' })).toBeOnTheScreen();
  act(() => {
    oldError({ nativeEvent: { error: 'late failure from old request' } });
    oldLoad({ nativeEvent: { source: { width: 400, height: 300 } } });
  });
  expect(onContentError).toHaveBeenCalledTimes(1);
  expect(screen.queryByRole('button', { name: '重新加载图片' })).not.toBeOnTheScreen();
  expect(screen.getByRole('image', { name: 'Preview，正在加载' })).toBeOnTheScreen();

  fireEvent(screen.getByLabelText('Preview'), 'load', {
    nativeEvent: { source: { width: 800, height: 600 } },
  });
  expect(screen.getByRole('image', { name: 'Preview' })).toBeOnTheScreen();
  expect(screen.queryByRole('image', { name: 'Preview，正在加载' })).not.toBeOnTheScreen();
});

test('image retry asks the current resolver for a fresh source and headers', () => {
  const { controller } = document('root = Stack([Image("Preview", "asset://preview")])');
  let source = { uri: 'https://example.com/expired.png', headers: { Authorization: 'old-test-header' } };
  const resolveImage = jest.fn(() => source);
  render(<NativeContentProvider resolveImage={resolveImage}>
    <OpenUIDocument message={controller} library={library} />
  </NativeContentProvider>);
  expect(resolveImage).toHaveBeenCalledTimes(1);
  fireEvent(screen.getByLabelText('Preview'), 'error', { nativeEvent: { error: 'expired' } });

  source = { uri: 'https://example.com/refreshed.png', headers: { Authorization: 'new-test-header' } };
  fireEvent.press(screen.getByRole('button', { name: '重新加载图片' }));
  expect(resolveImage).toHaveBeenCalledTimes(2);
  expect(screen.getByLabelText('Preview').props.source).toEqual(source);
  fireEvent(screen.getByLabelText('Preview'), 'load', { nativeEvent: { source: { width: 400, height: 300 } } });
  expect(screen.getByRole('image', { name: 'Preview' })).toBeOnTheScreen();
});

test('a resolver exception can recover through the same compact retry placeholder', () => {
  const { controller } = document('root = Stack([Image("Preview", "asset://preview")])');
  const failure = new Error('Temporary mapping failure');
  const onError = jest.fn();
  const resolveImage = jest.fn()
    .mockImplementationOnce(() => { throw failure; })
    .mockReturnValue({ uri: 'https://example.com/recovered.png' });
  render(<NativeContentProvider resolveImage={resolveImage} onError={onError}>
    <OpenUIDocument message={controller} library={library} />
  </NativeContentProvider>);
  expect(onError).toHaveBeenCalledWith(failure);
  expect(screen.getByText('点击重试')).toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '重新加载图片' }));
  expect(resolveImage).toHaveBeenCalledTimes(2);
  expect(screen.getByLabelText('Preview').props.source.uri).toBe('https://example.com/recovered.png');
  expect(screen.queryByRole('button', { name: '重新加载图片' })).not.toBeOnTheScreen();
});

test('image callbacks captured before an epoch replacement are inert even before React commits', () => {
  const { controller } = document('root = Stack([Image("Previous", "https://example.com/previous.png")])');
  const onContentError = jest.fn();
  render(<NativeContentProvider onError={onContentError}>
    <OpenUIDocument message={controller} library={library} />
  </NativeContentProvider>);
  const previous = screen.getByLabelText('Previous');
  const oldError = previous.props.onError;
  const oldLoad = previous.props.onLoad;

  act(() => {
    const next = controller.begin('root = Stack([Image("Replacement", "https://example.com/replacement.png")])');
    oldError({ nativeEvent: { error: 'retired request failed before React commit' } });
    oldLoad({ nativeEvent: { source: { width: 1, height: 20 } } });
    controller.complete(next);
  });
  expect(onContentError).not.toHaveBeenCalled();
  expect(screen.queryByLabelText('Previous')).not.toBeOnTheScreen();
  expect(screen.getByRole('image', { name: 'Replacement，正在加载' })).toBeOnTheScreen();

  fireEvent(screen.getByLabelText('Replacement'), 'load', {
    nativeEvent: { source: { width: 800, height: 600 } },
  });
  expect(screen.getByRole('image', { name: 'Replacement' })).toBeOnTheScreen();
});

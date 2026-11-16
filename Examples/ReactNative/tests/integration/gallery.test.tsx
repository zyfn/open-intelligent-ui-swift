import { StrictMode } from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { Renderer } from '@openuidev/react-lang';
import App from '../../App';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import type { MessageController } from '../../src/runtime/message';
import { capturePress } from './native-events';

// The package's published mock supplies native window metrics only. App,
// FlatList, OpenUIDocument, Renderer, parser and Store are their real modules.
jest.mock('react-native-safe-area-context', () =>
  require('react-native-safe-area-context/jest/mock').default);

beforeEach(() => { jest.useFakeTimers(); });
afterEach(() => {
  act(() => { jest.runOnlyPendingTimers(); });
  jest.useRealTimers();
});

function showInteraction() {
  fireEvent.press(screen.getByRole('button', { name: '添加交互样例' }));
  fireEvent.press(screen.getByRole('button', { name: '清空历史' }));
  expect(screen.getByLabelText('至少两个字符')).toBeOnTheScreen();
}

test('the real Gallery survives StrictMode effect replay, theme changes, and message unload/restore', async () => {
  render(<StrictMode><App /></StrictMode>, { concurrentRoot: true });
  // The Gallery defers unmount disposal to a microtask so React development
  // effect replay can retain the still-mounted controllers.
  await act(async () => {
    jest.runAllTicks();
    jest.advanceTimersByTime(100);
  });
  expect(screen.getByRole('header', { name: '给旅程留一点空白' })).toBeOnTheScreen();
  await act(async () => { fireEvent.press(screen.getByRole('link', { name: 'Morio' })); });
  expect(screen.getByText('宿主事件 · 仅在本地记录，最近 3 条')).toBeOnTheScreen();

  showInteraction();
  fireEvent.changeText(screen.getByLabelText('至少两个字符'), 'Finn');
  fireEvent.changeText(screen.getByLabelText('name@example.com'), 'finn@example.com');
  const renderer = screen.UNSAFE_getByType(Renderer);

  fireEvent.press(screen.getByRole('button', { name: '深色主题' }));
  expect(screen.getByRole('button', { name: '深色主题' }).props.accessibilityState.selected).toBe(true);
  expect(screen.UNSAFE_getByType(Renderer)).toBe(renderer);
  expect(screen.getByLabelText('至少两个字符')).toHaveDisplayValue('Finn');
  expect(screen.getByText('你好，Finn')).toBeOnTheScreen();

  fireEvent.press(screen.getByRole('button', { name: '卸载消息' }));
  expect(screen.queryByLabelText('至少两个字符')).not.toBeOnTheScreen();
  expect(screen.getByText('消息视图已卸载。恢复后会读取宿主保存的字段。')).toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '恢复消息' }));
  expect(screen.getByLabelText('至少两个字符')).toHaveDisplayValue('Finn');
  expect(screen.getByLabelText('name@example.com')).toHaveDisplayValue('finn@example.com');
  expect(screen.getByText('你好，Finn')).toBeOnTheScreen();
});

test('Gallery stop freezes the stream and a new replay cannot receive stale edits or transport', async () => {
  render(<App />);
  showInteraction();
  fireEvent.changeText(screen.getByLabelText('至少两个字符'), 'Previous generation');
  const lateChange = screen.getByLabelText('至少两个字符').props.onChangeText;
  const controller = screen.UNSAFE_getByType(OpenUIDocument).props.message as MessageController;
  const retired = controller.getHandle();

  act(() => {
    fireEvent.press(screen.getByRole('button', { name: '流式回放输入与动作' }));
    lateChange('Late event from retired field');
    jest.advanceTimersByTime(160);
  });
  fireEvent.press(screen.getByRole('button', { name: '停止输入与动作' }));
  const stopped = controller.getSnapshot();
  expect(stopped.phase).toBe('interrupted');
  expect(stopped.source.length).toBeGreaterThan(0);
  expect(controller.getSavedFields(retired)).toBeUndefined();
  expect(screen.getByText('已停止 · 预览已冻结')).toBeOnTheScreen();
  act(() => { jest.advanceTimersByTime(10_000); });
  expect(controller.getSnapshot()).toBe(stopped);

  fireEvent.press(screen.getByRole('button', { name: '流式回放输入与动作' }));
  await act(async () => { jest.advanceTimersByTime(10_000); });
  expect(screen.getByText('已完成 · 可以交互')).toBeOnTheScreen();
  expect(screen.getByLabelText('至少两个字符')).toHaveDisplayValue('');
  fireEvent.changeText(screen.getByLabelText('至少两个字符'), 'Current generation');
  act(() => { jest.advanceTimersByTime(10_000); });
  expect(screen.getByLabelText('至少两个字符')).toHaveDisplayValue('Current generation');
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $name: 'Current generation' });
});

test('retired Gallery rows cannot restart a disposed host message', () => {
  render(<App />);
  const retired = screen.UNSAFE_getByType(OpenUIDocument).props.message as MessageController;
  const lateReplay = capturePress('流式回放阅读与图片');
  const lateStop = capturePress('停止阅读与图片');
  showInteraction();
  expect(retired.getSnapshot().source).toBe('');
  expect(() => act(() => { lateReplay(); lateStop(); })).not.toThrow();
  expect(retired.getSnapshot().source).toBe('');
  expect(screen.getByLabelText('至少两个字符')).toHaveDisplayValue('');
});

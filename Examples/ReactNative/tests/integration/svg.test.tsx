import { TextDecoder, TextEncoder } from 'node:util';
import { StyleSheet, View } from 'react-native';
import { SvgXml } from 'react-native-svg';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import { fetch as nativeFetch } from 'expo/fetch';
import { NativeContentProvider } from '../../src/library/components/contentPolicy';
import { MAX_SVG_BYTES, readSvgResponse, validateNativeSvg } from '../../src/library/components/svgSource';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from '../../src/runtime/message';
import { library as contentTestLibrary } from '../../src/library';

// Only the native network boundary is controlled. XML, SvgXml, parser and Store are real.
jest.mock('expo/fetch', () => ({ fetch: jest.fn() }));
globalThis.TextDecoder ??= TextDecoder as typeof globalThis.TextDecoder;
globalThis.TextEncoder ??= TextEncoder as typeof globalThis.TextEncoder;
const fetchMock = nativeFetch as jest.Mock;
const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160"><rect width="320" height="160" fill="blue"/><text x="12" y="24">原生图形</text></svg>';
const controllers = new Set<MessageController>();
afterEach(() => { controllers.forEach(controller => controller.dispose()); controllers.clear(); fetchMock.mockReset(); jest.useRealTimers(); });

function response(source = svg, chunks?: Uint8Array[], declared?: string) {
  const queue = chunks ?? [new TextEncoder().encode(source)];
  let index = 0;
  const reader = {
    read: jest.fn(async () => index < queue.length ? { done: false, value: queue[index++] } : { done: true }),
    cancel: jest.fn(async () => undefined), releaseLock: jest.fn(),
  };
  return { ok: true, headers: { get: () => declared ?? null }, body: { getReader: () => reader }, reader };
}

function show(source: string, options: { complete?: boolean; resolveImage?: (source: string) => { uri: string; headers?: Record<string, string> } | undefined } = {}) {
  const message = createMessageController('svg'); controllers.add(message);
  const handle = message.begin(source);
  if (options.complete !== false) message.complete(handle);
  const onError = jest.fn();
  render(<NativeContentProvider resolveImage={options.resolveImage} onError={onError}>
    <OpenUIDocument message={message} library={contentTestLibrary} />
  </NativeContentProvider>);
  return { message, handle, onError };
}

test('SVG uses its viewBox ratio, ignores legacy forced height and opens a native preview by tapping the graphic', () => {
  show(`root = Stack([SVG(${JSON.stringify(svg)}, null, "Diagram", 9999)])`);
  expect(screen.UNSAFE_getByType(SvgXml).props.xml).toBe(svg);
  expect(screen.UNSAFE_getAllByType(View).some(view => StyleSheet.flatten(view.props.style)?.aspectRatio === 2)).toBe(true);
  expect(screen.UNSAFE_getAllByType(View).some(view => StyleSheet.flatten(view.props.style)?.height === 9999)).toBe(false);
  fireEvent.press(screen.getByRole('button', { name: 'Diagram' }));
  expect(screen.getByRole('button', { name: '关闭图形预览' })).toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '关闭图形预览' }));
  expect(screen.queryByRole('button', { name: '关闭图形预览' })).not.toBeOnTheScreen();
});

test('SVG accepts bounded local gradients and references with readable XML escapes', () => {
  const source = '<svg viewBox="0 0 100 100"><defs><linearGradient id="paint"><stop offset="0" stop-color="red"/></linearGradient><g id="shape"><rect width="10" height="10" fill="url(#paint)"/></g></defs><use href="#shape"/><text x="1" y="20">A &amp; B</text></svg>';
  expect(validateNativeSvg(source)).toEqual({ xml: source, aspectRatio: 1 });
});

test.each([
  '<svg viewBox="0 0 10 10"><script>alert(1)</script></svg>',
  '<svg viewBox="0 0 10 10"><foreignObject>HTML</foreignObject></svg>',
  '<svg viewBox="0 0 10 10" onload="alert(1)"/>',
  '<svg viewBox="0 0 10 10"><use href="https://example.com/other.svg#shape"/></svg>',
  '<svg viewBox="0 0 10 10"><path style="fill:url(https://example.com/a.svg)" d="M0 0 L1 1"/></svg>',
  '<svg viewBox="0 0 10 10"><path fill="u&#114;l(https://example.com/a.svg)" d="M0 0 L1 1"/></svg>',
  '<!DOCTYPE svg [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><svg viewBox="0 0 10 10"><text>&xxe;</text></svg>',
  '<svg viewBox="0 0 10 10"><image href="data:image/png;base64,xx"/></svg>',
  '<svg viewBox="0 0 10 0"/>',
  '<svg viewBox="0 0 10 10"><g></svg>',
  '<svg viewBox="0 0 10 10"><use href="#missing"/></svg>',
  '<svg viewBox="0 0 10 10"><g id="loop"><use href="#loop"/></g></svg>',
  '<svg viewBox="0 0 10 10"><path d="M 1e999 0"/></svg>',
  '<svg viewBox="0 0 10 10" __proto__="unsafe"/>',
])('rejects active, external, malformed or unbounded SVG input %#', source => {
  expect(() => validateNativeSvg(source)).toThrow();
});

test('SVG source, nodes, depth and local-reference expansion all have independent bounds', () => {
  expect(() => validateNativeSvg(`<svg viewBox="0 0 1 1"><text>${'a'.repeat(MAX_SVG_BYTES)}</text></svg>`)).toThrow(/size/);
  expect(() => validateNativeSvg(`<svg viewBox="0 0 1 1">${'<path d="M0 0"/>'.repeat(4100)}</svg>`)).toThrow(/budget/);
  expect(() => validateNativeSvg(`<svg viewBox="0 0 1 1">${'<g>'.repeat(34)}${'</g>'.repeat(34)}</svg>`)).toThrow(/budget/);
  const repeated = '<g id="n0"><rect width="1" height="1"/></g>'
    + Array.from({ length: 14 }, (_, index) => `<g id="n${index + 1}"><use href="#n${index}"/><use href="#n${index}"/></g>`).join('');
  expect(() => validateNativeSvg(`<svg viewBox="0 0 1 1"><defs>${repeated}</defs><use href="#n14"/></svg>`)).toThrow(/reference budget/);
});

test('SVG enforces exclusive content/src using the same compact retry surface', () => {
  const { onError } = show(`root = Stack([SVG(${JSON.stringify(svg)}, "https://example.com/a.svg", "Both")])`);
  expect(screen.getByRole('button', { name: '重新加载图形' })).toBeOnTheScreen();
  expect(screen.getByText('点击重试')).toBeOnTheScreen();
  expect(fetchMock).not.toHaveBeenCalled();
  expect(onError).toHaveBeenCalledTimes(1);
});

test('remote SVG waits for completion and uses the host mapping, headers and bounded native fetch', async () => {
  fetchMock.mockResolvedValue(response());
  const resolveImage = jest.fn(() => ({ uri: 'https://example.com/mapped.svg', headers: { Authorization: 'test-header' } }));
  const { message, handle, onError } = show('root = Stack([SVG(null, "asset://diagram", "Remote")])', { complete: false, resolveImage });
  expect(resolveImage).not.toHaveBeenCalled(); expect(fetchMock).not.toHaveBeenCalled();
  act(() => { message.complete(handle); });
  await act(async () => { await Promise.resolve(); });
  expect(onError.mock.calls.map(call => call[0].message)).toEqual([]);
  await waitFor(() => expect(screen.getByRole('button', { name: 'Remote' })).toBeOnTheScreen());
  expect(resolveImage).toHaveBeenCalledWith('asset://diagram');
  expect(fetchMock).toHaveBeenCalledWith('https://example.com/mapped.svg', expect.objectContaining({
    headers: { Authorization: 'test-header' }, credentials: 'omit', redirect: 'error', signal: expect.any(AbortSignal),
  }));
});

test('remote SVG retry re-resolves the resource after a failed request', async () => {
  fetchMock.mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce(response());
  const resolveImage = jest.fn().mockReturnValueOnce({ uri: 'https://example.com/old.svg' })
    .mockReturnValueOnce({ uri: 'https://example.com/fresh.svg', headers: { Token: 'refreshed-test-token' } });
  show('root = Stack([SVG(null, "asset://diagram", "Retry")])', { resolveImage });
  await waitFor(() => expect(screen.getByRole('button', { name: '重新加载图形' })).toBeOnTheScreen());
  fireEvent.press(screen.getByRole('button', { name: '重新加载图形' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Retry' })).toBeOnTheScreen());
  expect(resolveImage).toHaveBeenCalledTimes(2);
  expect(fetchMock.mock.calls[1][0]).toBe('https://example.com/fresh.svg');
  expect(fetchMock.mock.calls[1][1].headers).toEqual({ Token: 'refreshed-test-token' });
});

test('SVG can retry a resolver exception even when the thrown value cannot be converted to a string', async () => {
  fetchMock.mockResolvedValue(response());
  const resolveImage = jest.fn().mockImplementationOnce(() => { throw Object.create(null); })
    .mockReturnValueOnce({ uri: 'https://example.com/recovered.svg' });
  const { onError } = show('root = Stack([SVG(null, "asset://diagram", "Recovered")])', { resolveImage });
  await waitFor(() => expect(screen.getByRole('button', { name: '重新加载图形' })).toBeOnTheScreen());
  expect(onError).toHaveBeenCalledWith(expect.any(Error));
  expect(fetchMock).not.toHaveBeenCalled();
  fireEvent.press(screen.getByRole('button', { name: '重新加载图形' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Recovered' })).toBeOnTheScreen());
  expect(resolveImage).toHaveBeenCalledTimes(2);
});

test('changing src within one document aborts the old target and ignores its later successful result', async () => {
  let resolveOld!: (value: ReturnType<typeof response>) => void;
  fetchMock.mockReturnValueOnce(new Promise(resolve => { resolveOld = resolve; }))
    .mockResolvedValueOnce(response(svg.replace('320 160', '300 100')));
  const { onError } = show(`root = Stack([drawing, change])
$src = "https://example.com/old.svg"
drawing = SVG(null, $src, "Target")
change = Button("Change source", @Set($src, "https://example.com/new.svg"))`);
  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
  const oldSignal = fetchMock.mock.calls[0][1].signal as AbortSignal;
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Change source' })); });
  await waitFor(() => expect(screen.getByRole('button', { name: 'Target' })).toBeOnTheScreen());
  expect(fetchMock).toHaveBeenCalledTimes(2);
  expect(oldSignal.aborted).toBe(true);
  await act(async () => { resolveOld(response()); await Promise.resolve(); });
  expect(screen.UNSAFE_getByType(SvgXml).props.xml).toContain('300 100');
  expect(onError).not.toHaveBeenCalled();
});

test('old SVG results and diagnostics are rejected between epoch retirement and React commit', async () => {
  let rejectOld!: (error: Error) => void;
  fetchMock.mockReturnValue(new Promise((_, reject) => { rejectOld = reject; }));
  const { message, onError } = show('root = Stack([SVG(null, "https://example.com/old.svg", "Old")])');
  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
  const signal = fetchMock.mock.calls[0][1].signal as AbortSignal;
  await act(async () => {
    const next = message.begin(`root = Stack([SVG(${JSON.stringify(svg)}, null, "New")])`);
    rejectOld(new Error('old response error'));
    await Promise.resolve();
    message.complete(next);
  });
  expect(onError).not.toHaveBeenCalled();
  expect(signal.aborted).toBe(true);
  expect(screen.getByRole('button', { name: 'New' })).toBeOnTheScreen();
});

test('SVG response streaming preserves split UTF-8 and cancels oversized chunks', async () => {
  const bytes = new TextEncoder().encode('图形');
  const valid = response('', [bytes.slice(0, 2), bytes.slice(2)]);
  await expect(readSvgResponse(valid, new AbortController().signal)).resolves.toBe('图形');
  const oversized = response('', [new Uint8Array(MAX_SVG_BYTES + 1)]);
  await expect(readSvgResponse(oversized, new AbortController().signal)).rejects.toThrow(/size limit/);
  expect(oversized.reader.cancel).toHaveBeenCalledTimes(1);
  const announced = response('', [], String(MAX_SVG_BYTES + 1));
  await expect(readSvgResponse(announced, new AbortController().signal)).rejects.toThrow(/size limit/);
  expect(announced.reader.read).not.toHaveBeenCalled();
});

test('remote SVG times out and aborts without leaving a spinning surface', async () => {
  jest.useFakeTimers();
  fetchMock.mockImplementation((_url, options) => new Promise((_, reject) => {
    options.signal.addEventListener('abort', () => reject(new Error('aborted')));
  }));
  show('root = Stack([SVG(null, "https://example.com/slow.svg", "Slow")])');
  await act(async () => { await Promise.resolve(); });
  expect(fetchMock).toHaveBeenCalledTimes(1);
  await act(async () => { jest.advanceTimersByTime(15000); await Promise.resolve(); });
  expect(fetchMock.mock.calls[0][1].signal.aborted).toBe(true);
  expect(screen.getByRole('button', { name: '重新加载图形' })).toBeOnTheScreen();
});

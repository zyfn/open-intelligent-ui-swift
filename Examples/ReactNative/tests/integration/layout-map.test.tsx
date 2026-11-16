import { act, fireEvent, render } from '@testing-library/react-native';
import { Camera, Marker } from '@maplibre/maplibre-react-native';
import { library, NativeContentProvider, NativeMapProvider } from '../../src/library';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController } from '../../src/runtime/message';
import { capturePress } from './native-events';

function document(source: string) {
  const message = createMessageController('layout'); message.complete(message.begin(source));
  return message;
}

test('tabs preserve hidden input state and accordion panels retain their own values', async () => {
  const message = document(`root = Stack([Tabs([TabItem("a", "第一页", [Input("name", "称呼")]), TabItem("b", "第二页", [TextContent("另一页")])]), Accordion([AccordionItem("one", "展开", [Input("note", "备注")])])])`);
  const tree = render(<OpenUIDocument message={message} library={library} />);
  fireEvent.changeText(tree.getByLabelText('称呼'), 'Finn');
  fireEvent.press(tree.getByRole('tab', { name: '第二页' }));
  expect(tree.queryByLabelText('称呼')).toBeNull();
  fireEvent.press(tree.getByRole('tab', { name: '第一页' }));
  expect(tree.getByLabelText('称呼').props.value).toBe('Finn');
  fireEvent.press(tree.getByRole('button', { name: '展开' }));
  fireEvent.changeText(tree.getByLabelText('备注'), 'Keep');
  fireEvent.press(tree.getByRole('button', { name: '展开' }));
  fireEvent.press(tree.getByRole('button', { name: '展开' }));
  expect(tree.getByLabelText('备注').props.value).toBe('Keep');
  tree.unmount(); message.dispose();
});

test('modal closes its official boolean binding and an old close callback cannot target a replacement', async () => {
  const source = `root = Stack([Button("打开", @Set($open, true)), Modal("设置", $open, [TextContent("内容")])])\n$open = false`;
  const message = document(source);
  const tree = render(<OpenUIDocument message={message} library={library} />);
  await act(async () => { fireEvent.press(tree.getByRole('button', { name: '打开' })); });
  const close = capturePress('关闭弹窗');
  await act(async () => { close(); });
  expect(message.getSavedFields(message.getHandle())?.$open).toBe(false);
  await act(async () => { fireEvent.press(tree.getByRole('button', { name: '打开' })); });
  act(() => { message.complete(message.begin(source.replace('$open = false', '$open = true'))); });
  await act(async () => { close(); });
  expect(tree.getByRole('button', { name: '关闭弹窗' })).toBeTruthy();
  tree.unmount(); message.dispose();
});

test('carousel navigation, card slots and icon action use native controls and remain inert after retirement', async () => {
  const message = document(`root = Stack([Card([TextContent("卡片")]), Carousel([[TextContent("一")],[TextContent("二")]]), IconButton("收藏", Icon("heart"), @ToAssistant("收藏"))])`);
  const onAction = jest.fn();
  const tree = render(<OpenUIDocument message={message} library={library} onAction={onAction} />);
  fireEvent.press(tree.getByRole('button', { name: '下一页' }));
  expect(tree.getByText('2 / 2')).toBeTruthy();
  const old = capturePress('收藏');
  await act(async () => { old(); });
  expect(onAction).toHaveBeenCalledTimes(1);
  act(() => { message.begin(); });
  await act(async () => { old(); });
  expect(onAction).toHaveBeenCalledTimes(1);
  tree.unmount(); message.dispose();
});

const mapSource = `root = Stack([Map([MapPoint("西湖",30.242637,120.134544,null,null,"湖边散步"),MapPoint("德寿宫",30.2412,120.16862,null,null,"历史建筑")],"wgs84")])`;

test('map selection, fullscreen and native request retry retain identity and reject old callbacks', async () => {
  const message = document(mapSource);
  const report = jest.fn();
  const tree = render(<NativeContentProvider onError={report}>
    <OpenUIDocument message={message} library={library} />
  </NativeContentProvider>);
  const oldFailure = tree.getByTestId('openui-native-map').props.onDidFailLoadingMap;
  fireEvent.press(tree.getAllByRole('button', { name: '选择德寿宫' }).at(-1)!);
  expect(tree.getByText('历史建筑')).toBeTruthy();
  fireEvent.press(tree.getByRole('button', { name: '展开地图' }));
  expect(tree.getByRole('button', { name: '收起地图' })).toBeTruthy();
  act(() => { oldFailure(); });
  expect(report).not.toHaveBeenCalled();
  fireEvent.press(tree.getByRole('button', { name: '收起地图' }));
  const failure = tree.getByTestId('openui-native-map').props.onDidFailLoadingMap;
  act(() => { failure(); });
  expect(report).toHaveBeenCalledTimes(1);
  fireEvent.press(tree.getByRole('button', { name: '重新加载地图' }));
  expect(tree.getByTestId('openui-native-map')).toBeTruthy();
  act(() => { failure(); });
  expect(report).toHaveBeenCalledTimes(1);
  act(() => { message.begin(); });
  act(() => { failure(); });
  expect(report).toHaveBeenCalledTimes(1);
  tree.unmount(); message.dispose();
});

test('partial maps make no native tile request and the host owns the map style', () => {
  const message = createMessageController('partial-map');
  const handle = message.begin(mapSource);
  const tree = render(<NativeMapProvider mapStyle="https://example.com/style.json">
    <OpenUIDocument message={message} library={library} />
  </NativeMapProvider>);
  expect(tree.queryByTestId('openui-native-map')).toBeNull();
  act(() => { message.complete(handle); });
  expect(tree.getByTestId('openui-native-map').props.mapStyle).toBe('https://example.com/style.json');
  tree.unmount(); message.dispose();
});

test('a current native view completion fits the latest points rather than the old render closure', async () => {
  const message = document(`root = Stack([Map($moved ? [MapPoint("New",30,120)] : [MapPoint("Old",10,20)]), Button("Move map", @Set($moved,true))])
$moved = false`);
  const tree = render(<OpenUIDocument message={message} library={library} />);
  try {
    const completion = tree.getByTestId('openui-native-map').props.onDidFinishLoadingMap;
    await act(async () => { fireEvent.press(tree.getByRole('button', { name: 'Move map' })); });
    const camera = tree.UNSAFE_getByType(Camera).props.ref.current;
    act(() => { completion(); });
    expect(camera.easeTo).toHaveBeenCalledWith(expect.objectContaining({ center: [120, 30] }));
    expect(camera.easeTo).not.toHaveBeenCalledWith(expect.objectContaining({ center: [20, 10] }));
  } finally { tree.unmount(); message.dispose(); }
});

test('a retained marker callback resolves the current CRS coordinates for its stable place id', async () => {
  const message = document(`root = Stack([Map([MapPoint("West lake",30.242637,120.134544)], $crs), Button("Convert CRS", @Set($crs,"gcj02"))])
$crs = "wgs84"`);
  const tree = render(<OpenUIDocument message={message} library={library} />);
  try {
    const pick = tree.UNSAFE_getByType(Marker).props.onPress;
    await act(async () => { fireEvent.press(tree.getByRole('button', { name: 'Convert CRS' })); });
    const point = tree.UNSAFE_getByType(Marker).props.lngLat;
    const camera = tree.UNSAFE_getByType(Camera).props.ref.current;
    expect(point).not.toEqual([120.134544, 30.242637]);
    act(() => { pick(); });
    expect(camera.easeTo).toHaveBeenCalledWith(expect.objectContaining({ center: point }));
  } finally { tree.unmount(); message.dispose(); }
});

test('native map failures are isolated by actual view lifetime and reported once per view', () => {
  const points = Array.from({ length: 6 }, (_, index) => `MapPoint("Place ${index}",30,${120 + index / 100})`).join(',');
  const message = document(`root = Stack([Map([${points}])])`);
  const report = jest.fn();
  const tree = render(<NativeContentProvider onError={report}>
    <OpenUIDocument message={message} library={library} />
  </NativeContentProvider>);
  try {
    const retired = tree.getByTestId('openui-native-map').props.onDidFailLoadingMap;
    fireEvent.changeText(tree.getByLabelText('筛选地点'), 'No matching place');
    expect(tree.queryByTestId('openui-native-map')).toBeNull();
    fireEvent.changeText(tree.getByLabelText('筛选地点'), '');
    const failure = tree.getByTestId('openui-native-map').props.onDidFailLoadingMap;
    act(() => { retired(); });
    expect(report).not.toHaveBeenCalled();
    expect(tree.getByTestId('openui-native-map')).toBeOnTheScreen();
    act(() => { failure(); failure(); });
    expect(report).toHaveBeenCalledTimes(1);
    fireEvent.press(tree.getByRole('button', { name: '重新加载地图' }));
    act(() => { failure(); });
    expect(report).toHaveBeenCalledTimes(1);
    expect(tree.getByTestId('openui-native-map')).toBeOnTheScreen();
  } finally { tree.unmount(); message.dispose(); }
});

test('same-epoch action replacements retire IconButton and map link callbacks even after A to B to A', async () => {
  const message = document(`root = Stack([Button("Swap actions", @Set($changed, !$changed)), IconButton(label, Icon("heart"), @ToAssistant(label)), Map([MapPoint("Lake",30,120,null,url)])])
$changed = false
label = $changed ? "New" : "Old"
url = $changed ? "https://example.com/new" : "https://example.com/old"`);
  const onAction = jest.fn();
  const tree = render(<OpenUIDocument message={message} library={library} onAction={onAction} />);
  try {
    const oldIcon = capturePress('Old');
    let link = tree.getByRole('link', { name: '查看Lake' });
    while (typeof link.props.onPress !== 'function') {
      if (!link.parent) throw new Error('Missing native link callback');
      link = link.parent;
    }
    const oldLink = link.props.onPress;
    await act(async () => { fireEvent.press(tree.getByRole('button', { name: 'Swap actions' })); });
    expect(tree.getByRole('button', { name: 'New' })).toBeOnTheScreen();
    await act(async () => { oldIcon(); oldLink(); });
    expect(onAction).not.toHaveBeenCalled();
    await act(async () => { fireEvent.press(tree.getByRole('button', { name: 'Swap actions' })); });
    await act(async () => { oldIcon(); oldLink(); });
    expect(onAction).not.toHaveBeenCalled();
    await act(async () => {
      fireEvent.press(tree.getByRole('button', { name: 'Old' }));
      fireEvent.press(tree.getByRole('link', { name: '查看Lake' }));
    });
    expect(onAction).toHaveBeenCalledTimes(2);
    expect(onAction).toHaveBeenCalledWith(expect.objectContaining({ humanFriendlyMessage: 'Old' }));
    expect(onAction).toHaveBeenCalledWith(expect.objectContaining({ type: 'open_url', params: { url: 'https://example.com/old' } }));
  } finally { tree.unmount(); message.dispose(); }
});

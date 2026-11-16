import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { BuiltinActionType, type RendererProps } from '@openuidev/react-lang';
import DateTimePicker from '@react-native-community/datetimepicker';
import { Circle, Path } from 'react-native-svg';
import { library } from '../../src/library';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from '../../src/runtime/message';
import { dataSamples } from '../../src/demo/dataSamples';
import gallery from '../../../Gallery/Resources/Components/openui.json';
import { capturePress } from './native-events';

const controllers = new Set<MessageController>();
const diagnostics: string[] = [];
const onError = (errors: { message: string }[]) => { diagnostics.push(...errors.map(error => error.message)); };
afterEach(() => {
  for (const controller of controllers) controller.dispose();
  controllers.clear();
  expect(diagnostics.splice(0)).toEqual([]);
});

function document(source: string, action?: RendererProps['onAction']) {
  const controller = createMessageController('data');
  controllers.add(controller);
  const handle = controller.begin(source);
  controller.complete(handle);
  const onAction = jest.fn(action);
  const result = render(<OpenUIDocument message={controller} library={library} onAction={onAction} onError={onError} />);
  return { controller, handle, onAction, ...result };
}

const chartCases = [
  ['BarChart', 'chart-bar-0-0'], ['HorizontalBarChart', 'chart-bar-0-0'],
  ['LineChart', 'chart-line-0'], ['AreaChart', 'chart-area-0'], ['RadarChart', 'chart-radar-0'],
  ['PieChart', 'chart-slice-0'], ['RadialChart', 'chart-radial-0'],
  ['SingleStackedBarChart', 'chart-segment-0'], ['ScatterChart', 'chart-point:0:0'],
] as const;

test.each(chartCases)('the unchanged Gallery %s program renders its actual SVG family', (name, shape) => {
  document(gallery[name].program);
  expect(screen.getByTestId(`openui-chart-${name}`)).toBeOnTheScreen();
  expect(screen.getByTestId(shape)).toBeOnTheScreen();
  expect(screen.queryByText(/完整数据$/)).not.toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '查看完整数据' }));
  expect(screen.getByRole('header', { name: /完整数据/ })).toBeOnTheScreen();
  const expected = name === 'ScatterChart' ? '步行记录 · 1：x 1，y 30'
    : name === 'PieChart' || name === 'RadialChart' || name === 'SingleStackedBarChart' ? '交通：60'
      : '周一 · 步行分钟：30';
  expect(screen.getByRole('button', { name: expected })).toBeOnTheScreen();
});

test('point inspection and full-data pagination are separate from the quiet default view', () => {
  const labels = Array.from({ length: 13 }, (_, index) => `Day ${index + 1}`);
  const values = labels.map((_, index) => index - 4);
  document(`root = Stack([LineChart(${JSON.stringify(labels)}, [Series("Count", ${JSON.stringify(values)})], "step")])`);
  expect(screen.queryByText('Day 1 · Count：-4')).not.toBeOnTheScreen();
  fireEvent.press(screen.getByTestId('chart-point-0-0'));
  expect(screen.getByText('Day 1 · Count：-4')).toBeOnTheScreen();
  fireEvent(screen.getByRole('image', { name: '折线图' }), 'longPress');
  expect(screen.getByRole('button', { name: 'Day 12 · Count：7' })).toBeOnTheScreen();
  expect(screen.queryByRole('button', { name: 'Day 13 · Count：8' })).not.toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '下一页数据' }));
  expect(screen.getByRole('button', { name: 'Day 13 · Count：8' })).toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '关闭数据' }));
  expect(screen.queryByRole('header', { name: /完整数据/ })).not.toBeOnTheScreen();
});

test('real SVG line variants and series toggles keep their distinct behavior', () => {
  const { controller } = document('root = Stack([LineChart(["A", "B", "C"], [Series("Count", [1, 3, 2])], "natural")])');
  const path = screen.UNSAFE_getAllByType(Path).find(node => node.props.testID === 'chart-line-0');
  expect(path?.props.d).toContain(' C');
  expect(path?.props.d).not.toContain(' H');
  fireEvent.press(screen.getByRole('checkbox', { name: '显示 Count' }));
  expect(screen.queryByTestId('chart-line-0')).not.toBeOnTheScreen();
  fireEvent.press(screen.getByRole('checkbox', { name: '显示 Count' }));
  const point = screen.UNSAFE_getAllByType(Circle).find(node => node.props.testID === 'chart-point-0-0')!;
  const retired = point.props.onPress;
  act(() => {
    const next = controller.begin('root = Stack([LineChart(["New"], [Series("Other", [42])])])');
    retired();
    controller.complete(next);
  });
  expect(screen.queryByText('A · Count：1')).not.toBeOnTheScreen();
  expect(screen.getByRole('checkbox', { name: '显示 Other' })).toBeChecked();
});

test('negative proportion data is explicitly rejected while its exact data stays available', () => {
  document('root = Stack([PieChart(["Revenue", "Refund"], [20, -5], "donut")])');
  expect(screen.getByText('此图表需要非负数。原始负数保留在完整数据中。')).toBeOnTheScreen();
  expect(screen.queryByTestId('chart-slice-0')).not.toBeOnTheScreen();
  fireEvent(screen.getByRole('image', { name: '饼图' }), 'accessibilityAction', { nativeEvent: { actionName: 'showData' } });
  expect(screen.getByRole('button', { name: 'Refund：-5' })).toBeOnTheScreen();
});

test('zero, empty and very large finite radial data finish without invented proportions', () => {
  const first = document('root = Stack([PieChart(["A", "B"], [0, 0]), LineChart([], [])])');
  expect(screen.getByText('正值合计为 0')).toBeOnTheScreen();
  expect(screen.getByText('暂无数据')).toBeOnTheScreen();
  expect(screen.queryByTestId('chart-slice-0')).not.toBeOnTheScreen();
  first.unmount();
  const huge = `1${'0'.repeat(308)}`;
  document(`root = Stack([RadialChart(["A", "B"], [${huge}, ${huge}])])`);
  const path = screen.UNSAFE_getAllByType(Path).find(node => node.props.testID === 'chart-radial-0');
  expect(path?.props.d.match(/ A/g)).toHaveLength(2);
  expect(path?.props.d).not.toMatch(/NaN|Infinity/);
});

test('SVG point budgets preserve the last item through native data pagination', () => {
  const count = 2_001;
  const labels = Array.from({ length: count }, (_, index) => `L${index + 1}`);
  document(`root = Stack([LineChart(${JSON.stringify(labels)}, [Series("Value", ${JSON.stringify(labels.map(() => 1))})])])`);
  expect(screen.getByText(`共 ${count} 个数据点。超过单图绘制上限，请分页查看完整数据。`)).toBeOnTheScreen();
  expect(screen.queryByTestId('chart-line-0')).not.toBeOnTheScreen();
  fireEvent.press(screen.getByRole('button', { name: '查看完整数据' }));
  for (let page = 1; page < Math.ceil(count / 12); page++) {
    fireEvent.press(screen.getByRole('button', { name: '下一页数据' }));
  }
  expect(screen.getByRole('button', { name: 'L2001 · Value：1' })).toBeOnTheScreen();
});

test('read-only column data pages without losing custom action cells', async () => {
  const values = Array.from({ length: 11 }, (_, index) => `Place ${index + 1}`);
  const { onAction } = document(`root = Stack([Table([Col("Place", ${JSON.stringify(values)}), Col("Action", [Button("Inspect", @ToAssistant("Inspect", {place: "Place 1"}))], "action")])])`);
  expect(screen.getByText('Place 10')).toBeOnTheScreen();
  expect(screen.queryByText('Place 11')).not.toBeOnTheScreen();
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Inspect' })); });
  expect(onAction).toHaveBeenCalledTimes(1);
  expect(onAction).toHaveBeenCalledWith(expect.objectContaining({ params: { context: { place: 'Place 1' } } }));
  fireEvent.press(screen.getByRole('button', { name: '下一页' }));
  expect(screen.getByText('Place 11')).toBeOnTheScreen();
  expect(screen.queryByText('Place 1')).not.toBeOnTheScreen();
});

const columns = [
  { key: 'item', header: 'Item', type: 'text' },
  { key: 'amount', header: 'Amount', type: 'number' },
  { key: 'reference', header: 'Reference', type: 'url' },
  { key: 'status', header: 'Status', type: 'select', options: [
    { value: 'planned', label: 'Planned' }, { value: 'booked', label: 'Booked' },
  ] },
  { key: 'date', header: 'Date', type: 'date-single' },
];
const rows = [{ id: '1', values: ['Transport', 60, 'https://example.com', 'planned', '2026-11-20'] }];
const table = (name = 'budget', data = JSON.stringify(rows)) => `EditableTable(${JSON.stringify(name)}, ${JSON.stringify(columns)}, ${data})`;

test('EditableTable uses typed native editors and sends the exact named-form Save Changes contract', async () => {
  const { controller, handle, onAction, unmount } = document(`root = Stack([${table()}])`);
  expect(screen.getByLabelText('Reference · 第 1 行').props.keyboardType).toBe('url');
  expect(screen.getByRole('button', { name: 'Date · 第 1 行' })).toBeOnTheScreen();
  fireEvent.changeText(screen.getByLabelText('Item · 第 1 行'), 'Train');
  fireEvent.changeText(screen.getByLabelText('Amount · 第 1 行'), '88.5');
  fireEvent.changeText(screen.getByLabelText('Reference · 第 1 行'), 'https://example.com/train');
  fireEvent.press(screen.getByRole('button', { name: 'Status · 第 1 行' }));
  fireEvent.press(screen.getByRole('radio', { name: 'Booked' }));
  fireEvent.press(screen.getByRole('button', { name: 'Date · 第 1 行' }));
  const chosen = new Date(2026, 10, 22, 12);
  act(() => { screen.UNSAFE_getByType(DateTimePicker).props.onChange(
    { type: 'set', nativeEvent: { timestamp: chosen.getTime(), utcOffset: 0 } }, chosen); });
  fireEvent.press(screen.getByRole('button', { name: '完成Date · 第 1 行' }));
  expect(controller.getSavedFields(handle)?.budget).toBeUndefined();
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Save Changes' })); });
  const saved = [{ id: '1', values: ['Train', 88.5, 'https://example.com/train', 'booked', '2026-11-22'] }];
  expect(controller.getSavedFields(handle)).toMatchObject({ budget: { budget: { value: saved, componentType: 'EditableTable' } } });
  expect(onAction).toHaveBeenCalledTimes(1);
  expect(onAction).toHaveBeenCalledWith(expect.objectContaining({ type: BuiltinActionType.ContinueConversation,
    humanFriendlyMessage: 'Save Changes', formName: 'budget', params: {},
    formState: { budget: { budget: { value: saved, componentType: 'EditableTable' } } } }));
  expect(screen.queryByRole('button', { name: 'Save Changes' })).not.toBeOnTheScreen();
  unmount();
  render(<OpenUIDocument message={controller} library={library} onError={onError} />);
  expect(screen.getByLabelText('Item · 第 1 行')).toHaveDisplayValue('Train');
  expect(screen.getByLabelText('Amount · 第 1 行')).toHaveDisplayValue('88.5');
  expect(screen.getByRole('button', { name: 'Status · 第 1 行' })).toHaveAccessibilityValue({ text: 'Booked' });
});

test('an invalid numeric draft cannot publish, and Reset restores the baseline', async () => {
  const { controller, handle, onAction } = document(`root = Stack([${table()}])`);
  fireEvent.changeText(screen.getByLabelText('Amount · 第 1 行'), '1e999');
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Save Changes' })); });
  expect(screen.getByText('请先把标记的数字单元格改为有限数值。')).toBeOnTheScreen();
  expect(screen.getByLabelText('Amount · 第 1 行')).toHaveDisplayValue('1e999');
  expect(onAction).not.toHaveBeenCalled();
  expect(controller.getSavedFields(handle)?.budget).toBeUndefined();
  fireEvent.press(screen.getByRole('button', { name: 'Reset' }));
  expect(screen.getByLabelText('Amount · 第 1 行')).toHaveDisplayValue('60');
  expect(screen.queryByText('请先把标记的数字单元格改为有限数值。')).not.toBeOnTheScreen();
});

test('EditableTable retains the canonical defaults for omitted column key and header', () => {
  document('root = Stack([EditableTable("defaults", [{type:"text"}], [{id:"1", values:["Value"]}])])');
  expect(screen.getByLabelText('default · 第 1 行')).toHaveDisplayValue('Value');
  expect(screen.queryByText('列定义不完整或包含不支持的编辑类型。')).not.toBeOnTheScreen();
});

test('same-batch edits reach Save once and a synchronous host failure remains retryable', async () => {
  // The pinned runtime awaits its own action execution, but onAction is a void
  // callback; this does not assert that it awaits a remote host Promise.
  const host = jest.fn().mockImplementationOnce(() => { throw new Error('Host unavailable'); });
  const { controller, handle } = document(`root = Stack([${table()}])`, host);
  fireEvent.changeText(screen.getByLabelText('Item · 第 1 行'), 'First draft');
  const change = screen.getByLabelText('Item · 第 1 行').props.onChangeText;
  const save = capturePress('Save Changes');
  await act(async () => { change('Latest edit'); save(); save(); });
  expect(host).toHaveBeenCalledTimes(1);
  expect(controller.getSavedFields(handle)).toMatchObject({ budget: { budget: { value: [
    { id: '1', values: ['Latest edit', 60, 'https://example.com', 'planned', '2026-11-20'] },
  ] } } });
  expect(screen.getByText('保存动作未完成，请重试。')).toBeOnTheScreen();
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Save Changes' })); });
  expect(host).toHaveBeenCalledTimes(2);
  expect(screen.queryByRole('button', { name: 'Save Changes' })).not.toBeOnTheScreen();
});

test('a source update cannot silently discard an unsubmitted table draft', async () => {
  const next = [{ id: '1', values: ['New source', 90, 'https://example.com/new', 'booked', '2026-11-21'] }];
  const { onAction } = document(`root = Stack([${table('budget', '$rows')}, Button("Refresh", @Set($rows, ${JSON.stringify(next)}))])
$rows = ${JSON.stringify(rows)}`);
  fireEvent.changeText(screen.getByLabelText('Item · 第 1 行'), 'My draft');
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Refresh' })); });
  expect(screen.getByText('源数据已经变化。请先选择使用新数据，或保留当前草稿。')).toBeOnTheScreen();
  expect(screen.getByLabelText('Item · 第 1 行')).toHaveDisplayValue('My draft');
  expect(screen.getByRole('button', { name: 'Save Changes' })).toBeDisabled();
  fireEvent.press(screen.getByRole('button', { name: '使用新数据' }));
  expect(screen.getByLabelText('Item · 第 1 行')).toHaveDisplayValue('New source');
  expect(screen.getByLabelText('Amount · 第 1 行')).toHaveDisplayValue('90');
  expect(onAction).not.toHaveBeenCalled();
});

test('an old cell handler cannot write to a renamed table or an interrupted epoch', async () => {
  const source = `root = Stack([EditableTable($name, ${JSON.stringify(columns)}, ${JSON.stringify(rows)}), Button("Rename", @Set($name, "replacement"))])
$name = "budget"`;
  const { controller } = document(source);
  const old = screen.getByLabelText('Item · 第 1 行').props.onChangeText;
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Rename' })); });
  act(() => { old('Retired edit'); });
  expect(screen.getByLabelText('Item · 第 1 行')).toHaveDisplayValue('Transport');
  const current = screen.getByLabelText('Item · 第 1 行').props.onChangeText;
  act(() => {
    const next = controller.begin(source);
    expect(controller.interrupt(next)).toBe(true);
    current('Late edit after stop');
  });
  expect(screen.getByLabelText('Item · 第 1 行')).toHaveDisplayValue('Transport');
  expect(screen.getByLabelText('Item · 第 1 行')).toBeDisabled();
  expect(controller.getSavedFields(controller.getHandle())?.replacement).toBeUndefined();
});

test.each(dataSamples)('data sample $id renders through the real parser and native components', sample => {
  document(sample.source);
  expect(screen.getAllByRole('header').length).toBeGreaterThan(0);
});

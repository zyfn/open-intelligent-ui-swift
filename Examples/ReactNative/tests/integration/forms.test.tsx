import { act, fireEvent, render, screen } from '@testing-library/react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import NativeSlider from '@react-native-community/slider';
import { Picker } from '@react-native-picker/picker';
import { TextInput } from 'react-native';
import { library } from '../../src/library';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from '../../src/runtime/message';
import { formSamples } from '../../src/demo/formSamples';

const controllers = new Set<MessageController>();
const diagnostics: string[] = [];
const onError = (errors: { message: string }[]) => { diagnostics.push(...errors.map(error => error.message)); };
afterEach(() => {
  for (const controller of controllers) controller.dispose();
  controllers.clear();
  expect(diagnostics.splice(0)).toEqual([]);
});

function document(source: string, complete = true) {
  const controller = createMessageController('forms');
  controllers.add(controller);
  const handle = controller.begin(source);
  if (complete) controller.complete(handle);
  const onAction = jest.fn();
  const result = render(<OpenUIDocument message={controller} library={library} onAction={onAction} onError={onError} />);
  return { controller, handle, onAction, ...result };
}

function captureCheckbox(label: string): () => void {
  let node = screen.getByRole('checkbox', { name: label });
  while (typeof node.props.onPress !== 'function') {
    if (!node.parent) throw new Error(`No checkbox callback for ${label}`);
    node = node.parent;
  }
  return node.props.onPress;
}

test('a real Form validates all fields before a host action and Reset clears current validation', async () => {
  const { controller, onAction } = document(formSamples[0]!.source);
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: '记录资料' })); });
  expect(onAction).not.toHaveBeenCalled();
  expect(screen.getAllByText('This field is required')).toHaveLength(3);
  fireEvent.changeText(screen.getByLabelText('称呼'), 'Finn');
  fireEvent.changeText(screen.getByLabelText('邮箱'), 'invalid');
  fireEvent(screen.getByLabelText('邮箱'), 'blur');
  expect(screen.getByText('Please enter a valid email')).toBeOnTheScreen();
  fireEvent.changeText(screen.getByLabelText('邮箱'), 'finn@example.com');
  act(() => { screen.UNSAFE_getByType(Picker).props.onValueChange('hangzhou', 1); });
  fireEvent.changeText(screen.getByLabelText('补充说明'), 'A multiline\nnative note');
  expect(screen.getByLabelText('补充说明').props.multiline).toBe(true);
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: '记录资料' })); });
  expect(onAction).toHaveBeenCalledTimes(1);
  expect(onAction).toHaveBeenLastCalledWith(expect.objectContaining({ formName: 'contact',
    params: { context: { name: 'Finn', email: 'finn@example.com', city: 'hangzhou', notes: 'A multiline\nnative note' } },
  }));
  fireEvent.changeText(screen.getByLabelText('邮箱'), 'invalid again');
  expect(screen.getByText('Please enter a valid email')).toBeOnTheScreen();
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: '重置表单' })); });
  expect(screen.getByLabelText('称呼')).toHaveDisplayValue('');
  expect(screen.getByLabelText('邮箱')).toHaveDisplayValue('');
  expect(screen.queryByText('Please enter a valid email')).not.toBeOnTheScreen();
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $name: '', $email: '', $notes: '', $city: '' });
});

test.each(['same-name', 'different-name'])('a retired Input handler cannot write a replacement binding (%s)', async kind => {
  const secondName = kind === 'same-name' ? 'first' : 'second';
  const source = `root = Stack([field, Button("Swap field", @Set($mode, !$mode))])
$mode = false
$first = "Alpha"
$second = "Beta"
field = $mode ? Input("${secondName}", "Value", "text", null, $second) : Input("first", "Value", "text", null, $first)
`;
  const { controller } = document(source);
  const old = screen.getByLabelText('Value').props.onChangeText;
  const nativeID = screen.getByLabelText('Value').props.nativeID;
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Swap field' })); });
  expect(screen.getByLabelText('Value').props.nativeID).toBe(nativeID);
  act(() => { old('Late event from Alpha'); });
  expect(screen.getByLabelText('Value')).toHaveDisplayValue('Beta');
  fireEvent.changeText(screen.getByLabelText('Value'), 'Beta edit');
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Swap field' })); });
  act(() => { old('Even later Alpha event'); });
  expect(screen.getByLabelText('Value')).toHaveDisplayValue('Alpha');
  fireEvent.changeText(screen.getByLabelText('Value'), 'Current Alpha edit');
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $first: 'Current Alpha edit', $second: 'Beta edit' });
});

test('a standalone FormControl keeps its accessible label and local TextArea validation', () => {
  document('root = Stack([FormControl("Notes", TextArea("notes", "Write a note", 2, {required: true}))])');
  const input = screen.getByLabelText('Notes');
  expect(input.props.multiline).toBe(true);
  fireEvent(input, 'blur');
  expect(screen.getByText('This field is required')).toBeOnTheScreen();
  fireEvent.changeText(input, 'A note');
  expect(screen.queryByText('This field is required')).not.toBeOnTheScreen();
});

test('changing a Form namespace starts independent validation', async () => {
  const source = `root = Stack([form, Button("Swap form", @Set($mode, true))])
$mode = false
form = $mode ? Form("second", Buttons([Button("Submit", @ToAssistant("Submit"))]), [FormControl("Name", Input("name", "Name", "text", {required: true}, "Valid"))]) : Form("first", Buttons([Button("Submit", @ToAssistant("Submit"))]), [FormControl("Name", Input("name", "Name", "text", {required: true}, ""))])
`;
  document(source);
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Submit' })); });
  expect(screen.getByText('This field is required')).toBeOnTheScreen();
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Swap form' })); });
  expect(screen.getByLabelText('Name')).toHaveDisplayValue('Valid');
  expect(screen.queryByText('This field is required')).not.toBeOnTheScreen();
});

test('native Select writes its form namespace and freezes callbacks at an epoch boundary', () => {
  const source = 'root = Stack([Form("trip", Buttons([]), [FormControl("City", Select("city", [SelectItem("hz", "Hangzhou"), SelectItem("cd", "Chengdu")], "Choose", {required: true}))])])';
  const { controller } = document(source);
  const old = screen.UNSAFE_getByType(Picker).props.onValueChange;
  act(() => { old('hz', 1); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ trip: { city: { value: 'hz' } } });
  act(() => {
    const next = controller.begin(source);
    old('cd', 2);
    controller.complete(next);
  });
  expect(screen.UNSAFE_getByType(Picker).props.selectedValue).toBe('');
  expect(controller.getSavedFields(controller.getHandle())?.trip).toBeUndefined();
});

test('checkboxes, radio, switches, chips and option cards keep distinct values and cleared defaults', () => {
  const { controller, unmount } = document(formSamples[1]!.source);
  const breakfast = captureCheckbox('早餐');
  const parking = captureCheckbox('停车位');
  act(() => { breakfast(); parking(); });
  fireEvent.press(screen.getByRole('radio', { name: '靠过道' }));
  fireEvent(screen.getByRole('switch', { name: '推送提醒' }), 'valueChange', true);
  fireEvent.press(screen.getByRole('checkbox', { name: '散步' }));
  fireEvent.press(screen.getByRole('radio', { name: '安静阅读' }));
  expect(screen.getByRole('checkbox', { name: '暂未开放' })).toBeDisabled();
  const expected = {
    $facilities: { wifi: true, breakfast: true, parking: true }, $seat: 'aisle',
    $reminders: { email: true, push: true }, topics: { value: [] }, appearance: { value: '' },
  };
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject(expected);
  unmount();
  // Default hydration must not overwrite the host snapshot during either mount.
  for (let i = 0; i < 2; i += 1) {
    const next = render(<OpenUIDocument message={controller} library={library} onError={onError} />);
    expect(screen.getByRole('checkbox', { name: '散步' })).not.toBeChecked();
    expect(screen.getByRole('radio', { name: '安静阅读' })).not.toBeChecked();
    expect(screen.getByRole('radio', { name: '靠过道' })).toBeChecked();
    expect(controller.getSavedFields(controller.getHandle())).toMatchObject(expected);
    next.unmount();
  }
});

test('date ranges use native dates, persist JSON, and ignore a retired picker callback', () => {
  const source = 'root = Stack([DatePicker("Travel", "range", null, $travel)])\n$travel = {from: "2026-12-01", to: "2026-12-07"}';
  const { controller } = document(source);
  fireEvent.press(screen.getByRole('button', { name: 'Travel · 开始日期' }));
  const oldChange = screen.UNSAFE_getByType(DateTimePicker).props.onChange;
  const first = new Date(2026, 11, 2, 12);
  act(() => { oldChange({ type: 'set', nativeEvent: { timestamp: first.getTime(), utcOffset: 0 } }, first); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $travel: { from: first.toISOString(), to: '2026-12-07' } });
  fireEvent.press(screen.getByRole('button', { name: '完成Travel · 开始日期' }));
  fireEvent.press(screen.getByRole('button', { name: 'Travel · 结束日期' }));
  const staleDate = new Date(2026, 11, 5, 12);
  act(() => { oldChange({ type: 'set', nativeEvent: { timestamp: staleDate.getTime(), utcOffset: 0 } }, staleDate); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $travel: { from: first.toISOString() } });
  const end = new Date(2026, 11, 8, 12);
  act(() => { screen.UNSAFE_getByType(DateTimePicker).props.onChange({ type: 'set', nativeEvent: { timestamp: end.getTime(), utcOffset: 0 } }, end); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $travel: { from: first.toISOString(), to: end.toISOString() } });
  act(() => {
    const next = controller.begin(source);
    oldChange({ type: 'set', nativeEvent: { timestamp: end.getTime(), utcOffset: 0 } }, end);
    controller.complete(next);
  });
  expect(controller.getSavedFields(controller.getHandle())?.$travel).toBeUndefined();
  expect(screen.getByRole('button', { name: 'Travel · 开始日期' }).props.accessibilityValue.text).toBe('2026-12-01');
});

test('date-only values reject calendar overflow while accepting a real leap day', async () => {
  const { onAction } = document(`root = Stack([Form("dates", Buttons([Button("Submit dates", @ToAssistant("Dates"))]), [
    FormControl("Overflow", DatePicker("overflow", "single", {required: true}, "2026-02-30")),
    FormControl("Non-leap", DatePicker("nonleap", "single", {required: true}, "2026-02-29")),
    FormControl("Leap", DatePicker("leap", "single", {required: true}, "2028-02-29"))
  ])])`);
  expect(screen.getByRole('button', { name: 'Overflow' }).props.accessibilityValue.text).toBe('选择日期');
  expect(screen.getByRole('button', { name: 'Non-leap' }).props.accessibilityValue.text).toBe('选择日期');
  expect(screen.getByRole('button', { name: 'Leap' }).props.accessibilityValue.text).toBe('2028-02-29');
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Submit dates' })); });
  expect(onAction).not.toHaveBeenCalled();
  expect(screen.getAllByText('This field is required')).toHaveLength(2);
});

test('array sliders retain every handle, enforce ordering, and reject old domain callbacks', async () => {
  const source = `root = Stack([slider, Button("Tighten", @Set($tight, true))])
$tight = false
$range = [2, 8]
slider = $tight ? Slider("range", "discrete", 0, 10, 1, null, "Range", null, $range) : Slider("range", "discrete", 0, 100, 1, null, "Range", null, $range)
`;
  const { controller } = document(source);
  const [first, second] = screen.UNSAFE_getAllByType(NativeSlider);
  const retired = first!.props.onValueChange;
  act(() => { second!.props.onValueChange(6); first!.props.onValueChange(9); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $range: [6, 6] });
  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Tighten' })); });
  act(() => { retired(99); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $range: [6, 6] });
  act(() => { screen.UNSAFE_getAllByType(NativeSlider)[0]!.props.onValueChange(4); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $range: [4, 6] });
  act(() => {
    const next = controller.begin('root = Stack([Slider("empty", "continuous", 0, 10, null, null, "Empty", null, $value)])\n$value = []');
    controller.complete(next);
  });
  act(() => { screen.UNSAFE_getByType(NativeSlider).props.onValueChange(3); });
  expect(controller.getSavedFields(controller.getHandle())).toMatchObject({ $value: [3] });
});

test('all form samples remain read-only while streaming', () => {
  for (const sample of formSamples) {
    const doc = document(sample.source, false);
    for (const input of screen.queryAllByRole('checkbox').concat(screen.queryAllByRole('radio'), screen.queryAllByRole('switch'))) {
      expect(input).toBeDisabled();
    }
    for (const input of screen.UNSAFE_queryAllByType(Picker)) expect(input.props.enabled).toBe(false);
    for (const input of screen.UNSAFE_queryAllByType(NativeSlider)) expect(input.props.disabled).toBe(true);
    for (const input of screen.UNSAFE_queryAllByType(TextInput)) expect(input.props.editable).toBe(false);
    expect(doc.controller.getSavedFields(doc.handle)).toEqual({});
    doc.unmount();
  }
});

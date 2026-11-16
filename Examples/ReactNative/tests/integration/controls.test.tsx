import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { library } from '../../src/library';
import { NativeContentProvider } from '../../src/library/components/contentPolicy';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from '../../src/runtime/message';
import { capturePress } from './native-events';

const controllers = new Set<MessageController>();

afterEach(() => {
  for (const controller of controllers) controller.dispose();
  controllers.clear();
});

function complete(source: string) {
  const controller = createMessageController('controls');
  controllers.add(controller);
  const handle = controller.begin(source);
  controller.complete(handle);
  return controller;
}

test('required and email validation follows real edits, and @Reset restores both value and validation', async () => {
  const controller = complete(`root = Stack([email, reset])
$email = "seed@example.com"
email = Input("email", "Email", "email", {required: true, email: true}, $email)
reset = Button("Reset email", @Reset($email))
`);
  render(<OpenUIDocument message={controller} library={library} />);
  expect(screen.queryByText('This field is required')).not.toBeOnTheScreen();

  fireEvent.changeText(screen.getByLabelText('Email'), '');
  fireEvent(screen.getByLabelText('Email'), 'blur');
  expect(screen.getByText('This field is required')).toBeOnTheScreen();
  expect(screen.getByLabelText('Email').props.accessibilityHint).toBe('This field is required');

  fireEvent.changeText(screen.getByLabelText('Email'), 'invalid-address');
  expect(screen.queryByText('This field is required')).not.toBeOnTheScreen();
  expect(screen.getByText('Please enter a valid email')).toBeOnTheScreen();

  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Reset email' })); });
  expect(screen.getByLabelText('Email')).toHaveDisplayValue('seed@example.com');
  expect(screen.queryByText('Please enter a valid email')).not.toBeOnTheScreen();
  expect(screen.queryByText('This field is required')).not.toBeOnTheScreen();
});

test('numeric validation preserves the user draft and clears after a valid correction', () => {
  const controller = complete(`root = Stack([amount, preview])
$amount = "5"
amount = Input("amount", "Amount", "number", {numeric: true, min: 1, max: 10}, $amount)
preview = TextContent("Amount: " + $amount)
`);
  render(<OpenUIDocument message={controller} library={library} />);

  fireEvent.changeText(screen.getByLabelText('Amount'), 'not a number');
  fireEvent(screen.getByLabelText('Amount'), 'blur');
  expect(screen.getByLabelText('Amount')).toHaveDisplayValue('not a number');
  expect(screen.getByLabelText('Amount').props.accessibilityHint).toBeTruthy();
  expect(screen.getByText('Amount: not a number')).toBeOnTheScreen();

  fireEvent.changeText(screen.getByLabelText('Amount'), '11');
  expect(screen.getByLabelText('Amount').props.accessibilityHint).toBeTruthy();
  fireEvent.changeText(screen.getByLabelText('Amount'), '7');
  expect(screen.getByLabelText('Amount')).toHaveDisplayValue('7');
  expect(screen.getByLabelText('Amount').props.accessibilityHint).toBeUndefined();
  expect(screen.getByText('Amount: 7')).toBeOnTheScreen();
});

test('a failed host action is reported without an unhandled rejection, duplicate dispatch, or a stuck button', async () => {
  const controller = complete('root = Stack([Button("Try action", @ToAssistant("Try", {id: "item"}))])');
  const failure = new Error('Host refused the action');
  const onAction = jest.fn().mockImplementationOnce(() => { throw failure; });
  const onContentError = jest.fn();
  render(<NativeContentProvider onError={onContentError}>
    <OpenUIDocument message={controller} library={library} onAction={onAction} />
  </NativeContentProvider>);
  const press = capturePress('Try action');

  await act(async () => {
    press();
    press(); // Both native events arrive before React can commit disabled=true.
  });
  expect(onAction).toHaveBeenCalledTimes(1);
  expect(onContentError).toHaveBeenCalledTimes(1);
  expect(onContentError).toHaveBeenCalledWith(failure);
  expect(screen.getByText('操作暂时未完成，请重试。')).toBeOnTheScreen();
  expect(screen.getByRole('button', { name: 'Try action' })).toBeEnabled();

  await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Try action' })); });
  expect(onAction).toHaveBeenCalledTimes(2);
  expect(screen.queryByText('操作暂时未完成，请重试。')).not.toBeOnTheScreen();
  expect(screen.getByRole('button', { name: 'Try action' })).toBeEnabled();
});

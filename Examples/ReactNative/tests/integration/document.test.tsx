import { useEffect } from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import {
  BuiltinActionType,
  Renderer,
  defineComponent,
  type RendererProps,
} from '@openuidev/react-lang';
import { library } from '../../src/library';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import {
  createMessageController,
  type FrameScheduler,
  type MessageController,
} from '../../src/runtime/message';
import { capturePress } from './native-events';

const controllers = new Set<MessageController>();

afterEach(() => {
  for (const controller of controllers) controller.dispose();
  controllers.clear();
});

function frames() {
  const queue: { run: () => void; cancelled: boolean }[] = [];
  const schedule: FrameScheduler = run => {
    const frame = { run, cancelled: false };
    queue.push(frame);
    return () => { frame.cancelled = true; };
  };
  return {
    schedule,
    flush() {
      for (const frame of queue.splice(0)) if (!frame.cancelled) frame.run();
    },
  };
}

function documentSource(initial = 'Initial', tail = 'Ready') {
  return `root = Stack([field, preview, clear, submit, tail], "column", "m")
$name = ${JSON.stringify(initial)}
field = Input("name", "Name", "text", null, $name)
preview = TextContent("Value: " + $name)
clear = Button("Clear", @Set($name, ""), "secondary")
submit = Button("Send", @ToAssistant("Send", {name: $name}))
tail = TextContent(${JSON.stringify(tail)})
`;
}

function message(source: string, options: {
  complete?: boolean;
  messageId?: string;
  maxSourceCodeUnits?: number;
  fields?: Record<string, unknown>;
} = {}) {
  const clock = frames();
  const controller = createMessageController(options.messageId ?? 'message', {
    schedule: clock.schedule,
    maxSourceCodeUnits: options.maxSourceCodeUnits,
  });
  controllers.add(controller);
  const handle = controller.getHandle();
  if (options.fields) controller.saveFields(handle, options.fields);
  controller.append(handle, source);
  if (options.complete === false) clock.flush();
  else controller.complete(handle);
  return { controller, handle, clock };
}

/** Observe React identity while retaining the production Input implementation. */
function observedLibrary() {
  const mounts = jest.fn();
  const unmounts = jest.fn();
  const input = library.components.Input;
  const NativeInput = input.component;
  const observed = library.extend({
    components: { override: [defineComponent({
      name: input.name,
      props: input.props,
      description: input.description,
      component: props => {
        useEffect(() => {
          mounts();
          return () => { unmounts(); };
        }, []);
        return <NativeInput {...props} />;
      },
    })] },
  });
  return { library: observed, mounts, unmounts };
}

const staleAction = {
  type: BuiltinActionType.ContinueConversation,
  params: { name: 'retired' },
  humanFriendlyMessage: 'Retired action',
};

describe('official OpenUI native runtime', () => {
  test('an unbound field saves each official Store snapshot only once', () => {
    const { controller, handle } = message('root = Stack([Input("name", "Name", "text", null, "")], "column", "m")');
    const save = jest.spyOn(controller, 'saveFields');
    render(<OpenUIDocument message={controller} library={library} />);
    save.mockClear();
    fireEvent.changeText(screen.getByLabelText('Name'), 'Finn');
    expect(save).toHaveBeenCalledTimes(1);
    expect(controller.getSavedFields(handle)).toMatchObject({ name: { value: 'Finn' } });
    fireEvent.changeText(screen.getByLabelText('Name'), 'Updated');
    expect(save).toHaveBeenCalledTimes(2);
    expect(controller.getSavedFields(handle)).toMatchObject({ name: { value: 'Updated' } });
  });

  test('a successful save after remount clears an earlier persistence failure', () => {
    const { controller, handle } = message(documentSource());
    const onPersistenceError = jest.fn();
    const first = render(<OpenUIDocument message={controller} library={library}
      onPersistenceError={onPersistenceError} />);
    fireEvent.changeText(screen.getByLabelText('Name'), 'Saved');
    fireEvent.changeText(screen.getByLabelText('Name'), 'x'.repeat(64 * 1024));
    expect(onPersistenceError).toHaveBeenLastCalledWith(expect.any(RangeError));
    expect(controller.getSavedFields(handle)).toMatchObject({ $name: 'Saved' });
    first.unmount();

    render(<OpenUIDocument message={controller} library={library}
      onPersistenceError={onPersistenceError} />);
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Saved');
    fireEvent.changeText(screen.getByLabelText('Name'), 'Recovered');
    expect(controller.getError()).toBeNull();
    expect(controller.getSavedFields(handle)).toMatchObject({ $name: 'Recovered' });
    expect(onPersistenceError).toHaveBeenLastCalledWith(null);
    const recoveredCalls = onPersistenceError.mock.calls.length;
    fireEvent.changeText(screen.getByLabelText('Name'), 'Still healthy');
    expect(onPersistenceError).toHaveBeenCalledTimes(recoveredCalls);
  });

  test('a real field writes the shared binding, persists it, and emits one host action', async () => {
    const { controller, handle } = message(documentSource());
    const onAction = jest.fn();
    render(<OpenUIDocument message={controller} library={library} onAction={onAction} />);

    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Initial');
    fireEvent.changeText(screen.getByLabelText('Name'), 'Finn');
    expect(screen.getByText('Value: Finn')).toBeOnTheScreen();
    expect(controller.getSavedFields(handle)).toMatchObject({ $name: 'Finn' });

    await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Send' })); });
    expect(onAction).toHaveBeenCalledTimes(1);
    expect(onAction).toHaveBeenCalledWith(expect.objectContaining({
      type: BuiltinActionType.ContinueConversation,
      humanFriendlyMessage: 'Send',
      params: { context: { name: 'Finn' } },
    }));

    await act(async () => { fireEvent.press(screen.getByRole('button', { name: 'Clear' })); });
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('');
    expect(screen.getByText(/^Value:\s*$/)).toBeOnTheScreen();
    expect(controller.getSavedFields(handle)).toMatchObject({ $name: '' });
    expect(onAction).toHaveBeenCalledTimes(1); // @Set is local state, not a host effect.
  });

  test('streamed tail updates preserve the mounted field and hydrated binding', () => {
    const observed = observedLibrary();
    const prefix = documentSource('Generated default').replace('tail = TextContent("Ready")\n',
      'tail = TextContent("Part');
    const { controller, handle, clock } = message(prefix, {
      complete: false,
      fields: { $name: 'Restored draft' },
    });
    render(<OpenUIDocument message={controller} library={observed.library} />);
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Restored draft');
    expect(screen.getByLabelText('Name')).toBeDisabled();
    expect(observed.mounts).toHaveBeenCalledTimes(1);

    act(() => {
      controller.append(handle, ' one');
      controller.append(handle, ' and two")\n');
      clock.flush();
    });
    expect(screen.getByText('Part one and two')).toBeOnTheScreen();
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Restored draft');
    expect(observed.mounts).toHaveBeenCalledTimes(1);
    expect(observed.unmounts).not.toHaveBeenCalled();

    act(() => { controller.complete(handle); });
    expect(screen.getByLabelText('Name')).toBeEnabled();
    expect(observed.mounts).toHaveBeenCalledTimes(1);
    fireEvent.changeText(screen.getByLabelText('Name'), 'Edited after completion');
    expect(screen.getByText('Value: Edited after completion')).toBeOnTheScreen();
    expect(controller.getSavedFields(handle)).toMatchObject({ $name: 'Edited after completion' });
  });

  test('unmount/remount restores field values and rejects callbacks from the retired mount', () => {
    const { controller, handle } = message(documentSource());
    const onAction = jest.fn();
    const onError = jest.fn();
    const first = render(<OpenUIDocument message={controller} library={library}
      onAction={onAction} onError={onError} />);
    fireEvent.changeText(screen.getByLabelText('Name'), 'Saved edit');
    const retired = first.UNSAFE_getByType(Renderer).props as RendererProps;
    first.unmount();

    render(<OpenUIDocument message={controller} library={library}
      onAction={onAction} onError={onError} />);
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Saved edit');
    expect(screen.getByText('Value: Saved edit')).toBeOnTheScreen();
    onError.mockClear();

    act(() => {
      retired.onStateUpdate?.({ $name: 'Late stale write' });
      retired.onAction?.(staleAction);
      retired.onError?.([{ source: 'runtime', code: 'render-error', message: 'Retired error' }]);
    });
    expect(controller.getSavedFields(handle)).toMatchObject({ $name: 'Saved edit' });
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Saved edit');
    expect(onAction).not.toHaveBeenCalled();
    expect(onError).not.toHaveBeenCalled();
  });

  test('a new epoch isolates both renderer callbacks and native handlers before React commits', async () => {
    const { controller, handle: retiredHandle } = message(documentSource());
    const onAction = jest.fn();
    const result = render(<OpenUIDocument message={controller} library={library} onAction={onAction} />);
    fireEvent.changeText(screen.getByLabelText('Name'), 'Old edit');
    const retired = result.UNSAFE_getByType(Renderer).props as RendererProps;
    const lateChange = screen.getByLabelText('Name').props.onChangeText;
    const latePress = capturePress('Send');

    await act(async () => {
      const current = controller.begin(documentSource('New epoch'));
      // These closures were captured while enabled, before begin retired them.
      lateChange('Late native event');
      await latePress();
      retired.onStateUpdate?.({ $name: 'Late renderer callback' });
      retired.onAction?.(staleAction);
      controller.complete(current);
    });

    expect(controller.getSavedFields(retiredHandle)).toBeUndefined();
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('New epoch');
    expect(screen.getByText('Value: New epoch')).toBeOnTheScreen();
    expect(onAction).not.toHaveBeenCalled();
    expect(controller.getSavedFields(controller.getHandle())?.$name).not.toBe('Late renderer callback');
  });

  test('different controllers with the same public id and epoch do not share a live Store', () => {
    const first = message(documentSource('First'), { messageId: 'same-id' });
    const second = message(documentSource('Second'), { messageId: 'same-id' });
    const onAction = jest.fn();
    expect(first.handle.epoch).toBe(second.handle.epoch);
    const result = render(<OpenUIDocument message={first.controller} library={library} onAction={onAction} />);
    fireEvent.changeText(screen.getByLabelText('Name'), 'First edited');
    const retired = result.UNSAFE_getByType(Renderer).props as RendererProps;

    result.rerender(<OpenUIDocument message={second.controller} library={library} onAction={onAction} />);
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Second');
    act(() => {
      retired.onStateUpdate?.({ $name: 'Wrong controller' });
      retired.onAction?.(staleAction);
    });
    expect(first.controller.getSavedFields(first.handle)).toMatchObject({ $name: 'First edited' });
    expect(second.controller.getSavedFields(second.handle)?.$name).not.toBe('Wrong controller');
    expect(onAction).not.toHaveBeenCalled();
  });

  test('changing the library starts a fresh renderer mount and restores the saved field', () => {
    const observed = observedLibrary();
    const { controller } = message(documentSource());
    const result = render(<OpenUIDocument message={controller} library={observed.library} />);
    fireEvent.changeText(screen.getByLabelText('Name'), 'Keep this edit');
    expect(observed.mounts).toHaveBeenCalledTimes(1);

    const text = observed.library.components.TextContent;
    const NativeText = text.component;
    const replacementLibrary = observed.library.extend({
      components: { override: [defineComponent({
        name: text.name,
        props: text.props,
        description: text.description,
        component: props => <NativeText {...props}
          props={{ ...props.props, text: `Replacement: ${props.props.text}` }} />,
      })] },
    });
    result.rerender(<OpenUIDocument message={controller} library={replacementLibrary} />);
    expect(observed.mounts).toHaveBeenCalledTimes(2);
    expect(observed.unmounts).toHaveBeenCalledTimes(1);
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Keep this edit');
    expect(screen.getByText('Replacement: Value: Keep this edit')).toBeOnTheScreen();
  });

  test('interrupt flushes accepted input, freezes the preview, and ignores late input and actions', async () => {
    const prefix = documentSource('Frozen value').replace('tail = TextContent("Ready")\n',
      'tail = TextContent("Unfinished');
    const { controller, handle } = message(prefix, { complete: false });
    const onAction = jest.fn();
    render(<OpenUIDocument message={controller} library={library} onAction={onAction} />);
    const lateChange = screen.getByLabelText('Name').props.onChangeText;
    const latePress = capturePress('Send');

    await act(async () => {
      controller.append(handle, ' accepted tail');
      controller.interrupt(handle);
      lateChange('Ignored after stop');
      await latePress();
    });

    expect(controller.getSnapshot()).toMatchObject({
      phase: 'interrupted', source: prefix + ' accepted tail',
    });
    expect(controller.append(handle, '")')).toBe(false);
    expect(controller.complete(handle)).toBe(false);
    expect(screen.getByLabelText('Name')).toBeDisabled();
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Frozen value');
    expect(screen.getByRole('button', { name: 'Send' })).toBeDisabled();
    expect(onAction).not.toHaveBeenCalled();
  });

  test('an input budget failure keeps accepted source visible and a new epoch can recover', () => {
    const source = documentSource('Before error');
    const { controller, handle } = message(source, {
      complete: false, maxSourceCodeUnits: source.length + 32,
    });
    render(<OpenUIDocument message={controller} library={library} />);
    act(() => { expect(controller.append(handle, 'x'.repeat(64))).toBe(false); });
    expect(controller.getSnapshot()).toMatchObject({ phase: 'error', source });
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Before error');
    expect(screen.getByLabelText('Name')).toBeDisabled();

    act(() => {
      const next = controller.begin(documentSource('Recovered'));
      controller.complete(next);
    });
    expect(controller.getError()).toBeNull();
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Recovered');
    expect(screen.getByLabelText('Name')).toBeEnabled();
    fireEvent.changeText(screen.getByLabelText('Name'), 'Editable again');
    expect(screen.getByText('Value: Editable again')).toBeOnTheScreen();
  });

  test('actual parser diagnostics clear after a valid replacement', async () => {
    const { controller } = message('root = MissingNativeComponent("bad input")');
    const onError = jest.fn();
    render(<OpenUIDocument message={controller} library={library} onError={onError} />);
    await waitFor(() => {
      expect(onError.mock.calls.some(([errors]) => errors.length > 0)).toBe(true);
    });

    act(() => {
      const handle = controller.begin(documentSource('Valid replacement'));
      controller.complete(handle);
    });
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('Valid replacement');
    await waitFor(() => { expect(onError).toHaveBeenLastCalledWith([]); });
  });

  test('a root runtime failure freezes the document until a new epoch restores a healthy library', () => {
    const failure = new Error('Integration fixture: schema lookup failed');
    const reportConsoleError = console.error;
    jest.spyOn(console, 'error').mockImplementation((...args) => {
      // React reports a deliberately injected boundary error to the console.
      // Keep unrelated warnings/errors visible rather than silencing the suite.
      if (args.some(value => value === failure
        || (typeof value === 'string' && value.includes(failure.message)))) return;
      reportConsoleError(...args);
    });
    const brokenLibrary = { ...library, toJSONSchema: () => { throw failure; } };
    const { controller } = message(documentSource());
    const onError = jest.fn();
    const result = render(<OpenUIDocument message={controller} library={brokenLibrary} onError={onError} />);

    expect(controller.getSnapshot().phase).toBe('error');
    expect(controller.getError()).toBe(failure);
    expect(onError).toHaveBeenCalledWith([{
      source: 'runtime', code: 'render-error', message: failure.message,
    }]);

    result.rerender(<OpenUIDocument message={controller} library={library} onError={onError} />);
    expect(controller.getSnapshot().phase).toBe('error');
    expect(screen.getByLabelText('Name')).toBeDisabled();

    act(() => {
      const recovered = controller.begin(documentSource('After runtime recovery'));
      controller.complete(recovered);
    });
    expect(controller.getError()).toBeNull();
    expect(screen.getByLabelText('Name')).toHaveDisplayValue('After runtime recovery');
    expect(screen.getByLabelText('Name')).toBeEnabled();
  });

  test('the root boundary also contains an unprintable thrown value', () => {
    const cause = Object.create(null);
    const reportConsoleError = console.error;
    jest.spyOn(console, 'error').mockImplementation((...args) => {
      if (args.some(value => value === cause)) return;
      reportConsoleError(...args);
    });
    const brokenLibrary = { ...library, toJSONSchema: () => { throw cause; } };
    const { controller } = message(documentSource());
    const onError = jest.fn();
    render(<OpenUIDocument message={controller} library={brokenLibrary} onError={onError} />);
    expect(controller.getSnapshot().phase).toBe('error');
    expect(controller.getError()).toBeInstanceOf(Error);
    expect(onError).toHaveBeenCalledWith([{
      source: 'runtime', code: 'render-error', message: 'Error details could not be read',
    }]);
  });
});

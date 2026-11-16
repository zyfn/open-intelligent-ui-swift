import { act, render } from '@testing-library/react-native';
import { library, NativeContentProvider } from '../../src/library';
import { OpenUIDocument } from '../../src/runtime/OpenUIDocument';
import { createMessageController } from '../../src/runtime/message';
import { componentSamples } from '../../src/demo/componentSamples';
import catalog from '../../src/library/catalog.generated.json';

test('the native registry covers exactly the exported OpenUI contract and every existing component example', () => {
  const registered = Object.keys(library.components).sort();
  expect(registered).toEqual(catalog.components.map(component => component.name).sort());
  expect(registered).toEqual(componentSamples.map(sample => sample.label).sort());
  expect(registered).toHaveLength(87);
});

test.each(componentSamples)('renders the unchanged $label OpenUI Gallery program through the official runtime', async sample => {
  const message = createMessageController(sample.id);
  message.complete(message.begin(sample.source));
  const onError = jest.fn();
  const consoleErrors: unknown[][] = [];
  const error = jest.spyOn(console, 'error').mockImplementation((...args: unknown[]) => { consoleErrors.push(args); });
  const tree = render(<NativeContentProvider resolveImage={() => 1}>
    <OpenUIDocument message={message} library={library} onError={onError} />
  </NativeContentProvider>);
  try {
    await act(async () => {});
    expect(message.getSnapshot().phase).toBe('complete');
    expect(onError.mock.calls.flatMap(call => call[0])).toEqual([]);
    expect(consoleErrors).toEqual([]);
    expect(tree.toJSON()).not.toBeNull();
  } finally {
    tree.unmount(); message.dispose(); error.mockRestore();
  }
});

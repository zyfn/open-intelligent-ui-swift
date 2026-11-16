import { Text } from 'react-native';
import { render, screen } from '@testing-library/react-native';
import { Renderer, createLibrary, defineComponent } from '@openuidev/react-lang';
import { createStreamingParser } from '@openuidev/lang-core';
import { z } from 'zod/v4';

const NativeText = defineComponent({
  name: 'NativeText',
  description: 'A native text leaf for the integration harness.',
  props: z.object({ text: z.string() }),
  component: ({ props }) => <Text>{props.text}</Text>,
});
const nativeLibrary = createLibrary({ root: 'NativeText', components: [NativeText] });

test('standard native host mocks run the actual published Renderer and language core', () => {
  expect(require.resolve('@openuidev/react-lang')).toMatch(/index\.native\.cjs$/);
  expect(jest.isMockFunction(Renderer)).toBe(false);
  expect(jest.isMockFunction(createStreamingParser)).toBe(false);

  render(<Renderer library={nativeLibrary} response={'root = NativeText("Native runtime mounted")'}
    publishObservability={false} />);
  expect(screen.getByText('Native runtime mounted')).toBeOnTheScreen();
});

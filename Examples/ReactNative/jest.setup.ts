// Registers the library's native matchers and per-test cleanup. Do not replace
// @openuidev/react-lang or @openuidev/lang-core with test doubles.
import '@testing-library/react-native';

// MapLibre needs an actual native map surface. Mock only that SDK's native
// view/camera boundary; our map behavior and the official OpenUI runtime run.
jest.mock('@maplibre/maplibre-react-native', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    Map: React.forwardRef((props: Record<string, unknown>, ref: unknown) => React.createElement(View, { ...props, ref })),
    Marker: (props: Record<string, unknown>) => React.createElement(View, props),
    Camera: ({ ref }: { ref: unknown }) => {
      React.useImperativeHandle(ref, () => ({ fitBounds: jest.fn(), easeTo: jest.fn(), jumpTo: jest.fn() }));
      return null;
    },
  };
});

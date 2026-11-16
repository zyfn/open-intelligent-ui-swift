import { act, fireEvent, render } from '@testing-library/react-native';
import mockSafeAreaContext from 'react-native-safe-area-context/jest/mock';
import App from '../../App';

jest.mock('react-native-safe-area-context', () => mockSafeAreaContext);

test('Gallery searches the OpenUI component catalog and opens the original native example', async () => {
  const tree = render(<App />);
  fireEvent.press(tree.getByRole('button', { name: '打开OpenUI组件目录' }));
  expect(tree.getByRole('tab', { name: '组件 · 87' })).toBeTruthy();
  fireEvent.changeText(tree.getByLabelText('搜索OpenUI组件'), 'TextArea');
  fireEvent.press(tree.getByRole('button', { name: '打开TextArea样例' }));
  expect(tree.queryByLabelText('搜索OpenUI组件')).toBeNull();
  expect(tree.getByText('01 / TextArea')).toBeTruthy();
  fireEvent.press(tree.getByRole('button', { name: '打开OpenUI组件目录' }));
  fireEvent.changeText(tree.getByLabelText('搜索OpenUI组件'), 'nothing-matches');
  expect(tree.getByText('没有匹配的内容')).toBeTruthy();
  fireEvent.press(tree.getByRole('button', { name: '关闭组件目录' }));
  expect(tree.getByText('01 / TextArea')).toBeTruthy();
  tree.unmount(); await act(async () => {});
});

test('the original interaction sample explicitly resets both official variables', async () => {
  const tree = render(<App />);
  fireEvent.press(tree.getByRole('button', { name: '添加交互样例' }));
  fireEvent.changeText(tree.getByLabelText('至少两个字符'), 'Finn');
  fireEvent.changeText(tree.getByLabelText('name@example.com'), 'finn@example.com');
  await act(async () => { fireEvent.press(tree.getByRole('button', { name: '清空输入' })); });
  expect(tree.getByLabelText('至少两个字符').props.value).toBe('');
  expect(tree.getByLabelText('name@example.com').props.value).toBe('');
  tree.unmount(); await act(async () => {});
});

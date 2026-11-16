import { screen } from '@testing-library/react-native';

/** Capture the public callback before Pressability turns it into responder handlers. */
export function capturePress(label: string): () => void | Promise<void> {
  let node = screen.getByRole('button', { name: label });
  while (typeof node.props.onPress !== 'function') {
    if (!node.parent) throw new Error(`No press callback for ${label}`);
    node = node.parent;
  }
  return node.props.onPress;
}

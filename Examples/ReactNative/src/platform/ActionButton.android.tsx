import { ActionButtonBase, type ActionButtonProps } from './ActionButtonBase';

export default function ActionButton(props: ActionButtonProps) {
  return <ActionButtonBase {...props} radius={24} ripple={{ color: '#FFFFFF30' }} />;
}

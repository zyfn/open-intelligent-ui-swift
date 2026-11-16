import { useState } from 'react';
import { ActivityIndicator, Pressable, Text, View, type PressableProps } from 'react-native';
import { useOpenUITheme } from '../library/theme';

export type ActionButtonProps = {
  label: string;
  disabled: boolean;
  onPress: () => void;
  variant: string;
  type: string;
  size: string;
  busy?: boolean;
};

export function ActionButtonBase({ label, disabled, onPress, variant, type, size, busy = false,
  radius, ripple }: ActionButtonProps & { radius: number; ripple?: PressableProps['android_ripple'] }) {
  const theme = useOpenUITheme();
  const [focused, setFocused] = useState(false);
  const accent = type === 'destructive' ? theme.destructive : theme.accent;
  const primary = variant === 'primary';
  const foreground = primary
    ? type === 'destructive' ? theme.onDestructive : theme.onAccent
    : accent;
  const fontSize = size === 'extra-small' ? 13 : size === 'small' ? 14 : size === 'large' ? 17 : 16;
  const paddingHorizontal = size === 'extra-small' ? 12 : size === 'small' ? 14 : size === 'large' ? 22 : 18;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled, busy }}
      disabled={disabled}
      onPress={onPress}
      onFocus={() => setFocused(true)}
      onBlur={() => setFocused(false)}
      android_ripple={ripple ? { ...ripple, color: primary ? '#FFFFFF30' : '#80808026' } : undefined}
      style={({ pressed }) => ({
        minHeight: Math.max(theme.controlMinHeight, size === 'large' ? 56 : 0),
        minWidth: 0, flexShrink: 1, borderRadius: radius, paddingHorizontal, paddingVertical: 10,
        borderWidth: 2, borderColor: focused ? primary ? foreground : theme.focus : 'transparent',
        justifyContent: 'center', alignItems: 'center',
        backgroundColor: primary ? accent : variant === 'secondary' ? theme.surfaceMuted : 'transparent',
        opacity: disabled && !busy ? 0.55 : pressed ? 0.75 : 1,
      })}
    >
      <View pointerEvents="none" style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
        gap: 8, minWidth: 0, maxWidth: '100%', flexShrink: 1 }}>
        {busy ? <ActivityIndicator color={foreground} accessible={false} size="small" /> : null}
        <Text style={{ color: foreground, fontSize, lineHeight: Math.ceil(fontSize * 1.4),
          fontWeight: '600', textAlign: 'center', minWidth: 0, flexShrink: 1 }}>{label}</Text>
      </View>
    </Pressable>
  );
}

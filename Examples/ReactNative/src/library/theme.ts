import { createContext, createElement, useContext, useMemo, type ReactNode } from 'react';
import { useColorScheme } from 'react-native';

// Presentation tokens belong to the RN renderer; they do not change Lang values.
const gap = { none: 0, xs: 4, s: 8, m: 12, l: 16, xl: 24, '2xl': 32 } as const;

export type NativeTheme = {
  background: string;
  surface: string;
  surfaceMuted: string;
  ink: string;
  muted: string;
  border: string;
  accent: string;
  onAccent: string;
  destructive: string;
  onDestructive: string;
  focus: string;
  code: string;
  gap: Record<keyof typeof gap, number>;
  controlMinHeight: number;
};

export const theme: NativeTheme = {
  background: '#F4F3EF',
  surface: '#FFFFFF',
  surfaceMuted: '#EAF0EB',
  ink: '#202521',
  muted: '#5E6961',
  border: '#CAD3CC',
  accent: '#28664D',
  onAccent: '#FFFFFF',
  destructive: '#B33737',
  onDestructive: '#FFFFFF',
  focus: '#28664D',
  code: '#EDEFEA',
  gap,
  controlMinHeight: 48,
};

const darkTheme: NativeTheme = {
  background: '#141815',
  surface: '#1D241F',
  surfaceMuted: '#29332C',
  ink: '#F0F4F0',
  muted: '#B2BEB4',
  border: '#48584C',
  accent: '#A1D8B6',
  onAccent: '#102C1C',
  destructive: '#FFB4B4',
  onDestructive: '#4B1010',
  focus: '#A1D8B6',
  code: '#29302B',
  gap,
  controlMinHeight: 48,
};

const ThemeContext = createContext<NativeTheme | undefined>(undefined);
type ThemeOverrides = Omit<Partial<NativeTheme>, 'gap'> & { gap?: Partial<NativeTheme['gap']> };

export function NativeThemeProvider({ children, overrides, colorScheme = 'system' }: {
  children: ReactNode;
  overrides?: ThemeOverrides;
  colorScheme?: 'light' | 'dark' | 'system';
}) {
  const systemScheme = useColorScheme();
  const base = (colorScheme === 'system' ? systemScheme : colorScheme) === 'dark' ? darkTheme : theme;
  const value = useMemo(() => ({ ...base, ...overrides, gap: { ...base.gap, ...overrides?.gap } }), [base, overrides]);
  return createElement(ThemeContext.Provider, { value }, children);
}

export function useOpenUITheme(): NativeTheme {
  const supplied = useContext(ThemeContext);
  const scheme = useColorScheme();
  return supplied ?? (scheme === 'dark' ? darkTheme : theme);
}

/** Native host mocks come from Expo; OpenUI's renderer and language core stay real. */
module.exports = {
  preset: 'jest-expo',
  testMatch: ['<rootDir>/tests/integration/**/*.test.ts?(x)'],
  testEnvironmentOptions: {
    customExportConditions: ['react-native'],
  },
  // Expo 55's standard allowance plus the two ESM-only Markdown dependencies.
  // Transform their real code; replacing the parser would hide integration errors.
  transformIgnorePatterns: [
    '/node_modules/(?!(.pnpm|react-native|@react-native|@react-native-community|expo|@expo|@expo-google-fonts|react-navigation|@react-navigation|@sentry/react-native|native-base|marked|entities))',
    '/node_modules/react-native-reanimated/plugin/',
  ],
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
  clearMocks: true,
  restoreMocks: true,
};

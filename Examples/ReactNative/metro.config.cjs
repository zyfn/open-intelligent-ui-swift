const { getDefaultConfig } = require('expo/metro-config');
const path = require('node:path');

const config = getDefaultConfig(__dirname);
// Reuse the existing, credited images, component examples and generated icons.
config.watchFolders = [path.resolve(__dirname, '../Gallery/Resources'),
  path.resolve(__dirname, '../../Sources/SwiftOpenUI/Resources')];
module.exports = config;

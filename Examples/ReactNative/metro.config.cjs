const { getDefaultConfig } = require('expo/metro-config');
const path = require('node:path');

const config = getDefaultConfig(__dirname);
// Reuse the existing, credited Gallery photograph. No runtime or package aliases.
config.watchFolders = [path.resolve(__dirname, '../Gallery/Resources/Images')];
module.exports = config;

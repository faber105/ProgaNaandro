const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);
const aliases = {
  stream: require.resolve('stream-browserify'),
  events: require.resolve('events'),
  buffer: require.resolve('buffer'),
  process: require.resolve('process/browser'),
  util: require.resolve('util'),
  zlib: require.resolve('./zlib-shim'),
};

config.resolver.extraNodeModules = aliases;
const defaultResolveRequest = config.resolver.resolveRequest;
config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (aliases[moduleName]) return { type: 'sourceFile', filePath: aliases[moduleName] };
  return defaultResolveRequest
    ? defaultResolveRequest(context, moduleName, platform)
    : context.resolveRequest(context, moduleName, platform);
};

config.serializer.getModulesRunBeforeMainModule = () => [
  require.resolve('./polyfills.js'),
];

module.exports = config;

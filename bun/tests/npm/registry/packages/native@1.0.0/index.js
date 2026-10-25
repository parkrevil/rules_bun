// Returns the name of the platform package it loads for this platform.
const candidates = {
  "linux-x64": ["native-linux-x64", "native-linux-x64-musl"],
  "linux-arm64": ["native-linux-arm64"],
  "darwin-x64": ["native-darwin-x64"],
  "darwin-arm64": ["native-darwin-arm64"],
  "win32-x64": ["native-win32-x64"],
}[`${process.platform}-${process.arch}`] ?? [];
function load() {
  for (const candidate of candidates) {
    try {
      return require(candidate).name;
    } catch {}
  }
  throw new Error(`native: no platform package for ${process.platform}-${process.arch}`);
}
module.exports = load();

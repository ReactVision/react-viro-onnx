// Expo config plugin entry point.
// Expo resolves `app.plugin.js` at the package root when "@reactvision/react-viro-onnx"
// is listed in the app's plugins array. It delegates to the compiled plugin which adds
// the ViroReactONNX pod (iOS) and the onnxruntime-android dependency (Android).
module.exports = require("./plugin/build/withViroONNX").default;

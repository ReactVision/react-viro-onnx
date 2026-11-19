# Applied to the app that depends on this library, so a release build with R8
# (Expo SDK 58 turns it on by default) keeps what the native side needs.

# ONNX Runtime's JNI library (libonnxruntime4j_jni.so) builds TensorInfo,
# OrtException, OnnxModelMetadata and others through constructors no Java code
# calls, and ONNX Runtime ships no R8 rules of its own. Stripped, a model load or
# a detection aborts the app natively.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# This module's native methods keep their names and signatures for JNI.
-keepclasseswithmembernames,includedescriptorclasses class com.reactvision.viroonnx.** {
    native <methods>;
}

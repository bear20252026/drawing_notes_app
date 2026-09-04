# R8 混淆规则（外部审计 L2：release 启用 minify + 资源收缩）。
#
# Dart 代码由 AOT 编译为 libapp.so，不参与 Java/Kotlin 混淆；
# 本文件只约束 Android 原生插件层。各插件自带 consumer-rules 已保留
# 其反射入口，以下仅列本项目实测需要的额外保留项。

# flutter_secure_storage 通过反射与 Windows Credential Manager / Android
# Keystore 桥接，保守保留其数据模型，避免 release 收缩破坏凭据读写。
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# local_auth（生物识别快速解锁）经由 FragmentActivity 与 BiometricPrompt
# 交互，保留其回调桥接类。
-keep class androidx.biometric.** { *; }

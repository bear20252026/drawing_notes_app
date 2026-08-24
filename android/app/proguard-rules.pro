# ProGuard/R8 规则——绘图笔记应用（安全加固 P0）
# 保留 Flutter、Riverpod、加密库等关键类不被混淆。

# ==================== Flutter 框架 ====================
# Flutter 引擎和插件的必要保留。
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }
-dontwarn io.flutter.**

# Flutter 生成的插件注册。
-keep class com.example.drawing_notes_app.** { *; }
-keep class io.flutter.plugins.** { *; }

# ==================== Dart/Flutter 序列化 ====================
# 保留 toString() 和 toJson() 方法（JSON 序列化需要）。
-keepclassmembers class * {
    *** toJson();
    *** fromJson();
    java.lang.String toString();
}

# 保留 @JsonKey 注解的字段。
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ==================== Riverpod 状态管理 ====================
# Riverpod 使用反射生成 Provider，需保留相关类。
-keep class flutter_riverpod.** { *; }
-keep class riverpod.** { *; }
-keep class * extends flutter_riverpod.** { *; }
-dontwarn flutter_riverpod.**
-dontwarn riverpod.**

# ==================== 加密库 ====================
# cryptography 和 crypto 库的安全类。
-keep class cryptography.** { *; }
-keep class crypto.** { *; }
-dontwarn cryptography.**
-dontwarn crypto.**

# ==================== PDF 处理 ====================
# pdfrx 和 pdfx 库。
-keep class com.tom-roush.pdfbox.** { *; }
-keep class io.whiletrue.pdfrx.** { *; }
-dontwarn com.tom-roush.pdfbox.**
-dontwarn io.whiletrue.pdfrx.**

# ==================== 网络/同步 ====================
# Nextcloud/WebDAV 同步相关。
-keep class ch.ethz.** { *; }
-dontwarn ch.ethz.**

# ==================== 文件操作 ====================
# path_provider 和 file_picker。
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**
-dontwarn com.mr.flutter.plugin.filepicker.**

# ==================== 安全存储 ====================
# flutter_secure_storage。
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ==================== 通用规则 ====================
# 保留枚举值。
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 保留 Parcelable。
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# 保留 Serializable。
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# 保留 R 文件 资源引用。
-keepclassmembers class **.R$* {
    public static <fields>;
}

# 保留自定义 View 构造函数。
-keepclasseswithmembers class * {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# 不要移除 debug 信息（保留行号用于崩溃报告）。
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

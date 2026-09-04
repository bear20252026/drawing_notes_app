import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

plugins {

    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "gov.drawingnotes.drawing_notes_app"
    // flutter_secure_storage v11 要求 compileSdk >= 37（AAR 元数据硬约束）。
    // AGP 9.0.1 默认推荐上限 36 仅为软警告；SDK 37 在 GitHub Actions 运行器上可用。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "gov.drawingnotes.drawing_notes_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // A production APK/AAB must never silently use the debug key.
            signingConfig = signingConfigs.getByName("release")
            // R8 混淆 + 资源收缩（外部审计 L2）：Dart AOT 与 Java/Kotlin 插件代码
            // 收缩减包体、增加逆向成本。Dart 代码由 AOT 编译不受 ProGuard 影响；
            // 插件侧保留规则已随插件自带 consumer-rules 生效。若未来加入反射
            // 敏感插件导致 release 崩溃（ClassNotFoundException），在此追加
            // proguardFiles keep 规则，而不是全局关闭收缩。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

tasks.configureEach {
    if (name.contains("Release", ignoreCase = true) && !keystorePropertiesFile.exists()) {
        doFirst {
            throw GradleException(
                "Missing android/key.properties. Copy key.properties.example, " +
                    "configure a private release keystore, then retry the Release build.",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

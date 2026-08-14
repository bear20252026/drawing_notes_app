# 绘图笔记 1.1.0+2：正式安装包发布指南

**发布版本：** `1.1.0+2`  
**Windows 显示名：** 绘图笔记  
**发布目标：** Windows `.exe` 安装器、Android `.apk` 直装包、Android `.aab` 商店上传包。

## 对现有工具链理解的校正

您给出的整体顺序是正确的：Flutter 负责把 Dart/Flutter 工程编译为目标平台应用，Fastforge 负责调用目标打包器并收集产物，Inno Setup 负责把 Windows 运行目录制作成标准 Setup EXE。当前 Fastforge 0.6.12 的官方命令已经使用 `fastforge`，而旧名称 `flutter_distributor` 已更名但功能延续。[1] [2]

| 层级 | 工具 | 真正职责 | 不应混淆的边界 |
| --- | --- | --- | --- |
| 应用编译 | Flutter 3.44.9 / Dart 3.12.2 | 编译 Windows runner 或 Android APK/AAB；传递版本号 `1.1.0+2` | Flutter 本身不会生成 Windows 安装向导 |
| Windows 原生编译 | Visual Studio Build Tools、MSVC、CMake | 编译 Windows C++ runner 与插件 | 必须在 Windows 主机运行；Linux 无法原生替代此流程 |
| Windows 安装器 | Inno Setup 6 | 将 Windows Release bundle 做成带卸载、开始菜单和桌面快捷方式的 EXE | 需要稳定 AppId 才能识别覆盖安装 |
| 打包调度 | Fastforge 0.6.12 | 按 `distribute_options.yaml` 调用 Flutter build 和 EXE/APK/AAB maker，并输出到 `dist/` | 官方语法优先使用 `fastforge package --platform ... --targets ...` |
| Android 签名 | 私有 JKS/keystore + Gradle | 为 release APK/AAB 添加唯一签名，支持更新与 Play 上传 | 不能把 `key.properties` 或 keystore 提交到仓库，也不能发布 debug 签名包 |
| 可信发布（可选但推荐） | Windows 代码签名证书 | 为 Windows 安装器/EXE 签名，降低 SmartScreen 警告并确认发行主体 | Inno Setup 不会替代 Authenticode 代码签名 |

> **关键结论：** `flutter build windows --release` 生成的是可运行的 Windows bundle；`fastforge package --platform windows --targets exe` 会依据 `windows/packaging/exe/make_config.yaml` 调用 Inno Setup 生成可安装的 Setup EXE。两者不是相互替代关系，但不要在同一脚本里无必要重复构建。

## 已写入项目的发布配置

| 文件 | 作用 |
| --- | --- |
| `pubspec.yaml` | 版本已提升为 `1.1.0+2`，该版本自动进入 Android `versionName/versionCode` 与 Windows 文件版本 |
| `windows/packaging/exe/make_config.yaml` | Windows EXE 安装器配置；包含稳定 AppId、产品显示名、桌面图标、ICO 图标、中文/英文及 x64 兼容安装模式 |
| `distribute_options.yaml` | Fastforge `production` 发布任务，分别包含 `windows-exe`、`android-apk`、`android-aab` |
| `windows/runner/Runner.rc` | Windows 文件属性中的产品名、描述和版本资源 |
| `android/key.properties.example` | Android 私有 release keystore 的安全模板 |
| `android/app/build.gradle.kts` | 仅允许私有 keystore 对 Release 签名；缺失 `android/key.properties` 时明确中止 Release 构建 |
| `tools/release_windows.ps1` | Windows 一键预检、分析、测试、Fastforge EXE 打包与 SHA-256 清单 |
| `tools/release_android.ps1` | Android 一键预检、分析、测试、APK/AAB 打包与 SHA-256 清单 |

## Windows：生成正式 Setup EXE

请在您已经安装 Visual Studio、Flutter、Fastforge 与 Inno Setup 6 的 Windows PowerShell 中执行。您提供的 `C:\Users\17296\AppData\Local\Pub\Cache\bin` 路径可用，但 Windows 默认 Dart Pub Cache 往往是 `%APPDATA%\Pub\Cache\bin`；应以 `Get-Command fastforge` 的实际结果为准。

```powershell
cd "D:\AI编码工具\画板"
$env:Path += ";$env:APPDATA\Pub\Cache\bin"
fastforge --version
& ".\tools\release_windows.ps1"
```

脚本会执行 `flutter pub get`、`flutter analyze`、`flutter test`，随后调用：

```powershell
fastforge package --platform windows --targets exe
```

成功后应在 `dist\` 内看到最新 `.exe` 安装器与 `SHA256SUMS.txt`。首次安装和升级安装都应验证：应用可启动、已有本地笔记可保留、卸载可用、开始菜单/桌面快捷方式正确、安装器无法在未支持架构运行。Fastforge 的 Windows EXE 目标要求 Windows 与 Inno Setup 6。[3]

## Android：生成已签名 APK 和 AAB

先创建私有 keystore；下面密码仅为命令参数占位，请自行在密码管理器中生成高强度值，且不要在聊天、仓库或脚本中保存真实密码。

```powershell
cd "D:\AI编码工具\画板"
Copy-Item android\key.properties.example android\key.properties
keytool -genkeypair -v -keystore C:\secure\drawing-notes-release.jks `
  -alias release -keyalg RSA -keysize 4096 -validity 10000
```

然后编辑本机私有的 `android\key.properties`，确保 `storeFile` 指向真实 `.jks` 文件。完成后运行：

```powershell
& ".\tools\release_android.ps1"
```

脚本调用：

```powershell
fastforge package --platform android --targets apk,aab
```

其中 APK 用于内部真机安装和触控笔验收，AAB 用于 Google Play Console。Fastforge 官方将 APK 定义为可直接安装格式，AAB 用于由商店按设备配置生成优化 APK。[4] [5]

## 当前验证结果与环境边界

| 项目 | 结果 |
| --- | --- |
| 应用质量门禁 | `dart analyze` 零问题；`flutter test` **133** 项全部通过 |
| 当前 Flutter 版本 | Flutter 3.44.9 stable、Dart 3.12.2 |
| 当前沙箱 Android 构建 | 未生成，因为此 Linux 沙箱没有 Android SDK；`flutter build apk --debug` 已明确报告 `No Android SDK found` |
| 当前沙箱 Windows 安装器 | 未生成，因为 Windows EXE/Inno Setup 构建必须在 Windows 主机执行，且此环境没有 Fastforge/Inno Setup |
| Android production 签名 | 需由您持有私有 keystore 后执行；项目已防止静默退回 debug 签名 |

这意味着本次交付已经完成**可复现的正式发布配置与代码质量验证**；真正的 Windows Setup EXE 与生产签名 Android APK/AAB 必须在您已具备 Windows 工具链、Android SDK 和私有签名证书的本机运行上述脚本生成。

## 发布前验收清单

| 发布物 | 必检项 |
| --- | --- |
| Windows Setup EXE | 安装、升级覆盖、卸载、快捷方式、离线启动、本地数据保留、Windows Defender/SmartScreen 反馈 |
| Android APK | 安装、冷启动、存储权限、导入/导出、压感状态栏、掌托、横竖屏与低电量场景 |
| Android AAB | Play Console 上传、签名一致性、versionCode 单调递增、内部测试渠道安装 |
| 所有产物 | 使用 `SHA256SUMS.txt` 验证下载文件完整性；保留源代码 tag、版本号、构建日期和发布说明 |

## References

[1] [Fastforge Getting Started](https://fastforge.dev/getting-started)  
[2] [fastforge 0.6.12 on pub.dev](https://pub.dev/packages/fastforge)  
[3] [Fastforge EXE maker](https://fastforge.dev/makers/exe)  
[4] [Fastforge APK maker](https://fastforge.dev/makers/apk)  
[5] [Fastforge AAB maker](https://fastforge.dev/makers/aab)  
[6] [Fastforge distribution options](https://fastforge.dev/distribute-options)

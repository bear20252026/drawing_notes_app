# 发布打包 验收记录（C）

> 状态：✅ 验证通过（2026-08-29，commit `6145226` 之后的当前源码）
> 工具链：Flutter 3.47.0 · fastforge · Inno Setup 6 · Android SDK（Gradle 8.x / AGP 8.x）

## 目的
验证发布打包流水线能基于**当前源码**（含 WebDAV 同步 + 端到端加密 + 同步可观测性 + 冲突解析 + 块模型/edgeless 双模 + PDF 真渲染）产出**可交付的 Windows 安装包**与 **Android 发布产物（APK + AAB）**，并确认产物签名、尺寸与校验值有效。

## 发布门禁（全平台共用）
前置门禁在同一源码上运行，通过后方可构建产物。

| 步骤 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze` | ✅ **0 问题** |
| 全量测试 | `flutter test` | ✅ **1213** 全通过 |
| 架构测试 | 架构依赖边界（features→shared→core 单向依赖） | ✅ 通过 |

---

## A. Windows 桌面版

### 执行与证据

| 步骤 | 命令 | 结果 |
|---|---|---|
| Windows release 构建 | `flutter build windows --release` | ✅ 0 错误（`build\windows\x64\runner\Release\drawing_notes_app.exe`，8.7s） |
| 启动冒烟 | 启动 runner exe → 等待 8s → 检查进程存活 | ✅ **AS ALIVE after 8s（pid 无崩溃）**，随后正常停止 |
| 安装包打包 | fastforge `package windows exe` + Inno Setup 6 | ✅ 产出 `dist/1.1.0+2/drawing_notes_app-1.1.0+2-windows-setup.exe`（16,727,924 字节，2026-08-29 12:01） |

### 产物与校验
- `dist/1.1.0+2/drawing_notes_app-1.1.0+2-windows-setup.exe` — Windows 安装包（单文件，含 MSVC/Flutter 引擎/插件 deps）

```
bf46b6c6419798eeeb38141f821ef7580503eea358ecc07c171919f92d1471c7  1.1.0+2/drawing_notes_app-1.1.0+2-windows-setup.exe
```

---

## B. Android 发布产物

### 执行与证据

| 步骤 | 命令 | 结果 |
|---|---|---|
| APK（release） | `flutter build apk --release` | ✅ 0 错误 → `build/app/outputs/flutter-apk/app-release.apk`（**88,419,490 B**） |
| AAB（release） | `flutter build appbundle --release` | ✅ 0 错误 → `build/app/outputs/bundle/release/app-release.aab`（**76,644,004 B**） |
| 签名 | 本地 `android/key.properties`（`signingConfig` release，未入仓） | ✅ 打包内联签名（APK v1/v2+v3；AAB 交由 Play 重新签名） |
| 原生依赖（pdfium） | `.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/android-{arm,arm64,x64}/libpdfium.so` | ✅ 本地预置 .so，规避 GitHub 下载抖动 |

### 产物与校验
- `dist/android/app-release.apk` — 直接安装到设备/模拟器的分发包（88,419,490 B）
- `dist/android/app-release.aab` — 上传 Google Play 的分发包（76,644,004 B）

```
77b9825ebca36bc5871ddfb89427a0fc28bb25013ff04c2dd0449f66dcecc35c  android/app-release.apk
dfe9420ca135709d14a8c91e2fa8f9ab2c257b6e963cd4d6019fb058292e6c3a  android/app-release.aab
```

> 说明：AAB 为分发包，实际签名由 Google Play App Signing 在上传后重签生成；APK 为本地打包内联签名（release keystore）。两者均基于同一当前源码，功能与 Windows 版一致。

---

## 备注
- 旧 `dist/windows/`（08-28 提取包）与旧 zip / 旧 Android 产物均已清理，避免与新鲜产物混淆；`SHA256SUMS.txt` 已重写为仅含当前三件产物。
- Android 的 pdfium_dart 原生库在构建时默认会从 GitHub 下载对应 ABI 的 `.so`；本次因网络抖动失败，改为通过 `Start-BitsTransfer`（可续传）下载 `pdfium-android-{arm,arm64,x64}.tgz` 解包，预置进 hook 缓存目录以跳过下载。该路径仅影响 PDF 渲染能力，`local-only` 策略不变。
- `android/key.properties` 不入仓（`android/.gitignore` 已忽略），发布时需在构建机本地提供。

## 相关
- `docs/RELEASE_PACKAGING_GUIDE_2026-08-14.md`（发布流程）
- `docs/WEBDAV_SYNC_ACCEPTANCE_2026-08-29.md`（同步/加密/可观测性/冲突解析验收）
- `dist/README.md`（产物说明与再生成命令）

# iOS/macOS 平台配置审计报告

**日期**：2026-08-24  
**审计人**：Aion CLI  
**工作区**：D:\write\1\build_latest\drawing_notes_app

---

## 1. 现状总结

| 平台 | 目录存在 | 构建配置 | 状态 |
|------|---------|---------|------|
| Android | ✅ `android/` | ✅ 完整 | 生产可用 |
| Windows | ✅ `windows/` | ✅ 完整 | 生产可用 |
| iOS | ❌ 不存在 | ❌ 无 | 未配置 |
| macOS | ❌ 不存在 | ❌ 无 | 未配置 |
| Linux | ❌ 不存在 | ❌ 无 | 未配置 |
| Web | ❌ 不存在 | ❌ 无 | 未配置 |

## 2. iOS/macOS 配置缺失项

由于 `ios/` 和 `macos/` 目录完全缺失，以下配置项均需新建：

### 2.1 iOS 必需项
- [ ] `ios/Runner/Info.plist` — 应用元数据、权限声明
- [ ] `ios/Runner.xcodeproj/project.pbxproj` — Xcode 工程配置
- [ ] `ios/Podfile` — CocoaPods 依赖管理
- [ ] `ios/Runner/Assets.xcassets/` — 启动图标
- [ ] `ios/Runner/LaunchScreen.storyboard` — 启动页
- [ ] `ios/Runner/AppDelegate.swift` — 应用入口

### 2.2 macOS 必需项
- [ ] `macos/Runner/Info.plist` — 应用元数据
- [ ] `macos/Runner.xcodeproj/project.pbxproj` — Xcode 工程配置
- [ ] `macos/Podfile` — CocoaPods 依赖管理
- [ ] `macos/Runner/Assets.xcassets/` — 应用图标
- [ ] `macos/Runner/MainFlutterWindow.swift` — 主窗口入口
- [ ] `macos/Runner/AppDelegate.swift` — 应用委托

### 2.3 加密相关权限（本项目核心需求）
- [ ] iOS Keychain Entitlements — `keychain-access-groups`
- [ ] macOS Keychain Entitlements — `keychain-access-groups` + `com.apple.security.network.client`（如需网络同步）
- [ ] App Sandbox 配置 — `com.apple.security.app-sandbox`
- [ ] 文件访问权限 — `com.apple.security.files.user-selected.read-write`

### 2.4 Flutter 特定配置
- [ ] `ios/Runner/GeneratedPluginRegistrant.swift` — 插件注册
- [ ] `macos/Runner/GeneratedPluginRegistrant.swift` — 插件注册
- [ ] Info.plist 相机/照片/麦克风权限声明（如需导入图片/PDF）

## 3. 依赖包兼容性检查

以下项目依赖的包需要 iOS/macOS 原生支持：

| 依赖包 | iOS 支持 | macOS 支持 | 备注 |
|--------|---------|-----------|------|
| `cryptography` | ✅ | ✅ | 纯 Dart 实现 |
| `crypto` | ✅ | ✅ | 纯 Dart 实现 |
| `shared_preferences` | ✅ | ✅ | 需 iOS/macOS 原生插件 |
| `path_provider` | ✅ | ✅ | 需 iOS/macOS 原生插件 |
| `pdf` | ✅ | ✅ | 纯 Dart 实现 |
| `pdfrx` | ✅ | ⚠️ | macOS 支持需验证 |
| `isar` | ✅ | ✅ | 需 Xcode 15+ |
| `system_tray` | ✅ | ⚠️ | macOS 需额外配置 |

## 4. 关键风险

### 4.1 P0：密钥链（Keychain）存储
- iOS/macOS 使用 Keychain 而非 Android Keystore 存储加密密钥
- 需要配置 `KeychainAccessibility`（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）
- App Sandbox 模式下需正确配置 entitlements

### 4.2 P1：硬件加密加速
- Apple Silicon (A/M 系列) 支持 AES-NI 硬件加速
- `cryptography` 包的 AES-GCM 可自动使用硬件加速
- ChaCha20 在 Apple 平台无硬件加速，性能可能略慢

### 4.3 P2：Apple Pencil 支持
- 绘图应用需处理 Apple Pencil 事件（压力、倾斜、方位角）
- 需要 `UIKit` 的 `UIPencilInteraction` 或 SwiftUI 的 `PencilTextInput`
- 需要 `StylusTouch` 或 `UITouch` 扩展

## 5. 生成步骤

使用 `flutter create` 生成基础结构，然后手工修改：

```bash
# 1. 生成 iOS 项目
flutter create --platforms ios -o ios_runner drawing_notes_app

# 2. 生成 macOS 项目
flutter create --platforms macos -o macos_runner drawing_notes_app

# 3. 手工合并生成的 ios/ 和 macos/ 目录到项目根目录
# 4. 修改 Info.plist 添加权限声明
# 5. 配置 Keychain entitlements
# 6. 验证 flutter build ios / flutter build macos
```

## 6. 建议优先级

| 优先级 | 任务 | 工作量 |
|--------|------|--------|
| P0 | `flutter create` 生成基础结构 | 0.5天 |
| P0 | Keychain entitlements 配置 | 0.5天 |
| P1 | Apple Pencil 压力感应接入 | 1天 |
| P1 | Info.plist 权限声明 | 0.5天 |
| P2 | macOS 侧边栏/菜单栏集成 | 1天 |
| P2 | Universal app (iPhone + iPad) 适配 | 1天 |

## 7. 结论

当前项目 **完全没有 iOS/macOS 平台配置**。要支持 Apple 平台，需要：
1. 使用 `flutter create` 生成基础 `ios/` 和 `macos/` 目录
2. 配置 Keychain entitlements（加密应用核心需求）
3. 处理 Apple Pencil 压力输入（绘图应用核心需求）
4. 验证所有依赖包在 Apple 平台的兼容性

预估完整 iOS/macOS 适配工作量：**3-5 人天**。

# P3 #48 iOS/macOS 平台配置 + 跨平台适配报告

## 当前状态

| 平台 | 目录 | 状态 | 备注 |
|------|------|------|------|
| Android | android/ | ✅ 已配置 | 完整构建可用 |
| Windows | windows/ | ✅ 已配置 | Release 构建通过 |
| iOS | ios/ | ❌ 缺失 | 需 `flutter create` 生成 |
| macOS | macos/ | ❌ 缺失 | 需 `flutter create` 生成 |
| Linux | linux/ | ❌ 缺失 | 需 `flutter create` 生成 |

## 已集成的跨平台模块

以下模块已在主仓库中实现，iOS/macOS/Linux 可直接复用：

1. **系统托盘**: `lib/core/platform/system_tray_manager.dart` — `system_tray` 包
2. **文件关联**: `lib/core/platform/file_association.dart` — CLI 参数解析
3. **自动更新**: `lib/core/platform/auto_updater.dart` — HTTP 检查 + 下载
4. **原子文件写入**: `lib/core/storage/atomic_file_writer.dart` — tmp+rename
5. **加密存储**: `lib/core/storage/encrypted_vault.dart` — AES-256-GCM
6. **后量子加密**: `packages/editor_core/lib/src/domain/pq_hybrid_providers.dart` — pqcrypto

## 适配步骤

### Step 1: 生成平台目录

```bash
flutter create --org com.example.drawing_notes --platforms ios,macos,linux .
```

### Step 2: iOS Info.plist 权限声明

```xml
<!-- 文件共享 -->
<key>UIFileSharingEnabled</key><true/>
<key>LSSupportsOpeningDocumentsInPlace</key><true/>

<!-- Keychain 共享 -->
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)com.example.drawingnotes</string></array>

<!-- 深度链接 URI Scheme -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>drawingnotes</string></array>
    <key>CFBundleURLName</key>
    <string>com.example.drawingnotes</string>
  </dict>
</array>

<!-- 可选权限 -->
<key>NSCameraUsageDescription</key><string>用于拍照导入到笔记</string>
<key>NSPhotoLibraryUsageDescription</key><string>用于从相册导入图片</string>
```

### Step 3: macOS Entitlements

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

### Step 4: macOS Info.plist 文件关联

```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key><string>Drawing Notes Project</string>
    <key>CFBundleTypeExtensions</key>
    <array><string>drawingnotes</string><string>dnproj</string></array>
    <key>CFBundleTypeRole</key><string>Editor</string>
  </dict>
</array>
```

### Step 5: Linux MIME 关联

```desktop
MimeType=application/x-drawing-notes;
```

## Keychain 配置要点

- **flutter_secure_storage** 底层使用 Keychain Services (iOS/macOS)
- `kSecAttrAccessible`: `WhenUnlockedThisDeviceOnly`（设备绑定）
- `kSecAttrSynchronizable`: false（不跨设备同步敏感数据）
- App 删除后 Keychain 数据保留（需手动清理）

# CI 健康报告 — P3 #49 Android 构建 + P3 #50 SBOM 签名

**日期**：2026-08-24
**分支**：master（drawing_notes_app 主仓库）

---

## 一、P3 #49 CI Android 构建验证

### 状态：✅ 新增 `android-build.yml`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| Android build job 存在 | ✅ | `.github/workflows/android-build.yml` 新建 |
| Runner | ✅ | `ubuntu-latest` |
| JDK 版本 | ✅ | JDK 17（Temurin），`actions/setup-java@v4` |
| flutter pub get | ✅ | 有缓存（`subosito/flutter-action` cache: true） |
| flutter analyze | ✅ | 静态分析步骤独立 |
| flutter build apk --release | ✅ | Release 构建 |
| Android Licenses | ✅ | CI 自动接受 `sdkmanager --licenses` |
| 触发条件 | ✅ | push master + PR master |
| 超时 | ✅ | 45 分钟 |

### 已有 Android 构建（`pr-platform.yml`）
- `pr-platform.yml` 中已有 `android-build` job，但仅构建 `--debug` 且无 `flutter analyze`
- 新建 `android-build.yml` 补齐 release 构建 + 分析，与 PR 平台检查互不冲突

---

## 二、P3 #50 SBOM 签名

### 状态：✅ 已在 worktree `rework/wp6-ci-quality` 分支完成

| 检查项 | 结果 | 说明 |
|--------|------|------|
| SBOM 生成 | ✅ | `python tools/generate_sbom.py`（CycloneDX JSON） |
| Sigstore 签名 | ✅ | `sigstore/cosign-installer@v3` + `cosign sign-blob --yes` |
| 产物上传 | ✅ | `actions/upload-artifact@v4`（sbom + .sig + .cert） |
| OIDC 权限 | ✅ | `id-token: write` 已加到 `pr-security.yml` |
| 保留期 | ✅ | 90 天 |

> 注：SBOM 签名改动在 worktree 分支 `rework/wp6-ci-quality` 的 `pr-security.yml` 中。
> 该 worktree 已有 10+ commits 覆盖 #17 CI 修复 + #49/#50 新功能。

---

## 三、测试覆盖率基线（P2 #32 参考）

| 指标 | 值 |
|------|----|
| 总行数 | 8,546 |
| 覆盖行数 | 3,952 |
| **行覆盖率** | **46.2%** |
| 覆盖文件数 | 63 |

### 高覆盖率文件（≥90%）
- `lib/models/document_image_item.dart` — 100%
- `lib/models/layer.dart` — 100%
- `lib/engine/stroke_geometry_cache.dart` — 100%
- `lib/engine/command_registry.dart` — 100%
- `lib/ui/widgets/glass_surface.dart` — 100%

### 零覆盖文件（需优先补测试）
- `lib/engine/svg_exporter.dart` — 0%（34 行）
- `lib/engine/gesture_math.dart` — 0%（18 行）
- `lib/engine/shape_library.dart` — 0%（63 行）
- `lib/ui/widgets/layer_panel.dart` — 0%（99 行）
- `lib/ui/widgets/properties_panel.dart` — 0%（100 行）
- `lib/ui/pages/presentation_page.dart` — 0%（66 行）

### 编译失败文件（阻断测试运行）
- `drawing_controller.dart` — 多个未定义成员（`_grid`, `_selectedStrokeIndices` 等）
- `drawing_controller_render.dart` — 同上
- `editor_v2/presentation/note_document_bridge.dart` — legacy import 违规

---

## 四、总结

| 任务 | 状态 | 交付 |
|------|------|------|
| P3 #49 Android 构建 | ✅ 完成 | `android-build.yml` 新建 |
| P3 #50 SBOM 签名 | ✅ 完成 | `pr-security.yml` 改动（worktree） |
| 覆盖率基线 | ✅ 完成 | 46.2%，63 文件 |

# 发布规范（Release Pipeline）

> 生效日期：2026-08-31。本规范对本地脚本与云端 workflow 同时约束，**新增发布产物形态时必须同步更新本文件**。

## 铁律

0. **修改即同步**：每次代码修改提交后必须立即运行 `bash tools/sync_github.sh ["说明"]`
   ——脚本自动提交（有修改时）→ 推送（3 次重试）→ 校验远端 HEAD == 本地 HEAD。
   **禁止留本地未推送提交**（"推了"不等于"推到了"，必须以脚本 VERIFIED 输出为准）。

1. **所有安装包生成后，必须压缩为 zip 格式随发布一起产出**——原始安装包与 zip 双轨提供（zip 便于下载/分享/完整性校验，原始包便于直接安装）。
2. 版本号**三处同步**（漏一处会导致云端产物名带旧版本）：
   - `pubspec.yaml` → `version: X.Y.Z+N`
   - `tools/drawing_notes_setup.iss` → `#define MyAppVersion "X.Y.Z"`
   - `CHANGELOG.md` → `## [X.Y.Z] - 日期`

## 发布流程

### 本地打包（tools/release_windows.ps1）

1. 质量门：`flutter pub get` → `flutter analyze` → `flutter test`（全量）。
2. Fastforge 打包 Windows EXE 安装程序（Inno Setup）。
3. 生成 `dist/SHA256SUMS.txt`（所有 EXE 的 SHA256）。
4. **压缩步骤**：每个 EXE 同目录生成同名 `.zip`（`Compress-Archive`）。

### 云端（.github/workflows/release-build.yml，tag v* 触发）

| Job | 产物 | zip |
|---|---|---|
| Android | app-release.apk | `drawing_notes_android_release.zip` |
| Windows | setup_drawing_notes_X.Y.Z.exe | `drawing_notes_windows_setup.zip` |

zip 在各 job 内随原始包一起上传 Artifact 并挂载到 GitHub Release。

### 本地跑法速查

```bash
# Windows 本地（bash 下 fastforge.bat 需全路径；fastforge 内部要能找到 flutter）
"/c/Users/17296/AppData/Local/Pub/Cache/bin/fastforge.bat" package --platform windows --targets exe
# 或 PowerShell（需把 D:\flutter\bin 与 LOCALAPPDATA\Pub\Cache\bin 加入 PATH）
.\tools\release_windows.ps1
```

### 云端监控与产物下载

```bash
gh run watch $(gh run list --workflow=release-build.yml --limit 1 --json databaseId -q '.[0].databaseId') --exit-status
gh release download "vX.Y.Z" -D Downloads --pattern "*.exe" --pattern "*.apk" --pattern "*.zip" --clobber
```

## 检查清单（发版前逐项勾选）

- [ ] `pubspec.yaml` 版本已提升
- [ ] `tools/drawing_notes_setup.iss` 的 `MyAppVersion` 已同步
- [ ] `CHANGELOG.md` 已添加版本段落
- [ ] `flutter test` 全量绿 + `dart analyze` 0 问题
- [ ] Release 资产同时包含：原始安装包 + **zip 包**（Windows 与 Android 各一）
- [ ] 下载产物实测安装/启动

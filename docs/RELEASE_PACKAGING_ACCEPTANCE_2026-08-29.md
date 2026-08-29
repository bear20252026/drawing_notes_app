# Windows 发布打包 验收记录（C）

> 状态：✅ 验证通过（2026-08-29，commit `6145226` 之后构建）
> 工具链：Flutter 3.47.0 · fastforge · Inno Setup 6

## 目的
验证发布打包流水线能基于**当前源码**（含 WebDAV 同步 + 端到端加密 + 同步可观测性 + 块模型/edgeless 双模 + PDF 真渲染）产出可交付的 Windows 安装包，并确认应用能正常启动。

## 执行与证据

| 步骤 | 命令 | 结果 |
|---|---|---|
| 发布门禁（analyze + 全量测试） | `tools/release_windows.ps1`（内嵌 `flutter analyze` + `flutter test`） | ✅ 通过（`flutter analyze` 0 问题；`flutter test` **1176** 全通过） |
| Windows release 构建 | `flutter build windows --release` | ✅ 0 错误（`build\windows\x64\runner\Release\drawing_notes_app.exe`，8.7s） |
| 启动冒烟 | 启动 runner exe → 等待 8s → 检查进程存活 | ✅ **AS ALIVE after 8s（pid 无崩溃）**，随后正常停止 |
| 安装包打包 | fastforge `package windows exe` + Inno Setup 6 | ✅ 产出 `dist/1.1.0+2/drawing_notes_app-1.1.0+2-windows-setup.exe`（16,727,924 字节，2026-08-29 12:01） |

## 产物（git 忽略，`/dist/`）
- `dist/1.1.0+2/drawing_notes_app-1.1.0+2-windows-setup.exe` — Windows 安装包（单文件，含 MSVC/Flutter 引擎/插件 deps）
- `dist/SHA256SUMS.txt` — 校验清单

### SHA-256（安装包）
```
bf46b6c6419798eeeb38141f821ef7580503eea358ecc07c171919f92d1471c7  drawing_notes_app-1.1.0+2-windows-setup.exe
```

## 备注
- 旧 `dist/windows/`（08-28 提取包）与旧 zip 已清理，避免与新鲜产物混淆；SHA256SUMS.txt 已重写为仅含当前安装包。
- `dist/android/app-release.{apk,aab}` 为先前产物（未在本次 C 范围内更新），后续 Android 发布需重新构建。
- 本次 C 聚焦 Windows 发布路径；Android/iOS 打包发布未纳入（另行排期）。

## 相关
- `docs/RELEASE_PACKAGING_GUIDE_2026-08-14.md`（发布流程）
- `docs/WEBDAV_SYNC_ACCEPTANCE_2026-08-29.md`（同步/加密/可观测性验收）

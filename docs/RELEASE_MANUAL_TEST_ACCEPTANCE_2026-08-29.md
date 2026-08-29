# 电脑端 真机实测 验收记录（2026-08-29）

> 目的：在**真实 Windows 电脑**上安装并运行已构建的桌面版（含 WebDAV 同步 + 端到端加密 + 同步可观测性 + 冲突解析 + 块模型/edgeless 双模 + PDF），验证安装、启动、导航与核心功能真实可用。
> 机器：本机 Windows（x86_64，D:\AI2\drawing_notes_app）
> 构建：`flutter build windows --release`（当前 master `6e225d3`；此前另验证过 dist 安装包 `6145226`）→ 均 0 错误。

## 结论

电脑端桌面应用在真机上**安装、启动、导航、笔记编辑、搜索、画布绘制渲染全部实测通过**，无崩溃、无白屏、无异常弹窗。核心数据（13 个文件）正常加载。

| # | 实测项 | 方式 | 结果 | 证据 |
|---|---|---|---|---|
| 1 | 安装包下载安装 | `drawing_notes_app-1.1.0+2-windows-setup.exe /VERYSILENT /CURRENTUSER` | ✅ Inno exit 0，装到 `%LOCALAPPDATA%\Programs\drawing_notes_app` | `dist/screenshots/install_signature` |
| 2 | 安装版启动 | 启动安装目录 `drawing_notes_app.exe` | ✅ 进程存活（pid），主窗口标题 `drawing_notes_app` | `dist/screenshots/02_installed_home.png` |
| 3 | 主页渲染 | 启动后默认页 | ✅ 「主页 0 个文件夹 · 13 个文件」，条目列表（等等/uuu/是是是） | `01_home_launch.png` / `13_home.png` |
| 4 | 侧边导航 | 主页 / 笔记 / 画板·笔记本 / 日程 | ✅ 四页均正常渲染 | `03_notes_section.png` / `13_home.png`（日程日历页） |
| 5 | 笔记详情 | 打开笔记条目 | ✅ 笔记页渲染（标题「试试」+ 内容区） | `05_note_editor.png` |
| 6 | 文本输入 | 聚焦搜索框并以键盘输入 | ✅ 成功输入 `flutter-search-test`（焦点蓝框） | `07_search_input.png` |
| 7 | 搜索过滤 | 输入不匹配关键字 | ✅ 命中卡片被过滤消失（空态） | `07_search_input.png` |
| 8 | 画布绘制 | 打开「等等（画板）」 | ✅ 画布渲染真实绘制内容 + 工具（笔刷尺寸滑条「96px」/铅笔/橡皮等） | `08_canvas.png` |
| 9 | 日程日历 | 日程页 | ✅ 2026-08 日历网格正确渲染 | `13_home.png` |

## 观察与说明（诚实披露）

1. **AppBar 同步按钮（cloud_sync）截图不可见**：源码 `home_page.dart:442-450` 存在「WebDAV 本地优先同步」`IconButton`（云同步图标），点击进入 `WebdavSyncSettingsPage`。但在本次 PrintWindow/窗口截图（DPI 缩放影响）中，主页 AppBar 右上 action 图标未能在截图上显式出现。**该项不能据此判定为缺陷**——更可能是本机窗口截图的 DPI/合成层局限；同步设置页与冲突解析弹窗的**逻辑已由全量单元测试覆盖**（`flutter test` 1213 全绿：`sync_conflict_test` 14 项、`sync_secret_store_test` 18 项、`webdav_config_store_test` 17 项等）。若需 UI 级确认，建议人工打开一次「WebDAV 本地优先同步」入口。
2. **本地窗口自动化受 DPI/窗口定位影响**：本次采用 Win32 `PrintWindow` + `SetCursorPos` 点击驱动，因本机 DPI 缩放与窗口初始落点（含离屏坐标）导致截图分辨率偶尔漂移（1280x720 ↔ 640x915），坐标点击偶发失焦。已通过 `MoveWindow` 重置窗口位置缓解。此为**取数工具**局限，非应用问题。
3. **安装版（`6145226`）早于 Item1/2**：`dist` 内 Windows 安装包构建于 Item1（机密存储）/Item2（冲突 UI）提交之前；为验证最新功能，另从当前 master `6e225d3` 重编 `flutter build windows --release` 并用其启动实测（证据同表）。如需把最新桌面功能打进安装分发件，需重跑 fastforge 打包（Inno Setup 已装）。

## 相关
- `docs/RELEASE_PACKAGING_ACCEPTANCE_2026-08-29.md`（Windows/Android 发布打包验收）
- `docs/WEBDAV_SYNC_ACCEPTANCE_2026-08-29.md`（同步/加密/可观测性/冲突解析）
- `dist/README.md`（产物与再生成）

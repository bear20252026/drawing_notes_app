# 绘图笔记 App（Drawing Notes）

面向 **Windows 桌面 + Android** 的跨平台绘图与笔记应用，使用 **Flutter (Dart)** 开发。
本项目依据《绘图笔记App-完整方案汇编》开发计划实施，全部为本地离线功能，
**不涉及**云同步、账号系统、AI 功能、网络请求。

![CI](https://img.shields.io/github/actions/workflow/status/bear20252026/drawing_notes_app/ci.yml)
![License](https://img.shields.io/github/license/bear20252026/drawing_notes_app)

> **安全定位**：政府级安全设计——加密笔记（K_note 每笔记密钥）、策略引擎
> （默认拒绝）、会话守卫（自动锁定）、VFS 加密对象仓库（版本/原子提交）、
> 不可篡改审计（SHA-256 哈希链）、导入隔离（SVG/PDF 预检）。

---

## 里程碑：M0-M10（AFFiNE 1:1 + Apple HIG 双模式单风格）

本项目在 Phase 1-7 画布/笔记基础上，完成 AFFiNE 1:1 功能复刻与 Apple(HIG) 视觉标准化：

- **AFFiNE 块模型**：`NoteBlock`/`NoteBlockEditor` + `NoteBlockDoc`，块式富文本编辑器（Enter 分块/Backspace 合并/类型切换/斜杠菜单/块手柄拖拽/撤销重做/Markdown 双向）。
- **Edgeless 无限画布双模**：`EdgelessDoc`+`NoteFrame`+`EdgelessCamera`，note 帧在无限画布上拖拽/缩放/pan-zoom + 页/画布模式切换。
- **All Docs 工作台**：`all_docs/`（领域+查询+UI 三层），画布/笔记/块文档统一列表 + 分组（今天/本周/更早/从未更新）+ 工作区侧栏 + 新建/搜索。
- **WebDAV 端到端加密同步**：本地优先，`SyncCipher`(AES)+`SyncPlanner`+重试/可观测性/冲突可见性。
- **Apple(HIG) 双模式单风格**：一套结构风格走天下，按亮度切色板 —— 明亮=Apple（#0066CC/#F5F5F7/#1D1D1F），黑暗=深蓝（#4568A9/#181F2E，保留原设计）；token 见 `lib/core/theme/apple_design.dart`。
- **本地化护栏**：`material_ui` 与 `flutter/material` 双方言共用，注册双 GlobalMaterialLocalizations 修复 `No MaterialLocalizations found`（回归测试锁定）。

> 详细：`docs/M10_APPLE_HIG_ACCEPTANCE_2026-08-29.md` · `docs/ARCHITECTURE.md`

---

## 功能概览

| 阶段 | 内容 | 状态 |
|------|------|------|
| Phase 1 | 最小画布：绘制线条、撤销、清空 | ✅ 完成 |
| Phase 2 | 基础绘图工具：笔粗细、色板、橡皮擦（透明擦除）、吸管 | ✅ 完成 |
| Phase 3 | 图层系统：新建/删除/显隐/透明度/排序/合并 | ✅ 完成 |
| Phase 4 | 选区与变换：矩形/套索选区、移动/缩放/旋转、复制/粘贴/删除 | ✅ 完成 |
| Phase 5 | 笔记功能：笔记本/页面管理、文字输入、图片插入混排 | ✅ 完成 |
| Phase 6 | 文件管理与持久化：自动保存、作品列表缩略图、导出 PNG、删除确认 | ✅ 完成 |
| Phase 7 | 体验打磨：深色模式、双指手势、全屏模式、首次启动引导 | ✅ 完成 |
| 安全加固 | 专家审计闭环：P0-P2 封堵 + 军工审计链 + 加密体系（详见下文） | ✅ 完成 |

## 环境要求

- Flutter 3.47.0（Dart 3.12.2）或更高稳定版
- Windows 构建：Visual Studio 2022+（含"使用 C++ 的桌面开发"组件）
- Android 构建：Android SDK（compileSdk 36）+ JDK 17 及以上

## 快速开始

```bash
# 安装依赖
flutter pub get

# Windows 桌面运行
flutter run -d windows

# Android 设备/模拟器运行
flutter run -d android

# 构建产物
flutter build windows --debug
flutter build apk --debug
```

> 说明：本项目目录名为中文（`画板`），Android 构建已在
> `android/gradle.properties` 中设置 `android.overridePathCheck=true` 放行。

## 测试与静态检查

```bash
# 静态检查（本项目用 dart analyze，flutter analyze 的 LSP 通道与中文路径有兼容问题）
dart analyze

# 全部单元/组件测试（当前 1255+ 项——覆盖 Phase 1-7 + 安全审计回归 + M0-M10 AFFiNE 块模型/edgeless/All Docs/WebDAV 同步）
flutter test

# 架构守护（层方向/零循环/feature 隔离/耦合度量）
flutter test test/architecture_test.dart

# 边界检查与行数门禁
bash tools/check_boundaries.sh
python tools/code_guard.py --dir lib --force-native --json
```

## 安全特性（专家审计闭环）

| 安全组件 | 说明 |
| --- | --- |
| **加密笔记** | AES-256-GCM + AAD 上下文绑定（NIST SP 800-38D）——正文/媒体/回收站加密 |
| **K_note 每笔记密钥** | 每笔记独立数据密钥 + AAD 绑定笔记 ID——一笔记密钥泄露不影响其他（Knovya 模式） |
| **策略引擎** | 操作白名单**默认拒绝**（fail-closed）+ 审计（PolicyEngine）——导入/删除经策略门禁 |
| **会话守卫** | 失去焦点立即锁定（清除内存密钥）+ 文件选择器豁免 + 再认证（SessionGuard） |
| **VFS 加密对象仓库** | 对象清单 + 版本回溯 + AAD 绑定 + 原子提交（临时文件+rename——崩溃安全）——媒体对象已接入 |
| **不可篡改审计** | SHA-256 哈希链（prevHash 链接——篡改断链）+ verifyIntegrity（AuditLogger） |
| **导入隔离** | SVG 预检（XXE/Billion Laughs/脚本注入/膨胀防护）+ PDF 页数/大小配额 |
| **发布门禁** | SBOM 生成（CycloneDX）+ 秘密扫描（Gitleaks 模式）+ CI 集成 |

## 数据存储位置

所有数据保存在应用文档目录（`getApplicationDocumentsDirectory`）下：

```
<应用文档目录>/
├── documents/        独立画作工程文件（JSON，含全部图层与笔画）
├── thumbnails/       画作缩略图（PNG，列表页展示）
├── notebooks/        笔记本工程文件（JSON，含全部页面）
└── notebook_images/  笔记页插入的图片副本（新媒体走 VFS 加密对象）
```

## 技术要点

- 画布渲染：Flutter `CustomPainter` + `Canvas` API（未引入第三方绘图引擎）
- 笔画模型：矢量点列存储（撤销/重做、图层合并、任意分辨率导出无损）
- 图层缓存：离屏位图（`PictureRecorder → toImage`）保证绘制流畅
- 自动保存：变更后 800ms 防抖落盘 + 退出前兜底保存
- 删除保护：所有删除操作均有二次确认对话框
- 架构解耦：God Class 拆分（8 个纯计算服务提取——官方渐进节奏）+ 五域 Notifier

详细设计见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)、[`docs/AUDIT_REPORT_2026-08-15.md`](docs/AUDIT_REPORT_2026-08-15.md) 与 [`docs/PHASES.md`](docs/PHASES.md)。

## 开源

- 📄 许可证：[MIT](LICENSE)
- 🤝 贡献指南：[CONTRIBUTING.md](CONTRIBUTING.md)
- 🔒 安全政策：[SECURITY.md](SECURITY.md)
- 📜 行为准则：[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 📝 变更日志：[CHANGELOG.md](CHANGELOG.md)

## 开发计划约束遵守情况

- ✅ 仅声明 `windows` 与 `android` 平台，无 iOS/macOS/Web 适配代码
- ✅ 无任何网络请求、云服务 API、账号系统
- ✅ 无 AI 功能、图层混合模式、蒙版、PSD 导出、录音、协作、内购
- ✅ UI 层 / 绘图引擎层 / 数据存储层严格分层（见架构文档）

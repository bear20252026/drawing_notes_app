# 第三方组件与致谢（Third-Party Notices）

本项目的笔记/白板交互设计参照并部分复用以下开源项目的成果。感谢原作者。

## AFFiNE / BlockSuite

- 项目：<https://github.com/toeverything/AFFiNE>
- 版权所有 (c) 2020-present toeverything 及其贡献者
- 许可证：MIT（BlockSuite 及 AFFiNE 仓库声明部分）
- 使用方式：本应用的块编辑器交互（块模型、斜杠菜单、块句柄拖拽、
  浮动格式工具条、Page/Edgeless 双模、大纲等）参照 AFFiNE/BlockSuite
  的交互与信息架构实现；数据结构命名（如 `affine:connector`、
  `affine:group`）为对标说明而保留。
- 响应式布局（2026-08-31 追加）：移动端视图参照 AFFiNE
  `packages/frontend/core/src/mobile/` 的信息架构——设备级分流、桌面与
  移动端两棵独立视图树、侧栏功能拆进顶部 header（Tab/搜索/排序/更多菜单）、
  底部导航在输入法弹出时隐藏（VirtualKeyboardService 语义）。相关实现见
  `lib/features/all_docs/presentation/all_docs_page_mobile.dart` 与
  `lib/app/app_shell.dart`。

MIT 许可证文本（摘自 AFFiNE 仓库）：

```text
MIT License

Copyright (c) 2020-present toeverything

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 直接依赖许可表（P2 审计补齐）

下表为 `pubspec.yaml` 直接依赖的用途与许可证（版本见 `pubspec.lock`；
许可证 canonical 来源为各包 `pub.dev` 页面与仓库内 LICENSE 文件，
发版前可用 `pana`/`dart pub licenses` 复核）：

| 包 | 用途 | 许可证 |
|---|---|---|
| `meta` | 注解（`@visibleForTesting` 等） | BSD-3-Clause |
| `flutter` / `flutter_localizations` / `intl` | 框架 / 本地化 | BSD-3-Clause |
| `cupertino_icons` | iOS 风格图标字体 | BSD-3-Clause |
| `path_provider` / `shared_preferences` | 目录 / 轻量 KV | BSD-3-Clause |
| `file_selector` / `local_auth` | 文件选择 / 系统验证 | BSD-3-Clause |
| `vector_math` | 视口矩阵数学 | BSD-3-Clause |
| `http` | WebDAV 传输 | BSD-3-Clause |
| `crypto` | SHA-256/HMAC | BSD-3-Clause |
| `cryptography` | AES-256-GCM / Argon2id / PBKDF2 主实现 | Apache-2.0 |
| `pdf` | PDF 导出 | Apache-2.0 |
| `pointycastle` | PBKDF2 后台 isolate 实现（与 cryptography 逐字节一致） | MIT |
| `pdfrx`（+ `pdfrx_engine`） | PDFium 本地渲染 | MIT |
| `archive` / `image` | 压缩 / 图像编解码 | MIT |
| `perfect_freehand` | 压感笔触轮廓 | MIT |
| `xml` | WebDAV PROPFIND 解析 | MIT |
| `flutter_riverpod` | 状态管理 | MIT |
| `hotkey_manager` / `window_manager` | 全局快捷键 / 桌面窗口 | MIT |
| `flutter_secure_storage` | OS 凭据库（DPAPI/Keychain/Keystore） | BSD-3-Clause（发版前以 pub.dev 复核） |
| `cupertino_ui` | Apple 风格组件 | 以 pub.dev 声明为准（发版前复核） |

子包 `packages/editor_core` 与 `packages/notebook_domain`：零运行时依赖，
`publish_to: none`，不独立分发，随主包 MIT 许可。

## 字体资产

- `assets/fonts/DroidSansFallbackFull.ttf`（分页笔记 PDF 导出离线 CJK 字体）：
  Droid 字体家族，Apache License 2.0（来源：Android 开源项目；随系统
  发行物附带完整 LICENSE 副本，发版前确认 `THIRD_PARTY_NOTICES` 打包进产物）。

## 合规口径

- MIT/BSD 系列：保留版权声明即可——本文件 + 各包 pub.dev 溯源满足；
- Apache-2.0：须附许可证文本并声明修改——`cryptography`/`pdf`/
  Droid 字体未修改源码使用，发版产物附本文件即满足；
- 新增直接依赖时同步追加本表行（CI 可用 `dart pub deps`  diff 提醒）。

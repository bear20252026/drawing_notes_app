# 绘图笔记 App（Drawing Notes）

面向 **Windows 桌面 + Android** 的跨平台绘图与笔记应用，使用 **Flutter (Dart)** 开发。
**本地优先**：默认全部功能本地离线（**不涉及**账号系统、AI 功能）；同步为**可选的、
用户自配 WebDAV 端到端加密同步**（无官方云、不经过第三方服务器），
不用即零网络请求。

![CI](https://img.shields.io/github/actions/workflow/status/bear20252026/drawing_notes_app/ci.yml)
![License](https://img.shields.io/github/license/bear20252026/drawing_notes_app)

> **安全定位**：政府级安全设计——加密笔记（每笔记独立密钥）、策略引擎
> （默认拒绝）、会话守卫（自动锁定）、VFS 加密对象仓库（版本/原子提交）、
> 不可篡改审计（SHA-256 哈希链）、导入隔离（SVG/PDF 预检）。

---

## 产品形态：三种载体并存

| 载体 | 说明 |
|------|------|
| **打字笔记（块文档）** | AFFiNE 式块模型：段落/标题/列表/待办/代码/引用/分隔线/数据库块，斜杠菜单、块手柄拖拽、Markdown 双向、撤销重做、大纲栏、文档模板——**主推载体** |
| **分页画布（笔记本）** | 多页画册：每页独立矢量画布 + 文字/图片/形状混排，整本/多页 PDF 导出（页脚、CJK 字体嵌入）、密码保护与 USB 重置盘 |
| **无限画布（Edgeless）** | pan-zoom 相机 + 手绘风格（rough）形状、图表与连接线、对象橡皮擦、激光笔、对齐参考线、小地图、命令面板（Ctrl+K） |

三者在 **All Docs 工作台**统一管理：分组时间线、收藏、标签、回收站（软删除 + 30 天过期清理）、全局搜索、演示模式。

## 功能概览

| 领域 | 内容 | 状态 |
|------|------|------|
| 绘图引擎 | 压感笔画（perfect_freehand 轮廓化）、铅笔颗粒着色器（FragmentShader）、图层系统（显隐/透明度/排序/合并/离屏缓存）、选区变换、墨迹混合渲染（高亮笔 darken 合成） | ✅ |
| 块文档 | 数据库块（表格/看板/列表三视图）、附件与嵌入块、斜杠命令、块级撤销重做、HTML/Markdown 导出 | ✅ |
| 文档互操作 | PDF 导入为笔记底图（页数/体积三重上限）；导出 PDF（矢量+光栅混合、分页/页脚）、PNG、SVG、Word（RTF）、HTML、JSON、PPTX | ✅ |
| 工作台 | All Docs 三层架构（domain/query/UI）、桌面双栏 + 移动单栏自适应（900dp 断点）、快速搜索、演示模式 | ✅ |
| 同步 | 可选 WebDAV：AES 端到端加密、强制 https（本地回环例外）、冲突可见性、路径穿越防护、全链路操作超时 | ✅ |
| 安全 | 见下表（专家审计 + 军工审计链闭环） | ✅ |
| 可达性 | 触屏/鼠标/键盘三输入兼容、44px 触控目标、画布手柄语义化、Esc 统一关闭对话框、减弱动效三信号 | ✅ |

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

> 说明：若克隆到含中文/非 ASCII 字符的目录，Android 构建需在
> `android/gradle.properties` 保留 `android.overridePathCheck=true` 放行；
> 默认英文目录名（如 `drawing_notes_app`）无需该设置。

## 测试与质量门禁

```bash
# 静态检查（提交门禁：必须 No issues found）
flutter analyze

# 全部单元/组件测试（当前 1851 项——覆盖画布/块文档/安全审计回归/
# WebDAV 同步/导出链路 + 2026-09 全量审计回归；真 KDF 用例按标签拆分串行）
flutter test

# 架构守护（9 条规则：层方向含 rendering 层、零循环、feature 隔离、
# 洋葱规则、Martin 耦合度量基线）
flutter test test/architecture_test.dart

# 边界检查与行数门禁
bash tools/check_boundaries.sh
python tools/code_guard.py --dir lib --force-native --json
```

CI 五个工作流（CI / 软件质量工程门禁 / Code Guard / SBOM / Secret Scan）全部绿合并。

## 安全特性（专家审计闭环）

| 安全组件 | 说明 |
| --- | --- |
| **加密笔记** | AES-256-GCM + AAD 上下文绑定（NIST SP 800-38D）——正文/媒体/回收站加密，nonce 每次随机 |
| **每笔记独立密钥** | 独立数据密钥 + AAD 绑定笔记 ID——一笔记密钥泄露不影响其他（Knovya 模式） |
| **开屏密码 / 保险库** | Argon2id 派生 + 恒定时间比较 + 持久化指数冷却防爆破；信封加密（版本化）+ 原子提交 |
| **快速解锁** | Windows Hello / Android BiometricPrompt（local_auth），DPAPI/Keystore 绑定 |
| **USB 重置盘** | 分页画布/文件密码「忘记密码」重置（LUKS 同款：盘钥匙解 DEK → 新盐重绕密码槽） |
| **策略引擎** | 操作白名单**默认拒绝**（fail-closed）+ 审计（PolicyEngine）——导入/删除经策略门禁 |
| **会话守卫** | 切后台 / 最小化 / 纯失焦（`inactive`）**全量锁定**——走开屏锁并清除内存密钥，桌面与安卓一致（宽限期锚在**首个**后台信号，同会话重复信号不重锚）。原生文件对话框 / 系统权限弹窗 / 外部查看器抢焦点期间失焦走**豁免窗口**（默认不豁免、5 分钟 TTL 上界，防导入/导出/绑盘时假锁）。回前台一律经同一条 `AppLockService.verify`（防爆破失败计数与指数冷却、快速解锁语义不旁路）。（AppLockGate + SessionGuard） |
| **VFS 加密对象仓库** | 对象清单 + 版本回溯 + AAD 绑定 + 原子提交（临时文件+rename——崩溃安全） |
| **不可篡改审计** | SHA-256 哈希链（prevHash 链接——篡改断链）+ verifyIntegrity（AuditLogger）；用户可见错误一律脱敏 |
| **导入隔离** | SVG 预检（XXE/Billion Laughs/脚本注入/膨胀防护）+ PDF 页数/大小配额 + 超链接 scheme 白名单 |
| **发布门禁** | SBOM 生成（CycloneDX）+ 秘密扫描（Gitleaks 模式）+ CI 集成 |

## 数据存储位置

所有业务数据统一收进单一数据根 **系统应用支持目录** 下的 `绘图笔记数据/`
（Windows 通常为 `%APPDATA%\<应用>\绘图笔记数据\`——**S-02 方案 B**：
不落在「文档」Known Folder，默认不被 OneDrive 等云同步盘接管）。
首次访问自动把历史分散位置与旧的 `Documents/绘图笔记数据/` 整树迁入
新根，绝不覆盖已存在数据：

```
<系统应用支持目录>/绘图笔记数据/
├── documents/            画布工程文件（JSON，含全部图层与笔画）
├── documents_trash/      画布回收站
├── thumbnails/           画布缩略图
├── document_images/      画布导入图片副本
├── notebooks/            笔记本（分页画布）工程文件
├── notebook_images/      笔记本图片副本（按加密等级密封落盘）
├── blockdocs/            打字笔记（块文档）
├── blockdocs_trash/      打字笔记回收站
├── security/             保险库密钥 + 锁屏守卫密钥
└── *.json                收藏/标签/日程等轻量配置
```

## 技术要点

- 画布渲染：Flutter `CustomPainter` + `Canvas` API（未引入第三方绘图引擎）；
  视口剔除 + 分层渲染计划缓存 + 增量脏矩形重建
- 笔画模型：矢量点列存储（撤销/重做、图层合并、任意分辨率导出无损）；
  高频路径（书写/擦除拖拽）走 frameTick 驱动，面板刷新与画布重绘分离
- 重活隔离：大 JSON 编解码、加密信封、JPEG 压缩、ZIP 打包、PDF 合成均在
  后台 `Isolate.run`（主 isolate 零阻塞）
- 视觉体系：Apple HIG 静态令牌（`apple_design.dart`）+ Emil 动效令牌
  （`apple_motion.dart`）+ 液态玻璃浮层（blur σ=12 + saturate 1.4，仅浮层可用）
- 架构守护：Feature-First 分层（presentation/application/infrastructure/rendering/domain）
  + core 契约注入（跨 feature 零横向直连）+ dart_arch_test 9 规则门禁
- 自动保存：变更后防抖落盘 + 退出前兜底保存；关键写路径一律
  tmp + rename 原子提交（崩溃安全）

详细设计见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 与 [`docs/PHASES.md`](docs/PHASES.md)；
变更历史见 [`CHANGELOG.md`](CHANGELOG.md)。

## 开源

- 📄 许可证：[MIT](LICENSE)
- 🤝 贡献指南：[CONTRIBUTING.md](CONTRIBUTING.md)
- 🔒 安全政策：[SECURITY.md](SECURITY.md)
- 📜 行为准则：[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 📝 变更日志：[CHANGELOG.md](CHANGELOG.md)
- ✍️ 签名说明：安装包**未做代码签名**（个人开源项目，签名为外部成本决策）——
  Windows 首次运行若弹 SmartScreen「已保护你的电脑」，点「更多信息 → 仍要运行」即可；
  产物完整性以 Release 页附带的构建流水线（SBOM + Secret Scan）与版本 tag 为准。

## 开发计划约束遵守情况

- ✅ 仅声明 `windows` 与 `android` 平台，无 iOS/macOS/Web 适配代码
- ✅ 默认零网络请求、无云服务 API、无账号系统（同步为可选的用户自配 WebDAV 端到端加密）
- ✅ 无 AI 功能、图层混合模式、蒙版、PSD 导出、录音、协作、内购
- ✅ UI 层 / 绘图引擎层 / 数据存储层严格分层（见架构文档）

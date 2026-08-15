# 后续改进技术实施方案（2026-08-15）

> 依据：中英双语权威信源多方交叉验证（Flutter 官方文档/博客、riverpod.dev、
> pub.dev、掘金/技术栈/ourcoders 社区报道），截止 2026-08-15。
> 目的：为三项后续改进（完整接口化、material_ui 迁移、ChangeNotifier 全面替代）
> 提供可执行技术实施方案与支撑。

---

## 一、完整接口化（S4b：drawing→notes 横向依赖消除）

### 1.1 权威方案（交叉验证一致）
| 来源 | 核心结论 |
| --- | --- |
| Flutter 官方 dependency-injection 文档 | 层间通信靠**构造注入**；接口允许 swap 实现不改消费代码；fakes/mocks 可测 |
| 掘金《Flutter 组件化方案探索》(2026-07) | 依赖倒置 + 抽象接口（Dart 3 `abstract interface class`）+ 按业务域拆分接口包 + 构造注入 |
| 本项目已有基础 | `core/notes_accessor.dart`（INotebookAccessor 契约骨架）——与掘金方案一致 |

### 1.2 实施方案（渐进，不冒险）
```
Step 1（已完成）：core/notes_accessor.dart 接口契约骨架
Step 2：drawing 消费方（editor_exporter/search_service/editor_page）改为
        构造注入 INotebookAccessor（依赖接口，不依赖 notes 实现）
Step 3：notes 侧实现类 implements INotebookAccessor（如 NotebookAccessorImpl）
Step 4：app.dart 装配点（DI 组装）注入实现，drawing 完全不知 notes 存在
Step 5：边界脚本白名单清零，drawing→notes 横向依赖归零
```
- 关键：`abstract interface class`（Dart 3）+ 构造注入（官方推荐）
- 测试：fakes 实现接口即可单测 drawing 逻辑（官方 testing 指南）

## 二、material_ui/cupertino_ui 迁移评估（11 月弃用前）

### 2.1 权威事实（交叉验证一致）
| 来源 | 关键信息 |
| --- | --- |
| Flutter 官方 3.47 博客 + pub.dev/material_ui | 独立包 1.0 已发布；`dart fix --apply --code=migrate_design_widgets` 自动迁移 import |
| ourcoders/掘金/技术栈 (2026-08-13) | 迁移自愿但**11 月秋季版正式弃用旧库**；MaterialUiCompatibilityBridge 桥接生态迁移期 |
| 官方已知 bug | migrate 工具可能不更新 pubspec → 手动 `flutter pub add material_ui` |

### 2.2 迁移评估（本项目）
- **影响面**：本项目大量使用 `package:flutter/material.dart`（全 UI 层）+ 少量 cupertino（app_design）
- **风险**：第三方依赖（pdfrx/hotkey_manager 等）可能仍用旧 import → 需 MaterialUiCompatibilityBridge
- **时间窗口**：11 月弃用前完成；当前 3.47 可自愿迁移
- **实施方案**：
```
Step 1：flutter pub add material_ui（+cupertino_ui）
Step 2：dart fix --apply --code=migrate_design_widgets（自动改 import）
Step 3：MaterialApp.builder 包 MaterialUiCompatibilityBridge（桥接第三方旧依赖）
Step 4：验证视觉快照 + Impeller shader/文字渲染一致性
Step 5：288 测试回归 + 手动 UI 走查
```

## 三、ChangeNotifier → Riverpod Notifier 全面替代

### 3.1 权威方案（交叉验证一致）
| 来源 | 核心结论 |
| --- | --- |
| riverpod.dev from_change_notifier | AsyncNotifier 取代 ChangeNotifier：`build()` 替代 initState 初始化；AsyncValue 自动处理 loading/error/data；免 try/catch/finally 样板 |
| 社区迁移案例（Claude Code 全项目迁移） | 保留 Repository/实体不动；ProviderScope 取代 MultiProvider；全局 Provider 声明替代构造注入；ConsumerWidget+ref.watch 替代 Consumer |

### 3.2 实施方案（本项目，分模块渐进）
```
Step 1（已完成）：ProviderScope 接入 + themeProvider（app 层）
Step 2：DrawingController（核心，ChangeNotifier）→ Notifier
        - build() 承载初始化；state 承载文档状态
        - 方法与命令栈保持（application 层不动）
Step 3：EditorViewModel → Notifier/AsyncNotifier（UI 逻辑）
Step 4：AppThemeController → Notifier（darkModeProvider 对接）
Step 5：UI 层 Consumer → ConsumerWidget + ref.watch/ref.read
验证：每步独立 analyze + 288 测试回归
```
- 关键：**状态不可变 + AsyncValue**（官方强调"immutable state → 更少错误"）
- 红线：Repository/实体/业务逻辑不动（社区案例明确"data layer stays untouched"）

## 四、优先级与执行顺序建议

| 优先级 | 改进项 | 风险 | 依赖 |
| --- | --- | --- | --- |
| P0 | material_ui 迁移（11 月弃用硬期限） | 中 | flutter upgrade + dart fix |
| P1 | ChangeNotifier 全面替代（逐步） | 中 | Riverpod 已接入 |
| P1 | S4b 完整接口化 | 低-中 | 接口骨架已完成 |

## 五、交叉验证结论

三方权威信源（官方文档 + 官方博客 + 社区实践）**完全一致**：
1. 接口化：`abstract interface class` + 构造注入 + fakes 测试（掘金与官方同方案）
2. material_ui：`dart fix` 自动迁移 + 兼容桥接（官方博客 + 国内三站同内容）
3. Riverpod：AsyncNotifier + AsyncValue + ProviderScope（riverpod.dev 官方 + 社区案例）

> 本方案为后续改进提供完整支撑；按 P0→P1 渐进执行，每步独立验证、独立提交。

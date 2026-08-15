# 项目架构评估与优化方案（2026-08-15）

> 依据：Flutter 官方 app-architecture 文档（2026-05 更新，中英双语核实）+ 社区
> Clean Architecture/Feature-First 实践 + AI 原生架构趋势（截止 2026-08-15）。
> 项目：中国政府内部开发项目（Flutter，画布+笔记双功能，280 测试基线）。
> 原则：架构评估不改变功能；优化"渐进、低风险、可回滚"；每文件 ≤500 行。

---

## 一、当前架构解析（实测结论）

### 1.1 目录结构（Layer-First 分层）
```
lib/
├── engine/    38 文件（绘图/笔记核心逻辑：controller/commands/codecs/sync）
├── models/     9 文件（实体：document/stroke/text_item/shape_item...）
├── storage/    7 文件（持久化：codec/storage_service/file_provider...）
├── ui/        32 文件（pages 19 + widgets 11 + 顶层）
└── 顶层       4 文件（main/app/app_design/theme_controller）
```

### 1.2 依赖方向（实测）
- `ui → engine`（13 文件）、`ui → models`（11 文件）、`ui → storage`
- `engine → models`（18 文件）、`engine → storage`（2 文件）
- `storage → models`（4 文件）
- **基本单向流**（ui → engine/storage → models），分层本身合理 ✅

### 1.3 自检三问（官方/社区评估标准）
| 检查项 | 结果 | 说明 |
| --- | --- | --- |
| ① 修改测试：改笔记字体是否需动绘图模块？ | ❌ **未通过** | 绘图（editor_page 系列）与笔记（notebook_view/home）**同层混放**于 ui/pages，无物理隔离 |
| ② 导入检查：绘图模块 import 是否出现 notes/？ | ❌ **未通过** | 无 feature 目录结构；notebook_view_page 直接 import engine（横向耦合） |
| ③ 单测可行性：业务逻辑能否脱离 dart:ui 测试？ | ⚠️ **部分不通过** | models 3 文件依赖 `dart:ui`（Offset/Color），非纯 Dart 实体 |

### 1.4 发现的问题（按严重度）
| # | 问题 | 严重度 | 影响 |
| --- | --- | --- | --- |
| A | 绘图/笔记**物理混放**（Feature-First 缺失） | 🔴 高 | 修改笔记可能影响绘图编译；无法按功能整体删除 |
| B | `notebook_view_page.dart` 直接依赖 engine（横向耦合） | 🟠 中 | 破坏单向流，跨模块改动互相影响 |
| C | models 依赖 `dart:ui`（实体不纯净） | 🟡 中 | 纯 Dart 单测受限；实体与 UI 库耦合 |
| D | `shape_library.dart`（engine）反向依赖 ui | 🟡 低 | 单处反向依赖（需核查后消除） |

---

## 二、2026 最佳实践对照（官方结论）

Flutter 官方（2026-05 app-architecture）推荐：
1. **两层基础**：UI 层（Views + ViewModels/MVVM）+ 数据层（Repositories + Services）
2. **可选 Domain 层**：复杂业务逻辑时加（interactors/use-cases）
3. **单向数据流（UDF）**：状态从数据层→逻辑层→UI；事件反向
4. **单一数据源（SSOT）**：Repository 是唯一可改数据的地方
5. **Feature-First 优先**（社区共识）：按功能切分（presentation/application/domain/data 子文件夹），删除/修改只需动一个文件夹
6. **AI 原生**（2026 加分项）：清晰分层让 AI 工具（Cursor/Copilot）精准定位，错误率降约 40%

## 三、目标架构（"AI 友好的模块化整洁架构"）

```
lib/
├── core/                        # 共享内核（不依赖功能模块）
│   ├── theme/                   # 全局颜色/字体（app_design/theme_controller 迁入）
│   ├── storage/                 # 抽象存储接口 IStorage（storage 迁移）
│   └── di/                      # 依赖注入（Service Locator，新增）
│
├── features/
│   ├── drawing/                 # 🎨 绘图功能（完全独立，可整删）
│   │   ├── domain/              # 绘图实体（画布/图层/笔画/形状）
│   │   ├── application/         # 绘图控制器/用例（engine controller/commands）
│   │   ├── infrastructure/      # 绘图引擎实现（渲染/缓存/编解码）
│   │   └── presentation/        # 绘图 UI（editor_page 系列/工具栏）
│   │
│   └── notes/                   # 📝 笔记功能（完全独立，可整删）
│       ├── domain/              # 笔记实体（标题/富文本块/页面）
│       ├── application/         # 笔记控制器/用例
│       ├── infrastructure/      # 富文本/存储实现
│       └── presentation/        # 笔记 UI（notebook_view/home/编辑器）
│
└── shared/                      # 跨功能共享 UI（通用按钮/弹窗/扩展）
    ├── widgets/
    └── extensions/
```

**关键规则**：
- 画布与笔记**物理隔离**：修改/删除任一模块不牵连另一个
- 依赖只从上往下：presentation → application → domain ← infrastructure（依赖倒置）
- **实体（domain）纯 Dart**：不 import dart:ui / flutter / storage（灵魂纯净）
- 跨模块共享走 `core/` + `shared/`，禁止直接横向 import

## 四、落地路线（渐进、低风险、可回滚）

| 阶段 | 动作 | 风险 | 验证 |
| --- | --- | --- | --- |
| S1 | **纯物理移动**：engine/models/storage/ui 按功能归入 features/{drawing,notes}/，git 只改路径不改内容 | 低 | analyze + 280 测试全绿 |
| S2 | 消除 D：核查 shape_library → ui 反向依赖，抽离共享常量到 core/ | 低 | analyze |
| S3 | 实体纯净化：models 中 Offset/Color 引用改纯 Dart 数值（如 (x,y) 或 double），或仅对纯实体（document/notebook）去 dart:ui | 中 | 单测 + 全量测试 |
| S4 | 横向耦合治理：notebook_view_page 对 engine 的依赖改为经 application 接口 | 中 | 依赖方向复查 |
| S5 | 引入 Riverpod（编译时安全/可测试）做状态管理，替换手写 Controller 接线 | 中-高 | 分模块迁移 |

**S1 立即可行**：当前 engine/models/storage/ui 已按层内聚，物理移动不改任何 import 相对路径的语义（用相对路径的项目内 import 会自动跟随目录变化——需核查 import 风格后执行）。

## 五、结论

**当前架构：分层合理（单向流 ✅）、实体纯净度 ⚠️、功能隔离 ❌。**

- **不用推翻重来**：分层（engine/models/storage/ui）方向正确，符合官方"两层+可选领域层"；
- **最需改进**：**Feature-First 物理隔离**（画布/笔记分家）——这是"寿命与进化成本"的关键；
- **次优**：实体纯净化（去 dart:ui）、横向耦合治理（notebook→engine）；
- **长期**：Riverpod 状态管理 + AI 原生（Monorepo/Modular Monolith 理念）。

> 本报告为架构评估与蓝图；落地按 S1→S5 渐进执行，每步独立验证、独立提交，
> 不破坏 280 测试基线。

# 架构重构蓝图（MVVM 分层 + 文件铁律）

> 状态：设计定稿 · 2026-08-13
> 依据：用户"施工蓝图"指令 + 政府级验收要求（可追溯、稳健、可维护）
> 原则：**不推倒重来**——现有 4 层架构（数据/引擎/存储/界面）方向正确且已通过
> 118 项测试；本次重构为**外科手术式拆分**：补 ViewModel 胶水层、拆超行文件、
> 强化依赖注入与防御性编程，全程测试全绿、风险可控。

---

## 1. 现状体检（2026-08-13 实测）

| 层 | 现有文件 | 行数 | 铁律(250) |
|---|---|---|---|
| Controller（胶水层雏形） | `engine/drawing_controller.dart` | 931 | 🔴 |
| Repository | `storage/storage_service.dart` / `notebook_storage.dart` | 213/299 | ✅/🟡 |
| Service | `engine/encryption_service.dart` / `search_service.dart` | 155/106 | ✅ |
| Renderer | `ui/canvas_painter.dart`(+MiniMap) / `engine/layer_compositor.dart` / `stroke_renderer.dart` | 264/102/142 | 🟡/✅ |
| Model | `models/`（document/notebook/stroke/layer/selection） | notebook 408 | 🔴 |
| View（最大痛点） | `ui/pages/editor_page.dart` | **2492** | 🔴 |

**结论**：违反铁律 6 个 🔴 + 2 个 🟡。核心问题是**巨型 View（editor_page）**
与**巨型 Controller（drawing_controller）**，且 editor_page 内混有纯展示组件、
工具栏、状态栏、对话框、浮层等本应独立的内容。

## 2. 目标架构（features/ 分层 + 4 层底座）

```
lib/
├── main.dart                  # 入口（<100 行，含单实例锁、依赖注入装配）
├── app/                       # 应用全局（MaterialApp、主题、路由）
├── features/                  # 按功能模块（新增层）
│   ├── editor/                # 编辑器模块
│   │   ├── view/              #   · 纯展示 Widget（不含业务逻辑）
│   │   │   ├── editor_page.dart          # 主页面：仅组装子组件
│   │   │   ├── toolbar_widget.dart       # 工具栏（工具切换按钮）
│   │   │   ├── statusbar_widget.dart     # 状态栏（缩放/工具/坐标）
│   │   │   └── mini_map_widget.dart      # 小地图
│   │   ├── viewmodel/         #   · 胶水层（UI ↔ 引擎/存储）
│   │   │   └── editor_viewmodel.dart     # 工具状态/选区/就地编辑/保存调度
│   │   └── model/             #   · 编辑器 DTO（页面级模型）
│   ├── notebook/              # 笔记本模块（页面管理）
│   └── password_disk/         # 密码盘模块（设置页）
├── core/                      # 4 层底座（现有结构保留，仅瘦身）
│   ├── engine/                #   【绘图引擎层】渲染/图层/手势/笔画
│   ├── data/                  #   【数据层】模型 + 压缩 + 序列化
│   ├── storage/               #   【存储层】文件/密码盘/仓库接口
│   └── crypto/                #   【加密层】AES-GCM + KDF
└── utils/                     # 工具（扩展函数、防御校验）
```

## 3. ViewModel 胶水层设计（关键新增）

**职责边界**（对应"高级程序员"分层铁律）：
- **View**：只负责显示与手势，**绝不写** `File.readAsBytes`、`_compositor.rasterize`、
  `if (await exists)`；
- **ViewModel（EditorViewModel）**：持有/协调 `DrawingController`（引擎）与
  `NotebookStorage`/`PasswordDisk`（存储）；管理工具状态、防抖保存（2s 计时器）、
  就地编辑提交、加密解锁会话密钥——**UI 只与 ViewModel 对话**；
- **Engine（DrawingController）**：纯引擎职责（笔画/图层/撤销/选区/视口/缓存），
  不感知 UI 与文件格式；
- **Repository/Storage**：纯 IO，不感知 UI。

**现有 DrawingController 的角色**：它已是事实上的引擎+部分调度，931 行。
重构时**不拆散它**（118 测试全部依赖其行为），而是：
1. 把"保存调度/会话密钥"等**跨层职责**上移到 EditorViewModel；
2. 把绘制/手势/浮层 UI 从 editor_page 下沉到独立组件。

## 4. 分阶段重构路线（每阶段验证全绿）

| 阶段 | 动作 | 风险 | 验证 |
|---|---|---|---|
| **R1** | editor_page 纯展示组件外移（番茄钟 `_PomodoroTimer`、快捷键行 `_ShortcutRow`、指纹徽章 → 独立文件） | 零（无状态耦合） | analyze+测试 |
| **R2** | 工具栏 → `features/editor/view/toolbar_widget.dart`（onTap 回调参数化） | 低（闭包改写） | analyze+测试 |
| **R3** | 状态栏 → `statusbar_widget.dart`；MiniMap → `mini_map_widget.dart` | 低 | analyze+测试 |
| **R4** | 建立 `EditorViewModel`：从 editor_page 抽取工具状态/防抖保存/会话密钥管理 | 中（行为不变，仅迁移） | 全量回归 |
| **R5** | 巨型 Controller/Model 按职责拆子文件（保留 public API 兼容） | 中 | 全量回归 |
| **R6** | 文档同步（ARCHITECTURE.md）+ 打包 | — | 冒烟+打包 |

**停止条件**：任何一步导致既有 118 测试变红 → 立即回退该步，不改"稳"。
（教训：上次"工具栏全用不了"源于静默风险，重构必须每步可逆、测试兜底。）

### R5 执行决策（2026-08-13 定稿）：命令类拆出，引擎状态机保留聚合

**已拆**：`HistoryEntry`/`DocCommand`/`SnapshotCommand`/`AddStrokeCommand`
→ 独立文件 `engine/document_commands.dart`（自包含、零状态耦合、可独立测试），
drawing_controller 通过 3 个公开包装方法（`restoreLayersSnapshot`/`touchDocument`/
`afterStrokeUndoRedo`）交互，行为完全一致。

**保留聚合（不拆）**：drawing_controller 的视口变换/图层快照/历史栈/缓存重建。
理由（依据"单一职责是红线、行数只是闹钟"的专家级原则）：
1. 这些逻辑**共享同一批私有状态**（`_document`/`_caches`/`_currentLayerIndex`
   等，80+ 处交叉引用），属于**同一个"引擎状态机"模块的单一职责**；
2. 它们属于**同一变化方向**（都随引擎状态变化而联动），不是"两个不同的
   变化方向"（对照口诀：负责 A 和 B 才拆，只负责 A 就安心放着）；
3. 强行拆子文件需引入跨文件公开包装方法，反而增加调用面与复杂度——
   是典型的"为了拆而拆"。

**结论**：874 行虽在警戒水位内偏高，但单一职责成立、内聚完好，保留聚合；
后续若出现真正独立的职责（如导出/取色独立成 Service），再按红线拆分。

## 5. 高级程序员思维落地清单（融入每一步）

1. **命名即文档**：变量带类型语义（`masterKey`/`recoveryEnvelope`），方法
   带失败语义（`decryptNotebookWithKey` 失败抛 `FormatException`）；
2. **防御性校验**：对外输入（文件路径、密钥长度、恢复密钥格式）入口处校验，
   非法即明确异常——不吞错；
3. **不可变数据**：PageVersion 快照深拷贝（已实现）；DTO 字段 `final`；
4. **异常外科手术**：区分"可预见业务错误（提示用户）"与"系统错误（日志+兜底）"；
5. **依赖注入**：`createPasswordDisk()` 按 `kDebugMode` 选 Mock/Real（已实现），
   编辑器存储依赖同理可注入；
6. **开关解耦**：新特性用配置开关包裹，发布与启用分离（政府验收可逐步开放）。

## 6. 与政府验收的关系

- **可追溯**：每阶段对应 git 提交 + 测试增量；
- **可维护**：单文件 ≤250 行目标（editor_page 2492 → 目标 ≤400，再逐步拆）；
- **抗腐化**：存储层换实现（本地→未来云端）只改 `core/storage`，业务零改动
  （DocumentRepository/NotebookRepository 接口已就绪）；
- **安全**：密码盘/加密逻辑集中在 `core/crypto` + `features/password_disk`，
  审计面清晰。

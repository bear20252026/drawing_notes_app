# 状态管理决策树（Riverpod ↔ 手工协作者）

> 定案 2026-11-15 ｜ 适用：全体贡献者与新成员
> 目的：**划清两套状态机制的边界**，防止后续开发"精神分裂"（同一份状态两处
> 持有、或不知道该往哪套里加）。

---

## 0. 一句话结论

**并存不是错，是必然。** 两套机制解决的是不同问题：

| 机制 | 解决什么 | 代价 |
| --- | --- | --- |
| **Riverpod** | 跨组件共享、可独立单测、生命周期自动释放 | 全局状态树重建成本；高频更新会触发无谓 rebuild |
| **手工协作者**（ChangeNotifier / 普通类 + 局部 setState） | 高频局部更新、精细帧控制、零重建开销 | 需自己管生命周期与释放 |

绘图编辑器每秒数十次指针事件、每帧重绘画布——把它塞进全局状态树是**性能自杀**。
反过来，主题/语言这类"一处改、全应用响应"的状态用手工传递是**样板地狱**。

---

## 1. 决策树（新增状态时按顺序问）

```
① 这份状态需要「跨路由/跨组件」共享吗？
   ├─ 否 → 走 ②
   └─ 是 → 走 ③

② 它的更新频率如何？
   ├─ 每帧/每次指针事件（画布、手势、拖拽草稿）
   │    → 【手工协作者】普通类持有 + 局部 setState / CustomPainter
   │      理由：零 rebuild 开销，精细帧控制
   └─ 用户操作级（按钮、表单、面板开关）
        → 【StatefulWidget 局部 state】
          理由：作用域最小，无需引入任何框架

③ 它是「配置/偏好」类（主题、语言、对比度、设置项）吗？
   ├─ 是 → 【Riverpod】Notifier + ref.watch
   │        位置：core/di/providers.dart（跨功能共享）
   └─ 否 → 走 ④

④ 它是「业务流水线」状态（保存队列、同步进度、加密会话）吗？
   ├─ 是 → 【手工协作者】+ 组合根注入
   │        理由：生命周期与业务事务绑定，不是 UI 重建问题；
   │              需要精确的 dispose / 清零时机（安全要求）
   └─ 否 → 走 ⑤

⑤ 它是「某个域的独立纯状态」，且需要独立单测吗？
   ├─ 是 → 【Riverpod】域内 Notifier（示范单元模式）
   │        位置：features/<域>/application/*_notifiers.dart
   │        参考：di_providers.dart 容器接入（drawing_notifiers 示范单元
   │        已于 R5 裁决删除，2026-11-17）
   └─ 否 → 默认【StatefulWidget 局部 state】，别过度设计
```

---

## 2. 当前真实分工（实测，2026-11-15）

**Riverpod 使用面：7 个文件 / 10 个 provider**——刻意保持薄。

| 位置 | 职责 | 机制 |
| --- | --- | --- |
| `core/di/providers.dart` | 主题（family 按对比度档）、主题模式 Notifier | Riverpod（跨功能共享） |
| `features/drawing/application/di_providers.dart` | **容器接入**：每文档一个 DrawingController（`autoDispose.family`） | Riverpod 壳 + 内部 ChangeNotifier |
| `features/drawing/presentation/editor_statusbar.dart` | 消费容器 provider（drawingControllerProvider） | Riverpod |
| `main.dart` / `app.dart` | ProviderScope 装配、主题消费 | Riverpod |

**手工协作者：44 个 StatefulWidget + 大量普通协作者类**——主体。

| 典型 | 为什么不用 Riverpod |
| --- | --- |
| `DrawingController`（971 行 + 8 part） | 每帧重绘、指针事件高频；内部 viewScale/viewOffset/_history/_selectionDraft 精细控制 |
| 存储写队列（`StorageWritePipeline`） | per-document 独占队列，事务语义，与 UI 重建无关 |
| 加密会话（`KekSessionCache` / `MediaCryptoService`） | 需要**精确的清零时机**（安全要求），不能交给框架的 dispose 时序 |
| 锁守卫（`AppLockGate` 生命周期） | 与 OS 生命周期信号绑定，需豁免窗口等自定义状态机 |

---

## 3. 迁移边界（审慎约定，**不要擅自推进**）

**R5 裁决（业主批准 2026-11-17）**：drawing_notifiers.dart 三域 Notifier 与
di_providers 派生 provider（drawingDirtyProvider 等）生产零消费，已整体删除。
容器本体 drawingControllerProvider 保留（已生产接线）。EditorViewModel 同期
去 ChangeNotifier 变纯状态协作者（刷新经 _applyState 单点）。

- `DrawingController` 内部的 `viewScale/viewOffset`、`_history/_historyPosition`、
  `_selectionDraft/_selectionTool` **暂不替换**——避免高频路径引入 rebuild。
- 脏标记由 `editor_statusbar` 直读 `controller.isDirty`（派生 provider 已删）。

**推进原则**：一次只迁一个域，迁完必须跑全量门禁 + UI 回归；不允许"顺手把
DrawingController 也改成 Notifier"。

---

## 4. 反模式（评审会挡）

| ❌ 反模式 | 为什么挡 |
| --- | --- |
| 同一份状态既在 provider 又在 controller 字段 | 两个真相，必然漂移 |
| 把每帧更新的画布状态放进 `ref.watch` | 每帧重建整棵子树，卡顿 |
| 用 provider 持有密钥/口令 | 框架 dispose 时序不可控，违反零化要求 |
| 在 `core/di/providers.dart` 加绘图专属 provider | 污染共享内核；且抬高 Martin instability（撞架构规则 3b 基线 0.4） |
| 新增状态不写归属注释 | 下一个人不知道该往哪套加 |

---

## 5. 新增 provider 的硬性要求

1. **顶层 `final` 不可变声明**（编译期安全、可 override 测试）。
2. **位置分域**：跨功能共享 → `core/di/providers.dart`；域专属 →
   `features/<域>/application/`。**core 只放共享的**。
3. **出向依赖尽量少**：`core/di` 每多一条 import，instability 就上一档
   （0.33 → 0.50 会撞架构门禁）。参数宁用 `bool` 不引枚举。
4. **写清职责注释**：这个 provider 是"已接管"还是"示范单元"，UI 侧有无命中。

---

## 6. 相关文档

- `AGENTS.md` §8 — 状态管理划界（本文件的强制摘要）
- `docs/ARCHITECTURE.md` — 分层与依赖方向
- `test/architecture_test.dart` 规则 3b — Martin 耦合度量基线
# drawing_notes_app 体验与质量审计报告（第 4 轮）

- **日期**：2026-09-05
- **范围**：用户交互体验（UX）、产品质量、UI 设计美观度
- **方法**：只读静态审计（294 个 Dart 源文件）+ 与前三轮报告比对抽查 + 小范围安全修复
- **前置报告**：`audit_ux_2026-09-02.html`（v1.8.0+31 基线）、`audit_round2_2026-09-03.html`、`audit_round3_2026-09-04.html`
- **验证限制**：本次审计在无 Flutter/Dart SDK 的环境完成，未运行 `flutter analyze` / 测试；所有结论基于代码证据（文件:行号），已实施的代码修改为局部声明式改动，合入前请跑 `flutter analyze && flutter test`。

---

## 一、总体评价

工程底子明显好于同类项目，前三轮审计暴露的多数 P0/P1 项在架构层面已有对策沉淀：

| 维度 | 现状 |
|---|---|
| 设计令牌 | `apple_design.dart` / `apple_motion.dart`：颜色、间距、圆角、排版、动效曲线/时长/弹簧全部注明规范出处 |
| 无障碍基建 | 高对比度档（`apple_contrast.dart`）、键盘焦点环（`apple_focus.dart`）、`MediaQuery` 减弱动效读取 |
| 主题工程 | M3 状态层、发丝线分隔、按钮 `minimumSize: 44×44`（`app_design.dart`） |
| 性能意识 | 液态玻璃着色器带平台性能闸门（`liquid_glass_shader.dart`）；锁屏模糊 sigma 30→18 已按上轮建议收敛（`pin_pad.dart:178-179`） |
| 锁屏组件 | 输错抖动清空、触感反馈、可变长度模式、窄屏 FittedBox 防溢出（`pin_pad.dart`） |
| i18n 基建 | `app_zh.arb` / `app_en.arb` 各 50 键完全对齐（第三轮确认） |

核心差距仍是第三轮那句结论：**「有设计系统、无设计执行」**——令牌层完备，但执行层硬编码、热区不达标、反馈缺失的问题成片存在。本轮在抽查确认前三轮问题仍未修复的同时补充了若干新证据，并直接修复了其中最安全的高频问题（见第五节）。

---

## 二、用户交互体验（UX）

### 高

1. **画布 8 向缩放手柄命中区仅 10×10px** — `lib/features/drawing/presentation/resize_handles.dart:38,76-95`
   手指接触面约 40px，10px 命中率极低；这是画板核心操作。**本轮已修复**（视觉不变，热区扩至 44×44，见 5.2）。

2. **触觉反馈近乎全库缺席** — 全库 `HapticFeedback` 仅 **4 处命中**（其中 3 处在 `pin_pad.dart`）。
   `ApplePressable`（全库按钮基座）、IconButton、Switch、Slider、列表滑动删除均无触感。触屏设备上「按了没反应」的廉价感主要来自这里。建议在 `ApplePressable` 内统一加 `HapticFeedback.selectionClick()`，一处改动全库受益。

3. **语义化（Semantics）几乎空白** — 全库 `Semantics(button: true)` 仅 **5 处命中 / 294 文件**。
   屏幕阅读器与无障碍树拿不到按钮角色；键盘/开关控制无法遍历主要操作。与项目已有的高对比度、焦点环基建形成明显落差。

### 中

4. **颜色选择器缺选中态 + 两处小 bug** — `lib/shared/widgets/color_picker_dialog.dart`
   - 预设色板点击后无「当前色」指示，用户无法确认选中了哪格（**本轮已修复**：外圈强调色描边 + 居中勾选 + 触感）；
   - RGB 读数恒为 0/1：`Color.r/g/b` 在新色彩模型下是 0–1 的 double，`.r.round()` 永远得 0 或 1，应为 `(r * 255).round()`（**本轮已修复**）；
   - 色相条触控区 22px、且实际渲染宽度约 320 与取色换算宽度 300 不一致（约 6.7% 色相偏差）（**本轮已修复**：热区 44px、宽度显式 300 对齐换算）。

5. **原生 AlertDialog 32 处**与定制 `AppleDialog` 并存，「确定/取消」文案生硬（第二、三轮已指出，本轮统计确认未收敛）。

6. **加载态 6 处裸用 CircularProgressIndicator**；项目已有 `skeleton.dart` 骨架屏组件但多数页面未接。

7. **首页 / 笔记本页 / 全部文档页无快捷键层**（第三轮，`home_page.dart` / `notebook_view_page.dart` / `all_docs_page.dart`）——画板有完整快捷键层，管理类页面 Ctrl+N / F2 / Delete 全无。

8. **锁屏无宽限期**（第二轮 P0-4）：切后台即锁，Windows 任务视图扫一眼就回锁屏。建议 30s 可配置宽限。

### 低

9. `pin_pad.dart` 15 处、`app_lock_gate.dart` 8 处硬编码 `Colors.*`。锁屏白字磨砂属刻意的 iOS 复刻可保留，但建议抽命名常量（如 `_kLockInk`），避免与主题 token 混读后误判。

10. **画板上下文菜单仅右键可达**（第三轮：`editor_page_overlays.dart:102` 等），触屏与键盘双盲；弹菜单位置硬编码 `RelativeRect.fromLTRB(100,100,0,0)`。

---

## 三、产品质量

### 高（本轮抽查确认仍存在）

1. **裁剪保存 await 后 setState 缺 mounted 检查** — `lib/features/drawing/presentation/editor_page.dart:418` 附近（第三轮提出；本轮核对 415-420 行连续 await 后直写 setState，等待期间退出页面即 `setState() called after dispose()`）。

2. **日程页 await 后 setState 缺 mounted 检查 + 写入失败无提示** — `lib/features/schedule/presentation/schedule_page.dart:368-395`。本轮统计：该文件 `mounted` 仅 1 处命中（`:51`），三处事件操作（`:374/384/394`）仍裸奔，且无 try/catch，「添加失败」表现为「什么都没发生」。

3. **待办 store 无锁 read-modify-write** — `schedule_event_store.dart:92/99/110`（第三轮）。连点两次添加必丢一次更新；修法已指明：照抄 `note_block_doc_store.dart:134` 的 `_enqueue` 串行化。

4. **事务回滚失败只 print，画布停在半应用状态** — `lib/features/drawing/application/document_transaction.dart:64-68`（第三轮）。生产代码 print 残留 + 撤销栈不可信时用户不知情。

### 中

5. **删除笔记本遗留 .bak 孤儿文件** — `notebook_storage.dart:237/338-364`（第三轮）：隐私风险 + 行为不一致（其余三个存储已清理）。
6. **保险库槽位 .tmp 残留含被包装主密钥** — `lib/core/security/vault_key_service.dart:513-515`（第三轮）。
7. **l10n 名存实亡** — 本轮统计：硬编码中文 `Text('…')` 全库 **222 处**，仅 **13 个文件**引用 l10n；第三轮指认的 5 个整页零 l10n（`app_lock_settings_page` / `doc_page` / `app_shell` / `settings_page` / `all_docs_page_widgets`）应优先收编。
8. **`withOpacity` 弃用 API 散布数十文件**（精度损失 + 未来移除风险），建议批量迁移 `.withValues(alpha:)`（新 API 已在用，迁移无 SDK 门槛）。

### 低

9. 6 处弹窗 `TextEditingController` 不 dispose（第三轮清单）。
10. PDF 预览 / 首页缩略图 `Image.memory` 未降采样（第三轮）。
11. WebDAV 配置解析失败静默降级为空配置（第三轮）。

---

## 四、UI 设计 / 美观度

1. **「有系统、无执行」仍是最大的美观度短板**：`AppDesign` 与 `AppleColor` 双令牌源并存（10 个色值重复定义，5 个文件走旧源——第三轮），改新令牌对这 5 个文件不生效，配色会静默分叉。建议 `app_design.dart` 改为 re-export 别名层。
2. **缩放手柄用 `#42A5F5`（Material 蓝）游离于品牌色板外**（`resize_handles.dart`）——品牌强调色为 `#0066CC`。本轮未改：画布视觉需实机对比验证，建议下轮连同选中框/吸附线一起统一。
3. **弹窗语言不统一**（见 UX-5）：圆角、阴影、按钮排布在 32 处原生弹窗与定制弹窗间漂移。
4. **空态两极分化**（第二轮 #27）：部分页面有插画引导，部分只有一行灰字。
5. **字号硬编码散落数十文件**（`fontSize:` 直写），与 `AppleTypeScale` 梯子并存——排版四元组（字号/字重/行高/字距）被拆开后只剩字号，行高字距丢失，这是「看起来差不多但不够精致」的微观原因。
6. 本轮已统一：颜色选择器内全部直角色块 → 圆角 + 发丝线描边（`outlineVariant` token），对话框内观感与卡片/输入框语言对齐。

---

## 五、本轮已实施的改进（2 个代码文件，均为局部声明式 UI 改动）

### 5.1 `lib/shared/widgets/color_picker_dialog.dart`
| 改动 | 价值 |
|---|---|
| 预设色板加选中态（强调色外圈 + 对勾，新增 `_Swatch` 组件） | 用户第一次能确认「当前选的是哪格」 |
| `_sameColor` 容差比较 | HSV 往返有分量误差，`==` 会让选中态间歇失效 |
| 色域框 / 色相条加圆角（sm/xs）+ `outlineVariant` 发丝线 | 与全局卡片/输入框描边语言统一 |
| 色相条热区 22px → 44px（视觉不变） | HIG/WCAG 最小触控尺寸 |
| 色相条显式宽 300，与 `_pickHue` 换算对齐 | 修复约 6.7% 色相偏移 |
| RGB 读数 `(r*255).round()` | 修复恒显示 0/1 的 bug |
| 全部 `Colors.black26/white24` → `outlineVariant`/`outline` token | 深色模式下描边不再突兀 |
| 色板/色阶/最近色点击加 `HapticFeedback.selectionClick()` | 选中确认感 |

### 5.2 `lib/features/drawing/presentation/resize_handles.dart`
- 命中区 10×10 → **44×44**，视觉手柄保持 10×10 居中（桌面观感零变化；外层 `Stack(clipBehavior: Clip.none)` 已确认不会裁切热区）。
- 取舍说明：极小元素上相邻手柄热区会重叠（后声明者优先），已在代码注释中标注；如需更精细可按元素尺寸缩放 `_hitSize`。
- 附注：本文件原始行尾为 CRLF，本次重写为 LF；Dart 工具链两种均接受，但请知悉 diff 会显示整文件变更。

### 5.3 本报告
- `docs/AUDIT_UX_ROUND4_2026-09-05.md`

> 验证声明：沙箱无 Flutter/Dart SDK，以上改动未编译验证；全部为保守的局部 widget 改动，未触碰业务逻辑、状态流与公开 API。合入前请运行 `flutter analyze && flutter test`。

---

## 六、建议修复路线图（按投入产出排序）

| 批次 | 内容 | 对应条目 |
|---|---|---|
| U1 止血 | mounted 检查（editor/schedule）、schedule 无锁写入串行化、事务回滚异常化、错误文案人话化 + 重试 | 三-1/2/3/4，二-8 |
| U2 触控与反馈 | `ApplePressable` 统一触感、全库热区 ≥44 收尾（properties_panel / tags_view / edgeless 按钮）、Semantics 角色标注、上下文菜单长按/键盘入口 | 二-1/2/3/10 |
| U3 视觉统一 | 弹窗统一 AppleDialog、骨架屏接入、双令牌源收编、空态规范、l10n 收编 5 页面、withOpacity → withValues | 二-5/6，三-7/8，四-1/3/4 |
| U4 性能 | 画布包围盒剔除 + RepaintBoundary、序列化/加密进 isolate、图片降采样、搜索防抖 | 第二轮 P1 |

铁律沿用前三轮：批内不删功能、纯增强；每批 `flutter analyze` 0 告警 + 全量测试绿再进下一批。

---

## 附：本轮统计证据

| 指标 | 数值 | 说明 |
|---|---|---|
| Dart 源文件 | 294 | lib/ 下 |
| `HapticFeedback` 命中 | 4 处 | 其中 3 处在 pin_pad.dart |
| `Semantics(button: true)` | 5 处 | 无障碍角色标注近乎空白 |
| 原生 `AlertDialog(` | 32 处 | 与定制 AppleDialog 并存 |
| 裸 `CircularProgressIndicator(` | 6 处 | 骨架屏组件存在但未普及 |
| `showSnackBar` | 36 处 | 反馈主通道 |
| 硬编码中文 `Text('…')` | 222 处 | 仅 13 个文件引用 l10n |
| 硬编码 `Colors.*` 集中文件 | pin_pad 15 / app_lock_gate 8 | 锁屏族组件未走 token |

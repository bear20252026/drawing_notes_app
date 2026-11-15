# material_ui 迁移可行性评估（实测定案 2026-11-15）

> **结论：不是「纯体力活」，而是框架级替换。当前不做，本文记录实测证据与
> 将来若要做的前置条件。** 两次尝试（2026-11-14 自动迁移、2026-11-15 单文件
> 试点）均失败，失败根因不同，下文逐条给证据。

---

## 一、现状数据（`flutter analyze` 实测）

| 项 | 数量 |
| --- | --- |
| `deprecated_member_use` info 总数 | **270** |
| 其中 `package:flutter/material.dart` 导入弃用 | 207 |
| 其中 `GlobalMaterialLocalizations` 弃用 | 34 |
| 其中 `GlobalCupertinoLocalizations` 弃用 | 29 |
| 受影响文件（material 导入） | 207（lib + test + integration_test） |
| `flutter_localizations` 引用文件 | 27 |

**弃用来源**：Flutter 3.47.0-0.0.pre 起，`flutter/material.dart` 整体标记弃用，
官方建议改用 pub.dev 上的 `material_ui` / `cupertino_ui` 包。

**依赖现状**：两包已作为**传递依赖**存在于 `pubspec.lock`
（`material_ui 1.11.0` / `cupertino_ui 1.1.6`），`pubspec.yaml` 未直接声明。

---

## 二、两次尝试的失败根因（不同层次）

### 尝试 1（2026-11-14）：`dart fix --code=migrate_design_widgets`

- 自动改了 208 处，随后出现 **52 处 `ambiguous_import` +
  `non_constant_list_element`**，编译失败，整体回退。
- **根因**：`flutter_localizations` 与 `material_ui` / `cupertino_ui`
  **同时导出同名** `GlobalMaterialLocalizations` / `GlobalCupertinoLocalizations`。
  两个导入并存 → 符号歧义。

### 尝试 2（2026-11-15）：单文件试点 + 精确 `show` 导入

在 `lib/app.dart` 上按「移除全量 localizations 导入、改精确 `show`」方案试点：

```dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
```

**歧义问题确实解决了**，但暴露出**更深一层的阻塞**——3 处类型不兼容：

```
error • The argument type 'ThemeMode' can't be assigned to the parameter type 'ThemeMode?'
error • The argument type 'Provider<ThemeData>' can't be assigned to 'ProviderListenable<ThemeData?>'
error • The argument type 'ThemeData' can't be assigned to the parameter type 'ThemeData?'
```

**根因（关键）**：`material_ui` **不是 `flutter/material` 的别名或转发**，而是
**一套完整平行的 Material 实现**：

| 证据 | 位置 |
| --- | --- |
| 自定义 `ThemeData` | `material_ui/lib/src/theme_data.dart` |
| 自定义 `ThemeMode` / `MaterialApp` | `material_ui/lib/src/app.dart`（`class MaterialApp extends StatefulWidget`） |
| 自定义 `Theme` | `material_ui/lib/src/theme.dart` |
| 只复用 widgets 层 | `material_ui.dart` 仅 `export 'package:flutter/widgets.dart'` |

即：**两套 `ThemeData` 是不同类型，不能互相赋值**。项目现有的主题体系
（`core/theme/` 全家 + Riverpod provider）产出的是 Flutter 版 `ThemeData`，
喂给 material_ui 版 `MaterialApp` 必然类型错。

---

## 三、真实工作量（不是正则能解决的）

| 受影响面 | 数量 | 说明 |
| --- | --- | --- |
| `Theme.of(context)` 调用 | **227** | 每处返回类型变了，下游字段访问需逐一核对 |
| `ThemeData` 使用点 | **39** | 主题构造全部要换成 material_ui 版 |
| `MaterialApp` / `CupertinoApp` | **11** | App 根换实现 |
| 自定义 `RenderObject` / `CustomPainter` | 15 文件 | 与 widgets 层交互，需验证兼容 |
| 依赖 material 的测试文件 | **115** | `flutter_test` 的 widget 测试基建同步受影响 |
| `core/theme/` 主题体系 | 8 文件 | apple_design / app_design / 对比度 / 焦点 / 动效等全部重构 |

**并且**：`core/theme/app_design.dart` 等被 23 个文件依赖、`apple_design.dart`
被 80 个文件依赖——主题层是**高扇入枢纽**，换类型会波及全 UI 层。

---

## 四、判定：当前不做

**理由**：
1. **收益**：消除 270 条 **info 级**提示（不影响编译、不影响运行、CI 已用
   `--no-fatal-infos` 放行）。
2. **代价**：整个 UI 层换框架 + 227 处主题调用核对 + 115 个测试文件适配 +
   高扇入主题枢纽重构。
3. **风险**：绘图编辑器是 5.1 万行最复杂域，含 15 个自定义渲染文件；
   换 Material 实现可能引入难以定位的渲染/手势回归。

**收益/代价严重失衡**，且 info 级提示不构成技术风险。

---

## 五、将来若要做：前置条件与顺序

**不要**再用 `dart fix` 批量或正则替换——两次失败已证明不可行。正确顺序：

1. **等上游稳定**：确认 `material_ui` 与 Flutter 主线的类型关系是否收敛
   （目前两套 ThemeData 并存是根本障碍）。若上游提供兼容层/类型别名，
   工作量会大幅下降。
2. **先建主题适配层**：在 `core/theme/` 内引入单一转换点，把内部主题模型
   与具体 Material 实现解耦（现在是直接产出 Flutter `ThemeData`）。
   **这一步本身有独立价值**，可先做。
3. **再切 App 根**：11 处 App 根 + 主题 provider 一次性切换，跑全量 UI 回归。
4. **最后批量换导入**：207 个文件的 import 替换（此时才是体力活）。
5. **收尾**：移除 CI 的 `--no-fatal-infos` 旗标（4 处 workflow）。

**每步都必须**：全量门禁 + 三平台构建 + UI 回归（integration_test 7 个套件）。

---

## 六、当前处置（已生效）

- CI 4 处 `flutter analyze` 使用 `--no-fatal-infos`，info 级弃用不判红。
- 本文档作为**决策依据留档**，避免后人重复尝试已证伪的路径。
- 若上游类型关系收敛，重开评估时请先更新本文的实测数据。
# 子包边界与职责（核实定案 2026-11-15）

> 背景：审计中曾把 `packages/notebook_domain` 判为「近乎空壳、建议合并回主库」。
> **该判断有误**——只数了文件数，没看职责与门禁。本文记录核实结论，避免后人
> 重复误判、误删。

---

## 结论：两个子包都保留，不合并、不删除

| 子包 | 文件数 | 真实职责 | 判定 |
| --- | --- | --- | --- |
| `packages/editor_core` | 3 个 .dart + 测试 | 几何引擎（`GeometryEngine`）、`document_v2` 领域模型；被组合根 `geometryEngine` 使用 | **保留**：有实质内容 |
| `packages/notebook_domain` | 2 个 .dart | **六边形架构的 domain 端口契约**（3 个接口） | **保留**：是架构契约，不是空壳 |

---

## notebook_domain 为什么不是空壳

它承载 3 个**端口接口**（依赖倒置的 domain 侧契约）：

```dart
abstract interface class NotebookRepositoryPort { open / save / lock }
abstract interface class MediaRepositoryPort { read / store }
abstract interface class KeyProviderPort { deriveKey }
```

**三重证据表明它在架构里有承重作用**：

1. **被生产代码引用**：`lib/app/composition_root.dart` 持有这三个端口的
   注册位（`notebookRepository` / `mediaRepository` / `keyProvider`）。
2. **被两条架构门禁钉住**：
   - `test/architecture/forbidden_import_test.dart` —— 纯 Dart 约束
     （禁 Flutter / dart:io）+ **文件数基线 2**（删文件会当场判红）
   - `test/architecture/v2_dependency_boundaries_test.dart` —— V-004 同类约束
3. **设计意图明确**：ADR-001 的 domain 唯一可信来源，`infrastructure` 侧
   adapter（`EncryptedNotebookRepositoryV2` / `MediaRepositoryV2` / 平台
   KeyStore）实现这些端口——**domain 不依赖实现**（R-02/R-03）。

**当前状态如实说明**：端口已定义、注册位已留，但 adapter **尚未接线**
（组合根注释标 C-07 续批）。这是「契约先行、实现后补」的有意分期，
不是废弃代码。

---

## editor_core 为什么不合并回 features/

- 它是**纯 Dart 包**（无 Flutter 依赖），有独立 `pubspec` 与测试，
  受同样的纯 Dart 门禁保护——这份隔离本身是价值（几何算法可独立单测）。
- 合并会触碰 `features/drawing` 大量 import，而 drawing 是 5.1 万行的
  最复杂域。**收益（省一层 path 依赖）远小于风险（动最复杂域的依赖图）**。

---

## 关于 `lib/infrastructure/`

本地空目录，**git 未跟踪、全仓零引用**。不在版本库里，无需清理动作。
（若将来要落 domain 端口的 adapter，这里是自然落点。）

---

## 给后人的判据

判断一个包/目录是否「空壳」，**不能只数文件数**，要依次核实：

1. 有没有生产代码 import？（`grep -rn '<包名>' lib`）
2. 有没有架构门禁钉着它？（`grep -rn '<包名>' test/architecture`）
3. 文件里是接口契约还是实现？契约少而承重是正常的。
4. 有没有 ADR / 注释说明分期意图？

四条都过不了，才考虑清理；且**删改必须先征求用户同意**（AGENTS.md §7）。
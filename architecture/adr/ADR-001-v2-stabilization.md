# ADR-001：V2 稳定化渐进重构（2026-08-16）

状态：Deferred（暂缓——W3 裁决 2026-09-02：不推进 editor_core V2 全量重构，
避免僵尸决策。项目当前以增量修复批次演进；本文档保留作为架构演进参考，
其中「单一事实来源 / 依赖单向 / 敏感写失败关闭」等原则继续有效并已在
现有批次中逐项落实。若未来重启 V2 迁移，以本 ADR 为起点重新评估。）

## 背景

专家评审确认：项目当前**同一件事被多个地方管理**（形状多套几何、密钥多份状态、
页面多条保存路径、Android/Windows 无共同验收门槛）。需要大范围但有边界的重构——
**不是"删库重来"**。

## 决策（专家方案——严格执行不能偏移）

1. **资产处置**：保留约 45% 领域资产与稳定基础能力；抽离重建约 35% 高耦合
   编辑器、安全会话和存储编排；封存约 20% 实验性/双轨/未验证功能。
2. **框架**：Flutter 保留；内部架构必须换（应用层 + 平台适配边界）。
3. **目标架构**：
   - `packages/editor_core`（纯 Dart——Document 不可变/Commands/GeometryEngine/
     History/Serialization——禁 Flutter/dart:io/file_selector/path_provider/
     shared_preferences）
   - `packages/notebook_domain`（纯 Dart——NotebookSession/KeyHandle/LockPolicy/
     UseCases/Ports——禁 Widget/BuildContext/Platform/File）
   - `lib/app`（composition root + 唯一 ThemeController）+ `features/editor_v2` +
     `infrastructure`（storage v1 只读/v2/加密/平台 adapter/审计）+ `legacy`（禁新依赖）
   - 依赖单向：`presentation → application → domain/ports ← infrastructure`
4. **六批迁移**：A 安全护栏（3-5 天）→ B 几何核心（1 周）→ C 命令历史（1-2 周）
   → D 会话存储（1-2 周）→ E Editor V2 主路径（1-2 周）→ F 按价值恢复+删旧。
5. **冻结**：4 周——允许 Android 恢复/安全修复/V2 核心迁移/测试发布治理；
   延后图表/演示/同步/插件/形状库/非关键导出。
6. **数据兼容**：V1 只读兼容；V2 密文容器（schemaVersion + notebookId +
   keyEnvelope + authenticated payload）；迁移=复制、认证、校验、切换（绝不覆盖 V1）。

## 非协商规则（R-01~R-10）

单一概念单一所有者 / V2 绝不 import legacy / UI 绝不直接访问文件·密钥·VFS /
敏感写失败关闭 / 锁定必须阻断渲染编辑保存导出媒体 / 一 PR 一变更类型 /
P0P1 bug 必须回归测试 / 受影响需 Android+Windows 双证据 / 发布需签名·哈希·SBOM·
manifest·attestation / AI 必须遵守 issue scope·ADR·测试契约。

## 后果

- 正：单一事实源、平台可替换、可验证演化、Android 主路径 1-2 周内恢复。
- 负：4 周功能冻结；旧代码只做 P0 修复；V2 只接管自动化验收的一条用户路径。
- 回滚：V1 原文件只读保留；迁移过程从不覆盖 V1；V2 失败不影响旧文件。

来源：`C:\Users\17296\Desktop\绘图笔记：代码树级重构决策与渐进迁移蓝图.md` +
`FINAL_EXECUTION_MANIFEST.yaml`（专家方案——严格执行）

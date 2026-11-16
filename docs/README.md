# docs/ 索引

> 本目录 120+ 个文档按「现行规范」与「历史快照」两类维护。
> 快照类仅作过程证据留档，规则以现行类为准；两者冲突时**一律以现行类为准**。
>
> **判断口径**：凡涉及当前行为，以**代码 + 门禁**为准；文档若与代码冲突，
> 信代码并更新文档。

## 现行规范（随时维护，是唯一事实来源）

| 文档 | 角色 |
|---|---|
| [`../AGENTS.md`](../AGENTS.md) | 协作约定总纲：门禁纪律、发版流程、§8 状态管理划界、§9 part 命名与导航 |
| [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md) | 设计总纲：四来源分域规则 + 冲突裁决表 + 玻璃配方 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 架构与依赖规则（模块表、依赖方向、镜像测试结构） |
| [`CODE_REVIEW_POLICY.md`](CODE_REVIEW_POLICY.md) | 代码评审政策 |
| [`ACCEPTANCE_CHECKLIST.md`](ACCEPTANCE_CHECKLIST.md) | 验收清单 |
| [`../SECURITY.md`](../SECURITY.md) | 安全能力口径与**保证边界**（对外表述须与本文一致） |
| [`STATE_MANAGEMENT_DECISION_TREE.md`](STATE_MANAGEMENT_DECISION_TREE.md) | Riverpod ↔ 手工协作者决策树（新增状态前必读，2026-11-15） |
| [`PACKAGES_BOUNDARY.md`](PACKAGES_BOUNDARY.md) | 子包职责与「如何判断空壳」判据（2026-11-15） |
| [`AUDIT_FULL_2026-09-07.md`](AUDIT_FULL_2026-09-07.md) | 2026-09-07 全量审计台账（100+ 大类 / 259 修复 / 118 提升 + 未决清单） |
| `CAPACITY_BUDGET_2026-08-28.md` | 容量预算（内存/性能基线，随版本更新数值） |
| `COMMAND_CYCLE_GOVERNANCE_2026-08-27.md` | 命令周期治理 |

根目录 [`DESIGN.md`](../DESIGN.md) 为静态视觉宪法（生成物，不可改）。

## 当前决策与方案（2026-11-15 新增）

| 文档 | 结论 |
|---|---|
| [`MATERIAL_UI_MIGRATION_ASSESSMENT.md`](MATERIAL_UI_MIGRATION_ASSESSMENT.md) | **迁移当前不做**：material_ui 是平行 Material 实现，两套 ThemeData 类型不兼容；附将来若做的前置条件与顺序 |
| [`K_NOTE_WIRING_PLAN.md`](K_NOTE_WIRING_PLAN.md) | K_note 媒体接线**分 4 批方案**；批 4 涉不可逆全量重加密，需业主批准 |
| [`SECURITY_HARDENING_GUIDE.md`](SECURITY_HARDENING_GUIDE.md) | **面向用户**的安全操作指南（外部锚怎么留存、哪些必须靠系统层全盘加密） |

## 历史快照（按日期命名，已被现行规范吸收或取代）

- `*_2026-08-14.md` / `*_2026-08-15.md`：早期架构分析、验收记录。
- `*_2026-08-27.md` ~ `*_2026-08-31.md`：代码审计轮次、结构评估。
- `AUDIT_UX_ROUND4_2026-09-05.md` 等：UX 审计轮次。
- 其余带日期后缀的文档：同样按快照对待。

判定规则：文件名含 `YYYY-MM-DD` 后缀的一律视为历史快照，除非它出现在上表「现行规范」中。

**典型陷阱（历史结论已被推翻，勿再引用）**：

| 过期说法 | 当前事实 | 依据 |
|---|---|---|
| 「VFS 已实现未启用」 | 已接入生产（解锁收口 configure+setKey） | SECURITY.md / M-01 |
| 「审计链是无密钥 SHA-256」 | 已升级带密钥 HMAC-SHA256 锚 + 世代号 + 外部锚 | SECURITY.md / M-05 |
| 「notebook_domain 是空壳，建议合并」 | 是承重的端口契约，受 2 条架构门禁保护 | PACKAGES_BOUNDARY.md |
| 「旧版 v2/v3/v4 密文兼容读」 | 已删除旧版支持，一律 fail-closed 拒绝 | CHANGELOG M-06 |
| 「媒体走全局会话密钥，K_note 未接线」 | K_note 已全量接入生产（v5 media 槽 + LRU 映射 32 本）；全局会话派生路径已删除 | SECURITY.md / CHANGELOG 2026-11-16 |

## 新增文档的纪律

1. **规范/决策类**：写清定案日期，并在上面两张表挂一行。
2. **时点快照类**：文件名带日期，**不挂进现行规范**。
3. **结论被推翻时**：不删旧文档（保留追溯），在旧文档顶部加一行
   「⚠️ 本文结论已于 YYYY-MM-DD 被 `<新文档>` 取代」，并更新本索引的陷阱表。
4. **与代码冲突时**：信代码，改文档——文档不是事实来源，代码 + 门禁才是。
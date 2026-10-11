# 安全政策（Security Policy）

本项目采用政府级安全设计（加密笔记 / K_note 每笔记密钥 / 策略引擎 / 会话守卫 /
VFS 加密对象仓库 / 篡改可检测审计哈希链 / 导入隔离）。我们认真对待安全漏洞——
请通过**负责任披露**提交，切勿在公开 Issue 中描述漏洞细节。

## 支持版本

| 版本 | 支持状态 |
| --- | --- |
| 1.1.x | ✅ 支持（当前稳定版） |
| < 1.1 | ⚠️ 仅重大安全修复 |

## 漏洞报告

请通过以下**私有**通道报告（公开 Issue 会暴露细节给攻击者）：

1. **GitHub Private vulnerability reporting**（推荐）——仓库 **Settings → Security → Private vulnerability reporting** 启用后可直接提交
2. 或私信维护者（GitHub 账号：`bear20252026`）

报告请包含：
- 影响版本（`pubspec.yaml` 的 version）
- 复现步骤（最小样例优先）
- 影响分析（可被利用的后果）
- 建议修复（可选）

## 响应承诺

| 阶段 | 时限 |
| --- | --- |
| 收到确认 | 7 天内 |
| 影响评估（修复计划 / 风险接受声明） | 30 天内 |
| 安全修复 | 优先于功能开发（不晚于下一稳定版） |

## 安全特性概述（已落地——供审计参考）

| 特性 | 说明 |
| --- | --- |
| 加密笔记 | AES-256-GCM + AAD 上下文绑定（NIST SP 800-38D）——正文/媒体/回收站加密 |
| K_note 每笔记密钥 | 独立数据密钥 + AAD 绑定笔记 ID——防跨笔记密文交换 |
| 策略引擎 | 操作白名单**默认拒绝**（fail-closed）+ 审计（PolicyEngine） |
| 会话守卫 | 失去焦点立即锁定（内存密钥 fillRange 清零）+ 再认证 |
| VFS 加密对象仓库 | 对象清单 + 版本回溯 + AAD 绑定 + 原子提交（崩溃安全） |
| 篡改可检测审计 | 无密钥 SHA-256 哈希链（prevHash 链接——篡改断链）+ verifyIntegrity（校验范围见下节） |
| 导入隔离 | SVG 预检（XXE/Billion Laughs/脚本注入/膨胀）+ PDF/文本配额 |
| 发布门禁 | SBOM（CycloneDX）+ 秘密扫描（Gitleaks 模式）+ CI 集成 |

## 审计链的保证边界（口径说明，2026-10-11）

审计哈希链提供的是**篡改可检测（tamper-evident）**，不是防篡改
（tamper-proof）。据 `lib/core/security/audit_logger.dart` 实测：

- **链是无密钥 SHA-256**（`log()` 生成 prevHash/hash，无 HMAC / 无签名）：能改写
  `audit.log` 的攻击者可以整链重算，检测不到其改写。提升保证等级需要**带密钥的
  日志段**或**外部追加锚（append-only anchor / 签名收据）**——属能力升级，
  业主尚未裁决，本仓当前**未实现**。
- **verifyIntegrity() 只重放内存链**：遍历进程内保留的最近 ≤1000 条（滚动裁剪
  上限），**不读任何文件**。因此「校验通过」只代表当前进程最近这些条目自洽。
- **文件侧跨重启重放验证未实现**：条目虽以 JSONL 追加落 `security/audit.log`
  （超 1 MiB 轮转为 `audit.log.1`），但没有任何生产代码读回这些文件做重放——
  进程重启后旧历史不参与校验。
- **已知非问题**：滚动裁剪曾会误报「已篡改」，已由链锚点 checkpoint
  （`_anchorPrevHash`）修复并有回归用例（`test/audit_logger_test.dart:70`）；
  文件轮转不产生该误报。

## 安全开发实践

- CI 门禁：`dart analyze` 零问题 / 391+ 测试全过 / 架构规则 +5 / 边界 / 行数 / 秘密扫描 / SBOM
- 涉密自查：每次提交前核对（不提交真实密钥/口令/令牌——技术标识符误报人工核对）
- 依赖锁定：`pubspec.lock` 固化 + CVE 核查脚本（`tools/check_deps.sh`）

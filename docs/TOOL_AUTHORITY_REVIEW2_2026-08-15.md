# 新增 AI/MCP 代码质量工具权威调查意见（2026-08-15）

> 调查对象：第二批 11 个工具（去除已落地的 Open Code Review/Skylos/py-cq，新增核实 8 个：
> polyscan、Valknut、desloppify、VibeDoctor、Codex Security CLI、KyZN、RepoPilot、HotspotTriage）。
> 调查方式：中英双语全网搜索权威源（GitHub 官方仓库、PyPI、npm、官网、官方文档），逐工具
> 核实真实性、许可证、成熟度、语言支持。
> 适用场景：中国政府特殊支持内部开发项目，主语言 **Dart/Flutter**，辅助脚本 Python（tools/）。
> 结论先行：**新增 8 个工具全部真实存在**；其中 **desloppify（支持 Dart）与 RepoPilot
> （本地优先、语言无关、零上传）** 对本项目最契合；外部 LLM 依赖型工具（Codex Security/KyZN）
> 因涉密红线不引入、仅借鉴方法论。

---

## 一、逐工具核实结果（权威信源）

| # | 工具 | 真实仓库/包 | 许可证 | 成熟度 | 语言支持 |
| --- | --- | --- | --- | --- | --- |
| 1 | polyscan | ludo-technologies/polyscan | 开源 | 2 star / 140 commits | JS/TS（jscan）+ Python（pyscn）；**暂无 Dart**（C++/Go/Rust 规划中） |
| 2 | Valknut | sibyllinesoft/valknut | 开源 | v1.5.0 / Rust | Python/TS/Rust/Go/C++（**无 Dart**）；文档健康+AST 指标+MCP |
| 3 | desloppify | peteromallet/desloppify | **OSNL-0.2** | **3k star** / PyPI | **29 语言含 Dart**（full plugin depth）；机械检测+LLM 审查+修复循环 |
| 4 | VibeDoctor | @neuralaxis/vibedoctor | **GPL-3.0** | npm v2.1 | **仅 JS/TS/Python**；扫描聚合+修复计划+MCP+Agent Skills |
| 5 | Codex Security CLI | openai/codex-security | 开源 | **9.8k star** / 297 commits | 语言广泛；扫描/验证/修复安全漏洞；**需 OpenAI 访问（Trusted Access for Cyber）** |
| 6 | KyZN | bokiko/KyZN | 开源 | 纯 Bash | 语言无关（git 级）；Claude Code 驱动 4 专家代理+构建验证 |
| 7 | RepoPilot | MykytaStel/repopilot | 开源 | Rust CLI | **语言无关（git diff 级）**；本地优先+MCP+**零上传** |
| 8 | HotspotTriage | avnovikov/HotspotTriage | 开源 | MCP 服务 | **仅 Python**（Radon/Pylint/DeepCSIM 热点评分） |

## 二、语言适用性与安全红线评估（对本项目 Dart/Flutter）

| 工具 | Dart 支持 | 外部 LLM/上传 | 政府项目契合度 |
| --- | --- | --- | --- |
| desloppify | ✅ 29 语言含 Dart（full plugin） | LLM 审查可本地/可配置 | 🟢 高（但 OSNL-0.2 许可需法务确认） |
| RepoPilot | ✅ 语言无关（git diff 级） | **零上传、无 LLM 调用** | 🟢 **最高**（本地确定性证据，符合涉密红线） |
| polyscan | ❌ 暂无 Dart | 本地分析 | 🟡 仅 tools/ Python 脚本域（pyscn 已落地） |
| Valknut | ❌ 无 Dart | 可选 AI 指导 | 🟠 仅借鉴方法论 |
| VibeDoctor | ❌ 仅 JS/TS/Python | 本地扫描 | 🔴 不适用（GPL + 无 Dart） |
| Codex Security CLI | 语言广泛 | **需 OpenAI 访问（涉密不可）** | 🔴 不适用（外部 LLM 红线） |
| KyZN | 语言无关 | **需 Claude Code（外部 LLM）** | 🔴 不适用（涉密不可）；借鉴"代理+构建验证+严重度分批" |
| HotspotTriage | ❌ 仅 Python | 本地 | 🟡 仅 tools/ Python 脚本域 |

## 三、分类结论

### 🟢 A. 可直接引入（语言支持 + 许可/安全兼容）

| 工具 | 理由 | 引入方式 |
| --- | --- | --- |
| **RepoPilot** | 本地优先 Rust CLI + MCP；git diff 级语言无关；**零上传、无 LLM 调用**；安全边界/行为变更/blast radius/taint 证据 | CI 新增 job：`repopilot review . --base origin/main --fail-on-review definitely`（先 preview 观测）；`repopilot ai context` 生成 P0-P3 修复交接单 |
| **desloppify** | 支持 29 语言含 Dart（full plugin）；机械检测（死代码/重复/复杂度/测试缺口）+ LLM 主观审查 + 优先级修复循环；状态跨会话持久 | ⚠️ 先确认 **OSNL-0.2 许可** 合规后接入：`desloppify scan && desloppify score`（CI 全库健康门禁） |

### 🟡 B. 适配引入（仅用于本项目 tools/ Python 辅助脚本）

| 工具 | 用途 |
| --- | --- |
| polyscan（pyscn 同源） | 对 tools/ 做 0-100/A-F 多角度评分（已落地 pyscn，polyscan 为家族升级） |
| HotspotTriage | 对 tools/ Python 代码做变更率/复杂度/重复度热点评分，路由 AI 代理聚焦 |

### 🟠 C. 仅借鉴方法论（不引入）

| 工具 | 借鉴点 |
| --- | --- |
| Valknut | AST 指标 + 文档健康（README/TODO 审计）+ MCP 端点架构 |
| KyZN | "4 专家代理（安全/正确性/性能/架构）+ 严重度分批修复 + 每次构建验证 + 健康分回退中止"流程 |
| Codex Security CLI | "扫描→验证可利用性→修复补丁"三步法（本地落地时套用其验证思路） |

### 🔴 D. 不适用

| 工具 | 原因 |
| --- | --- |
| VibeDoctor | GPL-3.0 传染 + 仅 JS/TS/Python，无 Dart |

## 四、政府项目合规红线（审慎结论）

1. **涉密数据不出域**：Codex Security CLI（需 OpenAI 访问）、KyZN（需 Claude Code）一律不引入；
   RepoPilot（零上传）与 desloppify（可本地 LLM）符合红线。
2. **许可审慎**：desloppify 为 **OSNL-0.2**（非 MIT/Apache），引入前需法务/合规确认；
   RepoPilot 许可证需在引入时核对（本地优先无依赖可优先评估）。
3. **审计留痕**：RepoPilot 输出为确定性证据（含 provenance/lifecycle/evidence），
   SARIF/JSON 归档 CI artifacts 供验收。

## 五、落地优先级建议

| 优先级 | 动作 |
| --- | --- |
| P0 | **RepoPilot 接入 CI**（本地优先、零上传、git diff 级——最契合政府涉密红线） |
| P1 | desloppify 评估 OSNL-0.2 许可后接入 Dart 全库健康门禁（支持 Dart 是最大亮点） |
| P1 | KyZN 的"四代理+构建验证"流程本地化（用本项目既有 analyze/test 门禁实现） |
| P2 | polyscan/HotspotTriage 对 tools/ Python 脚本做补充评分 |

> 本意见基于 2026-08-15 当日权威信源核实；核心判断：**新增 8 个工具中，RepoPilot（本地
> 零上传、语言无关）与 desloppify（支持 Dart）值得引入，前者因涉密安全红线优先；其余
> 外部 LLM 依赖型工具不引入、仅吸收方法论**。

# Python 生态代码质量工具权威调查意见（2026-08-15）

> 调查对象：用户提供的 11 个 Python 端质量工具（py-cq/python-code-quality、pyscn、
> pyrefact、PyRustor、Refactron、Open Code Review、diffray、ChatDBG、Skylos、Valknut、
> pylyzer）。
> 调查方式：中英双语全网搜索（GitHub 官方仓库、PyPI、lib.rs/crates.io、项目官网、
> 技术文档），逐工具核实真实性、许可证、成熟度、语言支持。
> 适用场景：本项目为中国政府特殊支持内部开发项目，主语言 **Dart/Flutter（87 文件）**，
> 辅助脚本为 Python（tools/*.py）。
> 结论先行：**11 个工具全部真实存在**；其中 **3 个可直接引入/适配引入本项目**、
> **6 个仅适用于本项目 Python 辅助脚本**、**2 个仅借鉴方法论**。

---

## 一、逐工具核实结果（权威信源）

| # | 工具 | 真实仓库 | 许可证 | 成熟度 | 语言支持 |
| --- | --- | --- | --- | --- | --- |
| 1 | python-code-quality | rhiza-fr/py-cq | MIT | 1 star，2026-02 创建 | Python（聚合 11 工具） |
| 2 | pyscn | ludo-technologies/pyscn | 开源 | PyPI v1.29.0 | Python（Go+tree-sitter 实现） |
| 3 | pyrefact | OlleLindgren/pyrefact | MIT | 47 star，2022 起 | Python |
| 4 | PyRustor | loonghao/PyRustor | MIT | 7 star，Rust+Python 绑定 | Python |
| 5 | Refactron | Refactron-ai/Refactron_lib | MIT（PyPI 版 Apache-2.0） | 6 star，npm shim | Python |
| 6 | Open Code Review | alibaba/open-code-review | **Apache-2.0** | **20.4k star**，阿里内部验证 | **语言无关（LLM+规则）** |
| 7 | diffray CLI | diffray/diffray | MIT | 12 star，多智能体 | **语言无关（LLM 评审）** |
| 8 | ChatDBG | plasma-umass/ChatDBG | **Apache-2.0** | **1.1k star**，FSE'25 论文 | C/C++/Python/Rust（pdb/lldb/gdb） |
| 9 | Skylos | duriantaco/skylos | **Apache-2.0** | **476 star**，v4.30.0 | **含 Dart**（死代码/安全/质量） |
| 10 | Valknut | sibyllinesoft/valknut | 开源 | v1.5.0，Rust | Python/TS/Rust/Go/C++（**无 Dart**） |
| 11 | pylyzer | mtshiba/pylyzer | MIT OR Apache-2.0 | **2.9k star**，Rust | Python（比 pyright 快 100 倍） |

## 二、语言适用性评估（对本项目 Dart/Flutter 主代码）

- **可直接分析 Dart 代码**：仅 **Skylos**（官方语言矩阵明确列出 Dart：死代码 ✅/安全 ✅/质量 ✅）。
- **语言无关（LLM/规则混合）**：Open Code Review（读 git diff + LLM 行级评审）、
  diffray（多智能体评审，CLI 语言无关）。
- **仅 Python**：py-cq/pyscn/pyrefact/PyRustor/Refactron/pylyzer——只适用于本项目
  `tools/` 下的 Python 辅助脚本（code_guard.py 等）。
- **不直接适用**：ChatDBG（面向 pdb/lldb/gdb，非 Dart VM 调试器）、Valknut（语言矩阵无 Dart）。

## 三、分类结论

### 🟢 A. 可直接引入（语言支持 + 许可兼容政府项目）

| 工具 | 理由 | 引入方式 |
| --- | --- | --- |
| **Skylos** | Apache-2.0；官方支持 Dart；本地优先 PR 扫描（死代码/安全/机密/AI 缺陷） | CI 新增 job：`skylos . -a`（GitHub Actions 集成现成） |
| **Open Code Review（阿里）** | Apache-2.0；20.4k star 经阿里大规模验证；确定性规则+LLM 行级评审；内置 NPE/线程安全/XSS/SQL 注入规则 | CI 新增 job：`ocr review`（需配置模型 endpoint；政府内网可配本地模型） |
| **diffray CLI** | MIT；多智能体评审（bug/安全/性能/风格）；本地运行不传云 | 开发期本地运行 `diffray review`（需 Claude Code/Cursor 订阅） |

### 🟡 B. 适配引入（仅用于本项目 Python 辅助脚本）

| 工具 | 用途 | 适配方式 |
| --- | --- | --- |
| **py-cq** | 聚合 ruff/bandit/vulture 等 11 工具评分 | 对 `tools/` Python 脚本做质量门禁 |
| **pyscn** | Python 架构分析（循环依赖/A-F 评分/HTML 报告） | 定期对 tools/ 做架构体检 |
| **pyrefact / PyRustor / Refactron** | 规则驱动 Python 自动重构 | 清理 tools/ 死代码/简化 |
| **pylyzer** | Rust 高速 Python 静态分析（LSP） | 编辑器/CI 对 tools/ 做类型检查 |

### 🟠 C. 仅借鉴方法论（不引入）

| 工具 | 借鉴点 |
| --- | --- |
| **ChatDBG** | "LLM 集成调试器回答为什么失败"——本项目可借鉴到 Flutter debugger 工作流（Dart VM 无现成等价物） |
| **Valknut** | AST 指标 + MCP 端点 + 重构 oracle 的分层架构——本项目已有的 metrics/MCP 思路可对照 |

### 🔴 D. 不适用

- 无（11 个工具均有至少"借鉴"价值；无与 Dart 直接冲突或高危许可项）。

## 四、政府项目合规红线（审慎结论）

1. **许可**：引入 A/B 类均选 MIT/Apache-2.0（兼容内部项目）；C 类 GPL 工具（如有）仅借鉴思想不引入代码——本批工具全部为 MIT/Apache-2.0 或开源，无 GPL 冲突。
2. **数据安全**：Open Code Review / diffray 调用外部 LLM 时，**不得上传涉密源码**——政府内网部署时优先 Skylos（本地）与 Open Code Review 的本地模型（Ollama/vLLM）端点。
3. **审计留痕**：所有门禁工具输出（JSON/SARIF）归档至 CI artifacts，供验收审计。

## 五、落地优先级建议

| 优先级 | 动作 |
| --- | --- |
| P0 | **Skylos 接入 CI**（Dart 死代码/安全门禁，本地优先，最快见效） |
| P1 | **Open Code Review** 接入评审（配内网 LLM 端点；对 PR 行级评审） |
| P1 | py-cq 对 tools/ 脚本做质量门禁（补 Python 侧短板） |
| P2 | diffray 本地多智能体评审（开发期可选） |
| P2 | pyscn/pylyzer 定期架构体检（Python 脚本域） |

> 本意见基于 2026-08-15 当日权威信源核实；核心判断：**对本项目 Dart 主代码，Skylos 是唯一
> 官方原生支持的静态分析工具（Apache-2.0），优先引入；Open Code Review 与 diffray 以
> LLM 评审补足动态/语义层面；6 个 Python 专用工具限定在 tools/ 辅助脚本域**。

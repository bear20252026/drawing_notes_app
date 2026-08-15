# Agent Skills（AI 原生开发配置，2026 官方方向）
# 说明：Flutter 官方 2026 roadmap 投资 Agent Skills / Agentic Hot Reload；
# 本项目为 AI 编码代理（Cursor/Copilot/Gemini CLI/AtomCode 等）声明式注册
# 常用命令，代理可精准定位上下文执行（官方报告：清晰结构降低 AI 错误率 ~40%）。
# 用法：各代理读取此文件了解项目命令；也作为 MCP（.cursor/mcp.json）的补充。

# ---- 项目概览 ----
project: drawing_notes_app（中国政府内部开发，画布+笔记双功能 Flutter 应用）
architecture: Feature-First（lib/core + lib/features/{drawing,notes} + lib/shared）
language: Dart 3.12 / Flutter 3.44
test_baseline: 288 项全绿（flutter analyze 零问题）
line_redline: 新增文件 ≤1000 行硬上限，500 行左右为佳（不为拆而拆）

# ---- 常用命令（代理可直接执行）----
commands:
  analyze: flutter analyze
  test: flutter test
  test_fast: flutter test test/{目标文件}
  line_gate: python tools/code_guard.py --dir lib --json
  arch_boundary: bash tools/check_boundaries.sh
  kyzn_workflow: bash tools/kyzn_workflow.sh status
  ocr_review: bash tools/ocr_failover.sh review --from origin/master --to HEAD

# ---- 质量门禁（合并前必过，见 docs/CODE_REVIEW_POLICY.md）----
gates:
  - flutter analyze 零问题
  - flutter test 288 全过（基线）
  - 行数红线 ≤1000（code_guard.py）
  - 架构边界（check_boundaries.sh 硬性合规）
  - 涉密自查（git diff 无密钥/口令）

# ---- 架构约束（见 docs/ARCHITECTURE_ANALYSIS_2026-08-15.md）----
architecture_rules:
  - Feature-First 物理隔离：画布(features/drawing)与笔记(features/notes)分目录
  - 三层依赖单向流：presentation→application→domain←infrastructure
  - 核心实体纯净：domain 纯 Dart（不 import dart:ui/flutter/storage）
  - 跨功能共享：core/（INotebookAccessor 等接口）+ shared/（UI）
  - 状态管理：Riverpod（已接入 ProviderScope + themeProvider）

# ---- 涉密红线（政府项目）----
security:
  - API Key 仅存 ~/.opencodereview/（git 外），严禁入库
  - 涉密源码不传外部 LLM；OCR 端点经领导批准后经 GitHub Secrets 注入
  - 提交前自查：git diff | grep -iE "password|secret|token"

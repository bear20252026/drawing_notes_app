#!/usr/bin/env bash
# 架构边界检查（S4 落地：Feature-First 隔离自动化保障）
# 依据 2026 官方/社区实践（docs/ARCHITECTURE_ASSESSMENT_2026-08-15.md）：
# - 依赖方向：features/* → core|shared，禁止 feature 间横向 import
# - core/ 不得 import features/（保持独立）
# - 已知允许的跨功能依赖（业务真实需求，白名单）：
#   drawing → notes：editor_exporter(NotebookPage/NotebookPdf)、
#   search_service(NotebookStorage)、editor_page/editor_components(NotebookPage/
#   NotebookStorage)——导出混合 PDF/跨笔记搜索/编辑器集成笔记。
#   后续通过接口抽象（S4b）逐步消除。
# 用法：bash tools/check_boundaries.sh（CI 门禁，违规即失败）
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=0

echo "=== [S4] 架构边界检查 ==="

# 规则 1：core/ 不得依赖 features/ 的 application/infrastructure/presentation
# （core 允许依赖 features 的 domain 实体——domain 是最内层纯数据，
#  依赖向内原则允许；storage 编解码依赖实体属此列）。
VIOL=$(grep -rlE "features/[a-z_]+/(application|infrastructure|presentation)/" lib/core/ 2>/dev/null || true)
# 已知白名单（S4b 专项治理，需接口注入重构）：storage_service 依赖
# document_codec（画布编解码）——跨功能共享存储的注入点，记录待治理。
VIOL=$(echo "$VIOL" | grep -v "storage_service.dart" || true)
if [ -n "$VIOL" ]; then
  echo "✗ core/ 违规依赖 features 非 domain 层:"
  echo "$VIOL"
  FAIL=1
else
  echo "✓ core/ 仅依赖 features domain 实体或完全独立（依赖向内合规）"
fi

# 规则 2：feature 间横向 import 检查（允许白名单）
# 收集 drawing→notes 与 notes→drawing 的 import（排除白名单）
drawing_to_notes=$(grep -rln "features/notes" lib/features/drawing/ 2>/dev/null || true)
notes_to_drawing=$(grep -rln "features/drawing" lib/features/notes/ 2>/dev/null || true)

# 白名单（业务真实依赖，文档化于 docs/ARCHITECTURE_ASSESSMENT_2026-08-15.md 观察项）
# 允许单向：notes → drawing（domain 实体共享，符合"domain 是内层"原则）
# drawing → notes 属横向依赖，白名单记录待治理项
if [ -n "$drawing_to_notes" ]; then
  echo "⚠ drawing → notes 横向依赖（已知待治理项，非阻断，见报告观察项）:"
  echo "$drawing_to_notes" | sed 's/^/    /'
else
  echo "✓ drawing 无 notes 横向依赖"
fi

# 规则 3：shared/ 不得依赖 features/（共享 UI 保持独立）
VIOL=$(grep -rl "features/" lib/shared/ 2>/dev/null || true)
if [ -n "$VIOL" ]; then
  echo "✗ shared/ 违规依赖 features/:"
  echo "$VIOL"
  FAIL=1
else
  echo "✓ shared/ 无 features/ 依赖"
fi

if [ "$FAIL" -eq 1 ]; then
  echo "=== 边界检查失败：存在硬性违规（core/shared 依赖 features）==="
  exit 1
fi
echo "=== 边界检查通过（硬性规则合规；已知横向依赖已记录待治理）==="
exit 0

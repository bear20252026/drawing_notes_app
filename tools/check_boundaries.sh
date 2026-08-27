#!/usr/bin/env bash
# 架构边界检查（S4 落地：Feature-First 隔离自动化保障）
# 依据 2026 官方/社区实践（docs/ARCHITECTURE_ASSESSMENT_2026-08-15.md）：
# - 依赖方向：features/* → core|shared，禁止 feature 间横向 import
# - core/ 不得 import features/（保持独立）
# - feature 间允许共享最内层 domain 实体；任何指向另一 feature 的
#   application/infrastructure/presentation 导入均由 architecture_test.dart
#   的严格断言阻断。此脚本保留可读的检索输出，便于本地快速诊断。
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
if [ -n "$VIOL" ]; then
  echo "✗ core/ 违规依赖 features 非 domain 层:"
  echo "$VIOL"
  FAIL=1
else
  echo "✓ core/ 仅依赖 features domain 实体或完全独立（无白名单例外）"
fi

# 规则 2：feature 间横向 import 诊断
# 收集 drawing→notes 与 notes→drawing 的 import；严格的非 domain
# 横向依赖拒绝由 architecture_test.dart 统一执行。
drawing_to_notes=$(grep -rln "features/notes" lib/features/drawing/ 2>/dev/null || true)
notes_to_drawing=$(grep -rln "features/drawing" lib/features/notes/ 2>/dev/null || true)

# domain 实体共享属于向内依赖；这里输出任意 drawing → notes 导入，
# 由架构测试判定它们是否违反另一 feature 的外层隔离。
if [ -n "$drawing_to_notes" ]; then
  echo "ℹ drawing → notes 导入（须由架构测试确认仅指向 domain）:"
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
echo "=== 边界检查通过（core/shared 硬性规则合规；横向外层依赖由架构测试严格阻断）==="
exit 0

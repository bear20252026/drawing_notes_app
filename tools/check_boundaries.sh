#!/usr/bin/env bash
# 架构边界检查（S4 落地：Feature-First 隔离自动化保障）
# 依据 2026 官方/社区实践（docs/ARCHITECTURE_ASSESSMENT_2026-08-15.md）：
# - 依赖方向：features/* → core|shared，禁止 feature 间横向 import
# - core/ 不得 import features/（保持独立）
# - feature 间允许共享最内层 domain 实体；任何指向另一 feature 的
#   application/infrastructure/presentation 导入均由 architecture_test.dart
#   的严格断言阻断。此脚本保留可读的检索输出，便于本地快速诊断。
#
# 【匹配范围】（P1 修正，审计 2026-10-04）判定「依赖」的唯一依据是
# **代码上下文里的 `import` / `export` 语句 URI**，由 _import_uris 的 awk
# 词法过滤产出：`//` 行注释、可嵌套 `/* */` 块注释、`'...'`/`"..."`/三引号
# 字符串体内出现的同形文本一律剔除；覆盖 `package:` 绝对 URI 与相对路径两
# 种写法，以及 `as` / `show` / `deferred` 等带前缀的语句（关键字与 URI 须同
# 行）。此前规则 1/3 是纯文本 grep，把三处 C-10 迁移说明注释
# （core/notes_accessor.dart、core/rendering/notebook_print_page_data.dart、
# core/theme/apple_palette.dart）当成依赖违规，本地门禁恒红——假红与假绿
# 同等致命（门禁一说谎就没人再信它）。改本脚本时先确认命中是不是 import。
# 已知边界：跨行写的 `import` 关键字+URI 不识别、原始三引号串里的同形
# `import '...'` 会被当语句（两者全仓实测 0 例）。
#
# 用法：bash tools/check_boundaries.sh（CI 门禁，违规即失败）
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=0

echo "=== [S4] 架构边界检查 ==="

# 提取代码上下文中的 import/export URI：输出 `文件:行号:URI`。
_AWK_IMPORT_URIS='
function isident(ch) { return ch ~ /[A-Za-z0-9_$]/ }
FNR == 1 { inblk = 0; bdepth = 0; tri = "" }
{
  line = $0
  n = length(line)
  i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    d = substr(line, i + 1, 1)
    if (inblk) {
      if (c == "*" && d == "/") { bdepth--; i += 2; if (bdepth <= 0) inblk = 0; continue }
      if (c == "/" && d == "*") { bdepth++; i += 2; continue }
      i++; continue
    }
    if (tri != "") {
      if (c == "\\") { i += 2; continue }
      if (substr(line, i, 3) == tri) { tri = ""; i += 3; continue }
      i++; continue
    }
    if (c == "/" && d == "/") break
    if (c == "/" && d == "*") { inblk = 1; bdepth = 1; i += 2; continue }
    if (c == "'"'"'" || c == "\"") {
      q = c
      if (substr(line, i, 3) == q q q) { tri = q q q; i += 3; continue }
      j = i + 1
      while (j <= n) {
        if (substr(line, j, 1) == "\\") { j += 2; continue }
        if (substr(line, j, 1) == q) break
        j++
      }
      i = j + 1
      continue
    }
    if (c == "i" || c == "e") {
      prev = (i > 1) ? substr(line, i - 1, 1) : " "
      w = substr(line, i, 6)
      if (!isident(prev) && (w == "import" || w == "export") && !isident(substr(line, i + 6, 1))) {
        j = i + 6
        while (j <= n && substr(line, j, 1) != "'"'"'" && substr(line, j, 1) != "\"") j++
        if (j <= n) {
          q2 = substr(line, j, 1)
          k = j + 1
          uri = ""
          while (k <= n) {
            cc = substr(line, k, 1)
            if (cc == "\\") { uri = uri substr(line, k, 2); k += 2; continue }
            if (cc == q2) break
            uri = uri cc
            k++
          }
          printf "%s:%d:%s\n", FILENAME, FNR, uri
          i = k + 1
          continue
        }
        i += 6
        continue
      }
    }
    i++
  }
}
'
_import_uris() {
  find "$1" -type f -name '*.dart' -exec awk "$_AWK_IMPORT_URIS" {} + 2>/dev/null || true
}

# 规则 1：core/ 不得依赖 features/ 的 application/infrastructure/presentation
# （core 允许依赖 features 的 domain 实体——domain 是最内层纯数据，
#  依赖向内原则允许；storage 编解码依赖实体属此列）。
VIOL=$(_import_uris lib/core | grep -E "features/[a-z_]+/(application|infrastructure|presentation)/" || true)
if [ -n "$VIOL" ]; then
  echo "✗ core/ 违规依赖 features 非 domain 层:"
  echo "$VIOL" | sed 's/^/    /'
  FAIL=1
else
  echo "✓ core/ 仅依赖 features domain 实体或完全独立（无白名单例外）"
fi

# 规则 2：feature 间横向 import 诊断
# 收集 drawing→notes 与 notes→drawing 的 import；严格的非 domain
# 横向依赖拒绝由 architecture_test.dart 统一执行。
drawing_to_notes=$(_import_uris lib/features/drawing | grep -E "features/notes/" || true)
notes_to_drawing=$(_import_uris lib/features/notes | grep -E "features/drawing/" || true)

# domain 实体共享属于向内依赖；这里输出任意 drawing → notes 导入，
# 由架构测试判定它们是否违反另一 feature 的外层隔离。
if [ -n "$drawing_to_notes" ]; then
  echo "ℹ drawing → notes 导入（须由架构测试确认仅指向 domain）:"
  echo "$drawing_to_notes" | sed 's/^/    /'
else
  echo "✓ drawing 无 notes 横向依赖"
fi
if [ -n "$notes_to_drawing" ]; then
  echo "ℹ notes → drawing 导入（棘轮基线见 architecture_boundary_ratchet_test.dart）:"
  echo "$notes_to_drawing" | sed 's/^/    /'
else
  echo "✓ notes 无 drawing 横向依赖"
fi

# 规则 3：shared/ 不得依赖 features/（共享 UI 保持独立）
VIOL=$(_import_uris lib/shared | grep -E "features/" || true)
if [ -n "$VIOL" ]; then
  echo "✗ shared/ 违规依赖 features/:"
  echo "$VIOL" | sed 's/^/    /'
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

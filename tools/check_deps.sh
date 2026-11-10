#!/usr/bin/env bash
# SBOM-CVE 依赖核查脚本（审计修复 2026-08-15，P4 建议项）。
#
# 2026 合规要求（docs.flutter.dev/security + ostorlab 清单）：
# - 生成并归档 SBOM（pubspec.lock 即 Flutter 侧 SBOM）
# - 定期核查依赖更新（CVE/修复版追踪）
# 本脚本：输出依赖概览（SBOM 摘要）→ 检查过期依赖（CVE 修复版面）→ 阈值判定。
#
# ── 门禁语义（2026-10 审计修复：原文只有打印、没有阈值也没有退出码）──────
# 注释原写「dev_dependencies 之外的可升级依赖 <= 阈值视为可发布（默认 3）」，
# 但脚本既没有阈值参数、也没有任何 exit code 判定——纯打印，门禁是空的。
# 现在补上真实判定：
#   可升级数 = `dart pub outdated` 表格里 Latest 列与 Current 列不同的包数
#   （口径：pubspec.lock 锁定版本落后于 pub.dev 上最新版的包）。
#   可升级数 > 阈值  → exit 1（不可发布）
#   可升级数 <= 阈值 → exit 0（可发布）
#   dart 不可用 / 输出不可解析 → exit 2（**不能把「查不了」判成通过**——本仓
#   「空集即通过」那一族里唯一的依赖域成员，故单列一个退出码）。
#
# 用法：
#   bash tools/check_deps.sh [--threshold 10]
#   THRESHOLD=10 bash tools/check_deps.sh      # 环境变量等价于 --threshold
#
# 退出码：0 可发布 / 1 超阈值 / 2 无法核查（dart 缺失或解析失败）/ 3 用法错误。
set -u

cd "$(dirname "$0")/.."

# ── 参数 ────────────────────────────────────────────────────────────────────
THRESHOLD="${THRESHOLD:-10}"
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold)
      [ $# -ge 2 ] || { echo "用法错误：--threshold 需要一个整数" >&2; exit 3; }
      THRESHOLD="$2"; shift 2 ;;
    --threshold=*)
      THRESHOLD="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "用法错误：未知参数 '$1'（支持 --threshold）" >&2
      exit 3 ;;
  esac
done
case "$THRESHOLD" in
  ''|*[!0-9]*)
    echo "用法错误：--threshold 必须是非负整数（收到 '$THRESHOLD'）" >&2
    exit 3 ;;
esac

echo "=== [1/4] SBOM 摘要（pubspec.lock 依赖清单）==="
LOCKED_TOTAL="$(grep -cE '^  [a-z_0-9]+:' pubspec.lock 2>/dev/null || echo 0)"
echo "锁定依赖总数: ${LOCKED_TOTAL}"
echo "直接依赖（pubspec.yaml dependencies + dev_dependencies）："
# 用 awk 精确切出 dependencies/dev_dependencies 两段（原实现用 grep 抓
# `^  name:` 会把 flutter: 段里的 assets:/shaders:/uses-material-design 与
# 注释行一起卷进来，输出过宽——这里按顶层键分段，只取段内一级条目）。
awk '
  /^dependencies:/          {sec="main";  next}
  /^dev_dependencies:/      {sec="dev";   next}
  /^[a-zA-Z_]/              {sec=""}      # 其它顶层键（flutter:/environment: 等）
  sec != "" && /^  [a-zA-Z_0-9]+:/ {
    line=$0; sub(/:.*/,"",line); gsub(/[ \t]/,"",line); if (line!="") print line
  }
' pubspec.yaml | sort -u | tr '\n' ' '
echo ""
echo "锁定关键包版本（CVE 追踪重点）："
for pkg in flutter_riverpod riverpod cryptography shared_preferences path_provider file_selector material_ui; do
  v="$(awk -v p="  ${pkg}:" '
    $0==p {found=1; next}
    found && /^  [a-z_0-9]+:/ {exit}
    found && /version:/ {v=$0; sub(/.*version: */,"",v); gsub(/[" ]/,"",v); print v; exit}
  ' pubspec.lock)"
  [ -n "$v" ] && echo "  ${pkg}: ${v}"
done
echo ""

echo "=== [2/4] 过期依赖检查（dart pub outdated）==="
if ! command -v dart >/dev/null 2>&1; then
  echo "（dart 不在 PATH，跳过——请确保 flutter/bin 在 PATH）"
  OUTDATED_RAW=""
else
  # dart pub outdated 的退出码在「全部最新」与「有可升级项」两种情况下都是 0
  # ——退出码不可靠，只能靠解析输出（故 `|| true` 之后仍要校验内容）。
  OUTDATED_RAW="$(dart pub outdated 2>&1 || true)"
  printf '%s\n' "$OUTDATED_RAW" | tail -30
fi
echo ""

# ── 解析可升级数 ─────────────────────────────────────────────────────────────
# `dart pub outdated` 实际输出（dart 3.x，列宽不齐、版本带 `*` 前缀）：
#   Package Name      Current  Upgradable  Resolvable  Latest
#   archive           *4.0.9    *4.0.9      4.6.0       4.6.0
#   crypto            *3.0.7    3.0.8       3.0.8       3.0.8
#   [*] indicates versions that are not the latest available.
#   direct dependencies:
#   dev_dependencies: all up-to-date.
#   transitive dependencies:
#   50 upgradable dependencies are locked (in pubspec.lock) to older versions.
# 判定口径：**Latest 列（第 5 列）与 Current 列（第 2 列）不同 ⇒ 可升级**。
# 注意三个坑：① 版本前导 `*` 必须剥掉；② 「Current/Upgradable」两列可能相同
# 而 Latest 才是真最新版（archive: Current 4.0.9 / Upgradable 4.0.9 / Latest
# 4.6.0 —— 只比前两列会漏掉它）；③ 脚注行与分段标题行不是数据行。
UPGRADABLE=0
UPGRADABLE_NAMES=""
SECTION=""
if [ -n "$OUTDATED_RAW" ]; then
  while IFS= read -r line; do
    # 分段标题（direct dependencies / dev_dependencies / transitive ...）
    case "$line" in
      *"dependencies:"*) SECTION="$line"; continue ;;
    esac
    # 跳过表头、脚注、空行、`[*] indicates...`
    case "$line" in
      ""|"Package Name"*|"[*] indicates"*|"Showing outdated"*) continue ;;
    esac
    case "$line" in
      *" packages "*|"To update"*) continue ;;
    esac
    # 数据行：至少 5 个字段，且第 2/5 字段形如版本号（可带 `*`）
    # shellcheck disable=SC2086
    set -- $line
    [ "$#" -ge 5 ] || continue
    name="$1"; current="$2"; latest="$5"
    case "$current" in \**) current="${current#\*}";; esac
    case "$latest"   in \**) latest="${latest#\*}";;   esac
    # 版本号形态校验：必须以数字开头（挡掉脚注里的英文词）
    case "$current" in [0-9]*) ;; *) continue ;; esac
    case "$latest"   in [0-9]*) ;; *) continue ;; esac
    if [ "$current" != "$latest" ]; then
      UPGRADABLE=$((UPGRADABLE + 1))
      # 归属分段（direct/dev/transitive）一并打出来，便于发布评审
      case "$SECTION" in
        *direct*)      scope="direct" ;;
        *dev_dep*)     scope="dev" ;;
        *transitive*)  scope="transitive" ;;
        *)             scope="-" ;;
      esac
      UPGRADABLE_NAMES="${UPGRADABLE_NAMES}${name} ${current}→${latest} (${scope}); "
    fi
  done <<EOF
$OUTDATED_RAW
EOF
fi

# 交叉校验：dart 自报的「N upgradable dependencies are locked ...」若大于逐行
# 计数，以较大者为准并在报告里说明（宁可误严，不可误松）。
SELF_REPORTED="$(printf '%s\n' "$OUTDATED_RAW" | grep -oE '^[0-9]+ upgradable dependencies' | grep -oE '^[0-9]+' | tail -1)"
if [ -n "$SELF_REPORTED" ] && [ "$SELF_REPORTED" -gt "$UPGRADABLE" ]; then
  UPGRADABLE="$SELF_REPORTED"
fi

echo "=== [3/4] 阈值判定 ==="
echo "可升级依赖数: ${UPGRADABLE}"
echo "阈值:         ${THRESHOLD}（--threshold 可改；含直接 + dev + 传递全部口径）"
if [ -n "$UPGRADABLE_NAMES" ]; then
  echo "可升级清单:"
  # 逐条换行太占屏；按 118 列折行（终端常见宽度），dev 依赖一并标注。
  printf '%s\n' "$UPGRADABLE_NAMES" | fold -s -w 118 | sed 's/^/              /'
fi
echo ""

echo "=== [4/4] 核查结论 ==="
if [ -z "$OUTDATED_RAW" ]; then
  echo "❌ 无法核查：dart 不在 PATH——「查不了」不等于「通过」。"
  echo "   修法：export PATH=\"\$HOME/development/flutter/bin:\$PATH\" 后重跑。"
  exit 2
fi
# dart pub outdated 在依赖解析失败时打印错误而非表格——此时同样不可判为通过。
if ! printf '%s\n' "$OUTDATED_RAW" | grep -q '^Package Name'; then
  echo "❌ 无法核查：dart pub outdated 未产出可解析的表格——依赖状态未知，不判通过。"
  exit 2
fi
if printf '%s\n' "$OUTDATED_RAW" | grep -qiE 'could not|failed to resolve|Error:|Exception:|No pubspec|Could not find'; then
  echo "❌ 无法核查：dart pub outdated 报告了解析错误——依赖状态未知，不判通过。"
  exit 2
fi
if [ "$UPGRADABLE" -gt "$THRESHOLD" ]; then
  echo "❌ 门禁未过：可升级依赖 ${UPGRADABLE} > 阈值 ${THRESHOLD}——视为不可发布。"
  echo "   修法：升级依赖（先查 pub.dev 安全公告），或评估后用 --threshold 显式调整。"
  exit 1
fi
echo "✅ 门禁通过：可升级依赖 ${UPGRADABLE} <= 阈值 ${THRESHOLD}——视为可发布。"
echo "提示：升级依赖前先查 pub.dev 对应版本的安全公告；riverpod/cryptography 等"
echo "安全敏感包升级后必须重跑 flutter analyze + flutter test（本仓库门禁）。"
exit 0

#!/usr/bin/env bash
# bump_version.sh —— 版本三处同步（AGENTS.md §7 发版约定的自动化，2026-09-27）。
#
# 用法：bash tools/bump_version.sh <X.Y.Z>
#   例：bash tools/bump_version.sh 1.17.34
#
# 行为：
#   1. pubspec.yaml  version: X.Y.Z+N   （N = 现有 build 号 + 1；首次可显式传 <X.Y.Z>+N）
#   2. tools/drawing_notes_setup.iss  MyAppVersion "X.Y.Z"
#   3. CHANGELOG.md  校验顶部条目已包含 X.Y.Z（不存在仅警告不阻塞——
#      变更内容需要人写，脚本不代拟）。
#   4. 全部改动打印 diff 摘要；不提交（git 操作留给提交者）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ $# -lt 1 ]; then
  echo "用法: bash tools/bump_version.sh <X.Y.Z>[+N]"
  exit 1
fi
NEW_VERSION="$1"
NEW_BASE="${NEW_VERSION%%+*}"

# 现版本与 build 号（锚定 version: 行——全文件扫会把依赖约束里的 "+1"
# （如 perfect_freehand ^2.5.2+1）也抓进来）。
# M-12 修复（2026-11-13 全面审计）：grep -oP 是 GNU 扩展，macOS BSD grep
# 不支持——改 sed 捕获组（BSD/GNU 通用）。
CURRENT_BASE="$(sed -n 's/^version: \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' pubspec.yaml)"
CURRENT_BUILD="$(sed -n 's/^version: [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*+\([0-9][0-9]*\).*/\1/p' pubspec.yaml)"
if [ "$NEW_BASE" = "$CURRENT_BASE" ]; then
  NEW_BUILD=$((CURRENT_BUILD + 1))
  NEW_VERSION="${NEW_BASE}+${NEW_BUILD}"
else
  if [[ "$NEW_VERSION" != *"+"* ]]; then
    NEW_BUILD=$((CURRENT_BUILD + 1))
    NEW_VERSION="${NEW_BASE}+${NEW_BUILD}"
  fi
fi

echo "→ 版本: $CURRENT_BASE+$CURRENT_BUILD ⇒ $NEW_VERSION"

# M-12 修复（2026-11-13）：BSD sed（macOS）的 -i 必须带备份后缀参数，
# GNU sed 的 -i 不带——按 uname 分派，两平台同一脚本可跑。
sed_inplace() {
  if [ "$(uname)" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# 1. pubspec.yaml
sed_inplace "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
grep -n "^version" pubspec.yaml

# 2. Inno Setup 脚本
sed_inplace "s/#define MyAppVersion \".*\"/#define MyAppVersion \"$NEW_BASE\"/" tools/drawing_notes_setup.iss
grep -n 'MyAppVersion "' tools/drawing_notes_setup.iss | head -1

# 3. CHANGELOG 顶部条目校验（仅警告）。
if ! head -30 CHANGELOG.md | grep -q "\[$NEW_BASE\]"; then
  echo "⚠ CHANGELOG.md 顶部 30 行未发现 [$NEW_BASE] 条目——发版前请补写变更记录。"
fi

echo "✓ 完成（未提交；请自查后 git add + commit）"

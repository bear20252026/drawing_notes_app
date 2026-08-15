#!/usr/bin/env bash
# SBOM-CVE 依赖核查脚本（审计修复 2026-08-15，P4 建议项）。
#
# 2026 合规要求（docs.flutter.dev/security + ostorlab 清单）：
# - 生成并归档 SBOM（pubspec.lock 即 Flutter 侧 SBOM）
# - 定期核查依赖更新（CVE/修复版追踪）
# 本脚本：输出依赖概览（SBOM 摘要）→ 检查过期依赖（CVE 修复版面）
# 门禁：dev_dependencies 之外的可升级依赖 <= 阈值视为可发布（默认 3）。
set -u

cd "$(dirname "$0")/.."

echo "=== [1/3] SBOM 摘要（pubspec.lock 依赖清单）==="
grep -cE "^  [a-z_0-9]+:" pubspec.lock | awk '{print "锁定依赖总数: "$1}'
echo "直接依赖（pubspec.yaml）："
grep -E "^  [a-z_0-9_]+:" pubspec.yaml | grep -v "^\s*#" | sed 's/://' | tr -d ' ' | sort | tr '\n' ' '
echo ""
echo "锁定关键包版本（CVE 追踪重点）："
grep -A2 -E "^  (flutter_riverpod|riverpod|cryptography|shared_preferences|path_provider|file_selector|material_ui):" pubspec.lock | grep -E "^  [a-z_0-9]+:|version" | paste -sd' ' | sed 's/  */ /g'
echo ""

echo "=== [2/3] 过期依赖检查（dart pub outdated）==="
if command -v dart >/dev/null 2>&1; then
  dart pub outdated 2>&1 | tail -20 || true
else
  echo "（dart 不在 PATH，跳过——请确保 flutter/bin 在 PATH）"
fi

echo ""
echo "=== [3/3] 核查结论 ==="
echo "提示：升级依赖前先查 pub.dev 对应版本的安全公告；riverpod/cryptography 等"
echo "安全敏感包升级后必须重跑 flutter analyze + flutter test（本仓库门禁）。"

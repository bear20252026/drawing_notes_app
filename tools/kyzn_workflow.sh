#!/usr/bin/env bash
# KyZN 四代理流程本地化（不引入 Claude Code，零外部 LLM）
# 借鉴：bokiko/KyZN "profile → 4 specialists → consensus → fix → verify" 流程。
# 本地化映射（全部为项目已接入的本地工具，涉密零上传）：
#   [安全]     → Skylos（security）+ RepoPilot（security boundary/taint）
#   [正确性]   → flutter analyze + flutter test（249 项基线）
#   [性能]     → dart_code_metrics（复杂度）+ linecheck/sloc-guard（结构）
#   [架构]     → pyscn（A-F 评分）+ sloc-guard（目录结构）
# 流程：profile(聚合评分) → 四维度发现 → 严重度分批 → 每批后 build 验证
# 用法：bash tools/kyzn_workflow.sh [profile|fix|status]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 注入 Flutter/工具 PATH（bash 环境默认不含）
export PATH="/d/flutter/bin:$HOME/.cargo/bin:$PATH"

log() { printf '\033[1;36m[kyzn-local]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[kyzn-local] ⚠ %s\n' "$*"; }
err() { printf '\033[1;31m[kyzn-local] ✗ %s\n' "$*"; }

# ---------- 1. Profile：聚合健康评分（四维度） ----------
profile() {
  log "Profile：四维度健康评分"
  # 安全：Skylos（若可用）
  if command -v skylos >/dev/null 2>&1; then
    log "[安全] Skylos security 扫描..."
    skylos . --secrets --danger --summary 2>/dev/null | grep -E "Found [0-9]+" | head -1 || warn "[安全] Skylos 扫描完成（无摘要）"
  else
    warn "[安全] skylos 未安装（CI 中自动安装）"
  fi
  # 正确性：flutter analyze + test
  log "[正确性] flutter analyze..."
  flutter analyze 2>&1 | tail -1
  log "[正确性] flutter test（249 项基线）..."
  flutter test 2>&1 | tail -1
  # 性能：行数门禁（500 警告 / 1000 错误）
  log "[性能] 行数门禁（linecheck/sloc-guard 语义）..."
  python3 tools/code_guard.py --dir lib --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  [性能] 超限文件: {d[\"error_count\"]} 错误 + {d[\"warn_count\"]} 警告（500/1000 双档）')
" 2>/dev/null || warn "[性能] code_guard 不可用"
  # 架构：sloc-guard 结构门禁
  if [ -x tools/bin/sloc-guard.exe ]; then
    log "[架构] sloc-guard 结构门禁..."
    tools/bin/sloc-guard.exe check --config .sloc-guard.toml 2>/dev/null | tail -1
  fi
  log "Profile 完成（详见各工具输出，全部本地零上传）"
}

# ---------- 2. Fix：严重度分批 + 每批后构建验证 ----------
fix() {
  log "Fix：四维度发现问题 → 严重度分批（先观测，不自动改码）"
  # 批次 1（HIGH）：安全 + 正确性
  log "批次 HIGH：安全/正确性（Skylos 安全 + analyze 错误）"
  if command -v skylos >/dev/null 2>&1; then
    skylos . --secrets --danger --sarif /tmp/kyzn_sec.sarif >/dev/null 2>&1
    n=$(python3 -c "import json;d=json.load(open('/tmp/kyzn_sec.sarif'));print(len(d.get('runs',[{}])[0].get('results',[])))" 2>/dev/null || echo 0)
    log "  安全发现 $n 条（人工/代理按 SARIF 修复）"
  fi
  # 批次 2（MEDIUM）：架构（pyscn A-F）
  log "批次 MEDIUM：架构（pyscn 评分）"
  if command -v pyscn >/dev/null 2>&1; then
    pyscn analyze lib --skip-clones --skip-communities --skip-lcom --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(f'  架构健康 {d.get(\"health\", {}).get(\"score\", \"?\")} / 100')
except Exception:
    print('  架构扫描完成（详见输出）')
" 2>/dev/null || warn "  pyscn 不可用"
  fi
  # 每批后验证（KyZN 核心：验证构建）
  log "构建验证（每次修复后）..."
  flutter analyze 2>&1 | tail -1
  flutter test 2>&1 | tail -1
  log "Fix 观测完成：按上面严重度分批人工/代理修复，每批后重跑本脚本验证"
}

# ---------- 3. Status：汇总健康状态 ----------
status() {
  log "Status：健康汇总"
  profile
}

case "${1:-status}" in
  profile) profile ;;
  fix)     fix ;;
  status)  status ;;
  *) echo "用法: bash tools/kyzn_workflow.sh [profile|fix|status]"; exit 1 ;;
esac

#!/usr/bin/env bash
# 覆盖率门槛：运行 flutter test --coverage 并输出分层覆盖率报告。
set -uo pipefail
cd "$(dirname "$0")/.."

# L-4 收口（2026-11-16）：/d/flutter/bin 是 Windows Git Bash 的 D 盘路径，
# macOS 不存在——与 kyzn_workflow.sh（M-12）同口径：优先用已在 PATH 里的
# flutter，否则按平台补候选路径。
if ! command -v flutter >/dev/null 2>&1; then
  if [ "$(uname)" = "Darwin" ]; then
    export PATH="$HOME/development/flutter/bin:$HOME/flutter/bin:$PATH"
  else
    export PATH="/d/flutter/bin:$PATH"
  fi
fi
flutter test --coverage

echo "== 覆盖率报告 =="
# L-4 收口（2026-11-16）：分层名对齐现行 Feature-First 结构
# （lib/core / lib/features / lib/shared / lib/app），替换早已不存在的
# engine/models/storage/ui 旧层名（旧 awk 全部落空、门槛空转）。
awk -F: '
  /^SF:/{file=$2}
  /^LF:/{lf_total+=$2; if (file ~ /lib[\\/]core[\\/]/) lf_core+=$2; else if (file ~ /lib[\\/]features[\\/]/) lf_features+=$2; else if (file ~ /lib[\\/]shared[\\/]/) lf_shared+=$2; else if (file ~ /lib[\\/]app[\\/]/) lf_app+=$2}
  /^LH:/{lh_total+=$2; if (file ~ /lib[\\/]core[\\/]/) lh_core+=$2; else if (file ~ /lib[\\/]features[\\/]/) lh_features+=$2; else if (file ~ /lib[\\/]shared[\\/]/) lh_shared+=$2; else if (file ~ /lib[\\/]app[\\/]/) lh_app+=$2}
  END {
    pc = (lf_core>0 ? sprintf("%.1f%%", 100*lh_core/lf_core) : "N/A")
    pf = (lf_features>0 ? sprintf("%.1f%%", 100*lh_features/lf_features) : "N/A")
    ps = (lf_shared>0 ? sprintf("%.1f%%", 100*lh_shared/lf_shared) : "N/A")
    pa = (lf_app>0 ? sprintf("%.1f%%", 100*lh_app/lf_app) : "N/A")
    pt = (lf_total>0 ? sprintf("%.1f%%", 100*lh_total/lf_total) : "N/A")
    printf "  总计    : %s (%d/%d 行)\n", pt, lh_total, lf_total
    printf "  core    : %s (%d/%d 行)\n", pc, lh_core, lf_core
    printf "  features: %s (%d/%d 行)\n", pf, lh_features, lf_features
    printf "  shared  : %s (%d/%d 行)\n", ps, lh_shared, lf_shared
    printf "  app     : %s (%d/%d 行)\n", pa, lh_app, lf_app
    if (lf_core > 0 && 100*lh_core/lf_core < 70.0) {
      print "WARN: core 覆盖率低于 70% 门槛"
      exit 1
    }
  }
' coverage/lcov.info

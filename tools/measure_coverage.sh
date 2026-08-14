#!/usr/bin/env bash
# 覆盖率门槛：运行 flutter test --coverage 并输出分层覆盖率报告。
set -uo pipefail
cd "$(dirname "$0")/.."

export PATH="/d/flutter/bin:$PATH"
flutter test --coverage

echo "== 覆盖率报告 =="
awk -F: '
  /^SF:/{file=$2}
  /^LF:/{lf_total+=$2; if (file ~ /engine[\\/]/) lf_engine+=$2; else if (file ~ /models[\\/]/) lf_models+=$2; else if (file ~ /storage[\\/]/) lf_storage+=$2; else if (file ~ /ui[\\/]/) lf_ui+=$2}
  /^LH:/{lh_total+=$2; if (file ~ /engine[\\/]/) lh_engine+=$2; else if (file ~ /models[\\/]/) lh_models+=$2; else if (file ~ /storage[\\/]/) lh_storage+=$2; else if (file ~ /ui[\\/]/) lh_ui+=$2}
  END {
    pe = (lf_engine>0 ? sprintf("%.1f%%", 100*lh_engine/lf_engine) : "N/A")
    pm = (lf_models>0 ? sprintf("%.1f%%", 100*lh_models/lf_models) : "N/A")
    ps = (lf_storage>0 ? sprintf("%.1f%%", 100*lh_storage/lf_storage) : "N/A")
    pu = (lf_ui>0 ? sprintf("%.1f%%", 100*lh_ui/lf_ui) : "N/A")
    pt = (lf_total>0 ? sprintf("%.1f%%", 100*lh_total/lf_total) : "N/A")
    printf "  总计   : %s (%d/%d 行)\n", pt, lh_total, lf_total
    printf "  engine : %s (%d/%d 行)\n", pe, lh_engine, lf_engine
    printf "  models : %s (%d/%d 行)\n", pm, lh_models, lf_models
    printf "  storage: %s (%d/%d 行)\n", ps, lh_storage, lf_storage
    printf "  ui     : %s (%d/%d 行)\n", pu, lh_ui, lf_ui
    if (lf_engine > 0 && 100*lh_engine/lf_engine < 70.0) {
      print "WARN: engine 覆盖率低于 70% 门槛"
      exit 1
    }
  }
' coverage/lcov.info

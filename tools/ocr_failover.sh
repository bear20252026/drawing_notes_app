#!/usr/bin/env bash
# OCR 双模型故障切换 + 额度监控脚本
# 用途：智谱 GLM 主审 → DeepSeek 备选自动切换；token 用量监控。
# 用法：
#   bash tools/ocr_failover.sh              # 查询当前激活模型
#   bash tools/ocr_failover.sh review ...   # 智谱优先评审，失败自动切 DeepSeek 重试
#   bash tools/ocr_failover.sh to-deepseek  # 手动切到 DeepSeek 备选
#   bash tools/ocr_failover.sh to-zhipu     # 手动切回智谱主审
#   bash tools/ocr_failover.sh usage        # 显示最近评审 token 用量
set -uo pipefail

OCR="${OCR_BIN:-ocr}"
CONFIG="${HOME}/.opencodereview/config.json"
LOG="${HOME}/.opencodereview/ocr_usage.log"

# 智谱优先 / DeepSeek 备选
ZHIPU_PROVIDER="z-ai"
ZHIPU_MODEL="glm-5.2"
DEEPSEEK_PROVIDER="deepseek"
DEEPSEEK_MODEL="deepseek-v4-pro"

log() { printf '\033[1;36m[ocr-failover]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ocr-failover] ⚠ %s\n' "$*"; }
err()  { printf '\033[1;31m[ocr-failover] ✗ %s\n' "$*"; }

current_provider() {
  python -c "import json,os; d=json.load(open(os.path.expanduser('~/.opencodereview/config.json'))); print(d.get('provider',''))" 2>/dev/null
}

switch_to() {
  local provider="$1" model="$2"
  "$OCR" config set provider "$provider" >/dev/null 2>&1
  "$OCR" config set model "$model" >/dev/null 2>&1
  log "已切换: $provider / $model"
}

# 测试当前模型连接
test_connection() {
  "$OCR" llm test >/dev/null 2>&1
}

usage_log() {
  if [ -f "$LOG" ]; then
    log "最近评审 token 用量（行数: $(wc -l < "$LOG")）:"
    tail -8 "$LOG"
  else
    log "暂无用量记录"
  fi
}

case "${1:-}" in
  "")
    log "当前激活: $(current_provider)"
    usage_log
    ;;
  to-deepseek)
    switch_to "$DEEPSEEK_PROVIDER" "$DEEPSEEK_MODEL"
    ;;
  to-zhipu)
    switch_to "$ZHIPU_PROVIDER" "$ZHIPU_MODEL"
    ;;
  usage)
    usage_log
    ;;
  review)
    shift
    # 智谱优先；失败（额度耗尽/超时）自动切 DeepSeek 重试一次
    if test_connection; then
      log "使用智谱主审: $ZHIPU_MODEL"
      if "$OCR" review "$@" 2>&1 | tee /tmp/ocr_review_out.txt; then
        # 记录 token 用量
        grep -oE "~[0-9]+ token\\(s\\) used" /tmp/ocr_review_out.txt >> "$LOG" 2>/dev/null || true
        exit 0
      fi
      warn "智谱评审失败（可能额度耗尽），切换到 DeepSeek 重试..."
    else
      warn "智谱连接失败，尝试 DeepSeek 备选..."
    fi
    switch_to "$DEEPSEEK_PROVIDER" "$DEEPSEEK_MODEL"
    log "使用 DeepSeek 备选: $DEEPSEEK_MODEL"
    "$OCR" review "$@" 2>&1 | tee /tmp/ocr_review_out.txt
    grep -oE "~[0-9]+ token\\(s\\) used" /tmp/ocr_review_out.txt >> "$LOG" 2>/dev/null || true
    # 评审结束后切回智谱（下次仍优先）
    switch_to "$ZHIPU_PROVIDER" "$ZHIPU_MODEL"
    ;;
  *)
    echo "用法: bash tools/ocr_failover.sh [review ...|to-deepseek|to-zhipu|usage]"
    exit 1
    ;;
esac

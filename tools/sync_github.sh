#!/usr/bin/env bash
# GitHub 同步机制（项目规范 docs/RELEASE_PIPELINE.md 强制项）：
# 每次代码修改提交后必须立即运行本脚本，确保远端与本地一致。
# 用法：bash tools/sync_github.sh ["提交说明"]   （无说明则仅推送已有提交）
set -euo pipefail
cd "$(dirname "$0")/.."

MSG="${1:-}"

# 1) 有修改则提交（未暂存+未跟踪全收）
if [ -n "$(git status --porcelain)" ]; then
  if [ -z "$MSG" ]; then
    MSG="chore: 同步本地修改 $(date +%Y-%m-%d\ %H:%M)"
  fi
  # L-14 护栏（2026-11-13 全面审计）：git add -A 曾把 spikes/ 268MB 实验
  # 产物全收进暂存区（.gitignore 补救前）。全收前先列出 >5MB 的未跟踪
  # 文件，命中即中止——大产物入库须人工确认（加 ignore 或显式 add）。
  BIG_UNTRACKED="$(git ls-files --others --exclude-standard -z \
    | xargs -0 -I{} sh -c 'test -f "{}" && find "{}" -size +5M' 2>/dev/null || true)"
  if [ -n "$BIG_UNTRACKED" ]; then
    echo "[sync] FATAL: 发现 >5MB 的未跟踪文件，已中止全量暂存：" >&2
    echo "$BIG_UNTRACKED" >&2
    echo "[sync] 请先加入 .gitignore 或显式 git add 后重试。" >&2
    exit 1
  fi
  git add -A
  git commit -q -m "$MSG"
  echo "[sync] committed: $MSG"
fi

# 2) 无未推送提交则结束
if [ -z "$(git log origin/master..HEAD --oneline 2>/dev/null)" ]; then
  echo "[sync] remote already up-to-date"
  exit 0
fi

# 3) 推送（最多重试 3 次，网络瞬断容错）
for i in 1 2 3; do
  if git push origin master -q; then
    break
  fi
  echo "[sync] push failed (attempt $i/3), retrying in 5s..."
  sleep 5
  if [ "$i" = "3" ]; then
    echo "[sync] FATAL: push failed after 3 attempts — 本地存在未推送提交，须人工处理" >&2
    exit 1
  fi
done

# 4) 验证：远端 HEAD 必须等于本地 HEAD（可靠性核心——推了≠推到了）
git fetch origin -q
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git ls-remote origin -h refs/heads/master | cut -f1)
if [ "$LOCAL" = "$REMOTE" ]; then
  echo "[sync] VERIFIED remote==local @ ${LOCAL:0:9}"
else
  echo "[sync] FATAL: remote($REMOTE) != local($LOCAL)" >&2
  exit 1
fi

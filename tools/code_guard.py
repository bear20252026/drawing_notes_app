#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""统一代码质量门禁（灵活回退版）。

政府项目行数约束门禁：新增文件硬上限 ≤1000 行（极限条件才可突破），
正常控制 500 行左右（<500 最佳）。

设计（专家级灵活回退）：
1. 若环境可用官方工具则优先使用：
   - sloc-guard（Rust，SLOC+目录结构+git diff 门禁）
   - linecheck（Rust，warn/error 双档轻量门禁）
2. 缺省（本机无 Rust 工具链 / CI 未安装）自动回退到本脚本内置检查，
   实现与 linecheck 一致的 "500 行警告 / 1000 行错误" 双档语义。

用法：
  python tools/code_guard.py            # 全量扫描 lib/（含回退逻辑）
  python tools/code_guard.py --dir lib  # 指定目录
  python tools/code_guard.py --warn 500 --error 1000
  python tools/code_guard.py --json     # JSON 输出（CI 仪表盘）
  python tools/code_guard.py --force-native  # 强制内置检查（跳过官方工具）

退出码：0=通过；1=有错误；2=仅警告（供 CI 分级）。
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

# 默认阈值：警告 500 行 / 错误 1000 行（对齐项目记忆与评估报告）
DEFAULT_WARN = 500
DEFAULT_ERROR = 1000

# 默认扫描目录（相对仓库根）
DEFAULT_DIRS = ["lib"]

# 忽略的目录/文件（构建产物、生成代码等）
IGNORED_DIRS = {".git", "build", ".dart_tool", "node_modules", "target", "dist", "vendor"}


@dataclass
class Violation:
    file: str
    lines: int
    limit: int
    status: str  # "warn" | "error"
    percent: int


def _is_ignored(path: Path) -> bool:
    return any(part in IGNORED_DIRS for part in path.parts)


def _walk_dart_files(directory: Path) -> List[Path]:
    files: List[Path] = []
    for root, dirs, names in os.walk(directory):
        # 就地过滤忽略目录，避免深挖构建产物
        dirs[:] = [d for d in dirs if d not in IGNORED_DIRS]
        for name in names:
            if name.endswith(".dart"):
                files.append(Path(root) / name)
    return files


def _count_lines(path: Path) -> int:
    """统计源行数：忽略空行与纯注释行（对齐 sloc-guard 的 skip_blank/skip_comments 语义）。"""
    count = 0
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:  # skylos: ignore —— SKY-D215 受管路径（读本地源文件——pyproject 已规则级豁免——inline 双保险）
            for raw in f:
                line = raw.strip()
                if not line:
                    continue
                if line.startswith("//") or line.startswith("/*") or line.startswith("*"):
                    continue
                count += 1
    except OSError:
        return 0
    return count


def native_scan(directory: Path, warn: int, error: int) -> List[Violation]:
    """内置检查：扫描目录下所有 Dart 文件，按双档阈值判定。"""
    violations: List[Violation] = []
    for f in _walk_dart_files(directory):
        lines = _count_lines(f)
        if lines > error:
            violations.append(
                Violation(f.name, lines, error, "error", int(lines * 100 / error))
            )
        elif lines > warn:
            violations.append(
                Violation(f.name, lines, warn, "warn", int(lines * 100 / warn))
            )
    return violations


def run_sloc_guard(directory: Path) -> Optional[int]:
    """尝试官方 sloc-guard；返回退出码，不可用返回 None。"""
    exe = shutil.which("sloc-guard")
    if exe is None:
        return None
    cfg = Path(".sloc-guard.toml")
    cmd = [exe, "check"]
    if cfg.exists():
        cmd = [exe, "check", "--config", str(cfg)]
    try:
        result = subprocess.run(cmd, cwd=directory, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        return result.returncode
    except OSError:
        return None


def run_linecheck(directory: Path, warn: int, error: int) -> Optional[int]:
    """尝试官方 linecheck；返回退出码，不可用返回 None。"""
    exe = shutil.which("linecheck")
    if exe is None:
        return None
    cmd = [exe, "--max-lines", str(error), str(directory)]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        return result.returncode
    except OSError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="统一代码质量门禁（行数约束）")
    parser.add_argument("--dir", default=None, help="扫描目录（默认 lib）")
    parser.add_argument("--warn", type=int, default=DEFAULT_WARN, help="警告阈值（默认 500）")
    parser.add_argument("--error", type=int, default=DEFAULT_ERROR, help="错误阈值（默认 1000）")
    parser.add_argument("--json", action="store_true", help="JSON 输出")
    parser.add_argument("--force-native", action="store_true", help="强制内置检查")
    args = parser.parse_args()

    root = Path.cwd()
    scan_dir = Path(args.dir) if args.dir else root / DEFAULT_DIRS[0]

    # 优先官方工具（灵活回退）；CI 已装 sloc-guard/linecheck 时走官方路径
    if not args.force_native:
        if args.dir is None:
            code = run_sloc_guard(root)
            if code is not None:
                print(f"[code-guard] sloc-guard 退出码 {code}")
                return code
        code = run_linecheck(scan_dir, args.warn, args.error)
        if code is not None:
            print(f"[code-guard] linecheck 退出码 {code}")
            return code

    # 内置回退检查
    violations = native_scan(scan_dir, args.warn, args.error)
    errors = [v for v in violations if v.status == "error"]
    warns = [v for v in violations if v.status == "warn"]

    if args.json:
        payload = {
            "tool": "code-guard-native",
            "warn_limit": args.warn,
            "error_limit": args.error,
            "violations": [v.__dict__ for v in violations],
            "error_count": len(errors),
            "warn_count": len(warns),
            "status": "error" if errors else ("warn" if warns else "ok"),
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        if violations:
            print(f"[code-guard] 违反行数约束的文件（警告 {args.warn} / 错误 {args.error}）：")
            for v in sorted(violations, key=lambda x: -x.lines):
                print(f"  {v.file}: {v.lines} 行 ({v.status} 阈值 {v.limit}, {v.percent}%)")
        else:
            print(f"[code-guard] 通过：{scan_dir} 下无超过 {args.warn} 行的 Dart 文件。")

    # 退出码分级：错误=1，仅警告=2，通过=0
    if errors:
        return 1
    if warns:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

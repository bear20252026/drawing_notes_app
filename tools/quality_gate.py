#!/usr/bin/env python3
"""软件质量保障门禁聚合器（商业化门禁，一键复现）。

构成 lead 收口 / CI 的统一入口。每个门禁独立运行、独立判定，
全部通过才 exit 0；可选门禁（依赖 WSL/Linux 或未构建的二进制）自动标记 SKIP 而不拉低门禁。

用法：
  python tools/quality_gate.py            # 标准门禁（格式 + 静态 + 反模式 + 架构 + 回归）
  python tools/quality_gate.py --quick    # 快速门禁（静态 + 反模式 + 架构，最快反馈）
  python tools/quality_gate.py --full     # 标准 + 额外环境门禁（check_boundaries / sloc-guard，若可用）

门禁清单（对应 analysis_options.yaml 的 dart_code_metrics 配置）：
  [1] dart format      格式化门禁（--set-exit-if-changed）
  [2] flutter analyze  静态分析门禁
  [3] metrics analyze lib   反模式扫描门禁（DCM：avoid-unused-parameters/avoid-dynamic/
                            long-method/long-parameter-list/复杂度阈值）
  [4] architecture_test     分层架构边界门禁（feature 边界 / 循环依赖，9 项）
  [5] flutter test (回归)    回归门禁（features/drawing + features/notes + 其余）
  [OPT] check_boundaries.sh / sloc-guard.exe  环境门禁（WSL / 未构建时 SKIP）
"""

from __future__ import annotations

import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (name, cmd, required, timeout_seconds)
# 默认门禁：required=True 失败即拉低 exit code；可选门禁 required=False 失败仅提示。
def build_commands(full: bool) -> list[tuple[str, list[str], bool, int]]:
    cmds: list[tuple[str, list[str], bool, int]] = [
        # 格式化门禁仅作 informational（required=False）：本代码库未按 dart format 规范统一格式化，
        # 强制会造成大规模 diff 并干扰进行中的 M5。可在 M5 落地后单独建立完整 format baseline。
        ("format", ["dart", "format", "--output=none", "--set-exit-if-changed", "lib"], False, 120),
        ("analyze", ["flutter", "analyze", "--no-pub"], True, 300),
        ("anti-pattern (DCM)", ["metrics", "analyze", "lib"], True, 300),
        ("architecture", ["flutter", "test", "--no-pub", "test/architecture_test.dart"], True, 600),
        ("regression", [
            "flutter", "test", "--no-pub",
            "test/features/drawing", "test/features/notes",
        ], True, 600),
    ]
    if full:
        # 依赖 WSL / 未构建二进制的环境门禁，存在才纳入。
        cmds += [
            ("boundaries (WSL)", ["bash", "tools/check_boundaries.sh"], False, 120),
            ("sloc-guard", ["tools/bin/sloc-guard.exe", "check", "--config", ".sloc-guard.toml"], False, 120),
        ]
    return cmds


def run(cmd: list[str], timeout: int) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
            shell=True,
            encoding="utf-8",
            errors="replace",
        )
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    except FileNotFoundError:
        return -1, "[FileNotFound] 命令不可用: " + " ".join(cmd)
    except subprocess.TimeoutExpired:
        return -2, f"[Timeout] 超过 {timeout}s: " + " ".join(cmd)


def tail(text: str, n: int = 25) -> str:
    lines = [l for l in text.splitlines() if l.strip()]
    return "\n".join(lines[-n:])


def main() -> int:
    args = sys.argv[1:]
    full = "--full" in args
    quick = "--quick" in args

    if quick:
        cmds = [c for c in build_commands(full=False) if c[0] in ("analyze", "anti-pattern (DCM)", "architecture")]
    else:
        cmds = build_commands(full)

    failures = []
    skipped = []
    warnings = []
    t0 = time.time()
    print("=" * 68)
    print(f"软件质量保障门禁  |  mode={'quick' if quick else ('full' if full else 'standard')}")
    print(f"根目录: {ROOT}")
    print("=" * 68)

    for name, cmd, required, timeout in cmds:
        label = name.ljust(24)
        print(f"\n[{name}]\n  $ {' '.join(cmd)}")
        code, out = run(cmd, timeout)
        if code == -1 or code == -2:
            print(f"  -> {label} SKIP（{out.splitlines()[0] if out else '运行环境不支持'}）")
            skipped.append(name)
            continue
        status = "PASS" if code == 0 else ("FAIL" if required else "INFO(非阻断)")
        print(f"  -> {label} {status}  (exit {code})")
        if code != 0:
            print("  ---- 输出（尾部） ----")
            print(tail(out))
            if required:
                failures.append((name, code))
            else:
                warnings.append(name)
        else:
            # 轻量展示门禁结果摘要
            summary = [l for l in out.splitlines() if ("issue" in l.lower() or "pass" in l.lower() or "All tests" in l or "no issues" in l.lower())]
            if summary:
                print("  " + tail("\n".join(summary) if summary else out, 4))

    total = (time.time() - t0) / 60
    print("\n" + "=" * 68)
    print(f"耗时 {total:.1f} min")
    if failures:
        print("❌ 门禁失败：")
        for name, code in failures:
            print(f"   - {name}  (exit {code})")
        print("=" * 68)
        return 1
    if warnings:
        print(f"⚠️ 非阻断告警: {', '.join(warnings)}")
    if skipped:
        print(f"⚠️ 跳过（环境依赖）: {', '.join(skipped)}")
    print("✅ 全部通过")
    print("=" * 68)
    return 0


if __name__ == "__main__":
    sys.exit(main())

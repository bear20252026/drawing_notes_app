#!/usr/bin/env python3
"""秘密扫描（发布材料门禁——专家审计最优先④，2026-08-16）。

Gitleaks 模式（regex + keywords 快速过滤 + 熵检测）的轻量实现：扫描工作区
文本文件中的敏感模式（私钥/API 令牌/凭据/高熵字符串），CI 阻断性检查——
发现即退出码 1。生产密钥/口令禁止入仓（专家要求）。

用法：python tools/scan_secrets.py [--path .] [--exclude sbom.cdx.json]
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

# 敏感模式（Gitleaks 式：regex + 关键字描述——命中即报告）。
RULES = [
    (re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"), "私钥（PEM）"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS Access Key"),
    (re.compile(r"github_pat_[0-9A-Za-z_]{22,}"), "GitHub PAT"),
    (re.compile(r"ghp_[0-9A-Za-z]{36,}"), "GitHub Token"),
    (re.compile(r"sk_live_[0-9a-zA-Z]{24,}"), "Stripe Live Key"),
    (re.compile(r"(?i)(api[_-]?key|secret|token|password)\s*[=:]\s*['\"][0-9a-zA-Z_\-]{16,}['\"]"),
     "凭据赋值（API key/secret/token/password）"),
    (re.compile(r"(?i)BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY"), "私钥块"),
]

# 扫描排除（构建/缓存/生成的产物）。
EXCLUDED_DIRS = {".git", ".dart_tool", "build", ".idea", ".vs", "node_modules", ".desloppify"}
EXCLUDED_FILES = {"sbom.cdx.json", "pubspec.lock", "untranslated_messages.json", "generated_plugin_registrant.cc"}
# 误报豁免（2026-08-16）：base62 字符集 const（fractional_index——默认
# 参数要求 const——合法字符集常量非密钥——高熵检测误报）。
EXCLUDED_PATHS = {"lib/core/canvas_model/fractional_index.dart"}
# 已知安全前缀（2026-09-02）：iVBORw0KGgo = PNG 文件头（\x89PNG\r\n\x1a\n）的
# base64 固定魔数——测试夹具的最小 1×1 PNG，内容人人皆知、非密钥，
# 高熵检测误报（熵 4.01，阈值 4.0 擦边）。
KNOWN_SAFE_PREFIXES = ("iVBORw0KGgo",)
# 二进制/无关扩展名跳过。
SKIP_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ttf", ".ico", ".exe", ".dll", ".pdb", ".class", ".jar", ".zip", ".lock"}


def shannon_entropy(s: str) -> float:
    """Shannon 熵（Gitleaks 熵检测——高熵字符串疑似随机令牌，阈值 4.0）。"""
    if not s:
        return 0.0
    freq = {}
    for ch in s:
        freq[ch] = freq.get(ch, 0) + 1
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in freq.values())


def scan_file(path: Path, findings: list) -> None:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return
    for line_no, line in enumerate(text.splitlines(), 1):
        for pattern, desc in RULES:
            m = pattern.search(line)
            if m:
                findings.append((str(path), line_no, desc, line.strip()[:80]))
        # 熵检测（Gitleaks 模式——高熵字符串疑似随机令牌，阈值 4.0）：
        # 仅检测引号内的长字符串（真实密钥/令牌通常出现在字符串字面量中——
        # 避免裸标识符/类名误报）。
        for token in re.findall(r"['\"]([0-9a-zA-Z_\-]{24,})['\"]", line):
            if token.startswith(KNOWN_SAFE_PREFIXES):
                continue
            if shannon_entropy(token) > 4.0:
                findings.append((str(path), line_no, f"高熵字符串（熵 {shannon_entropy(token):.2f}）", token[:32]))
                break  # 每行一条熵告警即可


def main() -> int:
    parser = argparse.ArgumentParser(description="秘密扫描（Gitleaks 模式）")
    parser.add_argument("--path", default=".")
    parser.add_argument("--exclude", action="append", default=[], help="额外排除路径")
    args = parser.parse_args()

    root = Path(args.path)
    findings: list = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if any(part in EXCLUDED_DIRS for part in rel.parts):
            continue
        if path.name in EXCLUDED_FILES or path.name in args.exclude:
            continue
        if rel.as_posix() in EXCLUDED_PATHS:
            continue
        if path.suffix.lower() in SKIP_EXTENSIONS:
            continue
        scan_file(path, findings)

    if findings:
        print(f"⚠ 发现 {len(findings)} 处潜在敏感信息：")
        for f, ln, desc, snippet in findings[:20]:
            print(f"  {f}:{ln} [{desc}] {snippet}")
        return 1
    print("✅ 未发现敏感信息（秘密扫描通过——Gitleaks 模式）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

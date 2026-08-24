#!/usr/bin/env python3
"""CVE 依赖扫描工具 —— 基于 OSV.dev API 扫描 pubspec.lock 中所有依赖。

用法：
    python tools/scan_cve.py                          # 扫描并输出到终端
    python tools/scan_cve.py --output report.md       # 输出到 Markdown 文件
    python tools/scan_cve.py --severity HIGH           # 只报告 HIGH/CRITICAL
    python tools/scan_cve.py --fail-on-critical        # 遇到 CRITICAL 时退出码 1（CI 用）

依赖：requests（pip install requests）
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError:
    print("ERROR: 需要 requests 库。请运行: pip install requests", file=sys.stderr)
    sys.exit(2)

# ─── 常量 ───────────────────────────────────────────────────────────────────

OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"
OSV_SINGLE_URL = "https://api.osv.dev/v1/query"
ECOSYSTEM = "Pub"  # Dart/Flutter pub ecosystem

SEVERITY_ORDER = {
    "NONE": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4,
}
SEVERITY_EMOJI = {
    "CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡",
    "LOW": "🟢", "NONE": "⚪", "UNKNOWN": "❓",
}


# ─── 数据结构 ────────────────────────────────────────────────────────────────

@dataclass
class Package:
    name: str
    version: str


@dataclass
class Vulnerability:
    vuln_id: str
    summary: str
    severity: str
    aliases: list[str] = field(default_factory=list)
    fixed_version: Optional[str] = None
    reference_url: Optional[str] = None


@dataclass
class ScanResult:
    package: Package
    vulnerabilities: list[Vulnerability] = field(default_factory=list)


# ─── pubspec.lock 解析 ──────────────────────────────────────────────────────

def parse_pubspec_lock(path: Path) -> list[Package]:
    """解析 pubspec.lock，提取所有依赖包名和版本。"""
    if not path.exists():
        print(f"ERROR: 找不到 {path}", file=sys.stderr)
        sys.exit(1)

    content = path.read_text(encoding="utf-8")
    packages: list[Package] = []
    lines = content.split("\n")
    current_package: Optional[str] = None

    for line in lines:
        pkg_match = re.match(r"^  ([a-zA-Z][a-zA-Z0-9_]*)\s*:\s*$", line)
        if pkg_match:
            current_package = pkg_match.group(1)
            continue
        if current_package:
            ver_match = re.match(r'^\s+version:\s*"(.+)"\s*$', line)
            if ver_match:
                packages.append(Package(name=current_package, version=ver_match.group(1)))
                current_package = None

    return packages


# ─── OSV.dev API 查询 ────────────────────────────────────────────────────────

def query_osv_batch(packages: list[Package], batch_size: int = 100) -> dict[str, list[dict]]:
    """批量查询 OSV.dev API。返回 {package_name: [vuln_json, ...]} 映射。"""
    results: dict[str, list[dict]] = {}

    for i in range(0, len(packages), batch_size):
        batch = packages[i : i + batch_size]
        queries = [
            {"package": {"name": pkg.name, "ecosystem": ECOSYSTEM}, "version": pkg.version}
            for pkg in batch
        ]

        try:
            resp = requests.post(
                OSV_BATCH_URL, json={"queries": queries}, timeout=30,
                headers={"Content-Type": "application/json"},
            )
            resp.raise_for_status()
            data = resp.json()
        except requests.RequestException as e:
            print(f"WARNING: 批量查询失败 ({e})，回退逐个查询", file=sys.stderr)
            for pkg in batch:
                vulns = query_osv_single(pkg)
                if vulns:
                    results[pkg.name] = vulns
            continue

        for pkg, result in zip(batch, data.get("results", [])):
            vulns = result.get("vulns", [])
            if vulns:
                results[pkg.name] = vulns

    return results


def query_osv_single(package: Package) -> list[dict]:
    """单个包查询 OSV.dev API。"""
    try:
        resp = requests.post(
            OSV_SINGLE_URL,
            json={"package": {"name": package.name, "ecosystem": ECOSYSTEM}, "version": package.version},
            timeout=15,
        )
        resp.raise_for_status()
        return resp.json().get("vulns", [])
    except requests.RequestException as e:
        print(f"WARNING: 查询 {package.name} 失败: {e}", file=sys.stderr)
        return []


# ─── 漏洞信息提取 ────────────────────────────────────────────────────────────

def extract_severity(vuln: dict) -> str:
    """从漏洞数据中提取严重性等级。"""
    severity_list = vuln.get("severity", [])
    for sev in severity_list:
        score_str = sev.get("score", "")
        if score_str:
            try:
                score = float(score_str.split("/")[-1]) if "/" in score_str else float(score_str)
                if score >= 9.0: return "CRITICAL"
                elif score >= 7.0: return "HIGH"
                elif score >= 4.0: return "MEDIUM"
                elif score > 0.0: return "LOW"
            except (ValueError, IndexError):
                pass

    db_severity = vuln.get("database_specific", {}).get("severity", "")
    if db_severity:
        return db_severity.upper()

    keywords = [k.lower() for k in vuln.get("keywords", [])]
    if "critical" in keywords: return "CRITICAL"
    elif "high" in keywords: return "HIGH"

    return "UNKNOWN"


def extract_fixed_version(vuln: dict) -> Optional[str]:
    """从漏洞数据中提取修复版本。"""
    for affected in vuln.get("affected", []):
        for rng in affected.get("ranges", []):
            for event in rng.get("events", []):
                if "fixed" in event:
                    return event["fixed"]
    return None


def extract_reference_url(vuln: dict) -> Optional[str]:
    """提取第一个参考链接。"""
    for ref in vuln.get("references", []):
        url = ref.get("url", "")
        if url:
            return url
    return None


def parse_vulnerability(vuln: dict) -> Vulnerability:
    """解析 OSV 漏洞数据。"""
    return Vulnerability(
        vuln_id=vuln.get("id", "UNKNOWN"),
        summary=vuln.get("summary", vuln.get("details", "无描述")[:200]),
        severity=extract_severity(vuln),
        aliases=vuln.get("aliases", []),
        fixed_version=extract_fixed_version(vuln),
        reference_url=extract_reference_url(vuln),
    )


# ─── 报告生成 ────────────────────────────────────────────────────────────────

def generate_report(
    scan_results: list[ScanResult], total_packages: int,
    output_format: str = "markdown",
) -> str:
    """生成扫描报告。"""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    vuln_count = sum(len(r.vulnerabilities) for r in scan_results)
    affected_count = len(scan_results)

    if output_format == "json":
        return _gen_json(scan_results, total_packages, vuln_count, affected_count, now)
    elif output_format == "text":
        return _gen_text(scan_results, total_packages, vuln_count, affected_count, now)
    return _gen_markdown(scan_results, total_packages, vuln_count, affected_count, now)


def _gen_markdown(results, total, vuln_count, affected, now):
    lines = [
        "# CVE 依赖扫描报告", "",
        f"> **扫描时间**：{now}  ",
        f"> **扫描引擎**：[OSV.dev](https://osv.dev/) API  ",
        f"> **生态系统**：Pub (Dart/Flutter)  ", "",
        "## 扫描摘要", "",
        f"| 指标 | 数值 |", f"|------|------|",
        f"| 扫描包数 | {total} |", f"| 受影响包数 | {affected} |",
        f"| 漏洞总数 | {vuln_count} |", "",
    ]

    if not results:
        lines.append("✅ **未发现已知漏洞** — 所有依赖版本安全。\n")
        return "\n".join(lines)

    results.sort(key=lambda r: max(
        (SEVERITY_ORDER.get(v.severity, -1) for v in r.vulnerabilities), default=-1,
    ), reverse=True)

    lines.append("## 漏洞详情\n")
    lines.append("| 包名 | 当前版本 | CVE 编号 | 严重性 | 修复版本 | 描述 |")
    lines.append("|------|----------|----------|--------|----------|------|")

    for result in results:
        for vuln in result.vulnerabilities:
            emoji = SEVERITY_EMOJI.get(vuln.severity, "❓")
            aliases_str = ", ".join(vuln.aliases[:3]) if vuln.aliases else "-"
            vuln_id = vuln.vuln_id if aliases_str == "-" else f"{vuln.vuln_id} ({aliases_str})"
            fixed = vuln.fixed_version or "未知"
            summary = vuln.summary[:80].replace("|", "\\|")
            lines.append(f"| {result.package.name} | {result.package.version} | "
                f"{vuln_id} | {emoji} {vuln.severity} | {fixed} | {summary} |")

    lines.append("")
    lines.append("## 修复建议\n")

    has_fix = any(v.fixed_version for r in results for v in r.vulnerabilities)
    if has_fix:
        lines.append("以下依赖有已知修复版本，建议升级：\n```yaml")
        for r in results:
            for v in r.vulnerabilities:
                if v.fixed_version:
                    lines.append(f"  {r.package.name}: ^{v.fixed_version}  # 修复 {v.vuln_id}")
        lines.append("```\n")

    no_fix = [r for r in results if not any(v.fixed_version for v in r.vulnerabilities)]
    if no_fix:
        lines.append("以下依赖暂无已知修复版本，建议监控或寻找替代方案：\n")
        for r in no_fix:
            lines.append(f"- `{r.package.name}` ({r.package.version})")
        lines.append("")

    lines.append("## 参考链接\n")
    for r in results:
        for v in r.vulnerabilities:
            if v.reference_url:
                lines.append(f"- [{v.vuln_id}]({v.reference_url})")
    lines.append("")
    return "\n".join(lines)


def _gen_json(results, total, vuln_count, affected, now):
    return json.dumps({
        "scan_time": now, "ecosystem": "Pub",
        "total_packages": total, "affected_packages": affected,
        "total_vulnerabilities": vuln_count,
        "results": [{"package": r.package.name, "version": r.package.version,
            "vulnerabilities": [{"id": v.vuln_id, "severity": v.severity, "summary": v.summary,
                "aliases": v.aliases, "fixed_version": v.fixed_version,
                "reference_url": v.reference_url} for v in r.vulnerabilities]}
            for r in results],
    }, indent=2, ensure_ascii=False)


def _gen_text(results, total, vuln_count, affected, now):
    lines = [
        f"CVE 扫描报告 - {now}",
        f"扫描包数: {total}, 受影响: {affected}, 漏洞数: {vuln_count}",
        "=" * 60,
    ]
    for r in results:
        for v in r.vulnerabilities:
            emoji = SEVERITY_EMOJI.get(v.severity, "❓")
            lines.append(f"{emoji} [{v.severity}] {r.package.name}@{r.package.version}")
            lines.append(f"   {v.vuln_id}: {v.summary[:100]}")
            if v.fixed_version: lines.append(f"   修复版本: {v.fixed_version}")
            lines.append("")
    return "\n".join(lines)


# ─── 主入口 ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="CVE 依赖扫描工具 —— 基于 OSV.dev API")
    parser.add_argument("--lockfile", type=Path, default=Path("pubspec.lock"),
        help="pubspec.lock 文件路径")
    parser.add_argument("--output", "-o", type=Path, help="输出报告文件路径")
    parser.add_argument("--format", choices=["markdown", "json", "text"], default="markdown")
    parser.add_argument("--severity", choices=["LOW", "MEDIUM", "HIGH", "CRITICAL"], default="LOW",
        help="最低报告严重性")
    parser.add_argument("--fail-on-critical", action="store_true",
        help="CRITICAL 时退出码 1")
    parser.add_argument("--fail-on-high", action="store_true",
        help="HIGH+ 时退出码 1")
    args = parser.parse_args()

    print(f"📦 解析 {args.lockfile}...", file=sys.stderr)
    packages = parse_pubspec_lock(args.lockfile)
    print(f"   发现 {len(packages)} 个依赖", file=sys.stderr)

    print("🔍 查询 OSV.dev API...", file=sys.stderr)
    raw_vulns = query_osv_batch(packages)
    print(f"   发现 {len(raw_vulns)} 个受影响包", file=sys.stderr)

    min_level = SEVERITY_ORDER.get(args.severity, 0)
    scan_results: list[ScanResult] = []
    for pkg in packages:
        vulns_raw = raw_vulns.get(pkg.name, [])
        if not vulns_raw:
            continue
        vulns = [parse_vulnerability(v) for v in vulns_raw]
        vulns = [v for v in vulns if SEVERITY_ORDER.get(v.severity, 0) >= min_level]
        if vulns:
            scan_results.append(ScanResult(package=pkg, vulnerabilities=vulns))

    report = generate_report(scan_results, len(packages), args.format)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding="utf-8")
        print(f"✅ 报告已保存到 {args.output}", file=sys.stderr)
    else:
        print(report)

    if args.fail_on_critical:
        for r in scan_results:
            for v in r.vulnerabilities:
                if v.severity == "CRITICAL":
                    print("❌ 发现 CRITICAL 漏洞，退出码 1", file=sys.stderr)
                    sys.exit(1)

    if args.fail_on_high:
        for r in scan_results:
            for v in r.vulnerabilities:
                if SEVERITY_ORDER.get(v.severity, 0) >= SEVERITY_ORDER["HIGH"]:
                    print("❌ 发现 HIGH/CRITICAL 漏洞，退出码 1", file=sys.stderr)
                    sys.exit(1)

    print("✅ 扫描完成", file=sys.stderr)


if __name__ == "__main__":
    main()

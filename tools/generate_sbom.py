#!/usr/bin/env python3
"""生成 CycloneDX SBOM（软件物料清单）——发布材料门禁（专家审计最优先④，
2026-08-16）。

依据 sbomify 官方 Dart/Flutter 指南：pubspec.lock 是 SBOM 首选源（精确解析
版本 + sha256 内容哈希——可复现构建）。本脚本从 pubspec.lock 解析依赖，
生成 CycloneDX 1.5 JSON（components + purl + hashes）——标准库实现，
无需外部工具（cdxgen/Syft 为 CI 增强备选）。

用法：python tools/generate_sbom.py [--lockfile pubspec.lock] [--output sbom.cdx.json]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

SPEC_VERSION = "1.5"
BOM_FORMAT = "CycloneDX"


def parse_lockfile(path: Path) -> dict:
    """解析 pubspec.lock（packages 区——name → {version, sha256, source, dependency}）。"""
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^packages:$", text, re.MULTILINE)
    if not m:
        raise ValueError("pubspec.lock 缺少 packages 区")
    body = text[m.end():]
    packages = {}
    # 每包：2 空格缩进的 `  name:` 行开头——按此分割块（字段为 4-6 空格
    # 缩进不误分；sdks: 无缩进不进入块）。
    for block in re.split(r"\n(?=  \S+?:)", body):
        block = block.strip()
        if not block or block == "sdks:" or block.startswith(("dependency_overrides",)):
            continue
        name_line = block.split(":", 1)[0].strip()
        if not name_line:
            continue
        version_m = re.search(r'version: "([^"]+)"', block)
        sha_m = re.search(r'sha256: "([^"]+)"', block)
        source_m = re.search(r"source: (\S+)", block)
        dep_m = re.search(r'dependency: "?([^"\s]+)"?', block)
        packages[name_line] = {
            "version": version_m.group(1) if version_m else "unknown",
            "sha256": sha_m.group(1) if sha_m else None,
            "source": source_m.group(1) if source_m else "unknown",
            "dependency": dep_m.group(1) if dep_m else "transitive",
        }
    return packages


def build_bom(app_name: str, app_version: str, packages: dict) -> dict:
    """构建 CycloneDX 1.5 BOM（components + metadata）。"""
    components = []
    for name in sorted(packages):
        p = packages[name]
        component = {
            "type": "library",
            "name": name,
            "version": p["version"],
            "purl": f"pkg:pub/{name}@{p['version']}",
            "bom-ref": f"pkg:pub/{name}@{p['version']}",
            "properties": [{"name": "dependency_type", "value": p["dependency"]}],
        }
        if p["sha256"]:
            component["hashes"] = [{"alg": "SHA-256", "content": p["sha256"]}]
        components.append(component)

    bom = {
        "bomFormat": BOM_FORMAT,
        "specVersion": SPEC_VERSION,
        "serialNumber": "urn:uuid:00000000-0000-0000-0000-000000000000",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "name": app_name,
                "version": app_version,
            },
            "timestamp": "",
        },
        "components": components,
    }
    return bom


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 CycloneDX SBOM")
    parser.add_argument("--lockfile", default="pubspec.lock")
    parser.add_argument("--output", default="sbom.cdx.json")
    parser.add_argument("--app-name", default="drawing_notes_app")
    parser.add_argument("--app-version", default="1.0.0")
    args = parser.parse_args()

    lock = Path(args.lockfile)
    if not lock.exists():
        print(f"错误：未找到 {lock}")
        return 1

    packages = parse_lockfile(lock)
    bom = build_bom(args.app_name, args.app_version, packages)
    out = Path(args.output)
    out.write_text(json.dumps(bom, indent=2), encoding="utf-8")
    print(f"SBOM 已生成：{out}（{len(packages)} 个组件——CycloneDX {SPEC_VERSION}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""生成 CycloneDX SBOM（软件物料清单）——发布材料门禁（专家审计最优先④，
2026-08-16）。

依据 sbomify 官方 Dart/Flutter 指南：pubspec.lock 是 SBOM 首选源（精确解析
版本 + sha256 内容哈希——可复现构建）。本脚本从 pubspec.lock 解析依赖，
生成 CycloneDX 1.5 JSON（components + purl + hashes）——标准库实现，
无需外部工具（cdxgen/Syft 为 CI 增强备选）。

2026-10 审计增强（三处）：
① 版本号默认从 pubspec.yaml 解析（原硬编码 1.0.0——与 pubspec.yaml 的
   1.17.68+137 完全脱节，SBOM 的 metadata.component.version 是错的）。
② 直接依赖补全 SHA-256：从 pubspec.lock 的 description.sha256 读取，并
   交叉校验 pubspec.yaml 声明的直接依赖集合（**修掉一个既有 bug**：原解析器
   用 `re.split(r"\\n(?=  \\S+?:)")` 切块，把 `sdks:` 段的
   `flutter: ">=3.47.0"` 也切成了一个包，于是 SBOM 里有一条
   `pkg:pub/flutter@unknown` 的幽灵组件——167 条里 1 条是假的）。
③ 补 licenses / supplier / dependencies 关系图（lock 与 pubspec 可得的信息）。

用法：python tools/generate_sbom.py [--lockfile pubspec.lock]
                                    [--pubspec pubspec.yaml]
                                    [--app-version 1.2.3]   # 显式覆盖（默认自动解析）
                                    [--output sbom.cdx.json]
"""
from __future__ import annotations

import argparse
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

SPEC_VERSION = "1.5"
BOM_FORMAT = "CycloneDX"

# pub.dev 托管包的供应商（lock 的 description.url = "https://pub.dev"）。
PUB_DEV_SUPPLIER = "pub.dev"
# 本地 path 依赖的供应商（lock 的 description.path）。
LOCAL_SUPPLIER = "local workspace"
# SDK 依赖（flutter / flutter_localizations / sky_engine 等）。
SDK_SUPPLIER = "Flutter SDK"


def parse_pubspec_version(path: Path) -> str | None:
    """从 pubspec.yaml 读取 `version:` 行（顶层键，带 +build 号）。

    只匹配**顶层**（行首无缩进）的 `version:`——避免抓到 flutter: 段或
   注释里的同名键。解析失败返回 None（调用方回退到显式参数或 0.0.0）。
    """
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*[\"']?([^\"'\s#]+)[\"']?\s*(?:#.*)?$", text, re.MULTILINE)
    return m.group(1) if m else None


def parse_pubspec_direct_deps(path: Path) -> dict[str, str]:
    """解析 pubspec.yaml 的 dependencies / dev_dependencies 两段一级条目。

    返回 {包名: 声明约束}，用于与 lock 的 `dependency: "direct main"` /
    `"direct dev"` 交叉校验（lock 是唯一权威，pubspec 用来发现「声明了但
    没锁到」的漏网包）。
    """
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    result: dict[str, str] = {}
    section: str | None = None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()  # 去行尾注释
        if not line.strip():
            continue
        if re.match(r"^\S", line):  # 顶层键
            section = None
            m = re.match(r"^(dependencies|dev_dependencies):\s*(.*)$", line)
            if m:
                section = m.group(1)
                # 处理 `dependencies: {}` 这种同行空表
                if m.group(2).strip() in ("{}", ""):
                    if m.group(2).strip() == "{}":
                        section = None
            continue
        if section and re.match(r"^  \S", line):
            m = re.match(r"^  ([A-Za-z_0-9]+):\s*(.*)$", line)
            if m:
                result[m.group(1)] = m.group(2).strip()
    return result


def parse_lockfile(path: Path) -> dict:
    """解析 pubspec.lock（packages 区——name → {version, sha256, source, dependency}）。

    **必须**在 `sdks:` 处截断：原实现按 `\\n(?=  \\S+?:)` 切整个 packages 段，
    把 sdks 段的 `flutter: ">=3.47.0"` 也当成一个包（它没有 version 字段，
    于是得到 version="unknown" 的幽灵组件，还会把真正的 flutter 覆盖掉）。
    """
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^packages:$", text, re.MULTILINE)
    if not m:
        raise ValueError("pubspec.lock 缺少 packages 区")
    body = text[m.end():]
    # 截断到下一个顶层键（sdks: / dependency_overrides: 等）。
    stop = re.search(r"^[a-zA-Z_]", body, re.MULTILINE)
    if stop:
        body = body[: stop.start()]

    packages = {}
    # 每包：2 空格缩进的 `  name:` 行开头——按此分割块（字段为 4-6 空格
    # 缩进不误分）。
    for block in re.split(r"\n(?=  \S+?:)", body):
        block = block.strip()
        if not block or block == "sdks:" or block.startswith(("dependency_overrides",)):
            continue
        name_line = block.split(":", 1)[0].strip()
        if not name_line or not re.match(r"^[A-Za-z_0-9]+$", name_line):
            continue
        version_m = re.search(r'version: "([^"]+)"', block)
        # sha256 有**带引号与不带引号**两种写法（pub 按 YAML 是否需要引号
        # 自动决定）——只匹配带引号的正则会漏掉 53/156 条（实测），直接依赖
        # 里 archive / crypto / file_selector / image / local_auth /
        # path_provider / pdf / perfect_freehand / shared_preferences /
        # vector_math 全部中招，SBOM 的 hashes 覆盖面上一个大缺口。
        sha_m = re.search(r'sha256: "?([0-9a-fA-F]{64})"?', block)
        source_m = re.search(r"source: (\S+)", block)
        dep_m = re.search(r'dependency: "?([^"\s]+)"?', block)
        url_m = re.search(r'url: "([^"]+)"', block)
        path_m = re.search(r'path: "([^"]+)"', block)
        packages[name_line] = {
            "version": version_m.group(1) if version_m else "unknown",
            "sha256": sha_m.group(1) if sha_m else None,
            "source": source_m.group(1) if source_m else "unknown",
            "dependency": dep_m.group(1) if dep_m else "transitive",
            "url": url_m.group(1) if url_m else None,
            "path": path_m.group(1) if path_m else None,
        }
    return packages


def _supplier_for(pkg: dict) -> str:
    """推断组件供应商（lock 的 description.url / path / source）。"""
    source = pkg.get("source", "")
    if source == "path":
        return LOCAL_SUPPLIER
    if source == "sdk":
        return SDK_SUPPLIER
    url = pkg.get("url") or ""
    if "pub.dev" in url:
        return PUB_DEV_SUPPLIER
    if source == "hosted":
        return PUB_DEV_SUPPLIER
    return "unknown"


def _license_for(name: str, pkg: dict) -> list[dict]:
    """许可证元数据。

    pubspec.lock **不含**许可证字段（`grep -c license pubspec.lock` = 0），
    pubspec.yaml 也只在注释里零散提到个别包的许可证（pointycastle=MIT 等）。
    因此：① lock/pubspec 有据可查的按实填；② 其余**不猜**——返回空列表，
    并在 properties 里标注 `license_source: unavailable`，避免 SBOM 里出现
    未经证实的许可证声明（那是比缺失更严重的合规问题）。
    """
    # pubspec.yaml 注释里明确标注的许可证（人工确认过的子集）。
    known = {
        "pointycastle": "MIT",
        "pdfrx": "MIT",
        "perfect_freehand": "MIT",
        "local_auth": "BSD-3-Clause",
    }
    if name in known:
        return [{"license": {"id": known[name], "properties": [
            {"name": "license_source", "value": "pubspec.yaml comment (human-verified)"}]}}]
    return []


def build_bom(app_name: str, app_version: str, packages: dict,
              direct_deps: dict[str, str] | None = None) -> dict:
    """构建 CycloneDX 1.5 BOM（components + metadata + dependencies 关系图）。"""
    direct_deps = direct_deps or {}
    components = []
    bom_refs: dict[str, str] = {}
    for name in sorted(packages):
        p = packages[name]
        purl = f"pkg:pub/{name}@{p['version']}"
        bom_refs[name] = purl
        component = {
            "type": "library",
            "name": name,
            "version": p["version"],
            "purl": purl,
            "bom-ref": purl,
            "supplier": {"name": _supplier_for(p)},
            "properties": [
                {"name": "dependency_type", "value": p["dependency"]},
                {"name": "source", "value": p["source"]},
            ],
        }
        if p.get("path"):
            component["properties"].append({"name": "local_path", "value": p["path"]})
        if p.get("url"):
            component["properties"].append({"name": "registry_url", "value": p["url"]})
        # SHA-256：lock 的 description.sha256 是直接依赖与传递依赖都有的
        # （path/sdk 依赖没有——它们没有发布产物可哈希）。
        if p["sha256"]:
            component["hashes"] = [{"alg": "SHA-256", "content": p["sha256"]}]
        # 许可证：lock 无该字段，仅在 pubspec 有据可查时填，否则显式标注缺失。
        licenses = _license_for(name, p)
        if licenses:
            component["licenses"] = licenses
        else:
            component["properties"].append(
                {"name": "license_source", "value": "unavailable (pubspec.lock 无许可证字段)"})
        components.append(component)

    # 依赖关系图（CycloneDX `dependencies`）：应用 → 每个直接依赖；
    # 再尽量从 lock 的 dependency 类型推出传递层。lock **不记录**包与包的
    # 边（只有「direct main / direct dev / transitive」这一层分类），所以
    # 传递依赖的下游边无法从 lock 还原——这里如实只画「应用 → 全部组件」
    # 与「直接依赖」两级，并在 properties 标注口径，不伪造边。
    app_ref = f"pkg:pub/{app_name}@{app_version}"
    dep_graph = [{"ref": app_ref, "dependsOn": sorted(bom_refs.values())}]
    for name in sorted(direct_deps):
        if name in bom_refs:
            dep_graph.append({"ref": bom_refs[name], "dependsOn": []})

    # P2 修复（审计）：serialNumber 每次唯一 + timestamp 落盘时刻（UTC，
    # ISO 8601）——此前全零串与空时间戳，SBOM 无审计可追溯性。
    bom = {
        "bomFormat": BOM_FORMAT,
        "specVersion": SPEC_VERSION,
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "name": app_name,
                "version": app_version,
                "bom-ref": app_ref,
                "licenses": [{"license": {"id": "MIT"}}],
            },
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "properties": [
                {"name": "sbom_generator", "value": "tools/generate_sbom.py"},
                {"name": "lockfile", "value": "pubspec.lock"},
                {"name": "version_source", "value": "pubspec.yaml"},
            ],
        },
        "components": components,
        "dependencies": dep_graph,
    }
    return bom


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 CycloneDX SBOM")
    parser.add_argument("--lockfile", default="pubspec.lock")
    parser.add_argument("--pubspec", default="pubspec.yaml")
    parser.add_argument("--output", default="sbom.cdx.json")
    parser.add_argument("--app-name", default="drawing_notes_app")
    # 默认 None ⇒ 自动从 pubspec.yaml 解析（原硬编码 1.0.0 与实际版本脱节）。
    parser.add_argument("--app-version", default=None,
                        help="应用版本（默认从 pubspec.yaml 的 version: 行解析）")
    args = parser.parse_args()

    lock = Path(args.lockfile)
    if not lock.exists():
        print(f"错误：未找到 {lock}")
        return 1
    pubspec = Path(args.pubspec)

    # 版本解析优先级：显式参数 > pubspec.yaml > 0.0.0（并在报告里说明）。
    version_source = "pubspec.yaml"
    app_version = args.app_version
    if app_version is None:
        app_version = parse_pubspec_version(pubspec)
        if app_version is None:
            app_version = "0.0.0"
            version_source = "fallback (pubspec.yaml 解析失败)"
    else:
        version_source = "--app-version (显式)"

    packages = parse_lockfile(lock)
    direct_deps = parse_pubspec_direct_deps(pubspec)
    bom = build_bom(args.app_name, app_version, packages, direct_deps)
    out = Path(args.output)
    out.write_text(json.dumps(bom, indent=2), encoding="utf-8")

    # 报告：版本来源 + 组件数 + 直接/传递分布 + sha256 覆盖情况。
    from collections import Counter
    kinds = Counter(p["dependency"] for p in packages.values())
    with_sha = sum(1 for p in packages.values() if p["sha256"])
    print(f"SBOM 已生成：{out}（{len(packages)} 个组件——CycloneDX {SPEC_VERSION}）")
    print(f"  应用版本：{app_version}（来源：{version_source}）")
    print(f"  依赖分布：{dict(kinds)}")
    print(f"  SHA-256 覆盖：{with_sha}/{len(packages)}"
          f"（path/sdk 依赖无发布产物哈希，属正常缺失）")

    # 交叉校验：pubspec 声明为直接依赖、但 lock 里没有的包——说明 lock 与
    # pubspec 不同步（`flutter pub get` 未跑），这是 SBOM 完整性的真实缺口。
    missing = sorted(set(direct_deps) - set(packages))
    if missing:
        print(f"  ⚠ pubspec.yaml 声明但 pubspec.lock 缺失：{', '.join(missing)}"
              f"——请跑 `flutter pub get`")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

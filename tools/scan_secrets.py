#!/usr/bin/env python3
"""秘密扫描（发布材料门禁——专家审计最优先④，2026-08-16）。

Gitleaks 模式（regex + keywords 快速过滤 + 熵检测）的轻量实现：扫描工作区
文本文件中的敏感模式（私钥/API 令牌/凭据/高熵字符串），CI 阻断性检查——
发现即退出码 1。生产密钥/口令禁止入仓（专家要求）。

2026-10 审计扩展：规则 7 → 14（新增 JWT / GitLab PAT / GCP API key /
GCP service account / Azure 连接串 / NPM token / PyPI token），并新增
凭据类**文件名**检测（.env* / credentials* / secrets* / id_rsa / *.pem …）
——文件名命中即报告，作为内容扫描的补充面。

用法：python tools/scan_secrets.py [--path .] [--exclude sbom.cdx.json]
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys
from pathlib import Path

# 敏感模式（Gitleaks 式：regex + 关键字描述——命中即报告）。
#
# 2026-10 审计扩展：原有 7 条保留（编号 1-7，见下），新增 JWT / GitLab /
# GCP / Azure / NPM / PyPI 等供应商令牌规则（编号 8-14）。新增规则均先做
# 双向验证：① 正对照——用真实格式的令牌样本确认能命中；② 负对照——在
# 本仓 1000+ 文件上跑，确认 0 误报（尤其避免把 base64 图片/长标识符/哈希
# 常量误判成密钥）。
RULES = [
    # ── 原有 7 条（未改动）────────────────────────────────────────────────
    (re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"), "私钥（PEM）"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS Access Key"),
    (re.compile(r"github_pat_[0-9A-Za-z_]{22,}"), "GitHub PAT"),
    (re.compile(r"ghp_[0-9A-Za-z]{36,}"), "GitHub Token"),
    (re.compile(r"sk_live_[0-9a-zA-Z]{24,}"), "Stripe Live Key"),
    (re.compile(r"(?i)(api[_-]?key|secret|token|password)\s*[=:]\s*['\"][0-9a-zA-Z_\-]{16,}['\"]"),
     "凭据赋值（API key/secret/token/password）"),
    (re.compile(r"(?i)BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY"), "私钥块"),
    # ── 新增：JWT ───────────────────────────────────────────────────────
    # 三段式 base64url，首段解码后必是 {" 开头（eyJ）——这是 JWT 的固有
    # 形态而非任意 base64，故不会误报普通 base64 串。
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),
     "JWT（JSON Web Token）"),
    # ── 新增：GitLab ──────────────────────────────────────────────────────
    # glpat- 前缀是 GitLab PAT 的固定形态（20+ 随机字符）。
    (re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b"), "GitLab Personal Access Token"),
    # ── 新增：GCP ────────────────────────────────────────────────────────
    # AIza 前缀 + 35 字符（Google API key 固定 39 字符总长）。
    (re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"), "GCP API Key"),
    # GCP 服务账号 JSON 的固定 type 字段（值为 service_account 字面量）。
    # 注释里刻意不复写键值对原文——否则扫描器会命中自己的规则说明。
    (re.compile(r'"type"\s*:\s*"service_account"'), "GCP Service Account JSON"),
    # ── 新增：Azure ──────────────────────────────────────────────────────
    # Azure Storage 连接串的固定结构（AccountKey= 后接 base64 密钥）。
    (re.compile(r"(?i)DefaultEndpointsProtocol=https?;AccountName=[^;]+;AccountKey="),
     "Azure Storage Connection String"),
    # ── 新增：NPM ────────────────────────────────────────────────────────
    # npm_ 前缀 + 36 字符（NPM  classic token 的固定形态）。
    (re.compile(r"\bnpm_[0-9A-Za-z]{36}\b"), "NPM Access Token"),
    # ── 新增：PyPI ───────────────────────────────────────────────────────
    # pypi-AgEIcHlwaS5vcmc 是 PyPI token 的固定前缀（上传用 token）。
    (re.compile(r"\bpypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{20,}\b"), "PyPI Upload Token"),
]

# 扫描排除（构建/缓存/生成的产物）。
EXCLUDED_DIRS = {".git", ".dart_tool", "build", ".idea", ".vs", "node_modules", ".desloppify"}

# 门禁自证用的扫描面下限（审计 TE-TST-05，2026-10-16）：一次干净 clone 是
# `git ls-files` = 1019 个文件，取一半再一档之下——**只用来抓「一个文件都没扫到」**，
# 不用来抓日常增删。曾经想过 1500，那高于真实扫描面，第一次推送就会把 CI 打红。
MIN_SCANNED_FILES = 600
EXCLUDED_FILES = {"sbom.cdx.json", "pubspec.lock", "untranslated_messages.json", "generated_plugin_registrant.cc"}
# 误报豁免（2026-08-16）：base62 字符集 const（fractional_index——默认
# 参数要求 const——合法字符集常量非密钥——高熵检测误报）。
EXCLUDED_PATHS = {"lib/core/canvas_model/fractional_index.dart"}
# 凭据类文件名检测（2026-10 审计新增）：文件名本身形如 `.env` / `credentials`
# / `secrets` 说明这是凭据文件——这类文件本不该入仓，命中即报告（文件名检测
# 是内容扫描的补充面，不是替代：内容规则仍会照常扫这些文件的实际内容）。
#
# ⚠️ 口径经本仓实测校准（28 个误报 → 0）：第一版把 `*_password_manager.dart`
# / `*_secret_store.dart` 这类**源码标识符**也算进去，在本仓命中 28 个合法文件
# （session_secrets.dart / storage_file_password_manager.dart 等）——那是把
# 「文件名里含敏感词」误当成「这是凭据文件」。故这里只匹配**凭据文件本身的
# 命名惯例**，且要求敏感词独占文件名（前面是分隔符或位于开头），不匹配
# `xxx_password_yyy` 这种夹在中间的源码命名：
#   ✅ .env / .env.local / credentials.json / credentials.yaml / secrets.yaml
#       id_rsa / id_ed25519 / service_account.json / xxx.pem / xxx.p12 / xxx.pfx
#   ❌ storage_file_password_manager.dart / session_secrets.dart / password_reset.dart
CREDENTIAL_FILENAME_PATTERNS = [
    # .env / .env.local / .env.production.local（dotenv 凭据文件的固定名）。
    re.compile(r"^\.env(\.|$)", re.IGNORECASE),
    # 凭据文件：敏感词独占文件名前缀 + **受控的**环境限定词（prod/dev/local…）
    # + 配置类扩展名。限定词必须来自白名单——写成 `([._-].*)?` 这种任意后缀
    # 会让 `secret-scan.yml`（本仓真实存在的 workflow 文件名）被命中，实测
    # 就是一个误报；同时它还会把 `secret_store_test.dart` 之类夹在中间的
    # 源码标识符一并吃掉。白名单口径：
    #   ✅ credentials.json / credentials-prod.yaml / secrets.local.json / password.txt
    #   ❌ secret-scan.yml / session_secrets.dart / password_reset.dart
    re.compile(r"(?i)^(credentials?|secrets?|password|passwd|account[_-]?key)"
               r"([._-](prod|production|staging|stage|dev|development|local|test|qa|uat|"
               r"example|sample|template|private|public|key|keys|store|backup))?"
               r"\.(json|ya?ml|toml|ini|txt|env|cfg|conf)$"),
    # 私钥文件名惯例：id_rsa / id_ed25519 / id_ecdsa（OpenSSH 默认名）。
    re.compile(r"(?i)^id_(rsa|ed25519|ecdsa|dsa)$"),
    # GCP 服务账号 JSON：`service_account.json`（无分隔）与
    # `service-account.prod.json`（有分隔）两种命名都要覆盖。
    re.compile(r"(?i)^(service_account|service-account|serviceaccount)(\..*)?\.json$"),
    # 密钥材料扩展名（.pem / .p12 / .pfx / .jks / .keystore）——任何目录下的
    # 这类文件都属凭据文件，本不该入仓。
    re.compile(r"(?i)\.(pem|p12|pfx|jks|keystore|ppk)$"),
]
# 熵检测豁免（2026-09-05，审计 U4 批次发现）：l10n ARB 的 @key 元数据
# 是生成的标识符命名空间（如 lockVerifyCurrentPassword，熵 4.08）——
# 键名与密钥无关。仅豁免熵启发式：凭据 regex 规则仍照常扫描 ARB
# （翻译文案里若真出现 api_key=xxx 依旧拦截）。
ENTROPY_EXCLUDED_PATHS = {"lib/l10n/app_zh.arb", "lib/l10n/app_en.arb"}
# 已知安全前缀（2026-09-02）：iVBORw0KGgo = PNG 文件头（\x89PNG\r\n\x1a\n）的
# base64 固定魔数——测试夹具的最小 1×1 PNG，内容人人皆知、非密钥，
# 高熵检测误报（熵 4.01，阈值 4.0 擦边）。
KNOWN_SAFE_PREFIXES = ("iVBORw0KGgo",)
# 二进制/无关扩展名跳过。
SKIP_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ttf", ".ico", ".exe", ".dll", ".pdb", ".class", ".jar", ".zip", ".lock", ".xib"}

# ── 豁免清单条数上限（M4 漂移告警）──────────────────────────────────────
# 三条豁免清单（EXCLUDED_PATHS / ENTROPY_EXCLUDED_PATHS / EXCLUDED_FILES）
# 靠人工回测校准，条数持续增长意味着扫描面在收缩——超过 10 条即 warning。
# 不阻断（exit 0），但在 Step Summary 与 stdout 双重可见。
MAX_EXEMPTION_ENTRIES = 10


def shannon_entropy(s: str) -> float:
    """Shannon 熵（Gitleaks 熵检测——高熵字符串疑似随机令牌，阈值 4.0）。"""
    if not s:
        return 0.0
    freq = {}
    for ch in s:
        freq[ch] = freq.get(ch, 0) + 1
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in freq.values())


def scan_file(path: Path, findings: list, skip_entropy: bool = False) -> bool:
    """扫描单个文件；返回是否**真的读到了内容**。

    读不出来（权限、句柄被占、符号链接断、解码炸）以前是 `except OSError: return`——
    一声不响地把这个文件当成「干净」。这正是本仓「读不出来被答成没有」那一族
    （审计 STO-001 / STO-012 / SYN-D1 同形），而秘密扫描器最坏的失效方式就是
    「扫不到 ⇒ ✅ 通过」。现在把这一格上抛给调用方计数并在末尾打印。
    """
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    for line_no, line in enumerate(text.splitlines(), 1):
        for pattern, desc in RULES:
            m = pattern.search(line)
            if m:
                findings.append((str(path), line_no, desc, line.strip()[:80]))
        # 熵检测（Gitleaks 模式——高熵字符串疑似随机令牌，阈值 4.0）：
        # 仅检测引号内的长字符串（真实密钥/令牌通常出现在字符串字面量中——
        # 避免裸标识符/类名误报）。l10n ARB 走 ENTROPY_EXCLUDED_PATHS 豁免。
        if not skip_entropy:
            for token in re.findall(r"['\"]([0-9a-zA-Z_\-]{24,})['\"]", line):
                if token.startswith(KNOWN_SAFE_PREFIXES):
                    continue
                if shannon_entropy(token) > 4.0:
                    findings.append((str(path), line_no, f"高熵字符串（熵 {shannon_entropy(token):.2f}）", token[:32]))
                    break  # 每行一条熵告警即可
    return True  # 走到这里就是真的读到了内容（审计 R13：漏掉这一句时 1000 个文件
                 # 全被记成「读不出来」——见 commit message 里那条自查）


def main() -> int:
    parser = argparse.ArgumentParser(description="秘密扫描（Gitleaks 模式）")
    parser.add_argument("--path", default=".")
    parser.add_argument("--exclude", action="append", default=[], help="额外排除路径")
    args = parser.parse_args()

    root = Path(args.path)
    findings: list = []
    scanned = 0
    unreadable = 0
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
        # 凭据类文件名检测（内容扫描的补充面——文件名本身即凭据文件的信号）。
        if any(rx.search(path.name) for rx in CREDENTIAL_FILENAME_PATTERNS):
            findings.append((str(path), 0, "凭据类文件名（.env*/credential*/secret*/密钥文件）", "<文件名命中>"))
        scanned += 1
        if not scan_file(
            path, findings, skip_entropy=rel.as_posix() in ENTROPY_EXCLUDED_PATHS
        ):
            unreadable += 1

    # ── 门禁自证（审计 TE-TST-05 / R13，2026-10-16）──────────────────────
    # 本脚本原来的末尾只有一句「没有 findings 就 return 0」，而让 findings 为空
    # 有两种同形成因：① 真的干净；② **一个文件都没扫到**（cwd 不对、--path 指空、
    # 目录被挪走）。秘密扫描器走到 ② 时打印的是「✅ 未发现敏感信息」，
    # 属于本仓「空集即通过」那一族里唯一的**安全类**成员，所以必须下限先于结论。
    # 阈值取一次干净 clone 的扫描面（git ls-files = 1019 个文件）之下很宽的一档：
    # 只用于抓塌空，不参与日常增删。
    if scanned < MIN_SCANNED_FILES:
        print(
            f"❌ 门禁失明：只扫到 {scanned} 个文件（下限 {MIN_SCANNED_FILES}，"
            f"实测一次 clone 为 1019）——此时「没有 findings」是没在看，不是合规。"
        )
        return 2
    # 扫描面每次都说出来：让「扫了多少」与「有没有违规」两件事分开可见，
    # 这样某天 surface 从 1019 掉到 700 也能在日志里一眼看出来（而不是只看到通过）。
    print(f"扫描面：{scanned} 个文件（下限 {MIN_SCANNED_FILES}）")
    if unreadable:
        # 读不出来的文件以前被静默当成干净；现在至少让它们出现在输出里。
        print(f"⚠ 有 {unreadable} 个文件读不出来（已跳过，不计入「干净」）")

    # ── 豁免清单条数自检（M4 漂移告警）──────────────────────────────────
    # 三条豁免清单靠人工回测校准，条数持续增长意味着扫描面在收缩。
    # 超过 MAX_EXEMPTION_ENTRIES 即 warning（不阻断，但双重可见）。
    exemption_lists = {
        "EXCLUDED_PATHS": EXCLUDED_PATHS,
        "ENTROPY_EXCLUDED_PATHS": ENTROPY_EXCLUDED_PATHS,
        "EXCLUDED_FILES": EXCLUDED_FILES,
    }
    exemption_warnings = []
    for name, entries in exemption_lists.items():
        if len(entries) > MAX_EXEMPTION_ENTRIES:
            exemption_warnings.append(
                f"{name} 有 {len(entries)} 条（上限 {MAX_EXEMPTION_ENTRIES}）"
            )
    if exemption_warnings:
        print(f"⚠ 豁免清单超限：{'; '.join(exemption_warnings)}")

    # ── Step Summary（M4：scanned 与豁免状态落 GITHUB_STEP_SUMMARY）──────
    summary_lines = [
        "## 秘密扫描结果",
        "",
        f"- 扫描面：**{scanned}** 个文件（下限 {MIN_SCANNED_FILES}）",
        f"- 读不出来：{unreadable} 个",
        f"- 发现敏感信息：{len(findings)} 处",
        f"- 豁免清单上限：{MAX_EXEMPTION_ENTRIES} 条/清单",
    ]
    for name, entries in exemption_lists.items():
        marker = "⚠" if len(entries) > MAX_EXEMPTION_ENTRIES else "✅"
        summary_lines.append(f"- {marker} {name}：{len(entries)} 条")
    if exemption_warnings:
        summary_lines.append("")
        summary_lines.append("⚠ 豁免清单超限——扫描面在收缩，需人工复核。")
    summary_text = "\n".join(summary_lines)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write(summary_text + "\n")

    if findings:
        print(f"⚠ 发现 {len(findings)} 处潜在敏感信息：")
        for f, ln, desc, snippet in findings[:20]:
            print(f"  {f}:{ln} [{desc}] {snippet}")
        return 1
    print(
        f"✅ 未发现敏感信息（秘密扫描通过——Gitleaks 模式，"
        f"实扫 {scanned} 个文件、跳过读不出 {unreadable} 个）"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

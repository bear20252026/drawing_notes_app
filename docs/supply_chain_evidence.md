# 供应链与平台证据（Supply Chain & Platform Evidence）

> 状态：评估清单（专家审计 M-12，2026-08-15）
> 目标：可追溯依赖、可复现构建、制品来源证明（NIST SSDF/专家验收标准）

## 一、已有证据（✅ 已具备）

| 证据项 | 位置 | 说明 |
|---|---|---|
| 依赖锁文件 | `pubspec.yaml`（27 依赖）+ `pubspec.lock`（33KB） | 版本固化，可复现 `flutter pub get` |
| CI 门禁 | `.github/workflows/ci.yml` + `code-guard.yml` | 静态分析 + 架构规则 + 行数红线随 CI 运行 |
| SBOM-CVE 核查 | `tools/check_deps.sh` | 145 依赖 CVE 核查（SBOM 视角） |
| 架构守护 | `test/architecture_test.dart`（5 规则） | 层方向/零循环/隔离/六边形/度量 |
| 质量门禁 | `tools/code_guard.py`（行数红线）+ `check_boundaries.sh` | 发布前全绿 |

## 二、缺口（⏳ 需发布工程化补齐）

| 缺口 | 验收标准（专家 M-12） | 计划 |
|---|---|---|
| 结构化 SBOM（CycloneDX/SPDX） | 生成 CycloneDX/SPDX 清单 | CI 集成 `cyclonedx` 生成 + 存档 |
| SCA 依赖审计 | CI 阻断高危依赖 | 集成 osv-scanner/OWASP Dependency-Check |
| SAST 静态分析 | 每次提交扫描 | 集成 Semgrep/Dart analyzer --fatal-infos |
| secret scan | 无密钥入库 | 集成 gitleaks/trufflehog |
| 制品签名 | 每个制品可追溯 | 签名发布（代码签名证书） |
| 可复现构建 | commit → 锁文件 → 制品一致 | CI 构建缓存 + 版本记录 |

## 三、平台工程（⏳ 需平台配置）

- Android：禁止明文备份（allowBackup=false）、调试包限制、必要时 FLAG_SECURE
- iOS：NSFileProtectionComplete、备份排除
- 桌面：OS 凭据库/文件 ACL（Windows ACL 已由文件权限策略覆盖）

> 说明：平台配置与签名需发布流水线配合（非纯代码可完成），本清单作为证据
> 交接文档；代码侧已完成可复现构建基础（锁文件 + CI 门禁 + 架构守护）。

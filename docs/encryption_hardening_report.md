# 加密加强调研报告（2026-08-22——全球中英双平台调研）

> 调研目标：分析当前分层加密架构（内容层 AES-256-GCM + 元数据层 AES-SIV）
> 还能如何加强——联网搜索 2026 年最新信息（覆盖中文 + 英文平台）。

---

## 一、当前加密架构（基线）

```
分层加密架构（Cryptomator 借鉴——已实现/待实现）：
┌─────────────────────────────────────────────┐
│  元数据层：AES-SIV（目录/文件名——确定性加密）  │ ← 待实现
│  ┌───────────────────────────────────────┐  │
│  │ 内容层：AES-256-GCM + PBKDF2 60万次    │  │ ← ✅ 已实现
│  │        + AAD 绑定 + V2 magic 头        │  │
│  │  + 混合密钥（X25519 + ML-KEM → HKDF）   │  │ ← ⏳ 可选
│  └───────────────────────────────────────┘  │
│  会话层：NotebookSession + KeyHandle        │  ← ✅ 已实现
│        + LockPolicy（自动锁定）             │
└─────────────────────────────────────────────┘
```

---

## 二、2026 年最新加密加强方法调研（中英双平台）

### 英文平台

| 来源 | 加强方法 | 价值 |
|------|---------|------|
| **EPC 2026 指南**（欧洲支付理事会） | ① AES 为推荐标准 ② 主密钥分割（Secret Sharing——阈值恢复）③ 密钥用途隔离 | 防单点丢失/密钥滥用 |
| **SAFE 2026 草案**（IETF） | ① **AES-256-GCM-SIV**（NMR——抗 nonce 误用——nonce 复用降级为确定性而非泄露明文）② HPKE Auth Mode（认证封装——防伪冒）③ ChaCha20-Poly1305 ④ AEGIS-256 | 抗 nonce 误用/认证增强 |
| **后量子迁移指南**（2026-04） | ① ML-KEM（FIPS 203）/ML-DSA（FIPS 204）/SLH-DSA（FIPS 205）② 混合密钥封装（X25519 + ML-KEM-768——双方任一安全则会话安全）③ 密钥轮换（限制 KEK 寿命）④ 信封加密（每对象 DEK + KEK 包裹） | 量子 Day Zero 防护 |
| **AgePony**（移动端 age 实现） | ① ML-KEM-768 + X25519 混合接收者 ② 硬件密钥（Secure Enclave/FIDO NFC）③ 签名隐藏于密文 ④ 内存有界（64 KiB 缓冲） | 硬件密钥/内存安全 |

### 中文平台

| 来源 | 加强方法 | 价值 |
|------|---------|------|
| **《信息网络安全》2026-02** | ① 基于 TEE（Intel SGX）的层次角色基分级加密 ② 加密/密钥管理置于 TEE 硬件隔离 ③ 按数据敏感性分级密钥 | 运行时防护（防内存窃取） |
| **鲲鹏 TrustZone 套件**（华为） | ① TEE 硬件隔离（ARM TrustZone）② TA 镜像加密 + 安全存储支持**国密 SM4 硬件加速** ③ 远程证明（Attestation Service） | 国密合规/远程证明 |

---

## 三、可实施加强方向（8 项——按优先级）

### P0（核心加强——积木式纯 Dart——推荐先实施）

| # | 加强项 | 来源 | 方案 |
|---|--------|------|------|
| 1 | **密钥分割（Secret Sharing）** | EPC 2026 Rec 9 | Shamir 阈值方案（主密钥分成 N 份——M 份可恢复——防单点丢失）——纯 Dart 可测 |
| 2 | **信封加密（Envelope Encryption）** | 后量子迁移指南 | 每对象数据密钥（DEK）+ 主密钥包裹（KEK）——防批量泄露（一个 DEK 泄露只影响一个对象）——纯 Dart 可测 |
| 3 | **AES-256-GCM-SIV**（NMR） | SAFE 2026 | 抗 nonce 误用——nonce 复用不泄露明文（降级为确定性）——比 GCM 更稳 |

### P1（增强——推荐后续）

| # | 加强项 | 来源 | 方案 |
|---|--------|------|------|
| 4 | **密钥轮换（Key Rotation）** | 后量子迁移 | 定期轮换 KEK——限制密钥寿命——审计轮换历史 |
| 5 | **篡改检测 + 审计日志** | 安全最佳实践 | 操作日志哈希链（每个条目哈希前一条——篡改即断链） |
| 6 | **后量子混合（ML-KEM-768 + X25519）** | SAFE/AgePony | 混合密钥封装——经典 + 量子双保险（可用 pqforge 纯 Dart 包） |

### P2（可选——硬件/环境依赖）

| # | 加强项 | 来源 | 方案 |
|---|--------|------|------|
| 7 | **硬件安全（TEE/Secure Enclave）** | 中文 TEE 调研 | 移动端 Secure Enclave 存储主密钥——硬件隔离防内存窃取 |
| 8 | **蜜罐密钥（Honeypot Key）** | 安全最佳实践 | 诱饵密钥——检测入侵尝试（用诱饵密钥解密失败 = 有入侵者） |

---

## 四、实施建议（积木式——不搞崩）

```
P0（本轮可实施）：
  SecretSharing（Shamir 阈值——N 份 M 恢复——纯 Dart）
  EnvelopeEncryption（DEK/KEK 模型——纯 Dart）
  GCM-SIV 选择器（NMR 抗误用——算法选择模型）

P1（后续）：
  KeyRotation（轮换策略）
  AuditLog（哈希链审计）
  PQ-Hybrid（pqforge 包——后量子混合）

P2（硬件）：
  Secure Enclave 集成（移动端）
  HoneypotKey（入侵检测）
```

**原则**：每个加强项 = 独立积木块（纯 Dart 不可变——可独立测试——不搞崩——测试后合入——保留版权）。

---

## 五、参考来源

- EPC 2026 Guidelines on Cryptographic Algorithms and Key Management（欧洲支付理事会）
- SAFE 2026 Internet-Draft（IETF——AES-256-GCM-SIV/HPKE/ML-KEM）
- Post-Quantum Crypto Migration Plan（2026-04——systemshardening.com）
- AgePony（移动端 age——ML-KEM-768 + X25519 混合——硬件密钥）
- 《基于可信执行环境的层次角色基分级加密方案》信息网络安全 2026-26(2)
- 鲲鹏 BoostKit 机密计算 TrustZone 套件（国密 SM4 硬件加速）
- Cryptomator Vault 架构（AES-256-GCM + AES-SIV + Vault format 8）
- pqforge（pub.dev 2026-06-08——纯 Dart 后量子 + 经典混合）

---

Generated: 2026-08-22
Project: drawing_notes_app (绘图笔记)

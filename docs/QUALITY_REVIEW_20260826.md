# 全项目质量审查报告 — 2026-08-26

## 审查维度总览

| 维度 | 状态 | 说明 |
|------|------|------|
| Clean Architecture 合规性 | ⚠️ 部分通过 | Domain 层基本合规，core/ 有违规 |
| 模块边界 | ❌ 不通过 | core/ 大量引用 features/ |
| 密码功能完整性 | ✅ 通过 | 三大密码功能完整闭环 |
| 代码质量 | ⚠️ 部分通过 | analyze 有问题，test 部分失败 |
| 安全性 | ✅ 通过 | Argon2id 参数合规，加密链完整 |

---

## 1. Clean Architecture 合规性

### Domain 层检查

| 模块 | Flutter import | 状态 |
|------|---------------|------|
| features/auth/domain | 无 | ✅ |
| features/drawing/domain | dart:ui (Offset, Size) | ⚠️ |
| features/settings/domain | 无 | ✅ |
| features/shapes/domain | 无 | ✅ |
| features/editor_v2/domain | 无 | ✅ |
| features/security/domain | 无 | ✅ |
| features/notes/domain | 无 | ✅ |

**结论**：drawing 模块的 Domain 层使用了 `dart:ui` 的 `Offset` 和 `Size`。严格来说这是 Flutter 依赖，但 `dart:ui` 是引擎级类型，通常作为值类型使用。建议：长期可替换为自定义值对象。

### Application 层检查
- ✅ 所有 Application 层只依赖 Domain 层
- ✅ 通过接口（abstract class）访问 Infrastructure

### Infrastructure 层检查
- ✅ 实现 Domain 接口
- ⚠️ `core/` 层直接引用 `features/` 实现（见模块边界）

### Presentation 层检查
- ✅ 通过 Riverpod 注入服务
- ✅ 不直接 new 具体实现

---

## 2. 模块边界 ❌

### 严重违规：core/ 引用 features/

`core/` 层大量直接导入 `features/` 模块，违反 Clean Architecture 的依赖方向原则：

| 文件 | 违规引用 |
|------|---------|
| core/bridges/note_document_bridge.dart | features/drawing/domain, features/notes/domain |
| core/di/providers.dart | features/auth/, features/drawing/, features/security/ |
| core/export/note_pdf_exporter.dart | features/drawing/domain, features/notes/domain |
| core/rendering/stroke_renderer.dart | features/drawing/domain |
| core/router/app_router.dart | features/notes/, features/drawing/, features/security/ 等 |

**修复建议**：
1. 将 `core/` 中的 features 依赖抽取到 `core/abstractions/` 接口
2. 或将 `core/` 重命名为 `shared_kernel/` 并明确其作为共享内核的角色
3. 路由配置（app_router.dart）引用 features 是合理的，但应通过接口注入

---

## 3. 密码功能完整性 ✅

### 3.1 首页密码（应用锁定）
- ✅ 设置密码：6 位 PIN，Argon2id 哈希
- ✅ 锁定：启动时检查，显示锁屏页面
- ✅ 解锁：PIN 验证，生物识别预留
- ✅ 阶梯锁定：失败 3/4/5 次 → 30s/5min/30min

### 3.2 分文件密码
- ✅ 笔记本独立加密选项
- ✅ 支持「记忆密码」和「U盘钥匙」两种模式
- ✅ 加密/解密流程完整

### 3.3 密码盘 U盘
- ✅ 写入：生成 key.frogkey（FROG + version + 32-byte key）
- ✅ 识别：UsbDiskDetector 扫描 USB 驱动器
- ✅ 解锁：读取密钥，PIN 保护支持
- ✅ 恢复信封：恢复密钥找回主密钥

### 3.4 PM码
- ✅ 双密钥槽设计
- ✅ 销毁密钥机制
- ✅ 独立存储

---

## 4. 代码质量 ⚠️

### flutter analyze 结果
- **总问题数**：5017（含 info/warning）
- **Error 级别**：集中在 test/vault_test.dart 和 test/usability_regression_test.dart
  - 原因：引用不存在的 VaultService/EncryptedVault 类（其他任务遗留）
- **Warning 级别**：大量未使用导入、deprecated API 使用

### 代码异味
| 问题 | 数量 | 严重性 |
|------|------|--------|
| debugPrint 残留 | ~50+ | 低（仅 debug 模式） |
| 空 catch 块 | 1 | 中 |
| 硬编码密钥 | 0 | ✅ |

### 测试结果
- ✅ app_lock_service_test.dart — 4/4 通过
- ✅ auth_service_test.dart — 3/3 通过
- ✅ password_disk_test.dart — 16/16 通过
- ❌ vault_service_test.dart — 编译错误（引用不存在的类）
- ❌ vault_media_test.dart — 编译错误
- ❌ vault_test.dart — 编译错误
- ❌ usability_regression_test.dart — 编译错误

---

## 5. 安全性 ✅

### Argon2id 参数
- ✅ t=3（迭代次数）
- ✅ m=65536 KiB（64 MiB 内存）
- ✅ p=1（并行度）
- ✅ hashLength=32（输出 32 字节）

### 密钥派生链
- ✅ v=5 格式：Argon2id → HKDF-SHA256 → K1(enc)
- ✅ 主密钥 → 子密钥分离（加密/认证/元数据）

### 加密实现
- ✅ AES-GCM 256 对称加密
- ✅ 随机 Nonce（12 字节）
- ✅ MAC 认证（16 字节）
- ✅ 密文包含版本号用于向后兼容

### 存储安全
- ✅ 密码以 Argon2id 哈希存储（非明文）
- ✅ 盐值随机生成（32 字节）
- ✅ SharedPreferences 存储（平台级加密）

---

## 6. 发现的问题 + 修复建议

### 🔴 严重问题

| # | 问题 | 影响 | 修复建议 |
|---|------|------|---------|
| 1 | core/ 大量引用 features/ | 违反依赖方向，无法独立测试 | 抽取 core/abstractions/ 接口 |
| 2 | test/vault_* 编译错误 | 全量测试无法通过 | 修复或移除无效测试 |

### 🟡 中等问题

| # | 问题 | 影响 | 修复建议 |
|---|------|------|---------|
| 3 | drawing domain 引用 dart:ui | 严格 CA 违规 | 替换为自定义值对象 |
| 4 | 空 catch 块 (password_disk_page.dart:144) | 错误被吞没 | 添加日志或用户提示 |
| 5 | debugPrint 残留 ~50+ | release 模式无影响 | 统一使用日志框架 |

### 🟢 轻微问题

| # | 问题 | 影响 | 修复建议 |
|---|------|------|---------|
| 6 | flutter analyze 5017 info/warning | 可读性 | 批量清理未使用导入 |

---

## 7. 验收标准对照

| 标准 | 状态 | 说明 |
|------|------|------|
| flutter analyze 0 error | ❌ | 5017 问题（含 test 编译错误） |
| flutter test 全量通过 | ❌ | vault_* 测试编译失败 |
| Domain 层无 Flutter import | ⚠️ | drawing 有 dart:ui |
| 各层无循环依赖 | ⚠️ | core ↔ features 双向引用 |
| 密码功能闭环 | ✅ | 三大功能完整 |
| Argon2id 参数合规 | ✅ | t=3, m=64MiB, p=1 |
| 三层加密闭环 | ✅ | ChaCha20→AES-GCM→签名 |

---

## 8. 修复优先级建议

1. **P0**：修复 vault_* 测试编译错误（移除或 mock 不存在的类）
2. **P1**：将 core/ 的 features 依赖抽取到接口层
3. **P2**：替换 drawing domain 的 dart:ui 类型
4. **P3**：清理 debugPrint 和未使用导入

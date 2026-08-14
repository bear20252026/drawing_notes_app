# 密码盘（U盘即钥匙）设计方案

> 状态：设计定稿 · 2026-08-13
> 依据：docs/OPENSOURCE_STUDY.md 第九章（age/Cryptomator/VeraCrypt/KeePassXC/Picocrypt 研读）
> 目标：Windows 密码盘体验 + 军工级安全 + 免费（只需一块 U 盘）

---

## 1. 安全模型（零知识）

```
┌─────────────────────────────────────────────┐
│  用户持有一块 U 盘（密码盘）                  │
│  盘内文件：key.frogkey（256 位主密钥）        │
│  · 应用软件【不持久化】任何密钥               │
│  · 无 U 盘 → 谁也解不开（零知识架构）         │
└─────────────────────────────────────────────┘
```

- **主解锁**：插入 U 盘 → 应用读取 `key.frogkey` 中的 32 字节主密钥 → AES-256-GCM 解密；
- **恢复解锁**（U 盘丢失）：输入 24 位恢复密钥 → 派生 KEK → 解密数据头中的"主密钥信封"拿到主密钥 → 解密数据；
- **密码盘与密码保护互斥**：启用密码盘（U 盘密钥）的笔记本，不再使用记忆密码派生密钥（避免两套密钥混乱）。

## 2. 密钥文件格式（key.frogkey）

| 偏移 | 字段 | 大小 | 说明 |
|------|------|------|------|
| 0 | Magic | 4B | `0x46524F47`（"FROG"）标识 |
| 4 | 版本 | 1B | `0x01` |
| 5 | 随机填充/校验 | 27B | 填充至 32B；末尾 4B 为主密钥的 SHA-256 前 4 字节（防误盘/防篡改快速校验） |

密钥文件共 32 字节定长：`Magic(4) + Ver(1) + key[27]`？——**修正**：为保持密钥强度，密钥文件为：

```
0     4     5     37
|MAGIC| VER | 32 字节主密钥 |
```

主密钥 = `Random.secure()` 32 字节（256 位）。应用读取后先校验 Magic + VER，再取 32 字节密钥。**文件本身不加密**（U 盘即钥匙，密钥在物理上隔离）；U 盘丢失即密钥泄露风险，故提供恢复密钥机制 + 建议用户启用"密钥文件损坏防护"（备份第二个 U 盘）。

## 3. 加密数据文件头（笔记本 .json 加密形态）

对笔记本页面内容（JSON）加密后存盘：

```
{
  "encrypted": true,
  "mode": "keyfile",            // keyfile = U盘密钥模式
  "v": 1,                       // 格式版本
  "salt": "<16B base64>",       // 恢复密钥 KDF 盐（PBKDF2）
  "nonce": "<12B base64>",      // AES-GCM nonce（主密钥加密载荷）
  "ek": "<base64>",             // 主密钥信封：用 KEK 加密的主密钥（KEK 由恢复密钥+盐派生）
  "nonce2": "<12B base64>",     // AES-GCM nonce（KEK 加密主密钥用）
  "c": "<base64>"               // 密文（AES-256-GCM，主密钥）
}
```

- **解密主路径**：U 盘密钥 → 直接用 `c/nonce` 解密密文；
- **恢复路径**：恢复密钥 + salt → PBKDF2 派生 KEK → 用 `ek/nonce2` 解密得到主密钥 → 用主密钥解密密文；
- **先压缩后加密**（数据量大时）；GCM 认证保证防篡改。

## 4. 恢复密钥（24 位纸备份）

- 创建密码盘时，应用生成 24 位随机恢复密钥（大写字母+数字，去易混字符 0/O/1/I）：
  `XG9-7kL-PqR-2sW-8mV-3aZ-6bN-4cD`；
- UI 强制展示并提示用户抄写/截图（"丢失即永久无法恢复"警示）；
- 加密时用恢复密钥派生 KEK 包裹主密钥（见上 `ek` 字段），实现 U 盘丢失后的恢复。

## 5. Mock/Real 双实现（依赖注入）

```
abstract class PasswordDisk {
  Future<String?> pickDirectory();          // 选择密码盘位置（U盘目录/测试目录）
  Future<bool> createKeyFile(String dir);   // 生成并写入 key.frogkey，返回是否成功
  Future<List<int>?> readKey(String dir);   // 读取主密钥（失败返回 null）
  Future<bool> validateKeyFile(String dir); // 校验 Magic/版本/完整性
}

class RealPasswordDisk implements PasswordDisk  // file_selector 选 U 盘目录
class MockPasswordDisk implements PasswordDisk  // 固定测试目录（kDebugMode 注入）
```

- `main.dart` / `app.dart` 中按 `kDebugMode` 注入实例；
- UI/ViewModel 只依赖抽象接口，切换零改动。

## 6. 密钥信封（主密钥 ↔ 恢复密钥）

- 主密钥（MK，32B，U盘密钥）：加密页面内容；
- KEK：`PBKDF2(恢复密钥, salt, 100000次)` 派生；
- 信封：`ek = AES-GCM(KEK, nonce2, MK)`；
- U 盘丢失 → 恢复密钥 → 解信封得 MK → 解密。**改密码盘（换 U 盘）只需重做信封与密钥文件，无需重加密页面内容。**

## 7. 与现有加密（C3 密码保护）的关系

| 维度 | 现有 C3（密码保护） | 新增密码盘（keyfile） |
|------|---------------------|----------------------|
| 解锁 | 记忆密码 + PBKDF2 | U 盘密钥文件（零知识） |
| 恢复 | 无（评审后保留密文） | 24 位恢复密钥信封 |
| 密钥 | 密码派生 | 随机 256 位 |
| 共存 | —— | 笔记本加密模式二选一（`mode: password|keyfile`） |

## 8. 落地清单（对应任务 3/4/5）

1. `lib/storage/password_disk.dart`：PasswordDisk 抽象 + Real/Mock 实现；
2. `lib/engine/encryption_service.dart` 扩展：keyfile 模式加解密 + 信封；
3. 设置页 UI：创建密码盘 / 解锁 / 恢复密钥展示与验证；
4. 集成测试：Mock 密码盘 创建→加密→解锁→恢复 全闭环；
5. 全量验证（analyze + 测试 + 双端构建 + 打包）。

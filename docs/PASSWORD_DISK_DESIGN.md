# 重置密码盘（U 盘）设计方案

> 状态：N4 批 1 已落地 · 2026-09-02（命名体系定案版）
> 前身：key.frogkey「解锁钥匙」+ vault_reset.frogkey「恢复钥匙」双体系（已删除）
> 目标：一把 U 盘统一重置开屏密码与文件密码

---

## 1. 定案（2026-09-02 用户拍板）

U 盘只实现**一种功能 = 重置密码盘**：

```
插入 U 盘 → 点「忘记密码」→ 重置一个新密码
```

- 这一柄重置钥匙**既对开屏密码适用，也对文件密码适用**；
- 已删除「U 盘解锁钥匙」（key.frogkey 代开文件体系）与
  「U 盘恢复钥匙」（vault_reset.frogkey 开屏密码找回说法）两种说法及功能；
- 重置能力统一收进重置密码盘（沿用 vault_reset.frogkey 的
  LUKS/BitLocker 多保护器槽位架构作底层）。

## 2. 密码体系总览（两层锁 + 一把 U 盘）

| 层 | 保护对象 | 忘记密码 |
|----|----------|----------|
| 第 1 层 · 开屏密码 | 整个 App（+ 主密钥保险库） | 重置密码盘重设 |
| 第 2 层 · 文件密码 | 单个文件（画布✅/分页画布✅/笔记⬅️ N2 补） | 重置密码盘重设（批 2/3 接入） |
| 重置密码盘（U 盘） | ——（不是锁，是通道） | —— |

## 3. 钥匙文件格式（password_reset_disk.key）

37 字节定长 FROG v1（编解码内联于 `lib/core/storage/password_reset_disk.dart`）：

```
0     4     5     37
|MAGIC| VER | 32 字节随机钥匙 |
MAGIC = 0x46 0x52 0x4F 0x47（"FROG"）  VER = 0x01
```

- 钥匙 = `Random.secure()` 32 字节 CSPRNG，**不含任何主密钥副本**；
- 主密钥被它包裹后存在设备侧：
  - 开屏密码 → 保险库槽 2（`VaultKeyService.addUsbKeySlot`）；
  - 文件密码 → VaultFileCodec v3 信封槽（N4 批 2 实现）。

安全属性（与 LUKS/KeePass 一致）：
- 只偷 U 盘：解不开任何东西；
- 只偷设备：还有防爆破守卫挡着；
- 设备 + U 盘都拿到：等价于本人（两件东西分放两地正是防御的全部意义）。

## 4. 旧版兼容

- v1.5.x 绑定的 U 盘上是旧文件名 `vault_reset.frogkey`；
- `ResetDiskFile.readFrom` 优先读 `password_reset_disk.key`，
  不存在时**回退读旧文件名**——老 U 盘免重做；
- `deleteFrom` 新旧文件名一并清理。

## 5. 流程

### 绑定（应用锁设置页 → 重置密码盘 → 绑定）
验证当前密码 → 选 U 盘目录 → 写入 password_reset_disk.key →
保险库槽 2 以该钥匙包裹主密钥。

### 重置（锁屏 → 忘记密码？）
说明 → 选 U 盘 → 读钥匙（fail-closed）→ 两步输入新密码 →
`resetPinWithUsbKey` 重置保险库槽 1 → 重设开屏 PIN 哈希 → 清防爆破记录 → 放行。
冷却期内同样可用（被锁 24 小时干等没有意义）。

### 解除绑定
只删设备侧槽 2；U 盘上的钥匙文件须用户自行删除（弹窗明示）。

## 6. 已删除的旧体系（N4 批 1，2026-09-02）

| 删除项 | 原职责 |
|--------|--------|
| `password_disk.dart`（PasswordDisk/Real/Mock/PasswordDiskFile） | key.frogkey 代开体系 |
| `password_disk_page.dart` | 密码盘管理页 |
| `recovery_key_generator.dart` | 24 位恢复密钥生成 |
| `EncryptionMode.keyfile` | 笔记本 keyfile 加密模式（本机数据 0 使用，安全删除） |
| `Notebook.recoveryEnvelope` | keyfile 恢复信封字段 |
| `EncryptionService.encryptWithKey/decryptWithKey/wrapMasterKey/unwrapMasterKey` | keyfile 加解密 + 恢复信封 |
| `NotebookStorage.encryptAndSaveWithKey/decryptNotebookWithKey/saveWithKey` | keyfile 存取 |

> 保留：`encryptNotebookPayload/decryptNotebookPayload`（密码 v4 路径依赖）、
> `MediaCryptoService.setNotebookKey`（K_note 媒体密钥注入，N2 可能复用）。

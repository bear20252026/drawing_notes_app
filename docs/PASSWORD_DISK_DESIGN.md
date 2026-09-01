# 重置密码盘（U 盘）设计方案

> 状态：N4 批 1 + 批 2 已落地 · 2026-09-02（命名体系定案版）
> 前身：key.frogkey「解锁钥匙」+ vault_reset.frogkey「恢复钥匙」双体系（已删除）
> 目标：一把 U 盘统一重置开屏密码与文件密码（开屏密码 ✅ 批 1 · 画布文件密码 ✅ 批 2 · 分页画布 ⬅️ 批 3）

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
  - 文件密码 → VaultFileCodec **v3 信封 USB 槽**（批 2 已实现，见 §5.5）。

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

## 7. 文件密码 v3 双保护器信封（N4 批 2，2026-09-02）

### 7.1 落盘格式（`DNV|0x03|jsonLen(u32 BE)|JSON 槽位头|AES-GCM 载荷`）

```json
{"v":3,"slots":[
  {"type":"pw","salt":b64,"iter":600000,"wrapped":b64},
  {"type":"usb","wrapped":b64}
]}
```

- 载荷由**随机 32B DEK** 加密（AAD 与 v1/v2 同串 `drawing-notes|file|v1|<context>`）；
- 密码槽（PBKDF2 包裹 DEK）+ 可选重置盘槽（U 盘钥匙直接包裹 DEK）——
  LUKS/BitLocker 多保护器：两把钥匙开同一把 DEK；
- 槽位 AAD 绑定 context（`drawing-notes|file-slot|pw|v3|<ctx>` /
  `drawing-notes|file-slot|usb|v1|<ctx>`）——槽位不可跨文件移植；
- **DEK 按文档恒定**（会话缓存 `_sessionDocDeks`）：写入复用同一把 DEK，
  否则每次保存都会作废重置盘槽位；冷实例验密时从密码槽解出再缓存。

### 7.2 重置流程（`rewrapPasswordSlotV3`）

USB 钥匙解开 DEK → 新盐重绕密码槽 → **载荷密文与 USB 槽位字节一字节不动**
（LUKS 同款）→ 新密码生效、U 盘继续有效。不需要旧密码。

### 7.3 存储层 API（StorageService）

| API | 说明 |
|-----|------|
| `setFilePassword(id, pw, {resetDiskKey})` | v3 设密；插盘当场嵌入 USB 槽（可跳过） |
| `changeFilePassword(id, old, new)` | v3 保留 DEK/槽位；**v2 旧文件自动升级 v3** |
| `bindFileUsbSlot(id, pw, key)` | 事后绑定（密码管理 sheet「绑定重置密码盘」入口） |
| `resetFilePasswordWithUsb(id, key, newPw)` | 忘记密码通道（fail-closed 返回 false） |
| `hasFileUsbSlot(id)` | 读头部判断是否已绑定 |

### 7.4 UI 接入

- 首页与全部文档两处画布解锁弹窗加「忘记密码？」footer
  （`UnlockFlow.show` 新增 `footerLabel/onFooter`；移动端复用
  PinPadCore「紧急情况」槽位，桌面端 AlertDialog footer 链接，
  点击均先关弹窗再回调）；
- 重置流统一走 `FilePasswordResetFlow.show`
  （lib/fix/file_password_reset_flow.dart）：说明 → 判定已绑定 →
  选盘读钥匙 → 新密码两遍（≠开屏密码）→ 重置；
- 设密时弹窗询问「绑定重置密码盘？」（可跳过，事后可绑）。

### 7.5 兼容承诺

- **v2 旧文件只读兼容**：`isPasswordEnvelope` 同时覆盖 v2/v3；
  v2 走原 `decryptWithPassword` 路径，v3 走 `unlockWithPasswordV3`；
- v2 文件用户「修改一次密码」即自动升级 v3，之后可绑定重置盘；
- 忘记密码且从未绑定重置盘的旧 v2 文件：无法重置（弹窗明示）。

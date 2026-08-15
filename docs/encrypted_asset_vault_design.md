# 加密资产仓设计（Encrypted Asset Vault）

> 状态：设计定案（专家审计 H-03 数据保密重构专项，2026-08-15）
> 依据：专家审计交付包 H-03 + 全球调研（Inqrypt 分层加密 M→Kₙ→Content+Images、
> Heritage Archive 每对象 DEK、Flutter4Fun EncryptedFileImage 渲染模式）

## 一、问题（专家 H-03）

- 图片/PDF 副本明文存储于 `notebook_images/`——"加密笔记本"的媒体资产未加密
- 从未加密转加密时 `.bak` 可能保留历史明文
- 标题/时间元数据明文（已评估：行业先例 private_notes_light 同款取舍，保留）

## 二、目标架构（分层 DEK——Inqrypt 模式）

```
用户主密钥/会话密钥 (K_user)
    │  wrap（PBKDF2/KEK——复用 wrapMasterKey）
    ▼
每笔记 DEK (K_note) —— 随机 32 字节，存入笔记加密载荷（被 K_user 包裹）
    │  AES-256-GCM（AAD 绑定 notebookId——复用 v4 载荷）
    ▼
页面载荷 + 媒体资产（图片/PDF 副本密文化）
```

- 每笔记独立 DEK：**限制爆炸半径**（单笔记密钥泄露不影响其他笔记——Heritage 印证）
- 媒体加密：storeImage 用 K_note 加密副本写入（密文落盘）——渲染用
  **EncryptedFileImage（ImageProvider 重写 _loadAsync 解密）**（Flutter4Fun 标准模式）

## 三、实施步骤（后续专项，按可回溯小步）

1. **密钥链路**：INotebookAccessor.storeImage 增加可选密钥参数（会话主密钥/DEK 传入）
   ——契约改动（notebook_accessor_impl/调用方同步）
2. **storeImage 加密**：副本写入前用 K_note AES-GCM 加密（密文 `.enc` 后缀 +
   扩展名映射）——旧明文兼容（读取时魔数检测：明文 vs 密文）
3. **渲染解密**：editor_page_overlays 的 `Image.file` → `EncryptedFileImage`
   （读加密字节 → 解密 → decode——密钥从会话获取，仅内存）
4. **迁移**：旧明文副本解锁后自动重加密（复用 D-1 自动升级时机）——
   flutter_secure_storage 两步迁移模式（兼容期新旧并存）
5. **验收**：磁盘扫描无正文/图像明文（专家 H-03 标准）

## 四、关键风险与边界

- 渲染解密是异步（_loadAsync）——图片显示延迟可接受（Image.memory 同路径）
- 密钥仅内存（会话）——与 D-2/H-05 内存清理一致
- 纯 Dart 无法保证 String 擦除——平台工程（备份/截屏策略）另行补齐

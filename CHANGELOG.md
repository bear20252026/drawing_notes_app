# 变更日志（Changelog）

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增
- **CVE 依赖扫描工具**：`tools/scan_cve.py`，基于 OSV.dev API 扫描 pubspec.lock 中所有已知漏洞
- **CVE 扫描 CI Workflow**：`.github/workflows/cve-scan.yml`，PR 自动扫描 + 每周定时扫描 + 手动触发
- **Schema 迁移机制**：`lib/core/storage/migration/`，版本化存储格式迁移框架
  - `SchemaMigrator`：版本检测 → 链式执行 → 备份 → 失败回滚
  - `MigrationRunner`：应用启动时自动迁移
  - `allMigrations`：迁移注册表，新增迁移只需在此添加

### 依赖精简
- **PDF 包分析**：确认 `pdf`（生成）与 `pdfrx`（渲染）职责不同，均需保留；`pdfx` 已迁移删除，无残留引用

## [1.1.0] - 2026-08-16

### 安全（专家审计闭环——P0-P2 封堵 + 军工审计链 A-H + 专家审计包）

- 路径遍历 / 任意删除封堵：受管路径 + 非跟随链接检查 + 运行时校验（CVE-2026-55667 同源）
- 加密 v4 AAD 载荷（NIST SP 800-38D 上下文绑定）+ 严格封装校验（密钥包裹/固定字段长度）
- 媒体加密双端闭环：DAN 文件头 + K_note 每笔记密钥 + 明文兼容读取 + 幂等迁移
- 回收站（30 天保留 + 恢复/清空）+ PIN 保护（v2 KEK——OWASP 模式）
- 不可篡改审计：SHA-256 哈希链（prevHash 链接——篡改断链）+ verifyIntegrity
- 错误边界：FlutterError/PlatformDispatcher + 脱敏记录（仅错误类型/库名）
- 导入隔离：PDF 页数/大小配额 + 文本 20MB 配额 + **SVG 预检**（XXE/Billion Laughs/脚本注入/膨胀防护）
- 搜索加密安全：未解锁加密内容不可读（标题明文可搜——私有笔记先例模式）

### 架构（解耦 + 可测——官方渐进节奏）

- God Class 拆分：**8 个纯计算服务**提取（选区中心/变换/绑定判定/取色/图片缩放/形状缩放/线段相交/点线距离——权威算法对齐 tldraw/掘金）
- **PolicyEngine** 策略层：操作白名单默认拒绝（fail-closed）+ enforce/monitor 模式 + 审计——导入/删除门禁接入
- **SessionGuard** 会话守卫：失去焦点立即锁定（内存密钥清零）+ 文件选择器豁免 + 再认证
- **VFS 加密对象仓库**：对象清单 + 版本回溯 + AAD 绑定 + 原子提交（临时文件+rename——崩溃安全）——VaultService 接入层 + **媒体双轨接入**（新媒体 VFS 对象 + 旧 DAN 文件兼容——s3eg 双读窗口）

### 国际化

- gen_l10n 框架 + **75+ 中英语义化 key**（home/editor/note/disk/search/paper 六域全覆盖）
- untranslated-messages-file 排查配置（54/54 对齐无缺失）

### 工程化

- **SBOM 生成**（CycloneDX 1.5——145 组件）+ **秘密扫描**（Gitleaks 模式——引号内高熵检测）+ CI 集成（gitleaks-action@v3 + sbom.yml）
- actions/checkout/upload-artifact 升级 Node 24（修复弃用警告）
- 依赖锁定（pubspec.lock）+ CVE 核查脚本（check_deps.sh）

### 修复

- dispose 内存清零（D-2）/ 缓存竞态 / 位图泄漏 / 历史上限 / 路径校验（审计回归）
- 搜索去抖 + 依赖注入 / 性能基准（1200 笔画编解码）
- 全量验证门禁：`flutter analyze` 零问题 / **391+ 测试全过** / 架构规则 +5 全过 / 边界通过 / 行数 0 错误 / 涉密自查无涉密

---

## [1.0.0] - 2026-08-14

- Phase 1-7 全部完成（画布/绘图工具/图层/选区变换/笔记/持久化/体验打磨）
- 基础安全：删除确认/路径校验/自动保存
- 平台：Windows 桌面 + Android

# Drawing Notes App 全面代码架构审计报告（2026-08-15）

> 审计范围：`D:/write/1/build_latest/drawing_notes_app`（23602 行，lib 5 层）
> 审计方法：中英双语官方文档调研（docs.flutter.dev/security、dart.dev/security、riverpod.dev、
> OWASP 风格 checklist、ostorlab 中文清单交叉校验）+ 逐行代码审计 + 危险模式扫描 + 测试全量验证
> 审计结论：架构整体健康，1 个中危安全漏洞 + 4 项合规差距，修复建议见文末清单

---

## 一、2026 合规性对照（截止 2026-08-15）

| 检查项 | 状态 | 证据 |
| --- | --- | --- |
| 最小权限 | ✅ | AndroidManifest.xml 零 uses-permission |
| 明文流量禁用 | ✅ | 离线应用：lib 全量 0 处 HttpClient/Dio/WebSocket；`http://` 仅 XML schema 命名空间 |
| 无硬编码机密 | ✅ | 无 token/密码字面量；密码盘零知识架构（主密钥只存 U 盘 key.frogkey） |
| 敏感存储安全 | ✅ | shared_preferences 仅存 ThemeMode（非敏感）；机密走 AES-GCM-256 加密 |
| 加密强度 | ⚠️ | AES-GCM-256 ✓ + PBKDF2-HMAC-SHA256 10 万次迭代（**低于 OWASP 2026 推荐 60 万**） |
| 弱 PRNG | ❌ | **CWE-338**：恢复密钥用非安全 `Random()`（2 处，见漏洞 #1） |
| CI 门禁 | ✅ | flutter analyze 零问题 + 298 测试全过 + code_guard + check_boundaries 工具链完备 |
| 依赖版本 | ⚠️ | flutter_riverpod ^2.6.1（3.0 已发布 1 年+）；flutter_lints ^6.0.0 ✓ 最新 |
| 资源泄漏 | ✅ | _temporaryInkTicker / 倒计时 Timer 均正确 cancel（dispose 全覆盖） |
| 输入校验 | ⚠️ | `cmd /c start` 打开超链接无 scheme/元字符校验（见漏洞 #2） |
| SBOM/CVE 追踪 | ⚠️ | pubspec.lock 存在，未见 CVE 定期核查流程 |
| 异常健壮性 | ✅ | 加密路径 FormatException 统一包装（防 TypeError 破坏上层）；锁/磁盘异常保守降级 |

## 二、架构审计（Clean Architecture 5 层）

| 层 | 行数 | 审计结论 |
| --- | --- | --- |
| presentation | 12447 | 合理拆分 20 文件（page/actions/commands/dialogs/drag/editing/input/overlays/persistence/shortcuts/tools）；**偏大，可再拆** |
| application | 4686 | DrawingController + 5 分域文件（history/objects/render/selection/temporary）+ 命令模式；**主 controller 偏大** |
| infrastructure | 2976 | 加密/编解码/渲染缓存/形状识别/同步（纯本地）分层清晰 |
| domain | 1653 | 纯 Dart 领域模型（document/layer/stroke/shape/text/image/selection）无 UI 依赖 ✓ |
| core + shared | 1635 | DI（Riverpod）、密码盘、存储、主题、通用组件 |

亮点：
- **命令模式 + 事务回滚**：command_registry / document_commands / document_transaction（回滚失败逐条打印）
- **多文档隔离**：multi_document_controller_isolation_test 验证控制器互不污染
- **Riverpod 五域 Notifier 化迁移进行中**：viewport/selection/history/shapes/images（本系列已提交 5 个域）

改进点：
1. presentation 12447 行偏大（>40% 总量），建议按功能域继续拆（如编辑器拆分 editor 子目录）
2. 重复代码：`_generateRecoveryKey` 在 password_disk_page.dart 与 notebook_view_page_imports.dart **完全复制两份**（且同带漏洞）——应收敛为共享工具
3. DrawingController 主文件（1000+ 行）建议后续继续按域抽离

## 三、安全漏洞清单（按严重度）

### 漏洞 #1【中危】CWE-338 弱 PRNG 生成恢复密钥（影响真实加密路径）
- **位置**：`lib/features/notes/presentation/password_disk_page.dart:75`、`lib/features/notes/presentation/notebook_view_page_imports.dart:257`
- **问题**：24 位恢复密钥（字母表 32 字符 ≈ 113 bits 熵）用 `Random()`（线性同余伪随机、可预测）生成，而**该密钥经 PBKDF2 派生 KEK 包裹主密钥**（notebook_storage.dart:299/345 wrapMasterKey）——U 盘丢失的恢复路径建立在可预测的密钥材料上
- **对比证据**：同项目 PasswordDiskFile.generateKey()（password_disk.dart:38）正确使用 `Random.secure()`
- **修复**：两处 `Random()` → `Random.secure()`（一行修复）
- **验证**：security_regression_test.dart（14 测试）已覆盖加密回归，修复后全量重跑

### 漏洞 #2【低-中危】`cmd /c start` 命令注入面（本地自助触发）
- **位置**：`lib/features/drawing/presentation/editor_page_editing.dart:553`（_openHref）
- **问题**：href 为用户自行输入并绑定到元素，点击时 `Process.start('cmd', ['/c', 'start', '', href])`——cmd 会解析 href 中的 `&`、`|`、`^` 等元字符；`javascript:`/`file:` scheme 也未被拦截
- **降级因素**：桌面应用、href 为本人输入本人点击（无远程攻击面）
- **修复建议**：打开前校验 scheme 白名单（http/https/mailto）并拒绝含 cmd 元字符的输入；或改用 `url_launcher` 插件（平台安全打开）

### 漏洞 #3【低】PBKDF2 迭代次数低于 OWASP 2026 推荐
- **位置**：encryption_service.dart:16（100000 次）
- **问题**：OWASP Password Storage Cheat Sheet 2026 对 PBKDF2-HMAC-SHA256 推荐 **600,000 次**；10 万次仍可防基础字典攻击，但硬件加速下离线爆破成本偏低
- **修复建议**：提升至 600000（兼容旧数据：解密时按 `v` 字段分派迭代次数，v=1 用旧值、v=2 用新值）

### 漏洞 #4【低】flutter_riverpod ^2.6.1 非 2026 最新
- **问题**：Riverpod 3.0 已发布（StateProvider 等 legacy 化、== 过滤、Ref 统一、family Notifier 移除），2.6.1 仍受支持但非推荐
- **修复建议**：短期可维持；中长期按官方 3.0 迁移指南升级（本系列 Notifier 化迁移已与 3.0 语义对齐：不可变 state + == 过滤 + Notifier 无 mounted）

## 四、功能完整性核对（全部功能可完全实现）

**验证基础**：flutter analyze 零问题 + **298 单测全过（64 文件）** + 16 集成测试全过

| 功能域 | 单测覆盖 | 状态 |
| --- | --- | --- |
| 画布/笔画/手写 | phase1_canvas(6)/phase2_tools(5)/stroke_*(14)/stylus(4)/pencil_shader(3) | ✅ |
| 形状（识别/创建/绑定/渲染） | shape_*(13)/standalone_shape(2)/stroke_renderer_outline(4) | ✅ |
| 文本（run delta/样式） | text_run_delta(6)/text_style_regression(6) | ✅ |
| 图片（插入/编辑/持久化/资产生命周期） | document_image_*(13)/document_asset_lifecycle(3) | ✅ |
| 图层合成 | layer_compositor_cache(4)/highlighter_compositor(3)/phase3_layers(8) | ✅ |
| 选区/变换/混排对象 | phase4_selection(12)/selection_transform(2)/mixed_document_object(5)/reading_inversion(1) | ✅ |
| 无限画布/视口 | infinite_canvas(3)/view_transform_cache(4)/glass_surface(3) | ✅ |
| 导出（PPT/SVG/PDF/RTF） | export_payload(1)/pdf_hybrid(4)/paged_note_rtf(2)/paged_note_pdf_asset(1) | ✅ |
| 加密/密码盘/恢复 | security_regression(14)/password_disk(7)/password_disk_page(3)/notebook_keyfile(5)/notebook_page_metadata(2) | ✅ |
| 同步/搜索 | sync_service(5)/search_service(2) | ✅ |
| 命令/事务/脏跟踪 | command_registry(3)/command_palette(1)/document_transaction(6)/push_transaction(3)/dirty_tracking(5) | ✅ |
| Riverpod 五域迁移 | riverpod_providers(13) | ✅ |
| 回归/可用性 | fix_regression(10)/usability(4)/ux_*(15)/paper_template(2)/fractional_index(9)/eraser_*(6)/laser(2)/temporary_marker(2)/brush_preset(4)/multi_document(1) | ✅ |

**结论**：所有功能域均有实现 + 测试覆盖，无"只实现不验证"的死角；导出/加密/同步等关键路径有专项测试。

## 五、性能审计

| 项 | 结论 |
| --- | --- |
| 渲染缓存 | ✅ stroke_picture_cache（指纹缓存）/ layer_compositor_cache / view_transform_cache 三层缓存 |
| 增量重绘 | ✅ 脏标记 + 增量重建（dirty_tracking_test 5 测试） |
| 视口裁剪 | ✅ 无限画布仅绘制可见区（infinite_canvas_controller_test） |
| 临时标记 | ✅ 临时墨水/激光/橡皮擦 ticker 16ms 帧率控制 + dispose 清理 |
| 文本布局 | ✅ text_run_delta 增量差异计算 |

---

## 六、修复建议清单（按优先级）

| 优先级 | 修复项 | 改动量 | 建议 |
| --- | --- | --- | --- |
| P1 | 漏洞 #1：两处 `Random()` → `Random.secure()` | 2 行 | 立即修复 + security_regression 补测 |
| P2 | 漏洞 #2：href scheme 白名单 + cmd 元字符校验（或换 url_launcher） | ~15 行 | 下个迭代 |
| P2 | 漏洞 #3：PBKDF2 迭代提至 60 万（v 字段版本兼容解密） | ~10 行 | 下个迭代 |
| P3 | 漏洞 #4：Riverpod 3.0 迁移评估（迁移指南已存在） | 大 | 排期评估 |
| P3 | 重复代码收敛：_generateRecoveryKey 提取共享工具（顺带消漏洞 #1） | ~30 行 | 随 P1 一起 |
| P4 | 架构：presentation 12447 行再拆分、DrawingController 主文件按域抽离 | 中 | 长期 |
| P4 | SBOM/CVE 定期核查流程（dart pub outdated 纳入 CI） | 小 | 长期 |

> 已验证门禁：flutter analyze 零问题 / 298 单测全过 / 16 集成测试全过 / check_boundaries 通过 / code_guard 0 错误

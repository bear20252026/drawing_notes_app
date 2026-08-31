# 代码审计报告（2026-08-31 · 最严苛标准）

> 审计范围：全库（lib/ 1323 项测试基线）。方法：两路并行专项代理（安全 / 可靠性-性能-质量）
> + 最新改动（M12.4-M12.8）人工复核。所有问题均有实际读码证据。

## 总体健康度：B+（83/100）

- **安全基础扎实**：AES-GCM-256 + PBKDF2（60 万次迭代 + 版本迁移）、HTML 全量转义、
  PDF 导入三重资源预检、id 白名单校验、机密入 OS 凭据库——均达标。
- **最大短板**：写路径可靠性（保存副链丢 Future / 退出不 flush / 软删除非原子）
  与 M12.7-M12.8 新增功能的性能 масштаб（反向链接面板触发全库加载）。

---

## 高危（4 项）

### H1. 保存副链丢弃 Future +「已保存」假象
- 位置：`doc_controller.dart:17`（`void save()` 不 await `onSave`）；
  `doc_page.dart:_persist`（setState 显示"已保存"早于磁盘写入完成）
- 影响：标签编辑等副链保存的失败被静默吞掉，UI 显示已保存但数据未落盘。
- 修复：`save` 改 `Future<void>` 并 await；_persist 的 saved 状态由
  SaveScheduler.onSaved 回调驱动（单一事实源），禁用双轨状态写入。

### H2. 退出页面不 flush 防抖窗口
- 位置：`doc_page.dart`（无 pop/dispose flush 逻辑；SaveScheduler 防抖 800ms）
- 影响：最后 0.8 秒内的编辑在用户退出时丢失——用户可感知的数据丢失。
- 修复：`didPopNext`/dispose 前调用 `_saveScheduler.saveNow()`（若 dirty）。

### H3. 块文档存储无串行化 + 软删除非原子
- 位置：`note_block_doc_store.dart:72`（saveDocument 无写尾队列）、
  `:124`（deleteDocument = load→写 trash→删激活，非原子）
- 影响：自动保存与删除交错时，已删文档被旧内容复活或新内容被覆盖丢失；
  Windows 上 delete+rename 存在覆盖窗口。
- 修复：store 内加按 id 的写尾队列（Future chain per key）；软删除改为
  「rename 到 trash 目录」（单原子操作）再由 trash 读取包一层元数据。

### H4. 反向链接面板性能炸弹
- 位置：`doc_page.dart:_BacklinksPanel.didUpdateWidget`（updatedAt 每次自动
  保存都变）→ `_reload()` → `app_shell.dart:80 _loadAllBlockDocs` 全库 JSON
  加载 + `listIds()` 每次触发 `purgeExpiredTrash` 全盘扫描
- 影响：打字时每 ~1.2 秒全库解析一遍，几百篇笔记下严重卡顿。
- 修复：索引缓存 + 显式失效（仅文档集变化时重算）；purgeExpiredTrash 改为
  应用启动时执行一次 + 节流。

## 中危（8 项）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| M1 | PolicyEngine（全库仅 3 处 check） | 导出/回收站恢复/彻底删除/标签增删无门禁，加密笔记可明文导出 | 导出与 trash 操作补 policy 检查（`note.export`/`note.purge`） |
| M2 | trash 恢复路径 | trashName 缺正则校验（Windows 反斜杠遍历） | restore 前套用 isValidId |
| M3 | 密码盘 | PIN 下限 4 位可离线爆破 | 下限提升至 6 位 + 错误次数退避 |
| M4 | `doc_editor.dart:287` | slash 菜单 OverlayEntry 疑似 dispose 泄漏（需复核 dispose 全覆盖） | dispose 中统一 remove 两个 overlay |
| M5 | `app_shell.dart:213 _loadAllDocs` | 三源全量串行 JSON 装配，大库卡顿 | 分页/惰性 + BlockDocMeta 只读轻量头 |
| M6 | `doc_editor.dart:721 _syncText` | 每键 setState 全列表重建 + 全文档深拷贝入史栈 | 局部重建（仅当前块）+ 史栈限深/去抖 |
| M7 | 跨 feature 依赖 | `doc_page.dart:11` import all_docs/infrastructure/tag_store | TagStore 上收 `core/` 或 doc 模块 |
| M8 | `encryption_service.dart` v1 格式 | 明文密钥兼容残留 | 提供一次性迁移工具后移除 v1 分支 |

## 低危（6 项）

| # | 位置 | 问题 |
|---|---|---|
| L1 | `doc_page.dart:_createTagInline` | TextEditingController 未 dispose |
| L2 | `doc_export_io.dart:12` | sanitizeFileName 未去除尾点/尾空格（Windows 非法） |
| L3 | `doc_export_io.dart:26` | existsSync/createSync 同步 IO 在 UI isolate |
| L4 | search_page/manage/home_tabs 的 DocPage | 未注入 tagStore/allDocsLoader（功能不一致） |
| L5 | 异常提示 | 部分写路径失败仅 debugPrint，无用户提示 |
| L6 | 日志 | 少量 debugPrint 输出文件路径（泄露面） |

## 建议（不构成缺陷）

- HomePage 无 loadDocs 时的 fallback 加载路径为生产死路径（仅测试用），可标注 @visibleForTesting。
- `_BacklinksPanel` 的 didUpdateWidget 恒等比较可改为显式 version 计数。
- 块合并（Backspace）边界逻辑较简单，建议补空嵌套用例测试。
- `note_block_doc_markdown.dart` 为唯一 Markdown 转换源 ✓（M12.6 已去重），保持。

## 确认达标项（无需整改）

AES-GCM-256 + PBKDF2 加密链路（含版本迁移与输入上限）、HTML 导出全量转义、
PDF 导入三重资源预检、id 白名单路径校验、doc_editor 删块资源 dispose、
SaveScheduler 主链设计、策略门禁的删除操作。

---

## 优先级改进路线图

| 阶段 | 内容 | 目标 |
|---|---|---|
| **P0（本周）** | ~~H1 保存链统一 + H2 退出 flush + H3 store 写尾队列与原子软删除~~ ✅ 已完成（2026-08-31，H1/H2=5c0ece3，H3=写尾队列+rename 原子化+双格式兼容，1324 测试全绿） | 数据零丢失 |
| **P1（下周）** | ~~H4 反向链接索引缓存化 + M1 门禁补齐 + M2 trash 校验 + M4 Overlay 泄漏~~ ✅ 已完成（2026-08-31：shell 内存缓存+_bumpDataVersion 统一失效；purgeExpiredTrash 节流 1h；白名单补 note.purge/note.export.markdown/html 并 enforceCheck 接线导出与 trash 操作；M2 已由 H3 的 _trashPathFor isValidId 校验覆盖；M4 dispose 补 slash overlay 移除。1324 测试全绿） | 性能与门禁 |
| **P2** | M5 列表轻量化 + M6 编辑器局部重建 + M7 TagStore 解耦 + M3 PIN 策略 | 大库体验 |
| **P3** | ~~低危清理 + 装配一致性 + 死路径标注~~ ✅ 已完成（2026-08-31：L1 controller dispose；L2 文件名尾点/尾空格；L3 导出全异步 IO；L4=DocPage 增 blockDocStore 统一兜底装配（五入口全对齐，反向链接/标签能力全入口生效）；L6 确认无路径泄露（唯一 debugPrint 仅记错误类型）。**重要修复：M12.7 提交中反向链接面板 UI 实际缺失（补丁中断致写入丢失、测试未覆盖 UI 层故全绿）——本轮补齐 _BacklinksPanel+body 装配+blockDocStore 兜底路由。1324 测试全绿） | 长期可维护 |

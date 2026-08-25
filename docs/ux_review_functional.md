# UX 功能复查报告

**复查时间**: 2026-08-25  
**复查范围**: 导航流程、数据持久化、导出功能、加密流程、异常处理、性能体验  
**工作区**: `D:\write\1\build_latest\drawing_notes_app`  
**复查方法**: 代码级审查 + 端到端路径追踪

---

## 1. 导航流程完整性

### 1.1 首页 → 新建画布 → 绘画 → 保存 → 返回首页

| 步骤 | 状态 | 说明 |
|------|------|------|
| 新建画布入口 | ✅ | `_createDrawing()` 弹出命名对话框 → 创建 `DrawingDocument` → 推入 `EditorV2Screen` |
| 编辑器初始化 | ✅ | `EditorV2Screen.initState()` 调用 `_notifier.createDocument()` 初始化画布状态 |
| 绘画手势 | ✅ | `GestureDetector` 的 `onPanStart/Update/End` 调用 `startStroke/extendStroke/endStroke` |
| 自动保存 | ✅ | 800ms 防抖 `_autoSaveTimer` → `_saveNow()` → `StorageService().saveJson()` |
| 返回首页 | ✅ | `WillPopScope.onPopInvokedWithResult` → `_saveNow()` → `Navigator.pop` → `_refresh()` |

**结论: ✅ 全流程顺畅**

### 1.2 首页 → 新建笔记 → 打字 → 保存 → 返回首页

| 步骤 | 状态 | 说明 |
|------|------|------|
| 新建笔记本入口 | ✅ | `_createNotebook()` → 弹出命名对话框 → `NotebookStorage.save()` → `EditorV2Screen(note mode)` |
| 编辑器初始化 | ✅ | `initState` 中 `_notifier.loadNoteDocument(widget.documentId)` |
| 打字输入 | ✅ | `NoteEditorWidget` 使用 `TextEditingController`，`onChanged` 回调更新 ViewModel |
| 格式化工具栏 | ✅ | `_NoteFormattingToolbar` 按钮接入 `_notifier` 的格式化操作 |
| 自动保存 | ✅ | 800ms 防抖 → `saveNoteDocument()` → `StorageService().saveJson()` |
| 返回首页 | ✅ | `WillPopScope` → `_saveNow()` → `Navigator.pop` → `_refresh()` |

**结论: ✅ 全流程顺畅**

### ⚠️ 1.3 严重问题：打开已有画作用的是旧 V1 编辑器！

| 路径 | 导航目标 | 状态 |
|------|----------|------|
| `_createDrawing()` | `EditorV2Screen` | ✅ V2 |
| `_quickRecord()` | `EditorV2Screen` | ✅ V2 |
| `_openDrawing(meta)` | **`EditorPage` (V1)** | ❌ **不一致** |
| `_createNotebook()` | `EditorV2Screen` | ✅ V2 |
| `_openNotebook(nb)` | `EditorV2Screen` | ✅ V2 |

**根因**: `home_page.dart` 第 201 行：
```dart
builder: (_) => EditorPage(document: doc, docStorage: _docStorage),
```
应该改为 `EditorV2Screen(documentId: meta.id)`。

**影响**: 用户新建画布 → 用 V2 编辑器 → 返回首页 → 打开同一画布 → 用 V1 编辑器。两个编辑器的保存路径不同，可能导致数据丢失或格式不兼容。

**修复建议**: 将 `_openDrawing()` 改为使用 `EditorV2Screen`，保持统一架构。

### 1.4 搜索 → 打开结果 → 返回

| 步骤 | 状态 | 说明 |
|------|------|------|
| 搜索入口 | ✅ | `_openSearch()` → 构建 `SearchIndex` → 弹出 `SearchWidget` 对话框 |
| 索引加载 | ✅ | `SearchIndexBuilder.build()` 异步构建，有加载指示器 |
| 搜索结果跳转 | ✅ | `_navigateToTarget()` → 笔记本走 `_openNotebook(nb)`，画作走 `_openDrawing(meta)` |
| 返回 | ✅ | 搜索面板关闭 → 编辑器返回 → `_refresh()` |

**结论: ✅ 全流程顺畅**

### 1.5 设置 → 修改主题 → 返回

| 步骤 | 状态 | 说明 |
|------|------|------|
| 主题切换入口 | ✅ | 首页 AppBar 的 `IconButton` → `ref.read(themeModeProvider.notifier).cycle()` |
| 设置页入口 | ✅ | `PopupMenuButton` → 导航到 SettingsPage |
| 设置页内切换 | ⚠️ | 设置页的 Switch `onChanged` 是空实现（`// TODO: 接入 ThemeNotifier`） |
| 首页切换 | ✅ | 首页直接通过 `themeModeProvider` 切换，立即生效 |

**结论: ⚠️ 首页主题切换正常，但设置页的 Switch 未接入 ThemeNotifier**

### 1.6 密码盘 → 创建/解锁 → 返回

| 步骤 | 状态 | 说明 |
|------|------|------|
| 密码盘入口 | ✅ | 首页 `PopupMenuButton` → `/password-disk` |
| 创建密码盘 | ✅ | 选择目录 → 生成 `key.frogkey` → Argon2id 哈希 PIN → 展示恢复密钥 |
| 解锁密码盘 | ✅ | 选择目录 → 读取密钥 → `AuthGuard.authenticate()` → 导航 |
| 返回首页 | ✅ | `_authenticateAndNavigate()` → `router.go('/')` |

**结论: ✅ 全流程顺畅**

---

## 2. 数据持久化验证

### 2.1 画布持久化

| 场景 | 状态 | 说明 |
|------|------|------|
| 新建 → 画一笔 → 保存 → 关闭 → 重新打开 | ✅ | `StorageService().saveJson()` → SHA-256 哈希 → `loadJson()` 验证完整性 |
| 自动保存 | ✅ | 800ms 防抖 → `_saveNow()` → JSON 序列化 → 写入文件 |
| 返回时保存 | ✅ | `WillPopScope.onPopInvokedWithResult` → `_saveNow()` |
| 文件格式 | ✅ | JSON + SHA-256 哈希 + `.bak` 备份 |

**结论: ✅ 持久化完整**

### 2.2 笔记持久化

| 场景 | 状态 | 说明 |
|------|------|------|
| 新建 → 打字 → 保存 → 关闭 → 重新打开 | ✅ | `NoteDocument.toJson()` → `StorageService().saveJson()` |
| 自动保存 | ✅ | 800ms 防抖 → `saveNoteDocument()` → JSON 序列化 |
| NoteParagraph 序列化 | ✅ | `toJson()/fromJson()` 支持 id, content, type |
| 磁盘恢复 | ✅ | `_loadNoteFromDisk()` 异步加载，try-catch 保护 |

**结论: ✅ 持久化完整**

### 2.3 设置持久化

| 场景 | 状态 | 说明 |
|------|------|------|
| 主题模式切换 | ✅ | `themeModeProvider` → SharedPreferences 持久化 |
| 重启后保持 | ✅ | Provider 初始化时读取 SharedPreferences |

**结论: ✅ 设置持久化正常**

### ⚠️ 2.4 删除 → 回收站 → 恢复

| 场景 | 状态 | 说明 |
|------|------|------|
| 删除画作 | ✅ | `_deleteDrawing()` → `_confirmDelete()` → `_docStorage.delete()` |
| 回收站入口 | ✅ | `_showTrashDialog()` → `_docStorage.getTrash()` |
| 恢复 | ✅ | `_docStorage.restoreTrash()` → `_refresh()` |
| 永久删除 | ✅ | `_docStorage.deleteTrashPermanently()` |
| 清空回收站 | ✅ | `_docStorage.purgeTrash()` |
| ⚠️ 笔记本回收站 | ❌ | `_deleteNotebook()` 调用 `_nbStorage.delete()` — **永久删除，无回收站** |
| ⚠️ 策略门禁 | ⚠️ | `PolicyEngine().check('note.delete')` 可能拒绝删除操作 |

**结论: ⚠️ 笔记本删除是永久删除（无回收站），画作删除有回收站**

---

## 3. 导出功能端到端

### 3.1 导出功能可用性

| 导出类型 | 状态 | 说明 |
|----------|------|------|
| 画板 → PDF | ✅ | `CanvasPdfExporter` — 将 `List<Stroke>` 渲染到 PDF 页面 |
| 笔记 → PDF | ✅ | `NotePdfExporter` — 将 `NoteDocument` 渲染到 PDF 页面 |
| 多页 → PPT | ✅ | `PptxExporter` — 使用 `dart_pptx` 生成 PPTX 文件 |
| 画板 → PNG | ✅ | `CanvasImageExporter` — Canvas 渲染为 PNG |
| 旧版 V1 导出 | ✅ | `editor_page_actions.dart` 提供完整的导出 UI（按钮/对话框/保存路径选择） |
| V2 编辑器导出 | ❌ | **V2 编辑器 (`EditorV2Screen`) 没有导出 UI** |

### 3.2 ⚠️ V2 编辑器缺少导出入口

**根因**: `EditorV2Screen` 的 AppBar 和工具栏中没有导出按钮。导出功能仅在旧版 V1 编辑器 (`EditorPage`) 的菜单中实现。

**影响**: 用户使用 V2 编辑器创建的画布/笔记无法导出。

**修复建议**: 在 V2 编辑器的更多菜单中添加导出入口，复用 `CanvasPdfExporter` / `NotePdfExporter`。

### 3.3 导出路径选择

| 场景 | 状态 | 说明 |
|------|------|------|
| 路径选择对话框 | ✅ | `FilePicker.platform.getDirectoryPath()` |
| 保存到选择的目录 | ✅ | 使用 `File(path).writeAsBytes()` |
| 文件命名 | ✅ | 自动生成带时间戳的文件名 |
| 导出失败提示 | ⚠️ | V1 有 `showErrorSnackBar`，V2 缺少 |

---

## 4. 加密功能端到端

### 4.1 密码盘创建/解锁流程

| 步骤 | 状态 | 说明 |
|------|------|------|
| 选择目录 | ✅ | `FilePicker.platform.getDirectoryPath()` |
| 输入 PIN | ✅ | 最小 6 位，`TextEditingController` |
| 创建 key.frogkey | ✅ | `PasswordDisk.createKeyFile()` → 随机 256 位密钥 |
| Argon2id 哈希 | ✅ | `EncryptionService.hashPinWithArgon2()` → t=3, m=64MiB |
| 恢复密钥生成 | ✅ | `RecoveryKeyGenerator.generate()` → 24 位 |
| 解锁 | ✅ | `PasswordDisk.readKeyFile()` → `AuthGuard.authenticate()` |
| 恢复密钥解锁 | ✅ | `EncryptionService.decryptMasterKey()` → 恢复主密钥 |

**结论: ✅ 加密流程完整**

### 4.2 加密文件验证

| 场景 | 状态 | 说明 |
|------|------|------|
| 加密后文件内容为密文 | ⚠️ | `EncryptionService` 已实现，但未在保存流程中自动调用 |
| 自动加密 | ⚠️ | 当前无自动加密机制，需用户手动启用 |
| AuthGuard 检查 | ✅ | 路由重定向检查 `AuthGuard.instance.passwordDiskExists && !isAuthenticated` |

**结论: ⚠️ 加密框架已建，但未自动集成到保存流程**

### 4.3 错误处理

| 场景 | 状态 | 说明 |
|------|------|------|
| 密码输入错误 | ✅ | PasswordDiskPage 显示错误提示 |
| key 文件损坏 | ✅ | `.bak` 备份恢复 |
| 目录不存在 | ✅ | `FileSystemException` 捕获并提示 |

---

## 5. 异常流程

### 5.1 错误处理覆盖

| 场景 | 状态 | 说明 |
|------|------|------|
| 打开不存在的文档 | ✅ | `_openDrawing()` → `_docStorage.load()` → null 检查 → `_showSnack('文件不存在')` |
| 存储失败 | ✅ | `_showSnack()` 显示错误消息，不崩溃 |
| 密码输入错误 | ✅ | PasswordDiskPage 显示 "PIN 不正确" 提示 |
| 导出失败 | ⚠️ | V1 编辑器有 `showErrorSnackBar`，V2 编辑器没有 |
| 网络错误 | N/A | 无网络功能 |
| GoRouter 404 | ✅ | `CustomErrorPage` + `NotFoundPage` |

### 5.2 错误恢复

| 场景 | 状态 | 说明 |
|------|------|------|
| 重试机制 | ✅ | 首页加载失败有 "重试" 按钮 |
| 文件损坏恢复 | ✅ | `.bak` 备份机制 — SHA-256 哈希验证 → 主文件损坏时自动恢复备份 |
| 崩溃恢复 | ⚠️ | 无崩溃报告或自动恢复机制 |

---

## 6. 性能体验

### 6.1 页面加载

| 场景 | 状态 | 说明 |
|------|------|------|
| 首页加载 | ✅ | `_refresh()` 异步加载文档和笔记本列表 |
| 编辑器打开 | ✅ | `Future.microtask(() => ...)` 异步初始化，不阻塞 UI |
| 搜索索引构建 | ✅ | 有加载指示器，可中断 |
| 首次启动引导 | ✅ | `OnboardingService().showIfFirstLaunch()` → try-catch 保护 |

### 6.2 列表性能

| 场景 | 状态 | 说明 |
|------|------|------|
| 首页列表 | ✅ | `ListView.builder` 懒加载 |
| 时间线列表 | ✅ | `ListView.builder` 懒加载 |
| 回收站列表 | ✅ | `ListView.builder` 懒加载 |

### 6.3 绘画性能

| 场景 | 状态 | 说明 |
|------|------|------|
| 笔画渲染 | ✅ | `CanvasPainterV2` 使用 `CustomPainter` |
| 缩放/平移 | ✅ | `InteractiveViewer` 包裹画布 |
| 保存频率 | ✅ | 800ms 防抖，不频繁写磁盘 |

---

## 问题汇总

### ❌ P0 严重问题

| # | 问题 | 影响 | 修复建议 |
|---|------|------|----------|
| 1 | **`_openDrawing()` 使用旧 V1 编辑器 `EditorPage`** | 新建画布用 V2，打开已有画布用 V1，保存路径不一致可能导致数据丢失 | 改为 `EditorV2Screen(documentId: meta.id)` |
| 2 | **V2 编辑器没有导出 UI** | 用户在 V2 编辑器中无法导出 PDF/PNG/PPT | 在 V2 编辑器 AppBar 添加导出菜单项 |

### ⚠️ P1 中等问题

| # | 问题 | 影响 | 修复建议 |
|---|------|------|----------|
| 3 | **笔记本删除无回收站** | 画作有回收站，笔记本直接永久删除 | 为 `NotebookStorage` 添加回收站功能 |
| 4 | **设置页主题 Switch 未接入 ThemeNotifier** | 设置页的主题切换按钮不工作 | 接入 `ref.read(themeModeProvider.notifier)` |
| 5 | **加密未自动集成到保存流程** | 加密框架已建但需要手动启用 | 在保存流程中添加加密检查 |

### ℹ️ P2 轻微问题

| # | 问题 | 影响 | 修复建议 |
|---|------|------|----------|
| 6 | V2 编辑器导出失败时无错误提示 | 用户不知道导出是否成功 | 添加 SnackBar 错误提示 |
| 7 | 无崩溃恢复/上报机制 | 崩溃后数据可能丢失 | 添加崩溃日志记录 |

---

## 修复优先级

### 立即修复（P0）
1. **`_openDrawing()` 改为 `EditorV2Screen`** — 防止数据丢失
2. **V2 编辑器添加导出 UI** — 功能完整性

### 尽快修复（P1）
3. 笔记本添加回收站
4. 设置页主题 Switch 接入
5. 加密自动集成

### 可以延后（P2）
6. V2 导出错误提示
7. 崩溃恢复机制

# 安全审计与 Bug 修复报告

> 审计对象：绘图笔记 App（Flutter，Windows + Android）
> 审计日期：2026-08-13
> 审计方式：自动化工具 + 人工逐层代码审查
> 审计范围：全部 7 个 Phase 交付代码（models / engine / storage / ui）

---

## 一、审计结论

对全部代码执行了**六类专项审计**：存储安全、资源管理、异步竞态、
内存管理、UI 边界、正确性回归。共发现 **13 项问题**，全部确认并已修复。

**修复后回归验证：**

| 验证项 | 结果 |
|--------|------|
| 静态检查 `dart analyze` | ✅ 零告警（No issues found） |
| 全部单元测试（53 个） | ✅ 全部通过 |
| Windows 构建 | ✅ 构建成功 |
| Android 构建（APK） | ✅ 构建成功 |

---

## 二、发现项清单（按风险等级排序）

### 🔴 高优先级（3 项）—— 已全部修复

| # | 位置 | 问题描述 | 风险 | 修复方案 |
|---|------|----------|------|----------|
| H1 | `engine/drawing_controller.dart` | `dispose()` 后异步缓存重建完成仍调用 `notifyListeners()`，页面销毁瞬间可能触发"已释放对象"异常 | 崩溃/闪退 | 增加 `_disposed` 标记；dispose 置位；`_rebuildLayer` 重建完成后先检查 `_disposed`，已销毁则释放本次结果并直接返回 |
| H2 | `engine/drawing_controller.dart` | 缓存重建竞态：同一图层连续两次修改时，两次异步重建并发，后发起的先完成或旧图覆盖新图，导致画面显示过期内容 | 数据/显示错误 | 重建完成后检查 `cache.dirty` 是否仍为 true（期间又有新变更），是则放弃本次结果，交由下一次重建 |
| H3 | `ui/pages/editor_page.dart` | 多指手势中 `_onPointerUp()` 无参数签名，无法按 pointerId 移除指针，抬起一指会清空全部指针状态，导致剩余手指状态错乱 | 交互异常 | 回调改为传入 `PointerUpEvent`/`PointerCancelEvent`，按 `event.pointer` 精确移除；剩余 ≥2 指时重新校准捏合基准 |

### 🟡 中优先级（6 项）—— 已全部修复

| # | 位置 | 问题描述 | 风险 | 修复方案 |
|---|------|----------|------|----------|
| M1 | `engine/drawing_controller.dart` | `_rebuildCacheMap()` 用 `removeWhere` 移除图层缓存时**未释放其 ui.Image 位图**，撤销/重做恢复图层时反复泄漏 GPU 内存 | 内存泄漏 | 先收集被移除的 key，再逐个 `_caches.remove(key)?.dispose()` |
| M2 | `engine/drawing_controller.dart` | 撤销历史栈无上限，长时间会话内存无限增长 | 内存膨胀 | 增加 `maxHistoryEntries = 60` 上限，超出丢弃最旧记录并校正指针 |
| M3 | `storage/storage_service.dart` | 删除画作时**不同步删除缩略图**，磁盘残留孤儿文件 | 磁盘垃圾 | `delete()` 中同时删除对应缩略图（尽力而为） |
| M4 | `storage/notebook_storage.dart` | 删除笔记本时**未清理页面引用的图片副本**（注释声称清理但实现缺失） | 磁盘垃圾 | 新增 `_deleteAssociatedImages()`：删除前读取笔记本收集图片路径并逐个删除 |
| M5 | `ui/pages/editor_page.dart` | 自动保存无并发保护：防抖 Timer 触发与 dispose 兜底保存可能并发写同一文件 | 写冲突/文件损坏风险 | 增加 `_autosaving` 标志，保存执行期间跳过重入 |
| M6 | `storage/notebook_storage.dart` | `storeImage` 扩展名直接取自源文件（未校验），任意扩展名可入库 | 文件类型污染 | 扩展名白名单（png/jpg/jpeg/gif/webp/bmp/svg/heic 等），不匹配回退 png |

### 🟢 低优先级（4 项）—— 已全部修复

| # | 位置 | 问题描述 | 风险 | 修复方案 |
|---|------|----------|------|----------|
| L1 | `storage/storage_service.dart` | 文档 ID 直接拼接文件路径，未做字符白名单校验（防御性边界缺失） | 潜在路径遍历 | `isValidId()` 白名单校验（仅字母/数字/下划线），非法 ID 触发 assert |
| L2 | `storage/notebook_storage.dart` | 笔记本/pageId 直接拼接路径，未做校验（同上） | 潜在路径遍历 | 同上，`isValidId()` + `storeImage` 入口校验 |
| L3 | `engine/drawing_controller.dart` | `pickColorAt()`/`renderToPng()` 在 `toByteData` 抛异常时位图未释放（原实现 dispose 在 try 内、finally 只释放 picture） | 异常路径泄漏 | 改为 `ui.Image? image` + try/finally 统一释放 |
| L4 | `engine/drawing_controller.dart` | `dispose()` 可被重复调用 | 防御性 | 幂等：`if (_disposed) return;` |

---

## 三、审计过程说明

### 1. 存储层审计（M3/M4/M6/L1/L2）
- 检查点：路径拼接安全、ID 注入、原子写入、删除完整性、文件损坏容错。
- 结论：原子写入（tmp+rename）设计正确；损坏文件在列表读取时被跳过（不中断）；
  删除完整性存在 M3/M4 缺口，已补。

### 2. 资源管理审计（M1/L3/L4）
- 检查点：全部 `ui.Image`、`Picture`、`PictureRecorder` 的创建与释放配对。
- 结论：逐条核对后确认 `LayerCompositor.rasterize`、`renderToPng`、`pickColorAt`
  的正常路径释放均正确；修复了缓存 map 移除与异常路径两处泄漏。

### 3. 异步竞态审计（H1/H2/M5）
- 检查点：异步缓存重建顺序、dispose 后异步回调、自动保存并发。
- 结论：确认并修复了三处竞态，全部属于真实可达路径。

### 4. 撤销历史内存审计（M2）
- 结论：历史栈曾无上限；现限制 60 条，超出丢弃最旧。

### 5. UI/交互边界审计（H3）
- 检查点：空安全（`!` 使用点）、越界索引、clamp 范围、mounted 检查。
- 结论：既有代码的 mounted 检查与 clamp 用法正确；修复多指手势指针管理缺陷。

### 6. 正确性回归
- 修复后全部 53 个既有测试通过，未发现修复引入的回归。

---

## 四、未发现问题的方面（审计确认项）

- ✅ **无网络请求**：全部代码不含任何网络 I/O、云 API、账号系统（符合开发计划约束）
- ✅ **无敏感数据**：无凭据、密钥、个人隐私数据存储
- ✅ **原子写入**：所有文件保存采用"临时文件 + rename"防止写中断损坏
- ✅ **文件损坏容错**：列表读取跳过损坏文件，不影响其他内容
- ✅ **删除确认**：所有删除入口均有二次确认对话框
- ✅ **坐标边界**：视口缩放限制 0.05–20x，混排对象位置 clamp 在画布范围内
- ✅ **渲染资源**：`CanvasPainter` 只读引用位图，不持有（生命周期归控制器）

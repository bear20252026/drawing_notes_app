# 内存占用排查报告（2026-09-06）

## 结论（先看这里）

**1 GB 内存不是单一代码 bug 造成的，而是「引擎基线 + 多处常驻内存策略 + 2 处真泄漏」叠加的结果。**

这个 App 实际是「记事 + 手绘 + 块文档 + 数据库 + 加密保险库 + WebDAV 同步 + 无限画布 + PDF 导出 + 日程 + 演示」的 Flutter Windows 桌面套件（296 个 dart 文件），并非"简单记事+画"。

---

## 一、为什么基线就高（正常，无法靠改小 bug 消除）

Flutter Windows 桌面应用自带：Flutter 引擎 + Skia 渲染 + Dart VM + GPU 上下文，空应用基线就有 **150–300 MB**。这是运行时本身，与业务代码无关。

## 二、业务内存放大器（量级最大，但属设计取舍）

### 1. 每个图层一张全屏离屏位图（最大头）
- `layer_compositor.dart L43`：每张位图长边封顶 `maxBitmapLongEdge = 2048`
- 单层位图 = 2048×2048×4 字节 ≈ **16 MB**；N 个图层常驻 ≈ N × 16 MB
- 这是"画布跟手不卡"的核心设计（重绘只 `drawImage` 一次），是**用内存换帧率**。封顶是最近才加的（L20-23 注释"内存治理"），说明此前单张 A4 画布 ~35 MB 更糟。
- 修复方向：最小化时 / 切到后台时主动 `LayerRenderCache.dispose()` 释放离屏位图，回到前台再懒重建。

### 2. 文档图片解码缓存无 LRU 上限
- `document_image_cache.dart L28` `_images` 是整张 `Map`，**无任何淘汰**，直到关闭文档才 `dispose()`
- 解码上限放宽到 `canvasMaxLongEdge = 4096`（L104-105）→ 单张极端照片解码可达 **64 MB**
- 多图笔记累积很快到几百 MB。
- 修复方向：给 `_images` 加 LRU + 字节上限，按 z 序/可见性优先保活，离屏图片先 `dispose`。

## 三、真实内存泄漏（必须修）

### 3. `StrokePictureCache` LRU 淘汰时不释放原生 Picture
- `stroke_picture_cache.dart L60-62`：
  ```
  if (_entries.length > maxCacheCount) { _entries.removeAt(0); }  // ← 没 dispose()
  ```
- 只有 `invalidate()`（L68-73）才 `e.picture.dispose()`。被淘汰的 `ui.Picture` 持有的 Skia 原生内存**泄漏**，长期绘制持续累积。
- 修复：
  ```
  if (_entries.length > maxCacheCount) { _entries.removeAt(0).picture.dispose(); }
  ```

### 4. 块文档撤销历史 = 100 步 × 全文深拷贝
- `note_block_history.dart L36` `maxSteps = 100`
- `doc_editor.dart L359-366` 已有 500ms 击键合帧（好），但每个 burst 仍 `_history.push(_buildDocFromState())` 压入**整个 NoteBlockDoc 快照**
- 长文档 × 100 步，纯文本数据累积可观。
- 修复方向：长文档场景把 `maxSteps` 降到 30–50，或改增量 diff（与 drawing 侧 `AddStrokeCommand` 同思路）。

## 四、次级放大器

### 5. 首页 IndexedStack 保活 + 全部缩略图常驻
- `home_page_widgets.dart L48` 注释明确：`IndexedStack 保活下卡片 State 不销毁`
- 每张卡 `_thumbBytes`（L32）+ `Image.memory` 解码后 bitmap 常驻
- 笔记本很多时，整屏卡片 + 解码缩略图叠加。

### 6. 绘图撤销栈 60 步
- `drawing_controller.dart L583` `maxHistoryEntries = 60`
- 高频笔画是增量命令（小，OK）；但图层结构操作走 `SnapshotCommand`，持 before+after 两份图层列表（中等开销）。

## 五、建议处理优先级

| 优先级 | 项 | 类型 | 预期收益 |
|---|---|---|---|
| P0 | #3 StrokePictureCache dispose | 真泄漏 | 止住长期增长 |
| P0 | #2 图片缓存 LRU 上限 | 策略+半泄漏 | 砍掉图片大头 |
| P1 | #1 后台释放图层位图 | 策略 | 空载时大幅回落 |
| P1 | #4 历史步数下调/增量 | 策略 | 长文档降载 |
| P2 | #5 缩略图懒加载/释放 | 策略 | 列表多时有感 |

## 六、进一步实锤的验证方法
1. 任务管理器看「工作集」与「GPU 内存」分列 —— GPU 内存高 → 指向 #1/#2 位图。
2. 复现路径：新建多图层画布画几笔 → 内存跳涨（#1）；插入多张大图 → 再涨（#2）；长时间反复绘制 → 缓涨不回落（#3）。
3. 用 Observatory / DevTools 的 Memory 面板看 `dart:ui Image` 与 `Picture` 实例数与 retained size。

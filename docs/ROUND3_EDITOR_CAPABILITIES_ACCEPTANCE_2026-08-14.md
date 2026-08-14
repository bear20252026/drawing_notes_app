# 第三轮核心编辑器能力验收记录

**验收日期：** 2026-08-14  
**适用工程：** `drawing_notes_app`（Flutter 3.44.9 / Dart 3.12.2）  
**目标平台：** Windows、Android

## 验收结论

本轮已完成并验证三项此前缺失的核心闭环：**可消失高亮笔、手绘规则形状识别、独立绘图文档图片导入**。这些能力均已接入编辑器实际手势或工具栏、文档模型、持久化以及导出路径；它们不是仅有图标的占位功能。

| 能力 | 用户可见入口与行为 | 保存与恢复 | 自动化证据 |
|---|---|---|---|
| 可消失高亮笔 | 选择高亮笔后，在上下文栏切换“保存 / 自动消失”；自动消失笔迹约 4 秒以 ease-out 淡出 | 自动消失墨迹不写入图层、历史、文件或导出；保存模式保持原有普通高亮笔行为 | `test/temporary_marker_test.dart` |
| 手绘规则形状 | 使用钢笔或铅笔画出高置信度闭合矩形/椭圆，收笔后自动替换为可编辑规则形状 | 形状写入 `DrawingDocument.shapes`；一次撤销恢复原始手绘笔画，重做再次转形状 | `test/shape_recognizer_test.dart` |
| 独立绘图图片导入 | 绘图文档的图片工具选择本地图片后，将其置于画布中心 | 原文件复制到应用管理目录；路径、位置、尺寸、层级写入工程 JSON；重开后惰性解码并渲染；PNG 导出包含图片 | `test/document_image_persistence_test.dart` |

## 关键设计

> 形状识别采用**保守的、无副作用的几何识别器**。只有闭合、最小尺寸达标且误差低的钢笔或铅笔轮廓才会转为矩形或椭圆；开放线条、高亮笔及低置信度涂鸦一律保留为原笔画。

临时高亮笔在 `DrawingController` 内作为运行时临时队列维护，使用每帧轻量刷新和二次缓出曲线渲染。它不触碰图层和命令栈，因此不会污染保存内容或让“撤销”操作出现不可预期的临时笔迹。

独立绘图的图片元素采用 `DocumentImageItem`，与笔记页 `PageImageItem` 分离，避免模型循环依赖。`StorageService.storeImage()` 对源文件进行受控副本保存，`DocumentCodec` 实际序列化图片集合；控制器按需解码缓存图片，并在释放时销毁原生位图资源。无限画布内容范围和 PNG 导出路径均已纳入图片边界及位图合成。

## 全量质量门禁

已在沙箱中执行以下命令：

```bash
export PATH=/home/ubuntu/flutter/bin:$PATH
cd /home/ubuntu/drawing_notes_app
dart format lib test
dart analyze
flutter test --coverage
```

| 检查项 | 结果 |
|---|---|
| `dart format lib test` | 98 个文件已检查，0 个需要改动 |
| `dart analyze` | **No issues found** |
| `flutter test --coverage` | **186 项全部通过** |

全量运行期间发现两项遗留选区测试仍以“套索外接框中心”为变换锚点进行断言，与现已验收的“实际选中墨迹外接框中心”产品行为不一致。测试已按当前无漂移交互定义更新；缩放与旋转回归均已通过。

## 真机复验清单

Windows 与 Android 上应额外进行以下人工验收：先在绘图文档导入 PNG/JPEG，关闭并重新打开后检查图片位置，并导出 PNG 检查图片是否存在；然后以钢笔快速画矩形与椭圆，验证可撤销回原笔画；最后切换高亮笔“自动消失”，确认笔迹在约 4 秒内平滑消失且重新打开文档后不会出现。

PDF 导入仍依赖目标设备的 PDFium 环境。在 Linux 沙箱，PDF 导入使用注入式渲染后端覆盖服务逻辑；Windows 侧构建前应启用 Developer Mode，最终 PDFium 逐页渲染请在 Windows 或 Android 真机复验。

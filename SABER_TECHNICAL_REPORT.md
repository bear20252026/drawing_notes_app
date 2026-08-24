# Saber 开源笔记应用技术研究报告

> **许可证**: GPL-3.0（可直接复用，需保留原始版权声明）
> **GitHub**: https://github.com/saber-notes/saber
> **报告日期**: 2026-08-24
> **研究者**: 返修-图形取色组

---

## 一、画布渲染引擎

### 1.1 笔触数据结构（Stroke Model）

**核心文件**: `lib/components/canvas/_stroke.dart`

Saber 的笔触系统基于 `perfect_freehand` 库构建，核心数据模型：

| 属性 | 类型 | 说明 |
|------|------|------|
| `points` | `List<PointVector>` | 原始输入点，每个点含 (x, y, pressure) |
| `color` | `Color` | 笔画颜色 |
| `pressureEnabled` | `bool` | 是否启用压力感应 |
| `options` | `StrokeOptions` | perfect_freehand 配置 |
| `pageIndex` | `int` | 所属页面索引 |
| `toolId` | `ToolId` | 工具类型（钢笔/圆珠笔/荧光笔/铅笔等） |

**🔄 可复用代码**:
- `_stroke.dart` - Stroke 基类，含 LOD 双质量系统
- `_circle_stroke.dart` - 圆形笔画
- `_rectangle_stroke.dart` - 矩形笔画
- `packages/sbn/lib/tool_id.dart` - 工具类型枚举

### 1.2 LOD（细节层次）双质量系统

**核心文件**: `lib/components/canvas/_stroke.dart` 第37-46行

Stroke 内部维护两套缓存：
- **低质量路径** (`lowQualityPath`): 缩放 < 0.9 时使用，每4点取1点 + 直线段
- **高质量路径** (`highQualityPath`): 缩放 >= 0.9 时使用，所有点 + 贝塞尔平滑

**🔄 可复用代码**: LOD 渲染策略可直接移植到我们的 CanvasPainterV2

### 1.3 贝塞尔曲线平滑算法

**核心文件**: `lib/components/canvas/_stroke.dart` 第288-298行

```dart
static Path smoothPathFromPolygon(List<Offset> polygon) {
  final path = Path();
  path.moveTo(polygon.first.dx, polygon.first.dy);
  for (int i = 1; i < polygon.length - 1; i++) {
    final p1 = polygon[i];
    final p2 = polygon[i + 1];
    final mid = (p1 + p2) / 2;
    path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
  }
  return path..close();
}
```

**算法**: 对连续多边形顶点取中点，使用二次贝塞尔曲线连接各中点，控制点为原始顶点。

**🔄 可复用代码**: `smoothPathFromPolygon()` 方法可直接用于我们的画笔平滑

### 1.4 各工具差异化平滑参数

**核心文件**: `lib/data/tools/pen.dart` 第114-126行

| 工具 | smoothing | streamline | 特殊配置 |
|------|-----------|------------|----------|
| 钢笔(fountainPen) | 0 | 0.5 | pressureEnabled=true |
| 圆珠笔(ballpointPen) | 0 | 0.5 | pressureEnabled=false |
| 形状笔(shapePen) | 0 | 0 | 完全不做平滑 |
| 荧光笔(highlighter) | 0 | 0.5 | size=50 |
| 铅笔(pencil) | 0 | 0.1 | start/end taper 启用 |
| 激光笔(laserPointer) | 0.7 | 0.7 | 高平滑+高流线化 |

**🔄 可复用代码**: 工具参数配置可直接参考

### 1.5 画布缩放/平移实现

**核心文件**: `lib/components/canvas/interactive_canvas.dart`

基于 Flutter `InteractiveViewer` 修改的自定义版本：
- **缩放范围**: 0.3 - 10.0
- **惯性滑动**: 使用 `FrictionSimulation` 模拟摩擦力
- **鼠标滚轮**: Ctrl+滚轮缩放，普通滚轮平移
- **缩放吸附**: 接近 1.0x 时自动吸附（差值 < 0.05，延迟 200ms）

**🔄 可复用代码**:
- `interactive_canvas.dart` - 无限画布变换引擎
- `canvas_gesture_detector.dart` - 手势协调器
- `canvas_transform_cache.dart` - LRU 变换矩阵缓存

### 1.6 高性能渲染技术

**核心文件**: `lib/components/canvas/inner_canvas.dart` 第106-145行

**双层 CustomPaint 架构**:
```dart
RepaintBoundary(
  child: CustomPaint(
    painter: CanvasBackgroundPainter(...),      // 背景层
    foregroundPainter: CanvasPainter(...),       // 笔画层
    isComplex: true,     // 缓存光栅化结果
    willChange: true,    // 每帧可能变化
  )
)
```

**其他优化**:
- **视口裁剪**: 只渲染当前视口内的页面
- **铅笔 Shader**: 使用 GLSL Fragment Shader 生成铅笔纹理
- **荧光笔 saveLayer**: 按颜色分组，使用 BlendMode.darken/lighten
- **BSON 二进制格式**: 每点 8-12 字节 vs JSON 的 50+ 字节

**🔄 可复用代码**:
- `pencil.frag` - 铅笔 Fragment Shader
- 视口裁剪策略
- shouldRepaint 精细控制逻辑

---

## 二、文件系统和云同步

### 2.1 本地文件管理

**核心文件**: `lib/data/file_manager/file_manager.dart`

**文件格式**:
- `.sbn2` - 主笔记文件（BSON 二进制编码）
- `.sbn` - 旧版 JSON 格式（已弃用）
- `.sba` - ZIP 归档格式（含 .sbn2 + 资源附件）
- `.0`, `.1`, `.2` - 附件文件（数字后缀）
- `.p` - 预览文件

**🔄 可复用代码**: 文件管理器架构可参考

### 2.2 Nextcloud/WebDAV 同步

**核心文件**: `lib/data/nextcloud/saber_syncer.dart`

**同步架构**:
- 基于 `abstract_sync` 库
- 本地优先：所有编辑先保存到本地，异步同步到云端
- 增量同步：仅同步已变更的文件

**WebDAV 操作**:
- `PROP find` - 获取文件元数据
- `PUT` - 上传文件
- `MKCOL` - 创建目录
- `GET` - 下载文件

**🔄 可复用代码**: 同步架构设计可参考

### 2.3 冲突解决机制

**核心算法**: `getBestFile()` 方法（saber_syncer.dart 第462-505行）

**基于时间戳的版本比较**:
- 容差: 500ms 内视为相等
- 远程更新 → 下载远程版本
- 本地更新 → 上传本地版本

**特殊处理**:
- 预重新同步日期（处理 v0.18.4 之前的上传问题）
- 本地删除跟踪（防止重复操作）

**🔄 可复用代码**: 冲突解决算法可直接参考

### 2.4 加密安全

**核心文件**: `lib/data/nextcloud/nextcloud_client_extension.dart`

**双密码系统**:
1. NC密码 - 登录 Nextcloud 服务器
2. 加密密码 - AES 加密笔记内容

**密钥生成**:
- 加密密码 + 可重现盐值
- SHA-256 生成 32 字节密钥

**🔄 可复用代码**: 加密实现可参考（注意：盐值是硬编码的，生产环境应使用随机盐值）

---

## 三、PDF 处理

### 3.1 PDF 渲染方案

**依赖**: `pdfrx: ^2.4.2`

**核心文件**:
- `lib/components/canvas/image/pdf_document_cache.dart` - PDF 文档缓存
- `lib/components/canvas/image/pdf_editor_image.dart` - PDF 注释渲染

**渲染流程**:
1. `PdfDocumentCache` 维护 `Map<String, FutureOr<PdfDocument>>` 缓存
2. `PdfEditorImage.firstLoad()` 异步加载 PDF 文档
3. `buildImageWidget()` 返回 `PdfPageView` 渲染页面
4. 支持渐进式加载（`useProgressiveLoading: true`）

**🔄 可复用代码**:
- `pdf_document_cache.dart` - PDF 缓存管理
- `pdf_editor_image.dart` - PDF 注释渲染组件

### 3.2 PDF 导入工作流

**核心文件**: `lib/pages/editor/editor.dart` 第1182-1246行

```
用户选择 PDF → FilePicker.pickFile()
→ PdfDocumentCache.load(path)
→ 遍历所有页面
→ 为每个页面创建 PdfEditorImage
→ 添加到 coreInfo.pages
→ 记录历史变更
```

**🔄 可复用代码**: PDF 导入逻辑可直接参考

### 3.3 PDF 导出

**核心文件**: `lib/data/editor/editor_exporter.dart`

使用 `pdf: ^3.8.4` 包，将编辑器页面截图生成 PDF 矢量图。

---

## 四、状态管理和路由

### 4.1 状态管理架构

**模式**: ChangeNotifier + ValueNotifier + Stow（自定义方案）

**无第三方状态管理库**（无 Provider/Bloc/Riverpod）

**核心组件**:
- `Stows` 类 - 全局状态容器（`lib/data/prefs.dart`）
- `EditorCoreInfo` - 笔记核心数据（继承 ChangeNotifier）
- `EditorPage` - 页面数据（继承 ChangeNotifier）
- `EditorImage` - 图像密封类（继承 ChangeNotifier）

**🔄 可复用代码**:
- `Stows` 状态管理系统设计
- ChangeNotifier 模式应用

### 4.2 页面路由

**依赖**: `go_router: ^17.0.0`

**路由定义**: `lib/data/routes.dart`

```
/home/:subpage - 主页（recent/browse/whiteboard/settings）
/edit - 编辑器
/login - 登录
/logs - 日志
```

**🔄 可复用代码**: 路由配置模式可参考

### 4.3 主题/暗色模式

**依赖**:
- `yaru: ^10.2.0` - Linux 风格主题
- `dynamic_color: ^1.5.4` - 动态颜色支持
- `dynamic_yaru: ^0.2.0` - 动态 Yaru 主题

**核心文件**: `lib/components/theming/`

**主题架构**:
- `SaberTheme` - 主题创建器
- `YaruBuilder` - Linux/iOS/macOS 平台主题
- `DynamicMaterialApp` - 主题应用包装器

**🔄 可复用代码**:
- `adaptive_*.dart` - 自适应组件系列（图标/对话框/开关/文本框等）
- `saber_theme.dart` - 主题创建逻辑
- `yaru_builder.dart` - 平台主题适配

---

## 五、平台特定代码

### 5.1 平台检测与条件代码

**使用 `dart:io` 的 `Platform` 类检测平台**

关键检测点:
- 桌面平台初始化窗口管理器
- 移动平台启用后台同步和共享意图
- iOS 不监视根目录变化（性能考虑）

**🔄 可复用代码**: 平台检测模式可直接参考

### 5.2 原生插件

#### OnyxSDK Pen（Android 专属）

**位置**: `packages/onyxsdk_pen/`

**用途**: 为 Onyx 电子墨水设备提供高性能触控笔响应优化

**平台通道实现**:
- 通道名: `"onyxsdk_pen"`
- 方法: `isOnyxDevice()`
- PlatformView: `"onyxsdk_pen_area"`

**🔄 可复用代码**: 如果需要支持 Onyx 设备，可直接复用

#### 其他插件依赖

- `window_manager` - 桌面窗口管理
- `flutter_sharing_intent` - 移动端分享意图
- `workmanager` - 后台任务
- `flutter_secure_storage` - 安全存储
- `nextcloud` - Nextcloud 集成
- `sentry_flutter` - 错误监控

### 5.3 平台特定实现

#### Android
- Edge-to-edge 显示
- 多 ABI 支持
- 文件类型 Intent 过滤器
- 自动语言切换

#### iOS
- 最小后台获取间隔: 12小时
- 支持文档浏览器
- 多方向支持
- 禁用端到端加密要求

#### macOS
- 窗口关闭时退出应用
- 安全可恢复状态

#### Windows
- 1280x720 默认窗口
- C++17 标准

#### Linux
- GTK+ 3.0
- Flatpak/Snap 打包支持

---

## 六、可直接复用的代码清单

### ⭐ 高优先级（核心功能）

| 文件/函数 | 用途 | 许可证要求 |
|-----------|------|------------|
| `lib/components/canvas/_stroke.dart` | Stroke 数据模型 + LOD 系统 | 保留 GPL-3.0 声明 |
| `_stroke.smoothPathFromPolygon()` | 贝塞尔曲线平滑 | 保留 GPL-3.0 声明 |
| `lib/components/canvas/interactive_canvas.dart` | 无限画布变换引擎 | 保留 GPL-3.0 声明 |
| `lib/components/canvas/canvas_gesture_detector.dart` | 手势协调器 | 保留 GPL-3.0 声明 |
| `lib/components/canvas/inner_canvas.dart` | 双层 CustomPaint 架构 | 保留 GPL-3.0 声明 |
| `shaders/pencil.frag` | 铅笔 Fragment Shader | 保留 GPL-3.0 声明 |

### ⭐ 中优先级（增强功能）

| 文件/函数 | 用途 | 许可证要求 |
|-----------|------|------------|
| `lib/data/tools/pen.dart` | 工具参数配置 | 保留 GPL-3.0 声明 |
| `lib/data/tools/stroke_properties.dart` | StrokeOptions 配置 | 保留 GPL-3.0 声明 |
| `lib/components/canvas/image/pdf_editor_image.dart` | PDF 注释渲染 | 保留 GPL-3.0 声明 |
| `lib/components/canvas/image/pdf_document_cache.dart` | PDF 缓存管理 | 保留 GPL-3.0 声明 |
| `lib/components/theming/adaptive_*.dart` | 自适应组件系列 | 保留 GPL-3.0 声明 |

### ⭐ 参考实现（设计模式）

| 模块 | 参考文件 | 借鉴点 |
|------|----------|--------|
| 文件同步 | `saber_syncer.dart` | 时间戳冲突解决算法 |
| 加密 | `nextcloud_client_extension.dart` | AES 加密实现（需改进盐值） |
| 状态管理 | `prefs.dart` (Stows) | 全局状态容器设计 |
| 路由 | `routes.dart` + `main.dart` | go_router 配置模式 |
| 主题 | `saber_theme.dart` + `yaru_builder.dart` | 平台主题适配 |

---

## 七、技术亮点总结

### 1. 渲染性能优化
- LOD 双质量系统：缩小用低质量，放大用高质量
- 视口裁剪：只渲染可见页面
- Fragment Shader：铅笔纹理 GPU 加速
- BSON 二进制格式：文件体积缩小 5-6 倍

### 2. 手势处理
- 惯性滑动：FrictionSimulation 模拟摩擦力
- 缩放吸附：接近 1.0x 时自动吸附
- 手势区分：绘制 vs 平移 vs 缩放 vs 旋转

### 3. 跨平台适配
- 自适应组件系列（adaptive_*）
- 平台检测 + 条件初始化
- 原生插件支持特殊设备（Onyx）

### 4. 数据安全
- 端到端 AES 加密
- 本地优先 + 增量同步
- 时间戳冲突解决

---

## 八、对我们项目的参考价值

### 直接借鉴
1. **Stroke 模型 + LOD 系统** → 改进我们的画笔渲染性能
2. **smoothPathFromPolygon()** → 替换我们现有的贝塞尔平滑
3. **InteractiveCanvasViewer** → 改进我们的无限画布实现
4. **双层 CustomPaint** → 优化我们的画布渲染架构
5. **铅笔 Fragment Shader** → 添加铅笔工具效果

### 设计模式参考
1. **时间戳冲突解决** → 用于我们的云同步
2. **Stows 状态管理** → 用于我们的全局配置
3. **自适应组件系列** → 用于我们的跨平台 UI

### 注意事项
- GPL-3.0 要求衍生作品也必须开源
- 复用代码时必须保留原始版权声明
- 盐值等敏感配置应改进（使用随机盐值）
- 测试覆盖需要自行补充

---

*报告完成。所有可复用代码已标注，保留原始 GPL-3.0 版权声明。*

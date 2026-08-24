# Saber 开源笔记应用源码研究报告

> 研究时间：2026-08-24
> 项目：https://github.com/saber-notes/saber
> 许可证：GPL-3.0（我们项目同为开源，可直接照搬，保留版权声明即可）

---

## 一、文件存储与数据持久化

### 存储方案

Saber 使用自研的 **Stow** 库系列进行持久化（非 Isar/Hive/SQLite）：

| 库 | 用途 |
|---|---|
| `stow` (v0.6.0) | 通用持久化 |
| `stow_plain` (v0.6.0) | 明文存储 |
| `stow_secure` (v0.7.0) | 加密安全存储 |
| `stow_codecs` (v1.4.0) | 编解码器 |

核心类型：
- `PlainStow<T>` — 通用值持久化
- `SecureStow` — 凭证/密钥安全存储（Keychain/Keystore）
- `TransformedStow<T_in, T_out>` — 带序列化转换的包装器

### 文件格式

| 格式 | 说明 |
|---|---|
| `.sbn2` | 当前格式，BSON 二进制序列化 |
| `.sbn` | 旧版 JSON 格式（向后兼容） |
| `.sba` | ZIP 归档格式（含资产文件） |
| `.sbn2.N` | 资产文件（图片/笔画等媒体） |
| `.sbn2.p` | 预览图 |
| `.sbe` | AES 加密后的远程同步文件 |

**.sbn2 序列化结构**：
```dart
{
  'v': 19,           // sbn 版本号
  'ni': nextImageId, // 下一个图片 ID
  'b': backgroundColor, // 背景色 ARGB32
  'p': pattern.name, // 背景图案
  'l': lineHeight,   // 行高
  'z': pages,        // 页面列表
  'c': initialPageIndex
}
```

### 文件组织
```
App/Documents/Saber/
├── 笔记1.sbn2          # 主 BSON 文件
├── 笔记1.sbn2.0        # 资产文件（图片）
├── 笔记1.sbn2.1        # 资产文件（笔画）
├── 笔记1.sbn2.p        # 预览图
├── 文件夹1/
│   └── 笔记2.sbn2
└── ...
```

### 关键文件

| 文件路径 | 功能 |
|---|---|
| `lib/data/editor/editor_core_info.dart` | 笔记核心数据模型（15+ 字段，BSON 序列化） |
| `lib/data/editor/page.dart` | 页面数据模型（strokes/images/quill） |
| `lib/data/file_manager/file_manager.dart` | 文件管理器（路径操作/资产文件） |
| `lib/data/prefs.dart` | 用户偏好存储（50+ Stow 字段） |
| `lib/data/codecs/base64_codec.dart` | Base64 编解码 |
| `lib/data/nextcloud/saber_syncer.dart` | WebDAV 同步核心 |

---

## 二、绘图/手写引擎

### 架构分层

```
笔触数据层 → 笔触生成层 → 手势检测层 → 渲染层 → 画布合成层
```

### 核心依赖

| 包 | 版本 | 用途 |
|---|---|---|
| `perfect_freehand` | ^2.5.1 | 手写输入点 → 平滑笔触多边形 |
| `one_dollar_unistroke_recizer` | ^1.1.1 | 形状识别（直线/矩形/圆形/三角/星形） |
| `onyxsdk_pen` | 本地包 | Onyx 电子墨水屏硬件笔 |

### 笔触生成流程（perfect_freehand）

```
原始输入 (PointVector: x, y, pressure)
  → skipPoints() 按质量跳点
  → getStroke() 生成多边形轮廓
  → getPath() 转为 Flutter Path
    - 完成态：quadraticBezierTo 平滑曲线
    - 绘制态：直线段（性能优先）
```

### 双质量 LOD 系统

```dart
enum StrokeQuality(low: 4, high: 1); // 每 N 个点取 1 个
```

- 缩小状态 (`scale < 0.9`)：低质量路径（4 倍抽稀 + 无平滑）
- 正常/放大状态：高质量路径（全量点 + 平滑曲线）

### 各工具配置

| 工具 | 压感 | 大小范围 | 特殊处理 |
|---|---|---|---|
| 钢笔 | 开 | 1-25 | perfect_freehand 默认 |
| 圆珠笔 | 关 | 1-25 | 恒宽无压感 |
| 铅笔 | 开 | 1-15 | GLSL Shader 石墨纹理 + 两端锥形 |
| 荧光笔 | 关 | 10-100 | saveLayer + BlendMode.darken |
| 形状笔 | 关 | — | $1 Unistroke 实时识别 |
| 激光笔 | 关 | — | 双层发光 + 时间驱动渐隐 |
| 橡皮擦 | — | — | 基于笔触的擦除（非像素级） |

### 荧光笔渲染方案

```dart
// 相同颜色共享 saveLayer，darken 混合
canvas.saveLayer(bounds, Paint()
  ..blendMode = BlendMode.darken
  ..color = Color(0x64FFFFFF));  // 白色 39% alpha
// 绘制同色笔触
StrokeRenderer.drawStroke(canvas, stroke, ...);
canvas.restore();
```

### 橡皮擦算法

遍历笔触的 `lowQualityPolygon` 顶点，任一顶点到橡皮擦中心距离 ≤ 半径 → 移除整个笔触。性能优化：根据顶点数跳过检查。

### 关键文件

| 文件路径 | 功能 |
|---|---|
| `lib/components/canvas/_stroke.dart` | 笔触数据模型（点列表/双质量缓存） |
| `lib/components/canvas/_canvas_painter.dart` | CustomPainter 核心渲染器 |
| `lib/components/canvas/inner_canvas.dart` | 内层画布 Widget |
| `lib/components/canvas/canvas_gesture_detector.dart` | 手势检测与压力采集 |
| `lib/components/canvas/interactive_canvas.dart` | 自定义 InteractiveViewer |
| `lib/components/canvas/pencil_shader.dart` | 铅笔 GLSL Shader 加载器 |
| `shaders/pencil.frag` | 铅笔纹理 Fragment Shader |
| `lib/data/tools/_tool.dart` | 工具抽象基类 |
| `lib/data/tools/pen.dart` | 钢笔/圆珠笔实现 |
| `lib/data/tools/pencil.dart` | 铅笔工具 |
| `lib/data/tools/highlighter.dart` | 荧光笔工具 |
| `lib/data/tools/eraser.dart` | 橡皮擦工具 |
| `lib/data/tools/shape_pen.dart` | 形状识别笔 |
| `lib/data/tools/laser_pointer.dart` | 激光笔 |

---

## 三、加密实现

### 双层密钥体系

```
用户密码 + 固定盐值 → SHA-256 → 密码派生密钥（加密数据密钥）
                                      ↓
首次登录 → 随机生成 AES-256 Key + IV → 用密码派生密钥加密 → 上传服务器
                                        → 同时存入 SecureStow（本地 Keychain）
```

### 加密/解密流程

**上传**：本地字节 → AES-256-CBC 加密 → 上传（路径也加密为 .sbe）
**下载**：服务器字节 → AES-256-CBC 解密 → 写入本地

### 加密依赖

| 包 | 用途 |
|---|---|
| `encrypt` ^5.0.1 | AES 加密/解密 |
| `crypto` ^3.0.2 | SHA-256 哈希 |
| `flutter_secure_storage` ^11.0.0 | 安全存储密钥/IV |

### 关键文件

| 文件路径 | 功能 |
|---|---|
| `lib/data/nextcloud/saber_syncer.dart` | 同步核心（加密/解密/WebDAV） |
| `lib/data/prefs.dart` | SecureStow 存储密钥 |

---

## 四、UI/UX 架构

### 状态管理：自研 Stow 系统

不使用 Provider/Riverpod/Bloc，采用自研 Stow 响应式状态管理：
- `Stow` — 基础响应式状态（类似 ValueNotifier）
- 支持 `addListener()` / `.value` 响应式访问
- 支持 Codec 编解码
- 多 isolate 安全（`volatile` 标志）

### Widget 树结构

```
App → SentryWidget → TranslationProvider → GoRouter
  ├── HomePage (文件浏览)
  │   ├── MasonryFiles / GridFolders
  │   └── PreviewCard
  ├── EditorPage (编辑器)
  │   ├── InteractiveCanvas
  │   │   ├── InnerCanvas (背景+前景画家+图片+文本)
  │   │   ├── CanvasGestureDetector
  │   │   └── CanvasPainter
  │   ├── Toolbar (工具栏)
  │   └── EditorPageManager
  └── LoginPage (Nextcloud 登录)
```

### 路由

使用 `go_router`：`/` (主页)、`/editor` (编辑器)、`/login` (登录)

### 关键依赖

| 包 | 用途 |
|---|---|
| `go_router` | 声明式路由 |
| `dynamic_color` | Material You 动态颜色 |
| `flex_color_picker` | 颜色选择器 |
| `flutter_quill` | 富文本编辑 |
| `pdfrx` | PDF 查看 |

---

## 五、可以直接照搬的代码 ✅

> 注意：我们的项目也是开源的，GPL-3.0 代码可直接使用，保留原始版权声明。

| 文件路径 | 功能描述 |
|---|---|
| `lib/components/canvas/_stroke.dart` | 笔触数据模型（点列表/双质量缓存/序列化） |
| `lib/components/canvas/_canvas_painter.dart` | CustomPainter 核心渲染器 |
| `lib/components/canvas/canvas_gesture_detector.dart` | 手势检测、压力采集、缩放平移 |
| `lib/components/canvas/interactive_canvas.dart` | 自定义 InteractiveViewer（绘图/平移手势分类） |
| `lib/components/canvas/pencil_shader.dart` | 铅笔 GLSL Shader 加载器 |
| `lib/components/canvas/inner_canvas.dart` | 内层画布 Widget（背景+前景+图片+文本） |
| `lib/components/canvas/canvas.dart` | 外层画布 Widget |
| `lib/components/canvas/_canvas_background_painter.dart` | 画布背景渲染（纯色/线条/网格/圆点） |
| `lib/components/canvas/_circle_stroke.dart` | 圆形笔触子类 |
| `lib/components/canvas/_rectangle_stroke.dart` | 矩形笔触子类 |
| `lib/components/canvas/canvas_image.dart` | 画布内嵌图片 Widget |
| `shaders/pencil.frag` | 铅笔纹理 Fragment Shader（fbm 噪声） |
| `lib/data/tools/_tool.dart` | 工具抽象基类 |
| `lib/data/tools/pen.dart` | 钢笔/圆珠笔实现 |
| `lib/data/tools/pencil.dart` | 铅笔工具 |
| `lib/data/tools/highlighter.dart` | 荧光笔工具 |
| `lib/data/tools/eraser.dart` | 基于笔触的擦除工具 |
| `lib/data/tools/shape_pen.dart` | 形状识别笔（$1 Unistroke） |
| `lib/data/tools/laser_pointer.dart` | 激光笔（双层发光+渐隐） |
| `lib/data/editor/editor_core_info.dart` | 笔记核心数据模型 |
| `lib/data/editor/page.dart` | 页面数据模型 |
| `lib/data/file_manager/file_manager.dart` | 文件管理器 |
| `lib/data/codecs/base64_codec.dart` | Base64 编解码 |

---

## 六、可以借鉴的架构/设计模式 🔧

| 模式 | 说明 |
|---|---|
| **双质量 LOD 笔触系统** | 同一笔触缓存低/高质量两个版本，缩放时动态切换 |
| **笔触即擦除** | 橡皮擦直接操作笔触级别数据，撤销简单 |
| **荧光笔 saveLayer 合成** | 相同颜色共享 saveLayer + darken，重叠区域自然加深 |
| **GLSL Shader 铅笔纹理** | GPU 生成石墨纹理，缩小时降级为纯色 |
| **手势一次性决策** | ScaleStart 时决定绘图/平移，后续不变 |
| **工具继承体系** | Tool → Pen → Highlighter/Pencil/ShapePen，子类只传配置 |
| **笔触排序插入** | 按工具类型和颜色排序，确保渲染顺序 |
| **点优化去重** | 移除间距 < 0.1 * strokeWidth 的冗余点 |
| **Stow 持久化单例** | 强类型字段 + 自动持久化 + 类型安全 |
| **BSON 序列化** | 二进制格式比 JSON 更高效 |
| **资产文件分离** | 媒体文件与主笔记文件分离存储 |
| **WebDAV 路径加密** | 文件路径 AES 加密 + .sbe 扩展名 |

---

## 七、版权注意事项 ⚠️

### GPL-3.0 核心义务

1. **Copyleft**：衍生作品必须以 GPL-3.0 发布，允许开源项目直接使用
2. **源码公开**：分发二进制时必须提供完整源码
3. **修改声明**：保留原始版权声明，注明修改内容和日期
4. **无担保**：软件按 "AS IS" 提供
5. **专利保护**：贡献者自动授予专利许可

### 版权声明保留格式

```dart
// Copyright (C) 2021-2026 Aditya Khanna / Saber contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// [original file description]
// Modified by [your project] on [date]
// [your modifications]
```

### 依赖包许可证

Saber 的依赖包可能有各自许可证（MIT/Apache/BSD），使用时需逐个检查兼容性。

---

## 八、对 drawing_notes_app 的具体建议 💡

### 1. 绘图引擎
- **直接照搬** Saber 的 `_stroke.dart` 笔触数据模型和 `_canvas_painter.dart` 渲染器
- **直接照搬** `canvas_gesture_detector.dart` 手势处理管道
- **直接照搬** `pencil.frag` 铅笔纹理 Shader
- 保留 `perfect_freehand` 作为笔迹平滑核心

### 2. 文件格式
- **采用 BSON** 而非 JSON（性能更好、二进制支持）
- 参考 Saber 的 `.sbn2` 格式设计，资产文件分离存储
- 实现版本迁移机制（支持从旧格式自动升级）

### 3. 橡皮擦
- 当前我们已有基于笔触的擦除（EraserMode.stroke），与 Saber 方案一致
- 可借鉴 Saber 的顶点跳过优化（根据笔触复杂度跳过检查）

### 4. 荧光笔
- Saber 使用 `BlendMode.darken` + 白色半透明层，我们已改为 `srcOver` + 半透明笔触
- 可参考 Saber 的同色分组 saveLayer 机制，优化渲染性能

### 5. 加密
- 参考 Saber 的双层密钥体系设计，但改进安全性：
  - 使用 PBKDF2/Argon2 替代简单 SHA-256
  - 使用 AES-GCM 替代 AES-CBC（提供认证加密）
  - 为每个用户生成唯一随机盐值
- 参考 `flutter_secure_storage` 进行本地密钥存储

### 6. 状态管理
- 我们已使用 Riverpod，建议继续沿用（比 Stow 更成熟）
- 可参考 Saber 的 `Stow` 模式简化偏好设置的持久化

### 7. 铅笔纹理
- **直接照搬** `pencil.frag` GLSL Shader
- **直接照搬** `pencil_shader.dart` 加载器
- 实现缩小时降级为纯色混合近似的策略

### 8. 形状识别
- **直接照搬** `shape_pen.dart`（$1 Unistroke 识别器集成）
- 可扩展支持更多形状（星形、五边形等）

---

## 九、整体架构对比

| 维度 | Saber | drawing_notes_app |
|---|---|---|
| 持久化 | Stow 自研 | SharedPreferences + 自定义 |
| 文件格式 | BSON (.sbn2) | JSON |
| 绘图引擎 | perfect_freehand | perfect_freehand |
| 状态管理 | Stow (自研) | Riverpod |
| 加密 | AES-CBC + SHA-256 | 框架已建（待完善） |
| 路由 | go_router | Navigator |
| 同步 | Nextcloud WebDAV | 未实现 |
| 许可证 | GPL-3.0 | 开源（兼容 GPL） |

---

*报告完成。建议优先照搬 Saber 的绘图引擎核心文件（stroke/painter/gesture），保留原始版权声明。*

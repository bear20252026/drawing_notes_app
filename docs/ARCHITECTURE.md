# 架构说明（ARCHITECTURE）

> 本文件说明"绘图笔记 App"的分层架构与核心设计决策，
> 供项目负责人（可能非专业开发）理解整体结构。

## 一、总体分层

项目严格遵循三层分离：**UI 层 / 绘图引擎层 / 数据存储层**。
存储层可以整体替换（例如未来接云同步），而不影响绘图逻辑。

```
lib/
├── main.dart                    应用入口（仅装配）
├── app.dart                     根组件：主题 + 路由
├── app_theme_controller.dart    深色模式控制器（持久化用户选择）
│
├── models/                      数据模型层（纯数据，无逻辑依赖）
│   ├── stroke.dart              笔画（点列 + 笔刷参数）
│   ├── layer.dart               图层（笔画列表 + 显隐/透明度）
│   ├── document.dart            画布文档（图层集合 + 尺寸）
│   ├── selection.dart           选区（多边形 + 命中笔画索引）
│   └── notebook.dart            笔记本/页面/文字块/图片块
│
├── engine/                      绘图引擎层（核心逻辑，不依赖 UI）
│   ├── drawing_controller.dart  文档状态机：绘制/撤销/图层/选区/导出
│   ├── stroke_renderer.dart     笔画光栅化（平滑曲线 + 压感宽度）
│   ├── layer_compositor.dart    图层离屏位图合成（性能关键）
│   ├── gesture_math.dart        手势变换纯数学（旋转/缩放/平移，可单测）
│   ├── document_commands.dart   撤销命令类（HistoryEntry/DocCommand 等，R5 拆分）
│   ├── encryption_service.dart  加密服务（AES-256-GCM + PBKDF2 + 密码盘信封）
│   ├── command_registry.dart    命令注册表（快捷键/菜单/工具栏同源）
│   ├── plugin_registry.dart     插件接口（笔刷/工具扩展注册表）
│   └── search_service.dart      全文搜索（文字块 + 标题）
│
├── storage/                     数据存储层（本地文件，可整体替换）
│   ├── storage_service.dart     独立画作：JSON 工程文件 + PNG 缩略图
│   ├── notebook_storage.dart    笔记本：JSON 工程文件 + 图片副本
│   ├── password_disk.dart       U盘密码盘（Real/Mock 双实现 + 依赖注入）
│   ├── repository.dart          仓库接口抽象（Document/NotebookRepository）
│   └── document_codec.dart      编解码（版本化 JSON 格式）
│
└── ui/                          UI 层（页面 + 组件 + 渲染器）
    ├── pages/home_page.dart     首页（画作/笔记本列表、删除确认）
    ├── pages/editor_page.dart   编辑器主页面（手势调度、混排对象）
    ├── pages/notebook_view_page.dart  笔记本页面管理
    ├── pages/password_disk_page.dart  密码盘管理（创建/解锁/恢复/指纹）
    ├── pages/search_page.dart   全文搜索页
    ├── widgets/                 可复用组件
    │   ├── editor_components.dart  编辑器纯展示组件（番茄钟/快捷键/分页/连线）
    │   ├── editor_toolbar.dart     工具栏（状态 + 回调参数化）
    │   ├── editor_statusbar.dart   状态栏（工具/缩放/坐标）
    │   ├── editor_viewmodel.dart   编辑器 ViewModel（工具状态 + 防抖保存，R4）
    │   ├── layer_panel.dart        图层面板
    │   └── color_picker_dialog.dart 色板
    ├── canvas_painter.dart      画布 CustomPainter（含选区高亮 + 小地图）
    ├── onboarding.dart          首次引导
    └── app_theme_controller.dart 深色模式控制器（持久化用户选择）
```

## 二、核心设计决策

### 1. 笔画以"矢量点列"存储

- 每笔 = 一连串采样点（坐标 + 笔压）+ 笔刷参数（颜色/粗细/类型）。
- 不直接写死在位图上 → 撤销/重做、图层合并、任意分辨率导出均无损。
- 存储文件小（JSON），为未来云同步/多设备预留了干净的替换面。

### 2. 图层离屏位图缓存（性能关键）

- 绘制中：只画"正在画的一笔"（矢量路径），保证跟手不卡顿。
- 笔画结束：把该图层的全部笔画合成为一张位图（`PictureRecorder → toImage`），
  此后每帧只需 `drawImage` 一次。
- 任何内容变更（新增笔画/撤销/合并/变换）都会把对应图层标记为脏并重建缓存。
- 橡皮擦使用 `BlendMode.clear` + `saveLayer`，实现真正的"透明擦除"。

### 3. 撤销/重做 = 图层快照

- 每次操作前后保存"各图层笔画列表的拷贝"（`HistoryEntry.before/after`）。
- 优点：不依赖操作类型，笔画/图层/选区/变换全部统一支持撤销。
- 撤销后画新内容会丢弃"重做分支"（与主流绘图软件行为一致）。

### 4. 选区作用于笔画（矢量级）

- 矩形/套索选区画出一个多边形，命中检测 = 笔画上任意采样点落在多边形内。
- 选中后可移动/缩放/旋转/复制/粘贴/删除，全程走撤销历史。
- 与 CSP 等软件的"矢量图层"行为一致，天然支持无损缩放。

### 5. 自动保存（防抖）

- 编辑器在每次变更后安排 800ms 防抖定时器，连续操作结束后落盘一次。
- 退出页面时再兜底保存一次，最大限度避免数据丢失。
- 独立画作 → 工程文件 + 缩略图；笔记本页面 → 由上级页面保存整个笔记本。

### 6. 存储格式（版本化 JSON）

```
{ "version": 1, "document": { id, title, width, height, createdAt,
  updatedAt, layers: [ { id, name, visible, opacity, strokes: [...] } ] } }
```

- 原子写入：先写 `.tmp` 临时文件再重命名，防止写入中断损坏文件。
- 损坏文件在列表读取时被跳过，不影响其他内容。

## 三、手势与交互流

| 操作 | 处理 |
|------|------|
| 单指/鼠标拖动 | 绘制笔画（按下 start → 移动 extend → 抬起 end） |
| 双指捏合 | 缩放画布（两指距离比 → viewScale） |
| 双指旋转 | 旋转画布（两指连线角度差 → viewRotation） |
| 吸管工具点击 | 读取合成位图像素 → 更新画笔颜色 |
| 选区工具拖动 | 画矩形/套索 → 命中检测 → 变换控制条 |
| 文字工具点击 | 弹出输入框 → 生成文字块（可拖动/编辑/删除） |
| 图片按钮 | 文件选择器 → 复制副本进应用目录 → 生成图片块 |

## 四、测试策略

- 每个 Phase 都有对应测试文件（`test/phaseN_*.dart`），共 53 个用例。
- 测试重点：引擎层纯逻辑（绘制/撤销/选区/视口变换）与存储层（保存/加载/导出）。
- UI 层（按钮点击、对话框）通过双端构建 + 代码评审验证。

## 五、扩展预留

- **云同步**：存储层为独立模块，替换 `StorageService`/`NotebookStorage`
  的实现即可，绘图引擎与 UI 无需改动。
- **更多笔刷**：`BrushType` 枚举 + `StrokeRenderer` 增加渲染分支即可。
- **混合模式/蒙版**：`Layer` 增加字段，`LayerCompositor` 增加合成逻辑。

# 绘图笔记 App · 项目永久方案（Master Plan）

> 文档版本：1.0（2026-08-14）
> 状态：政府级验收标准，持续维护
> 本文件为团队协作的永久权威方案，覆盖：项目概述、进展时间线、完整功能清单、
> 系统架构、技术方向详解、团队协作规范、构建与交付。

---

## 一、项目概述

### 1.1 项目定位
**绘图笔记 App** 是一款面向政府内部使用的**手写绘图 + 笔记**桌面/移动应用。
融合白板（Whiteboard）、笔记（Note-taking）、画图（Drawing）三类工具的核心理念，
支持手写笔迹、文字混排、图形绘制、图表生成、图层管理与加密存储。

### 1.2 技术栈（固定）
| 维度 | 选择 | 说明 |
|---|---|---|
| 框架 | **Flutter / Dart** | 一套代码双端（Windows + Android） |
| 渲染 | CustomPainter + Canvas | 矢量笔画、增量重绘、离屏位图 |
| 数据 | 本地 JSON 工程文件 + PNG 缩略图 | 原子写入（tmp + rename） |
| 加密 | AES-256-GCM + PBKDF2(10万次) | 零知识密码盘（U盘即钥匙） |
| 打包 | fastforge 0.6.12 | Windows 安装包（Inno Setup） |
| 目标平台 | 仅 Windows + Android | 不引入 web/iOS |

### 1.3 核心设计红线（不可违反）
1. **全本地离线**：禁止网络请求、云同步、账号体系、AI 服务、PSD 导出；
2. **数据自主**：工程文件为开放 JSON 格式，可迁移、可编程、无锁定；
3. **可追溯**：每阶段验证（analyze → 测试 → 双端构建 → 冒烟 → 打包）+ git 留痕；
4. **单一职责**：一个文件一个单一逻辑域（红线）；行数 ≤400 仅为警戒闹钟（非法律）；
5. **分层架构**：UI / 引擎 / 数据 / 存储四层分离，存储层可整体替换。

### 1.4 代码规模（截至 2026-08-14）
- lib 源码：**39 个 Dart 文件**（engine 11 / models 5 / storage 6 / ui 17）
- 单元/回归测试：**17 个文件 / 118 用例**
- 集成测试：3 个文件（冒烟 5 / 工具栏 7 / 全链路 2）
- 文档：docs/ 8 篇 + 本 Master Plan

---

## 二、项目进展时间线

### Phase 1 · 画布与手写引擎（基础）
- 无限可绘制画布、画笔/橡皮擦、压感笔刷（速度模拟 + 真实压感）
- Catmull-Rom 平滑曲线渲染、增量脏矩形重建（含 saveLayer 底图修复）
- 多指缩放/旋转、滚轮缩放（锚点不漂移）

### Phase 2 · 基础绘图工具
- 矩形/套索选区、吸管取色、色域选色器（S/V 二维色域 + 色相条）
- 12 色板 + 色阶（ShadeList）+ 最近使用色

### Phase 3 · 图层系统
- 多图层管理、可见性、透明度、置顶/置底
- 离屏位图缓存 + 脏矩形增量重建（重建串行化 + dirty 复查防竞态）

### Phase 4 · 选区与变换
- 笔画选区（矩形/套索）、移动/缩放/旋转已选内容

### Phase 5 · 笔记混排（核心）
- 文字块（就地编辑、待办 checkbox、斜杠命令、便利贴、多行文本+宽度拖拽）
- 图片块（插入/拖动/缩放/裁剪）、形状块（矩形/椭圆/菱形/箭头/直线）
- 图表块（柱状/折线）、节点连线、克隆页、版本历史（上限 8）、标签

### Phase 6 · 文件与存储
- 工程文件 JSON + PNG 缩略图、原子写入（tmp + rename）、崩溃恢复（.bak）
- 导出 PNG / SVG / PDF / JSON / PPTX / 文本（Markdown/TXT）

### Phase 7 · 打磨
- 应用图标、系统深色联动、单实例应用、全屏模式

### 开源借鉴与增强（19 项）
- 层级树+页面克隆、全局标签、时间线视图、版本历史+diff 摘要
- AES-GCM 加密（PBKDF2 加盐 10 万次）、Markdown/文本导入、PDF 导出
- 节点连线/箭头、番茄钟、斜杠命令、宏、命令注册表、插件注册表
- 存储仓库接口抽象、分页预览、全局热键（Ctrl+Alt+N）
- 全文搜索、画布小地图、快捷键帮助面板、撤销命令模式、单实例

### 密码盘（U盘即钥匙，零知识架构）
- 主密钥（256 位随机）只存 U 盘 key.frogkey；应用不持久化任何密钥
- AES-256-GCM 主密钥加密 + 24 位恢复密钥信封（PBKDF2 派生 KEK）
- 军工级：连续 3 次解锁失败锁定 30 秒 + 密钥指纹仪表盘 + 状态动画

### 院士级架构重构（R1-R5）
- R1 纯展示组件外移、R2 工具栏拆分、R3 状态栏 + 手势数学
- R4 EditorViewModel 胶水层（MVVM）、R5 命令类拆分
- 引擎状态机保留聚合（专家决策，写入 ARCHITECTURE_REVISION.md）

### Excalidraw 生态对齐（三期 21 项 + P1-P3 补齐 16 项）
- 一期：SVG 导出、图形工具、形状编辑、对齐分布、样式面板、粘贴识别
- 二期：动画微交互、框选多选、图层顺序、样式刷、网格/吸附/适应画布、右键菜单
- 三期：元素复制粘贴、命令面板（Ctrl+K）、8向缩放+旋转手柄、删除淡出、缩放控件、线样式
- P1：箭头绑定（boundElementId）、多行文本、元素分组（groupId）
- P2：数字快捷键 1-9 + Alt 微调、色阶+自定义色、手型工具、图表、剪贴板 PNG 平台通道
- P3：动画尾迹、元素超链接、统计面板、元素级套索、字体族、手绘粗糙填充、图片裁剪

### UX 修复（最近一轮）
- 画笔压感收窄（连续清晰）、橡皮擦恒宽（擦除干净）
- 形状工具点击不画多余笔画、文字工具显示可见文本框

---

## 三、完整功能清单

### 3.1 画布与导航
| 功能 | 说明 |
|---|---|
| 无限画布 | 开关式，开启后联动适应画布 |
| 缩放/平移 | 滚轮缩放（锚点不漂移）、双指缩放旋转、手型工具拖动画布 |
| 网格显示/吸附 | 20px 网格 + 拖动吸附（可开关） |
| 适应画布 | Fit to Screen（100% / 放大 / 缩小） |
| 画布小地图 | 右下角缩略图，点击/拖动导航 |

### 3.2 工具
| 功能 | 说明 |
|---|---|
| 画笔/橡皮擦 | 压感笔刷（速度模拟 + 真实压感）、橡皮擦恒宽 |
| 吸管取色 | 点击画布取色 |
| 选区 | 矩形/套索（笔画级）+ 元素级套索（混排对象） |
| 框选多选 | 矩形框选多个混排对象，整体拖动/删除 |
| 文字工具 | 点击/双击画布插入文字，就地编辑（可见文本框） |
| 形状工具 | 矩形/椭圆/菱形/箭头/直线，点击画布放置 |
| 图表工具 | 粘贴数值生成柱状/折线图 |
| 连线工具 | 节点间创建连接线（起点橙色高亮） |
| 手型工具 | 拖动画布平移 |

### 3.3 混排对象
| 功能 | 说明 |
|---|---|
| 文字块 | 就地编辑、粗/斜/下划线/删除线、对齐、待办、便利贴、字体族、多行自动换行+宽度拖拽 |
| 图片块 | 插入/拖动/缩放/裁剪（4角手柄 + 重编码） |
| 形状块 | 5 种形状、填充/虚线/手绘、8向缩放+旋转手柄、箭头绑定（boundElementId） |
| 图表块 | 柱状/折线、数值标签 |
| 元素超链接 | href + 右键设置链接 + 点击打开 |
| 元素分组 | groupId 分组/取消分组，同组整体移动/删除 |

### 3.4 图层与组织
| 功能 | 说明 |
|---|---|
| 图层面板 | 常驻内嵌，可见性/透明度/顺序 |
| 图层顺序 | 置顶/置底/上移/下移（右键 + 菜单） |
| 层级树 | 页面层级 + 克隆页（CloneRef） |
| 标签系统 | 全局标签 |
| 版本历史 | 每页上限 8 版，深拷贝快照 + diff 摘要 |

### 3.5 数据与安全
| 功能 | 说明 |
|---|---|
| 工程文件 | JSON 开放格式 + PNG 缩略图，原子写入 |
| 崩溃恢复 | .bak 备份 + 损坏自动回退 |
| 加密 | AES-256-GCM + PBKDF2(10万次)，密码/密码盘双模式 |
| 密码盘 | U盘即钥匙（key.frogkey），恢复密钥信封，3 次失败锁定 30 秒 |
| 单实例 | 尽力而为锁（不静默退出） |

### 3.6 检索与时间线
| 功能 | 说明 |
|---|---|
| 全文搜索 | 搜索笔画/文字/标签，防陈旧响应 |
| 时间线视图 | 按时间浏览，条目可点击跳转 |

### 3.7 导出
| 功能 | 说明 |
|---|---|
| PNG / SVG / PDF / JSON / PPTX / 文本 | 全部可导出到文件 |
| 剪贴板 PNG | Windows CF_DIB 平台通道 |

### 3.8 演示与 UI
| 功能 | 说明 |
|---|---|
| 幻灯片演示 | 全屏逐元素展示（键盘/点击导航） |
| 命令面板 | Ctrl+K 可搜索全部命令 |
| 快捷键 | 1-9 切工具、Ctrl+Z/Y/B/I/E/C/V/D/K、Alt+方向键微调 |
| 主菜单 | 右上角汉堡菜单（导出/演示/图表/图书馆/无限画布/统计/快捷键） |
| 右侧属性面板 | 画笔颜色/粗细、形状样式（线宽/透明度/填充/虚线/手绘）、文字样式（字号/颜色/字体） |
| 统计面板 | 笔画/文字/图片/形状/图表/合计 |
| 深色模式 | 系统联动 + 手动切换 |
| 右键菜单 | 复制样式/分组/链接/删除/置顶/置底 |

---

## 四、系统架构

### 4.1 四层分层 + MVVM 胶水层（架构铁律）
```
┌─────────────────────────────────────────────┐
│  UI 层（lib/ui/）                           │
│   pages（编辑器/主页/笔记本/搜索/密码盘/演示） │
│   widgets（工具栏/状态栏/属性面板/组件/ViewModel）│
├─────────────────────────────────────────────┤
│  引擎层（lib/engine/）                       │
│   drawing_controller（状态机）              │
│   stroke_renderer / layer_compositor        │
│   command_registry / document_commands      │
│   encryption_service / search_service       │
│   gesture_math / shape_library / plugins    │
├─────────────────────────────────────────────┤
│  数据层（lib/models/）                      │
│   document / layer / stroke / notebook / selection │
├─────────────────────────────────────────────┤
│  存储层（lib/storage/）                     │
│   repository（抽象，可整体替换）             │
│   notebook_storage / storage_service        │
│   password_disk / document_codec            │
└─────────────────────────────────────────────┘
```
**分层铁律**：UI 不直接触碰 File / canvas / 计时器；引擎不依赖 UI；
存储层通过 repository 抽象隔离，可整体替换（本地 → 未来任何后端）。

### 4.2 MVVM 胶水层（EditorViewModel，R4 落地）
- `editor_viewmodel.dart`（~220 行）：统一持有工具状态（吸管/文字/连线/选区完成）
  与 800ms 防抖保存调度，ChangeNotifier 通知；
- View 只负责显示与手势，字段经 getter 委托、赋值经 setter；
- 效果：editor_page 瘦身，UI 与业务解耦，可单测。

### 4.3 命令模式（撤销/重做）
- `DocCommand` 抽象 + `AddStrokeCommand`（零拷贝逆操作）+ `SnapshotCommand`（低频快照桥接）；
- 历史上限 60；笔画级即时撤销，混排对象级快照兼容；
- 与引擎状态机（drawing_controller 874 行，保留聚合）通过公开包装方法
  （restoreLayersSnapshot / touchDocument / afterStrokeUndoRedo）交互。

### 4.4 目录结构与职责（源码清单 39 文件）
| 目录 | 文件 | 职责 |
|---|---|---|
| lib/engine/ | drawing_controller（状态机）、stroke_renderer（渲染）、layer_compositor（合成）、document_commands（命令）、command_registry（注册表）、plugin_registry（插件）、encryption_service（加密）、search_service（搜索）、gesture_math（数学）、shape_library（形状库） | 核心业务逻辑 |
| lib/models/ | document、layer、stroke、notebook、selection | 纯数据模型 + 序列化 |
| lib/storage/ | repository（抽象）、notebook_storage、storage_service、password_disk、document_codec | 持久化与安全 |
| lib/ui/pages/ | editor_page、home_page、notebook_view_page、search_page、password_disk_page、presentation_page | 页面 |
| lib/ui/widgets/ | editor_toolbar、editor_left_toolbar、editor_statusbar、editor_components、properties_panel、layer_panel、editor_viewmodel、color_picker_dialog | 组件与胶水层 |
| lib/ui/ | canvas_painter、onboarding、app、app_theme_controller | 画布渲染/引导/主题 |
| lib/main.dart | 入口 | 单实例锁 + 应用启动 |

### 4.5 渲染管线（性能核心）
- **矢量笔画**：Catmull-Rom 平滑曲线（张力 0.5），逐点压感变宽分段渲染；
- **增量脏矩形重建**：笔画绘制后仅重绘脏区域并烧入离屏底图（saveLayer 兜底 + clipRect 限定），
  重建串行化 + dirty 复查防竞态；
- **手绘风格**：seeded 顶点抖动 + 双重描边 + rough 阴影线填充（可开关）；
- **帧合并**：frameTick / notifyListeners 双通道，视口变换仅高频重绘画布层。

---

## 五、技术方向详解

### 5.1 渲染与画布
- **CustomPainter + Canvas**：全部绘制自研（无第三方渲染依赖）；
- **Catmull-Rom**：通过相邻控制点构造三次曲线，比二次贝塞尔更圆润；
- **脏矩形**：strokeBounds 含线宽余量 + Catmull-Rom 过冲余量（0.167×最大间距），
  防快速笔画末端被裁剪烧入底图；
- **手绘（rough.js 思路）**：math.Random(seed) 稳定抖动 ±2px + 双重偏移描边，
  rough 填充用 clipPath + 斜线阴影（hatch）。

### 5.2 压感笔刷
- 触控板/手写笔：真实 `pointer.pressure`（0~1）；
- 鼠标：速度模拟（快→细、慢→粗），范围收窄 `clamp(0.6, 1.0)` 保持笔迹连续；
- 橡皮擦恒宽（不受压感影响）；渲染按每点压力分段变宽。

### 5.3 加密与密码盘（零知识架构）
- **AES-256-GCM**（pointycastle）：认证加密防篡改；
- **PBKDF2-HMAC-SHA256** 加盐 10 万次：抗离线暴力破解；
- **密码盘**：主密钥（256 位 Random.secure）只存 U 盘 key.frogkey（37 字节定长），
  应用不持久化密钥；24 位恢复密钥纸备份 → PBKDF2 派生 KEK → 解密钥信封找回主密钥；
- 军工级：3 次解锁失败锁定 30 秒 + 密钥指纹 + Real/Mock 依赖注入（kDebugMode 切换）。

### 5.4 存储与数据
- **原子写入**：先写 tmp 再 rename，防写一半损坏；.bak 备份 + 损坏自动回退；
- **开放格式**：工程文件 JSON（图层/笔画/混排对象序列化，向后兼容缺省值）；
- **repository 抽象**：DocumentMeta + 仓库接口，存储层可整体替换。

### 5.5 快捷键与命令
- hotkey_manager（全局 Ctrl+Alt+N）+ 应用内 KeyboardListener；
- 命令注册表（可扩展命令集）+ 插件注册表；
- 数字键 1-9 切工具、Ctrl+Z/Y/B/I/E/C/V/D/K、Alt+方向键微调。

### 5.6 构建与打包（Windows）
- 固定 ASCII 镜像 `D:\huaban_build` 构建（中文路径触发 GBK 乱码）；
- C++ 平台通道文件需保存为 GBK 编码（MSVC 代码页 936，避免 C4819 视为错误）；
- flutter_window.h 需 include encodable_value.h / method_channel.h；
- fastforge 0.6.12 打包（Inno Setup），产物 drawing_notes_app-1.0.0+1-windows-setup.exe。

### 5.7 测试体系
- 单元/回归 118 用例（17 文件）：基础 53 + 安全 14 + UX 修复 7 + UX 增强 8 +
  fix 7 + 纸张 3 + 文字 6 + 搜索 2 + 密码盘 6 + keyfile 5 + 密码盘页面 3 + 可用性 4；
- 集成：冒烟 5 + 工具栏 7 + 全链路 2（integration_test/）；
- 每次改动固定流程：dart analyze 零告警 → 全部测试 → 双端构建 → 冒烟 → 打包 → git 提交。

---

## 六、团队协作指南

### 6.1 开发流程（每个功能点固定闭环）
```
1. 理解需求 → 明确功能边界（不做范围外增强）
2. 读相关代码（先读后改，绝不改未读代码）
3. 实现（分层落地：模型 → 引擎 → 存储 → UI）
4. 验证闭环（见 6.2）
5. git 提交（见 6.4）
6. 更新 docs 相关文档（可追溯）
```

### 6.2 验证闭环（政府级严谨，每步全绿才可继续）
| 步骤 | 命令/要求 | 通过标准 |
|---|---|---|
| 1. 静态检查 | `dart analyze`（中文路径下禁用 flutter analyze） | 零告警（error/warning/info 全 0） |
| 2. 单元测试 | `flutter test` | 118 用例全绿 |
| 3. 双端构建 | Windows release + Android APK（镜像 D:\huaban_build） | 双端成功 |
| 4. 冒烟测试 | `flutter test integration_test/smoke_test.dart -d windows` | 5 用例全绿 |
| 5. 打包 | fastforge（Inno Setup） | RELEASE SUCCESSFUL |
| 6. git 提交 | Conventional Commits | 留痕完整 |

### 6.3 工程约束（团队必须遵守）
1. **中文路径陷阱**：主目录 `D:\AI编码工具\画板` 触发构建链路 GBK 乱码，
   固定用 ASCII 镜像 `D:\huaban_build` 构建后同步回主项目；
2. **analyze 命令**：中文路径下 `flutter analyze` LSP 崩溃，固定用 `dart analyze`；
3. **C++ 平台通道**：flutter_window.cpp/.h 必须保存为 GBK 编码（MSVC 代码页 936），
   flutter_window.h 需 include encodable_value.h / method_channel.h；
4. **依赖版本**：hotkey_manager 固定 0.2.3、fastforge 0.6.12；
5. **红线**：禁止网络请求/云同步/账号/AI/PSD 导出；数据全本地。

### 6.4 Git 规范
- 提交信息：Conventional Commits（feat:/fix:/refactor:/docs:），主题英文 + 细节中文；
- 每次功能闭环一个提交；破坏性改动必须说明；
- 每阶段文档更新随代码同提交（可追溯）。

### 6.5 测试体系指南（新增功能必配测试）
| 测试类别 | 位置 | 覆盖 |
|---|---|---|
| 单元/回归 | test/phase*.dart、*_regression_test.dart | 渲染/命令/存储/加密/搜索/文字/密码盘 |
| 可用性回归 | test/usability_regression_test.dart | 用户视角问题回归 |
| 集成-冒烟 | integration_test/smoke_test.dart | 应用启动/主流程 |
| 集成-工具栏 | integration_test/toolbar_test.dart | 7 个工具可用性 |
| 集成-全链路 | integration_test/feature_test.dart | 端到端场景 |

### 6.6 构建与交付（发布流程）
```
1. 主项目全量验证（analyze + 测试）全绿
2. 同步 lib/ + pubspec.yaml + windows/runner 到 D:\huaban_build
3. 镜像内双端构建（Windows release + Android debug APK）
4. 冒烟测试（-d windows）
5. fastforge 打包 → dist/1.0.0+1/drawing_notes_app-1.0.0+1-windows-setup.exe
6. 复制到 D:\绘图笔记App-最新版.exe（字节校验一致）
7. 更新 INSTALL_VERIFICATION.md + 本 Master Plan 进展时间线
```

### 6.7 团队约定
- 每完成一个功能点即向团队同步（验证结果 + 提交号）；
- 遇到架构级决策（拆分/聚合）先写入 ARCHITECTURE_REVISION.md 再实施；
- 安全相关改动必过 SECURITY_AUDIT.md 清单；
- 新增依赖需说明用途并在本文件 5.6/6.3 登记。

---
*（Master Plan 维护：每完成一个阶段更新"二、进展时间线"与版本号；本文件为团队协作唯一权威方案。）*

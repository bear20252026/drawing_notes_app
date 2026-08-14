# 绘图笔记 App（Drawing Notes）

面向 **Windows 桌面 + Android** 的跨平台绘图与笔记应用，使用 **Flutter (Dart)** 开发。
本项目依据《绘图笔记App-完整方案汇编》开发计划实施，全部为本地离线功能，
**不涉及**云同步、账号系统、AI 功能、网络请求。

---

## 功能概览（按开发阶段）

| 阶段 | 内容 | 状态 |
|------|------|------|
| Phase 1 | 最小画布：绘制线条、撤销、清空 | ✅ 完成 |
| Phase 2 | 基础绘图工具：笔粗细、色板、橡皮擦（透明擦除）、吸管 | ✅ 完成 |
| Phase 3 | 图层系统：新建/删除/显隐/透明度/排序/合并 | ✅ 完成 |
| Phase 4 | 选区与变换：矩形/套索选区、移动/缩放/旋转、复制/粘贴/删除 | ✅ 完成 |
| Phase 5 | 笔记功能：笔记本/页面管理、文字输入、图片插入混排 | ✅ 完成 |
| Phase 6 | 文件管理与持久化：自动保存、作品列表缩略图、导出 PNG、删除确认 | ✅ 完成 |
| Phase 7 | 体验打磨：深色模式、双指手势、全屏模式、首次启动引导 | ✅ 完成 |

## 环境要求

- Flutter 3.44.9（Dart 3.12.2）或更高稳定版
- Windows 构建：Visual Studio 2022+（含"使用 C++ 的桌面开发"组件）
- Android 构建：Android SDK（compileSdk 36）+ JDK 17 及以上

## 快速开始

```bash
# 安装依赖
flutter pub get

# Windows 桌面运行
flutter run -d windows

# Android 设备/模拟器运行
flutter run -d android

# 构建产物
flutter build windows --debug
flutter build apk --debug
```

> 说明：本项目目录名为中文（`画板`），Android 构建已在
> `android/gradle.properties` 中设置 `android.overridePathCheck=true` 放行。

## 测试与静态检查

```bash
# 静态检查（本项目用 dart analyze，flutter analyze 的 LSP 通道与中文路径有兼容问题）
dart analyze

# 全部单元/组件测试（覆盖 Phase 1-7 核心逻辑）
flutter test
```

当前共 **74 个测试**，覆盖：
- Phase 1：绘制/撤销/重做/清空/单点墨点
- Phase 2：粗细/颜色/橡皮擦透明擦除/吸管取色
- Phase 3：图层新建/删除/显隐/透明度/排序/合并/撤销
- Phase 4：矩形/套索选区、命中检测、移动/缩放/旋转/复制/粘贴/删除
- Phase 5：笔记本/页面/文字块/图片块模型与存储
- Phase 6：保存/重新加载/缩略图/导出 PNG/删除/列表排序
- Phase 7：视口缩放/平移/旋转坐标换算
- 安全审计回归：14 项（dispose 防护/缓存竞态/位图泄漏/历史上限/路径校验等）
- UX 修复回归：7 项（绘制帧通知机制、页面 document 非空）

## 数据存储位置

所有数据保存在应用文档目录（`getApplicationDocumentsDirectory`）下：

```
<应用文档目录>/
├── documents/        独立画作工程文件（JSON，含全部图层与笔画）
├── thumbnails/       画作缩略图（PNG，列表页展示）
├── notebooks/        笔记本工程文件（JSON，含全部页面）
└── notebook_images/  笔记页插入的图片副本
```

## 技术要点

- 画布渲染：Flutter `CustomPainter` + `Canvas` API（未引入第三方绘图引擎）
- 笔画模型：矢量点列存储（撤销/重做、图层合并、任意分辨率导出无损）
- 图层缓存：离屏位图（`PictureRecorder → toImage`）保证绘制流畅
- 自动保存：变更后 800ms 防抖落盘 + 退出前兜底保存
- 删除保护：所有删除操作均有二次确认对话框

详细设计见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 与 [`docs/PHASES.md`](docs/PHASES.md)。

## 开发计划约束遵守情况

- ✅ 仅声明 `windows` 与 `android` 平台，无 iOS/macOS/Web 适配代码
- ✅ 无任何网络请求、云服务 API、账号系统
- ✅ 无 AI 功能、图层混合模式、蒙版、PSD 导出、录音、协作、内购
- ✅ UI 层 / 绘图引擎层 / 数据存储层严格分层（见架构文档）

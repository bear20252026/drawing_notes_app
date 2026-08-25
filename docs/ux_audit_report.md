# UX 审计报告 — 2026-08-25

## 审计范围
- 所有 GoRouter 路由的完整性和可访问性
- 导航流程（深度链接、文件关联、GoRouter 跳转）
- 响应式 UI / 移动端适配
- 功能可用性（占位符 vs 真实功能）

## 审计结果

### 🔴 CRITICAL — 已修复

| # | 问题 | 路由 | 影响 |
|---|------|------|------|
| 1 | V1编辑器路由是占位符 | `/editor/:docId` | 文件关联打开、深度链接、直接URL全部失效 |
| 2 | 笔记本路由是占位符 | `/notebook/:notebookId` | 深度链接打开笔记本失效 |

### 🟠 HIGH — 已修复

| # | 问题 | 路由 | 影响 |
|---|------|------|------|
| 3 | 设置路由是占位符 | `/settings` | 用户无法访问设置页面 |
| 4 | 搜索路由是占位符 | `/search` | 用户无法访问全局搜索 |
| 5 | 演示路由是占位符 | `/presentation` | 用户无法使用演示模式 |

### 🟡 MEDIUM — 已修复

| # | 问题 | 路由 | 影响 |
|---|------|------|------|
| 6 | 引导路由是占位符 | `/onboarding` | 新用户无法看到功能引导 |
| 7 | 形状库路由是占位符 | `/shape-library` | 用户无法管理自定义形状 |

### 🟢 LOW — 已修复

| # | 问题 | 文件 | 影响 |
|---|------|------|------|
| 8 | locale硬编码en | `lib/app.dart` | 中文用户看到英文界面 |

## 修复内容

### 1. 路由修复（`lib/core/router/app_router.dart`）
- 所有7个占位符路由已接入真实页面
- V1编辑器：新增 `_EditorPageWrapper` 异步加载 `DrawingDocument`
- 笔记本：新增 `_NotebookViewWrapper` 异步加载 `Notebook`
- 演示：新增 `_PresentationWrapper` 从笔记本加载内容并映射

### 2. 新建页面
- `SettingsPage` — 设置页面（主题、语言、加密、备份、关于）
- `OnboardingPage` — 4页引导流程（绘画、笔记、加密、密码盘）
- `ShapeLibraryPage` — 形状库管理页面

### 3. App配置
- `locale: const Locale('en')` → `locale: null`（跟随系统）

## 已知剩余问题

### 🟡 MEDIUM — HomePage 导航绕过 GoRouter
- `HomePage` 使用 `Navigator.of(context).push()` 而非 `context.go()`
- 影响：绕过 AuthGuard 认证检查
- 严重程度：中等（HomePage 是根路由，用户已认证后才能到达）
- 建议：后续迁移到 `context.push()` / `context.go()`

### 🟡 MEDIUM — EditorV2Screen 无实际保存功能
- `_saveNow()` 仅 `debugPrint()` 不写入存储
- 影响：V2 编辑器中新建的笔记无法保存
- 建议：后续接入 Notifier 持久化

### 🟢 LOW — EditorV2Screen 硬编码英文标题
- `'Editor V2 - ${widget.documentId}'` 为英文
- 建议：接入国际化系统

## 测试验证
- Router 测试：28/28 通过
- App Design 测试：6/6 通过
- Windows Debug 构建：成功
- 无新增编译错误

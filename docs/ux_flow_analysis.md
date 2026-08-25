# 用户操作流程分析报告

> 基于源码逐行审计的操作流程梳理
> 生成日期：2026-08-25

---

## 1. 整体应用架构

### 1.1 路由结构（GoRouter）

| 路由 | 页面 | 说明 |
|------|------|------|
| `/` | `HomePage` | 首页（3 Tab：无限画布 / 笔记本 / 最近） |
| `/editor-v2/:docId` | `EditorV2Screen` | V2 统一编辑器（画板/笔记共用） |
| `/editor/:docId` | `EditorPage` (V1) | 旧版画板编辑器 |
| `/notebook/:notebookId` | `NotebookViewPage` | 旧版笔记本视图 |
| `/password-disk` | `PasswordDiskPage` | 密码盘管理（路由守卫目标） |
| `/settings` | `SettingsPage` | 设置页 |
| `/search` | `SearchPage` | 全文搜索 |
| `/presentation` | `PresentationPage` | 演示模式 |
| `/onboarding` | `OnboardingPage` | 首次引导 |
| `/shape-library` | `ShapeLibraryPage` | 形状库 |

### 1.2 路由守卫（AuthGuard redirect）

```
用户打开任意页面
  ├─ 是否需要认证？（requiresAuth = passwordDiskExists && !encryptionSkipped）
  │   ├─ 是 → 重定向到 /password-disk?redirect=原目标
  │   └─ 否 → 正常进入
  └─ /password-disk 页面本身不被拦截（避免死循环）
```

---

## 2. 完整用户操作流程

### 2.1 首次启动流程

```
打开应用
  │
  ├─ [1] AuthGuard.initialize()
  │   ├─ 检查 SharedPreferences → encryptionSkipped?
  │   │   ├─ 是 → 自动认证通过
  │   │   └─ 否 → 继续
  │   └─ 检查 password_disk.json 是否存在？
  │       ├─ 不存在 → 自动认证通过（首次使用）
  │       └─ 存在 → 未认证
  │
  ├─ [2] 密码盘重定向检查
  │   ├─ 有密码盘且未跳过 → 重定向到 /password-disk
  │   └─ 无密码盘或已跳过 → 进入首页
  │
  ├─ [3] OnboardingService.showIfFirstLaunch()
  │   └─ 首次启动弹出引导页，可跳过
  │
  └─ [4] 显示首页（3 个 Tab）
      ├─ Tab 0: 无限画布（画板列表）
      ├─ Tab 1: 笔记本（笔记本列表）
      └─ Tab 2: 最近（最近编辑的文档）
```

### 2.2 画板操作流程

```
首页 Tab 0（无限画布）
  │
  ├─ 点击 FAB「新建无限画布」
  │   ├─ 弹出命名对话框
  │   ├─ 创建 DrawingDocument（id + title）
  │   ├─ Navigator.push → EditorV2Screen（whiteboard 模式）
  │   │   ├─ Canvas 绘图（CustomPainter + RepaintBoundary）
  │   │   ├─ 工具栏（ToolbarWidget）：笔/橡皮/形状/文字/图片
  │   │   ├─ 图层面板（SidebarWidget）：显示/隐藏图层
  │   │   ├─ 属性面板：颜色/粗细/不透明度
  │   │   ├─ 自动保存（800ms 防抖）
  │   │   ├─ 导出菜单：PNG / PDF / SVG / PPTX
  │   │   └─ 返回按钮 → 回到首页 → 刷新列表
  │   └─ 完成
  │
  ├─ 点击已有画板 → _openDrawing(meta)
  │   ├─ 加载 DrawingDocument
  │   ├─ Navigator.push → EditorPage（V1）
  │   │   └─ 打开已有文档继续编辑
  │   └─ 返回后刷新列表
  │
  └─ 长按画板 → 上下文菜单
      ├─ 重命名
      ├─ 删除（二次确认 → 回收站）
      └─ 演示模式
```

### 2.3 笔记本操作流程

```
首页 Tab 1（笔记本）
  │
  ├─ 点击 FAB「新建笔记本」
  │   ├─ 弹出命名对话框
  │   ├─ 创建 Notebook 对象
  │   ├─ 保存到 NotebookStorage
  │   ├─ Navigator.push → EditorV2Screen（note 模式）
  │   │   ├─ 线性文档编辑（AFFiNE Page 借鉴）
  │   │   ├─ 文本编辑 + 手写笔画
  │   │   └─ 自动保存
  │   └─ 返回后刷新列表
  │
  ├─ 点击已有笔记本 → Navigator.push → EditorV2Screen（note 模式）
  │
  ├─ 点击「加密」按钮 → _encryptNotebook()
  │   ├─ 弹出密码输入对话框
  │   ├─ 加密所有页面内容（EncryptionService）
  │   ├─ 保存 encryptedPayload 到 Notebook
  │   └─ 提示加密完成
  │
  ├─ 点击「解密」按钮（加密笔记本）
  │   ├─ 弹出密码输入对话框
  │   ├─ 解密验证（可能自动升级旧格式 v2→v3）
  │   └─ 进入 EditorV2Screen
  │
  └─ 长按笔记本 → 上下文菜单
      ├─ 重命名
      ├─ 删除（策略门禁 + 回收站）
      └─ 演示
```

### 2.4 最近操作流程

```
首页 Tab 2（最近）
  │
  ├─ 显示按修改时间排序的最近文档（画板 + 笔记本混合）
  │
  ├─ 点击 FAB「快速记录」→ _quickRecord()
  │   ├─ 创建临时笔记本
  │   ├─ 直接进入 EditorV2Screen（note 模式）
  │   └─ 快速记录想法
  │
  └─ 点击文档 → 跳转到对应编辑器
```

### 2.5 搜索流程

```
首页 AppBar → 搜索图标 / Ctrl+F / Cmd+F
  │
  └─ Navigator.push → SearchPage
      ├─ 全文搜索（倒排索引）
      ├─ 300ms 去抖（防每键全盘扫描）
      ├─ 结果：画板标题 + 笔记页面标题/内容 + 手写 OCR
      └─ 点击结果 → 跳转到对应文档/页面
```

### 2.6 密码盘操作流程

```
密码盘页面（/password-disk）
  │
  ├─ 状态卡片：显示已解锁/未解锁状态 + 密钥指纹
  │
  ├─ 创建密码盘
  │   ├─ 选择 U 盘目录（系统文件选择器）
  │   ├─ 询问是否启用 PIN 保护
  │   │   ├─ 启用 → 输入 PIN（至少 6 位）→ Argon2id + KEK 包裹
  │   │   └─ 不启用 → 直接创建
  │   ├─ 写入 key.frogkey 到 U 盘
  │   ├─ 生成 24 位恢复密钥 + 信封
  │   ├─ 弹出恢复密钥保存对话框（可复制）
  │   └─ 认证通过 → 导航到首页
  │
  ├─ 解锁
  │   ├─ 选择 U 盘目录
  │   ├─ 读取 key.frogkey
  │   ├─ 若 PIN 保护 → 输入 PIN
  │   ├─ 验证主密钥 → 显示指纹
  │   └─ 认证通过 → 导航到原目标页
  │
  ├─ 恢复密钥恢复
  │   ├─ 输入 24 位恢复密钥
  │   ├─ 用信封 + 恢复密钥 unwrap 主密钥
  │   └─ 认证通过
  │
  ├─ 锁定（仅已解锁时显示）
  │   └─ 清除内存中主密钥 → deauthenticate
  │
  └─ 跳过加密
      ├─ 确认对话框（警告明文存储）
      └─ skipEncryption() → 持久化到 SharedPreferences
```

### 2.7 设置页面

```
设置页面（/settings）
  │
  ├─ 外观设置：主题（系统/浅色/深色）/ 字体大小
  ├─ 加密与安全：密码盘管理入口
  ├─ 备份与同步：导出/导入
  └─ 关于：版本信息
```

---

## 3. 发现的痛点

### 🔴 P0 严重痛点

| # | 痛点 | 位置 | 影响 |
|---|------|------|------|
| 1 | **编辑器 V1/V2 并存混乱** | 首页 | 画板列表点击→V1 (`EditorPage`)；新建→V2 (`EditorV2Screen`)。用户打开旧画板进入 V1，新建进入 V2，两个编辑器功能和 UI 不同 |
| 2 | **密码盘页面仍过于复杂** | `/password-disk` | 5 个按钮 + 恢复密钥 + 跳过加密 + 状态卡，对新用户不友好 |
| 3 | **笔记本加密/解密流程侵入性强** | 首页 Tab 1 | 每次打开加密笔记本需输入密码；解密不保存，关闭后重新加密 |

### 🟡 P1 中等痛点

| # | 痛点 | 位置 | 影响 |
|---|------|------|------|
| 4 | **缺少全局返回/导航** | 编辑器 | EditorV2Screen 无明显返回首页的底部导航，需依赖 AppBar 返回 |
| 5 | **最近 Tab 无 FAB 一致** | 首页 Tab 2 | Tab 0/1 有新建按钮，Tab 2 是「快速记录」，用户可能困惑 |
| 6 | **笔记本删除策略门禁** | 首页 | PolicyEngine 拒绝删除后无解释，用户体验差 |
| 7 | **演示模式入口隐蔽** | 首页 | 仅通过长按上下文菜单进入，不易发现 |
| 8 | **旧版加密自动升级** | 首页 | v2→v3 自动升级发生在打开笔记本时，用户可能不了解发生了什么 |

### 🟢 P2 低优先级

| # | 痛点 | 位置 | 影响 |
|---|------|------|------|
| 9 | **设置页入口缺失** | 首页 AppBar | 设置页可通过 GoRouter 访问 `/settings`，但首页 AppBar 无直接入口按钮 |
| 10 | **形状库入口隐蔽** | 全局 | ShapeLibraryPage 路由存在但无 UI 入口 |
| 11 | **回收站 30 天规则无 UI 提示** | 首页 | AppBar tooltip 提到 30 天，但回收站对话框内无自动过期提示 |

---

## 4. 流程图

### 4.1 应用启动流程

```
                    ┌─────────────────┐
                    │  打开应用        │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ AuthGuard       │
                    │ .initialize()   │
                    └────────┬────────┘
                             │
                  ┌──────────▼──────────┐
                  │ encryptionSkipped?  │
                  ├──── yes ──────────►│──┐
                  │ no                  │  │
                  └──────────┬──────────┘  │
                             │             │
                  ┌──────────▼──────────┐  │
                  │ passwordDiskExists? │  │
                  ├──── no ────────────►│──┤
                  │ yes                  │  │
                  └──────────┬──────────┘  │
                             │             │
                  ┌──────────▼──────────┐  │
                  │ isAuthenticated?    │  │
                  ├──── yes ────────────►│──┤
                  │ no                  │  │
                  └──────────┬──────────┘  │
                             │             │
                    ┌────────▼────────┐    │
                    │ 重定向到         │    │
                    │ /password-disk   │    │
                    └─────────────────┘    │
                                           │
                    ┌──────────────────────▼─┐
                    │       首页 (3 Tab)      │
                    │  画板 | 笔记本 | 最近    │
                    └───────────────────────┘
```

### 4.2 新建画板流程

```
    首页 Tab 0
        │
    ┌───▼───┐
    │ FAB   │
    │ 新建   │
    └───┬───┘
        │
    ┌───▼───────┐
    │ 命名对话框 │
    └───┬───────┘
        │
    ┌───▼───────────────┐
    │ 创建 DrawingDocument│
    └───┬───────────────┘
        │
    ┌───▼───────────────┐
    │ Navigator.push     │
    │ → EditorV2Screen   │
    │   (whiteboard)     │
    └───┬───────────────┘
        │
    ┌───▼───────────────┐
    │ 编辑器功能         │
    │ • 画笔/橡皮/形状   │
    │ • 图层管理         │
    │ • 自动保存(800ms)  │
    │ • 导出(PNG/PDF/SVG)│
    └───┬───────────────┘
        │ 返回
    ┌───▼───────┐
    │ 刷新列表   │
    └───────────┘
```

### 4.3 编辑器版本混乱示意

```
    首页
     │
     ├─ 点击已有画板 ──► Navigator.push → EditorPage (V1) ← 旧版
     │                    • CustomPainter 绘图
     │                    • 旧版工具栏
     │                    • 旧版导出
     │
     ├─ 新建画板 ──────► Navigator.push → EditorV2Screen (whiteboard) ← 新版
     │                    • Riverpod ViewModel
     │                    • CustomPainter + RepaintBoundary
     │                    • 新版工具栏 + 侧边栏
     │                    • 更多导出格式
     │
     └─ 新建笔记本 ────► Navigator.push → EditorV2Screen (note) ← 新版
                          • 线性文档模式
                          • AFFiNE Page 借鉴
```

---

## 5. 改进建议

### 5.1 P0：统一编辑器版本

**问题**：V1 和 V2 并存，用户困惑。

**建议**：
1. 迁移所有画板打开逻辑到 `EditorV2Screen`
2. 移除 `EditorPage`（V1）的直接调用
3. `_openDrawing()` 改用 `EditorV2Screen`：
   ```dart
   Navigator.push(MaterialPageRoute(
     builder: (_) => EditorV2Screen(documentId: doc.id, mode: UnifiedEditorMode.whiteboard),
   ));
   ```
4. 添加 V1→V2 数据格式迁移逻辑（如需要）

### 5.2 P0：简化密码盘入口

**问题**：密码盘页面 5 个按钮太多。

**建议**：
1. 只保留「创建密码盘」和「解锁」两个主按钮
2. 「恢复密钥」折叠到高级选项（ExpansionTile）
3. 「锁定」按钮移到状态卡右上角图标
4. 「跳过加密」放在页面底部小字提示 + 文字按钮

### 5.3 P1：增加全局导航

**建议**：
- 首页 AppBar 添加「设置」图标入口
- 编辑器底部添加返回/主页按钮
- 底部导航栏（可选）：首页 / 编辑器 / 搜索

### 5.4 P1：统一 FAB 行为

**建议**：
- Tab 0 FAB：「新建画板」
- Tab 1 FAB：「新建笔记本」
- Tab 2 FAB：「新建文档」（根据当前选中的子类型决定是画板还是笔记本）

### 5.5 P2：策略拒绝提示

**建议**：
- PolicyEngine 拒绝时弹出 SnackBar 解释原因
- 或用 Dialog 展示详细说明

---

## 6. 测试覆盖

以下关键流程均有对应测试覆盖：
- 密码盘 CRUD + PIN 保护（9/9 tests）
- AuthGuard 跳过加密/恢复加密（8/8 tests）
- 导出功能（21/21 tests）
- 全量测试：1170 tests（2 pre-existing failures）

# 项目验收检查表（ACCEPTANCE CHECKLIST）

> 用途：政府项目验收依据。验收人员逐项核对，全部勾选通过后签署。
> 关联文档：[安全审计报告 SECURITY_AUDIT.md](./SECURITY_AUDIT.md)、[阶段验收 PHASES.md](./PHASES.md)、[架构说明 ARCHITECTURE.md](./ARCHITECTURE.md)

## 一、项目基本信息

| 项目 | 内容 |
|------|------|
| 项目名称 | 绘图笔记 App（Drawing Notes） |
| 技术栈 | Flutter 3.44.9（Dart 3.12.2） |
| 目标平台 | Windows 桌面 + Android |
| 代码位置 | `D:\AI编码工具\画板`（构建产物在 ASCII 镜像 `D:\huaban_build`） |
| 版本 | 1.0.0+1 |
| 验收日期 | 2026-08-13 |

---

## 二、功能验收（逐项勾选）

| # | 验收项 | 验收标准 | 结果 |
|---|--------|----------|------|
| F1 | 最小画布 | 鼠标/手指画连续线条，撤销/重做/清空可用 | ☐ |
| F2 | 绘图工具 | 笔粗细可调、色板选色、橡皮擦透明擦除、吸管取色 | ☐ |
| F3 | 图层系统 | 新建/删除/显隐/透明度/排序/合并，缩略图面板 | ☐ |
| F4 | 选区与变换 | 矩形/套索选区、移动/缩放/旋转、复制/粘贴/删除 | ☐ |
| F5 | 笔记功能 | 笔记本/页面管理、文字输入、图片插入混排 | ☐ |
| F6 | 文件管理 | 自动保存、作品列表缩略图、导出 PNG、删除二次确认 | ☐ |
| F7 | 体验打磨 | 深色模式、双指缩放/旋转、全屏、首次启动引导 | ☐ |

## 三、安全与健壮性验收

| # | 验收项 | 验收标准 | 结果 |
|---|--------|----------|------|
| S1 | 无网络请求 | 代码不含任何网络 I/O、云 API、账号系统 | ☐ |
| S2 | 路径安全 | ID 白名单校验，无路径遍历风险 | ☐ |
| S3 | 数据安全 | 原子写入（tmp+rename），自动保存防丢数据 | ☐ |
| S4 | 资源管理 | ui.Image/Picture 全部正确释放，无泄漏 | ☐ |
| S5 | 异步安全 | dispose 后无回调崩溃；缓存重建无竞态 | ☐ |
| S6 | 内存控制 | 撤销历史上限 60 条，无无限增长 | ☐ |
| S7 | 磁盘清理 | 删除画作/笔记本同步清理缩略图与图片副本 | ☐ |
| S8 | 删除保护 | 所有删除操作二次确认 | ☐ |

## 四、构建与产物验收

| # | 验收项 | 验收标准 | 结果 |
|---|--------|----------|------|
| B1 | 静态检查 | `dart analyze` 零告警 | ☐ |
| B2 | 自动化测试 | 74 个测试全部通过（53 功能 + 14 安全回归 + 7 UX 修复回归） | ☐ |
| B3 | Windows 构建 | `flutter build windows --release` 成功 | ☐ |
| B4 | Android 构建 | `flutter build apk --debug` 成功 | ☐ |
| B5 | 冒烟测试 | `flutter test integration_test -d windows` 5 用例通过 | ☐ |
| B6 | 安装包 | fastforge 生成 Windows 安装包（setup.exe，11.1MB） | ☐ |
| B7 | 安装包结构 | PE/MZ 头签名有效，可安装结构正确 | ☐ |

## 五、文档交付验收

| # | 验收项 | 文档 | 结果 |
|---|--------|------|------|
| D1 | 使用说明 | `README.md`（运行/构建/测试指南） | ☐ |
| D2 | 架构说明 | `docs/ARCHITECTURE.md`（分层架构与设计决策） | ☐ |
| D3 | 阶段验收记录 | `docs/PHASES.md`（Phase 1-7 实现与验收） | ☐ |
| D4 | 安全审计报告 | `docs/SECURITY_AUDIT.md`（13 项问题与修复） | ☐ |
| D5 | 本验收模板 | `docs/ACCEPTANCE_CHECKLIST.md` | ☐ |

---

## 六、验收结论

| 结论 | ☐ 通过　☐ 有条件通过　☐ 不通过 |
|------|------|
| 验收意见 |  |
| 遗留问题 |  |
| 验收人 |  |
| 验收日期 |  |

---

## 附：复验命令（验收人员可自行执行）

```bash
cd D:/huaban_build   # ASCII 路径镜像（中文路径会导致 CMake/打包编码问题）
dart analyze                     # 期望：No issues found
flutter test                     # 期望：All tests passed (74)
flutter build windows --release  # 期望：构建成功
flutter build apk --debug        # 期望：构建成功
flutter test integration_test -d windows   # 期望：5 用例通过
fastforge release --name release --jobs package-windows   # 期望：生成 setup.exe
```

> 注意：`flutter analyze`（LSP 通道）与中文路径存在环境级兼容问题，项目统一使用 `dart analyze`；
> 安装包构建（fastforge/CMake/Inno Setup）必须在 ASCII 路径（`D:\huaban_build`）执行，
> 产物 `dist/1.0.0+1/drawing_notes_app-1.0.0+1-windows-setup.exe` 可拷回任意位置分发。

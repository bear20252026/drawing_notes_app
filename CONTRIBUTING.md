# 贡献指南（Contributing）

感谢您对本项目的兴趣！以下指南帮助您顺利参与开发。本项目遵循
[行为准则](CODE_OF_CONDUCT.md)——参与即视为同意遵守。

## 开发环境

- Flutter 3.47.0（Dart 3.12.2）或更高稳定版
- Windows：Visual Studio 2022+（含"使用 C++ 的桌面开发"组件）
- Android：Android SDK（compileSdk 36）+ JDK 17 及以上

## 代码规范（合并门禁）

所有 PR 必须通过以下门禁（CI 自动执行——任一失败即阻塞合并）：

```bash
# 1. 静态检查零问题（本项目用 dart analyze）
dart analyze

# 2. 全部测试通过（当前 391+ 项）
flutter test

# 3. 架构守护（层方向/零循环/feature 隔离/耦合度量——+5 规则）
flutter test test/architecture_test.dart

# 4. 边界检查（硬性规则合规）
bash tools/check_boundaries.sh

# 5. 行数门禁（0 错误）
python tools/code_guard.py --dir lib --force-native --json
```

风格约定：
- 遵循 `analysis_options.yaml`（Flutter lints + 自定义规则）
- 新代码保持与周围一致的注释密度（中文注释保留——不强制改写）
- 不为不存在场景添加防御性代码（KISS/YAGNI——克制不过度抽象）
- **涉密自查**：不提交真实密钥/口令/令牌；安全相关标识符提交前人工核对

## 提交流程

1. **Fork** 本仓库并创建功能分支：`git checkout -b feat/xxx`
2. 提交使用 **Conventional Commits** 规范：
   - `feat:` 新功能（如 `feat: 会话守卫——自动锁定/再认证`）
   - `fix:` 缺陷修复（如 `fix: 路径遍历运行时校验`）
   - `refactor:` 重构（不改变行为）
   - `ci:` CI/构建变更（如 `ci: 修复 Node 20 弃用警告`）
   - `docs:` 文档变更
   - `test:` 测试变更
3. 提交前自查：`dart analyze` + 相关测试 + 涉密自查
4. 发起 **Pull Request** 到 `master`——CI 门禁自动执行（analyze/测试/架构/边界/行数/秘密扫描/SBOM）

## Issue 报告

- 提供：环境信息（OS/Flutter 版本）、复现步骤、期望行为与实际行为
- 安全漏洞请走 [SECURITY.md](SECURITY.md) 的私有披露通道（**不要在公开 Issue 中描述漏洞细节**）

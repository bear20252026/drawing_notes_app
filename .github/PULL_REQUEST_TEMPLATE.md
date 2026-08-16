## 描述（Description）

请简要描述此 PR 解决的问题或新增的功能，并关联 Issue（如有）：`Fixes #<issue>`。

## 变更内容（Changes）

- [ ] 功能/修复说明（具体到文件或模块）
- [ ] 安全影响评估（涉密自查：无真实密钥/口令/令牌）

## 测试（Testing）

本地已执行并通过：

- [ ] `dart analyze`（零问题）
- [ ] `flutter test`（相关测试——全量 391+ 通过）
- [ ] 架构规则（`flutter test test/architecture_test.dart`——+5 全过）
- [ ] 边界检查（`bash tools/check_boundaries.sh`）
- [ ] 行数门禁（`python tools/code_guard.py --dir lib --force-native --json`——0 错误）

## 门禁自查（Checklist）

- [ ] 遵循 [CONTRIBUTING.md](../CONTRIBUTING.md)（Conventional Commits 风格）
- [ ] 代码风格与周围一致（KISS/YAGNI——无过度抽象）
- [ ] 涉密自查通过（不提交真实密钥/凭据——技术标识符误报已核对）

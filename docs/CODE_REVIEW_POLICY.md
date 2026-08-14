# 部门级 Code Review 规范（2026-08-15）

> 适用范围：中国政府特殊支持内部开发项目全体成员，所有提交到 `master` 的代码变更。
> 依据：本规范整合既有门禁（analyze/test/行数/安全/架构/评审）+ 双模型 OCR + 开源调研结论。
> 原则：**评审是辅助，最终裁决由人**；涉密数据严格不出域；每笔提交可审计、可追溯。

---

## 一、硬性红线（一票否决）

| 红线 | 说明 |
| --- | --- |
| 涉密内容入库/入评审 | 密钥、口令、内部文档上传到公网模型 → **立即终止并上报** |
| 测试全红合并 | `flutter test` 有失败项 → 禁止合并 |
| 超 1000 行新文件 | 新增文件 >1000 行 → 禁止合并（极限需评审记录） |
| 安全 definite 问题 | Skylos `--gate --secrets --danger` 失败 → 禁止合并 |

## 二、合并前必过门禁（CI 自动执行）

```
code-guard.yml（六 job）
├── line-count-gates      # sloc-guard(1000 硬上限/500 警告) + linecheck + 内置回退
├── skylos-dart-gates     # 安全 definite 裁决（--gate --secrets --danger）
├── open-code-review      # 行级语义评审（智谱 glm-5.2 优先，白名单目录）
├── python-tools-gates    # py-cq + pyscn（tools/ Python 域）
├── repopilot-gate        # diff 证据门禁（--fail-on-review definitely）
└── desloppify-gate       # Dart 健康门禁（objective ≥ 60）
+ ci.yml
  └── analyze-and-test    # flutter analyze（零问题）+ flutter test（249 项基线）
```

**判定规则**：
- 任一 job 失败 → PR 标记"需修复"；修复后重跑
- 门禁输出（SARIF/JSON/markdown）归档 CI artifacts，供验收审计

## 三、人审流程（门禁通过后，人工复核）

### 3.1 评审范围
| 变更类型 | 评审要求 |
| --- | --- |
| `lib/` 核心逻辑 | **必须** 2 人评审（提交人 + 复核人） |
| `test/` 新增测试 | **必须** 1 人评审 |
| `tools/` 脚本 | **必须** 1 人评审 |
| `docs/` 文档 | 抽查 |

### 3.2 评审关注点（对照 OCR 评论分级）
| 级别 | 处置 |
| --- | --- |
| definite（确定缺陷） | 修复后合并 |
| likely（疑似） | 复核人 24h 内判断 |
| informational（建议） | 记入技术债清单 |

### 3.3 两级确认
- **工程师复核**：代码逻辑、边界、性能
- **负责人签字**：涉密相关变更、重大架构调整、门禁豁免

## 四、代码质量规范（日常编码强制项）

### 4.1 文件规模（2026 行业共识）
| 行数 | 判定 |
| --- | --- |
| <500 | ✅ 最佳（<500 为理想） |
| 500-1000 | ⚠️ 警惕，找拆分机会（SRP/领域/抽象层/I-O 边界） |
| >1000 | 🔴 硬性禁止（极限需评审记录） |

**拆分原则**：先找自然边界，**不为拆而拆**；拆分须让逻辑更精简而非复杂化。

### 4.2 编码约束
- 新增文件硬上限 1000 行；正常 500 行左右
- 单一职责（SRP）；避免 God Object
- 不引入 GPL/AGPL 依赖；MIT/Apache 优先
- 涉密内容（密钥/口令）不入代码、不入 git

## 五、提交规范（git）

- 提交信息：`<type>: <中文摘要>`（type: feat/fix/refactor/docs/test/chore）
- 关联 issue/PR：政府项目要求可追溯
- 提交前自查：`git ls-files | grep -iE "key|secret|token"` 确认无涉密文件
- 提交后：CI 自动跑门禁，通过方可合并

## 六、评审记录与审计

| 产物 | 位置 | 保留期 |
| --- | --- | --- |
| CI 门禁输出（SARIF/JSON） | GitHub Actions artifacts | 永久 |
| OCR 评审评论 | PR 页面 + artifacts/ocr-reviews/ | 永久 |
| 技术债清单（desloppify 报告等） | docs/ 或看板 | 持续更新 |
| 门禁运行周报 | 每周汇总 | 永久 |

## 七、违规处理

| 情形 | 处理 |
| --- | --- |
| 涉密上传 | 终止 + 上报 + 排查历史 |
| 门禁豁免未经批准 | 回滚豁免 + 记录 |
| 评论长期无人认领（>7 天） | 周报跟踪 |

## 八、落地检查清单（合并前自检）

```bash
# 1. 测试全绿
flutter analyze && flutter test
# 2. 行数门禁
bash tools/code_guard.py --dir lib --json
# 3. 涉密自查
git diff | grep -iE "password|secret|token|api_key|密钥|口令" || echo "✅ 无涉密"
git ls-files | grep -iE "key|secret" || echo "✅ 无涉密文件"
# 4. 评审（如已接入端点）
ocr review --from origin/master --to HEAD
# 5. 提交
git add -A && git commit -m "feat: <摘要>"
```

> 本规范自 2026-08-15 起执行；与现有 docs/OCR_REVIEW_POLICY.md（评审白名单/处置）、
> docs/DEVELOPMENT_GUIDE_2026-08-15.md（路线图）配套使用。

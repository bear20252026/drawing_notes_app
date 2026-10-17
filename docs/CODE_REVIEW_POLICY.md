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
| 安全 definite 问题 | Skylos **安全域**（`--gate --secrets`）失败 → 禁止合并（死代码域 `--danger` 仅归档报告，不阻断） |

## 二、合并前必过门禁（CI 自动执行）

```
code-guard.yml（六 job）
├── line-count-gates      # sloc-guard(1000 硬上限/500 警告) + linecheck + 内置回退
├── skylos-dart-gates     # 安全域阻断（--gate --secrets）+ 死代码域仅报告（--danger）
├── open-code-review      # 行级语义评审（智谱 glm-5.2 优先，白名单目录）
├── python-tools-gates    # py-cq + pyscn（tools/ Python 域）
├── repopilot-gate        # diff 证据门禁（--fail-on-review none，见 code-guard.yml:356）
└── desloppify-gate       # Dart 健康门禁（objective ≥ 60）
+ ci.yml
  └── analyze-and-test    # flutter analyze（零问题）+ flutter test（全量，条数以当次 CI 实录为准）
```

> 两处陈述与代码不符已按 2026-10-17 的逐行回读更正：本文此前把 repopilot 写成
> `--fail-on-review definitely`（实参是 `none`——definitely 级信号需人工确认，自动作业里
> 无法确认，所以刻意不阻断；findings 那条轴 `--fail-on` 仍在阻断），以及把全量测试写成
> 「249 项基线」（本仓 CI 实录：10-06 是 2219 通过/1 红，10-14 是 2415）。
>
> 还有一条要知道的**边界**（同日回读，属现状不是承诺）：`line-count-gates` 里那步「内置回退检查」
> 没有 `if: always()`，而上一步是 `sloc-guard … || exit $?` ⇒ sloc-guard 一旦失败，作业当场结束，
> 这条「兜底」在**失败路径上从不执行**（步骤自身又是 `continue-on-error: true` + `|| true`，
> 双重不阻断）。所以「Rust 工具不可用仍能发现超限文件」这句只在 sloc-guard **正常退出**时成立。

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
| CI 门禁输出（SARIF/JSON） | GitHub Actions artifacts | GitHub 默认 90 天（本仓全部 workflow 均未设 `retention-days`，2026-10-17 实测 grep 零命中——原写「永久」无依据） |
| OCR 评审评论 | PR 页面（GitHub 侧）+ artifacts/ocr-reviews/ | PR 页面随 PR 存在；artifacts 同上 90 天 |
| 技术债清单（desloppify 报告等） | docs/ 或看板 | 持续更新 |
| 门禁运行周报 | **尚未建立** | 原写「每周汇总 / 永久」，但 `.github/workflows/` 里 `schedule`/`cron` 零命中（2026-10-17）⇒ 那条产物从来不存在 |

## 七、违规处理

| 情形 | 处理 |
| --- | --- |
| 涉密上传 | 终止 + 上报 + 排查历史 |
| 门禁豁免未经批准 | 回滚豁免 + 记录 |
| 评论长期无人认领（>7 天） | 暂无自动跟踪（原写「周报跟踪」，依赖上一条不存在的周报）；现由下一轮全仓审计点名 |

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

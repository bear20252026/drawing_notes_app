# OCR 双主审模型配置与切换手册（2026-08-15）

> 适用：Open Code Review（OCR v1.9.3）本机/CI 评审模型配置。
> 原则：**智谱 GLM 优先 → DeepSeek 备选（额度用尽后启用）→ 反思层复用当前模型**。
> 安全：API Key 一律存放于 `~/.opencodereview/`（git 外），**严禁入库**；本手册不含任何密钥。

---

## 一、模型架构与优先级

```
┌──────────────────────────────────────────────┐
│ 主审模型（激活一个）                          │
│   🥇 z-ai（智谱 GLM-5.2）—— 默认优先          │
│   🥈 deepseek（DeepSeek-V4-Pro）—— 额度用尽后 │
│ 反思层（独立模块）→ 复用当前激活模型           │
└──────────────────────────────────────────────┘
```

| 角色 | Provider | 模型 | 官方端点 |
| --- | --- | --- | --- |
| 🥇 主审（优先） | `z-ai` | `glm-5.2` | `https://open.bigmodel.cn/api/paas/v4` |
| 🥈 备选 | `deepseek` | `deepseek-v4-pro` | `https://api.deepseek.com` |
| 反思层 | 复用当前 | 复用当前 | — |

---

## 二、首次配置（一次性）

### 2.1 安装 OCR

```bash
npm install -g @alibaba-group/open-code-review
```

### 2.2 配置智谱（主审，优先）

```bash
# 智谱官方端点：https://open.bigmodel.cn/api/paas/v4（OpenAI 兼容协议）
# API Key 从桌面凭据文件读取后配置（不手动粘贴）
ocr config set provider z-ai
ocr config set model glm-5.2
ocr config set providers.z-ai.api_key "<智谱_API_KEY>"
```

### 2.3 配置 DeepSeek（备选）

```bash
# DeepSeek 官方端点：https://api.deepseek.com（OpenAI 兼容协议）
ocr config set providers.deepseek.api_key "<DeepSeek_API_KEY>"
ocr config set providers.deepseek.model deepseek-v4-pro
```

### 2.4 验证连接

```bash
ocr llm test
# 期望输出：Source: provider:z-ai ... ✓ Connection test successful
```

---

## 三、日常使用与切换

### 3.1 默认评审（智谱优先，已激活）

```bash
ocr review --base origin/master --head HEAD
# 或对指定文件
ocr review --base origin/master --head HEAD --path lib/main.dart
```

### 3.2 智谱额度用尽 → 切换 DeepSeek 备选

```bash
ocr config set provider deepseek
ocr llm test   # 确认备选可用
ocr review --base origin/master --head HEAD
```

### 3.3 切回智谱（额度恢复后）

```bash
ocr config set provider z-ai
ocr config set model glm-5.2
ocr llm test
```

### 3.4 当前激活状态查询

```bash
# 查看 ~/.opencodereview/config.json 中 provider / model 字段
python -c "import json,os; d=json.load(open(os.path.expanduser('~/.opencodereview/config.json'))); print(d.get('provider'), d.get('model'))"
```

---

## 四、CI 集成（GitHub Actions）

OCR 在 CI 中通过 Secrets 注入端点（与上述本机配置独立）：

| Secret 变量 | 用途 |
| --- | --- |
| `OCR_LOCAL_ENDPOINT` | 模型端点地址（如智谱 OpenAI 兼容地址） |
| `OCR_LOCAL_MODEL` | 模型名（如 `glm-5.2`） |
| `OCR_API_KEY` | API Key（**仅存 GitHub Secrets，不入仓库**） |

配置路径：`仓库 → Settings → Secrets and variables → Actions → New repository secret`

---

## 五、安全红线（务必遵守）

| 事项 | 要求 |
| --- | --- |
| API Key 存放 | 仅 `~/.opencodereview/keys.json` 与 GitHub Secrets，**严禁入库/入文档** |
| 涉密源码 | 未经批准不得上传公网模型端点；内网/国产端点优先 |
| 配置复查 | 提交前 `git ls-files | grep -iE "key|api"` 确认无凭据入 git |
| 额度管理 | 智谱优先；额度用尽切 DeepSeek；勿混用消耗 |

---

## 六、故障排查

| 症状 | 处理 |
| --- | --- |
| `Connection test failed` | 检查 Key 是否正确、端点可达、额度是否耗尽 |
| 额度耗尽 | `ocr config set provider deepseek` 切换备选 |
| `model: None` | 重新 `ocr config set model glm-5.2` |
| CI 跳过评审 | 检查 GitHub Secrets 是否已配置 3 个变量 |

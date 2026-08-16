# legacy——V1 兼容层（专家目标架构——2026-08-16）

## 边界（非协商——R-02/R-03）

- **legacy 不能被新的 V2 模块依赖**（V2 绝不 import legacy）
- legacy 仅存 V1 兼容：只读解析（LegacyNotebookReader——V1 JSON/媒体目录
  只读兼容）与一次性迁移（复制-认证-校验-切换——专家"绝不覆盖 V1"）
- 禁止向 legacy 添加新业务功能（仅 P0 安全修复 / 兼容补丁 / 删除调用方）

## 当前状态（第一批迁移后——2026-08-16）

- V1 数据（明文 JSON 笔记本 / 媒体目录）保持只读兼容——DAN 检测 + 密文
  读取双轨
- V2 写入走密文容器（EncryptedWriteTransaction——I-004——主/备/临时无明文）
- 全局媒体迁移已关闭（I-003——绝不对旧媒体目录自动扫描——迁移改显式）
- 旧 `editor_page*` / `drawing_controller*` 列为 V1 兼容（禁止新增业务——
  批次 E/F 由 Editor V2 接管后删除）

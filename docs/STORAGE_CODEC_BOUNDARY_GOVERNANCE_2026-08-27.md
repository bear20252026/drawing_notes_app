# StorageService 文档编解码边界治理说明

**日期：2026-08-27**
**适用分支：`refactor/storage-codec-boundary`**

## 审计结论

`StorageService` 位于 `core/storage`，却直接导入 `features/drawing/infrastructure/document_codec.dart`，并在构造函数中以 `const DocumentCodec()` 作为默认实现。该关系使 core 对 feature 的基础设施层产生唯一的已知例外，因此边界脚本一直对 `storage_service.dart` 施加白名单。

编解码器的职责并非绘图展示或 feature 私有基础设施：它是本地 `.json` 工程文件的**存储格式适配器**。其全部依赖均为 `DrawingDocument` 及其领域对象，且唯一的生产消费者是 `StorageService`；其公开 `DocumentCodec` 类型也被纯编解码、恢复和性能回归测试直接使用。因此，将实现所有权移入 `core/storage` 可以消除反向跨层依赖，而不需要引入一层只会转发 `encode/decode` 的运行时接口、注册表或第二个状态源。

| 方案 | 结论 | 理由 |
|---|---|---|
| 在 core 定义接口、默认实现仍留在 drawing infrastructure | 不采用 | `StorageService` 仍需在生产默认构造路径中定位具体实现，DI 装配会扩大调用面并增加漏注入风险 |
| 新增全局 codec 注册表 | 不采用 | 当前只有一种离线绘图格式；注册时序、默认回退和测试隔离会新增状态与失败模式 |
| 迁移实现到 `core/storage` 并在旧路径兼容导出 | 采用 | 存储格式适配器与文件存取同层；无行为改写、无构造注入扩散，既有 `DocumentCodec` 导入保持有效 |

## 迁移边界

实现迁移到 `lib/core/storage/document_codec.dart`。旧的 `lib/features/drawing/infrastructure/document_codec.dart` 仅以 `export` 保持源兼容，不再声明实现。`StorageService` 改为导入 core 内实现；边界脚本移除对 `storage_service.dart` 的白名单后，`core/` 对 feature `application/infrastructure/presentation` 的导入将成为无例外硬性失败。

这不是文件格式迁移。`DocumentCodec` 的类名、构造器、`latestVersion`、`encode` 和 `decode` 的签名及 JSON v2 格式均不改变。旧导入路径继续获得同一个类型，而非包装器或子类型。

`DocumentCodec` 随迁移进入 `core/storage` 后会出现在 Martin 指标的收集范围中。它是依赖领域模型、被少量调用方使用的格式输出适配器，天然具有较高不稳定度；因此与既有 `core/rendering` 输出适配器一致，不纳入“domain/core 稳定数据层”的阈值计算。该分类只校准度量样本，不放松 core、feature 隔离、onion 或循环依赖的严格断言。

## 行为不变量

| 范围 | 必须保持 |
|---|---|
| 保存 | 调用时编码快照、按文档 ID 排队、临时文件写入、`.bak` 备份与原子替换语义不变 |
| 读取 | 正式文件优先、格式错误回退 `.bak`、瞬时 I/O 重试以及 `FormatException` 传播语义不变 |
| 恢复 | JSON 大小预检、版本拒绝、非法 ID 拒绝、局部对象隔离、默认图层回退和安全钳制不变 |
| 资产 | 删除前解码图片引用、共享图片保护、外部路径保护与备份清理不变 |
| 兼容 | 旧的 drawing infrastructure 导入路径与现有调用代码持续可编译；写出的字节与迁移前一致 |

## 验收标准

1. `StorageService` 不导入 feature 的 `infrastructure`、`application` 或 `presentation`。
2. `tools/check_boundaries.sh` 不再含 `storage_service.dart` 白名单，并在无例外条件下通过。
3. 旧路径和新路径导入的 `DocumentCodec` 可互换，序列化字节、版本常量和防御性恢复结果一致。
4. 覆盖保存重开、队列保序、`.bak` 回退、图片资产删除保护、编解码恢复及全量回归；Martin 稳定性样本仅统计稳定数据层。
5. 不修改 JSON、加密、文件名、目录、迁移或用户可见存储行为。

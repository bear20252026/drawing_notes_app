// 批次 DN-003（P0 数据丢失，2026-10-11）：画布文档防御预算的**单一事实来源**。
//
// 起因：`DocumentCodec` 的**解码侧**一直有防御预算（防 JSON 炸弹/OOM），超限
// 即静默截断；**编码侧一条上限都没有**。后果是「正常用户在一层里画过 1 万笔，
// 写出的文件自己都读不回来」——重开时静默截断，5s 防抖自动保存随即把截断后的
// 内容覆盖到正式文件，用户全程无感，真丢数据。
//
// 本文件把这组预算提升为公开常量，读写两侧引用同一组数字，杜绝漂移；编码侧
// 超出即抛 [DocumentBudgetException]（类型化异常，携带维度/实际值/上限/文档
// id），沿既有写路径可见化链路（`SaveScheduler.saveFailure`）呈现，不新增 UI 面。
//
// ⚠️ 这些数值是**上限**而不是可调优参数：任何一侧单独调大都会重新打开
// 「写得出、读不回」的缺口。改动必须同步 `test/core/storage/
// document_budget_symmetry_test.dart` 的不变式用例——它钉的是
// 「编码器允许写出的最大值 == 解码器能完整读回的最大值」。
//
// 本文件三段内容：
//   1. [DocumentBudgets] / [DocumentBudgetDimension]——读写共用的预算；
//   2. [DocumentBudgetException] + [DocumentDecodeReport]——越界这一事实的
//      类型化表达（编码侧抛出，解码侧作为上报记录）；
//   3. [IncompleteDocumentLoadGuard] + [DocumentIncompleteLoadException]——
//      「该文档本次是以不完整状态载入的」这一状态，以及它如何拦住覆盖写。
//
// 无 import：本文件是纯常量/纯值类型，供 `core/storage` 全域（含 isolate
// 编码路径）零依赖引用。这条纪律也是门禁要求——`architecture_test` 规则3b
// 断言 core/storage 每文件 Martin instability ≤ 0.4，一个只被 1 个文件引用
// 却又有 1 条出向依赖的新库会当场 0.5 撞红，所以完整性上报只能并在此处、
// 不能另立文件。
library;

/// 画布文档（DrawingDocument ↔ 工程文件）的防御预算。
abstract final class DocumentBudgets {
  /// 单个工程文件的字节上限（100MB）：解码入口预检直接拒绝，不进入解析。
  ///
  /// 与 `StorageService._maxListMetaBytes`（首页列表逐文件预检）同源——
  /// 两条入口此前各自写死一份 100MB，改一处漏一处。
  static const int maxFileBytes = 100 * 1024 * 1024;

  /// 单文档图层数上限。
  static const int maxLayerCount = 200;

  /// 单层笔画数上限（红蓝攻防 D-4 修复 2026-08-15）。
  static const int maxStrokesPerLayer = 10000;

  /// 单笔采样点数上限（链 C 修复 2026-08-15：D-4 只限笔画数，一笔可含
  /// 海量点——95MB 文件反序列化内存爆 500MB+）。
  static const int maxPointsPerStroke = 50000;

  /// 全文档笔画总数上限（H-02 补全：层 × 笔画累计，防 JSON 炸弹放大）。
  static const int maxTotalStrokes = 50000;

  /// 全文档采样点总数上限（H-02 补全）。
  static const int maxTotalPoints = 1000000;

  /// 全文档标准形状数上限。
  static const int maxShapeCount = 5000;

  /// 全文档受管图片对象数上限。
  static const int maxImageCount = 5000;

  /// 全文档文字块数上限。
  static const int maxTextCount = 5000;

  // ---- 取值域（**解码侧**的几何/样式钳位；编码侧的对称强制另批处置）----
  //
  // 说明：下面四项与上面九项不同——它们今天仍只在解码侧生效，编码侧未镜像
  // （见 `DocumentCodec.validateSnapshotForEncoding` 只遍历
  // [DocumentBudgetDimension.values]）。本批把它们并入同一事实来源是为了
  // 终结「两份数字各处一份」，而不是顺手扩大拒绝面：把取值域也纳入编码
  // 拒绝会改变合法文档的可保存集合，属于独立裁决，需另批与 UI 一起定。

  /// 坐标绝对值上限（超出视为损坏数据）。
  static const double maxCoordinateMagnitude = 1000000;

  /// 形状/图片单边尺寸上限。
  static const double maxObjectExtent = 8192;

  /// 笔画/描边线宽上限。
  static const double maxStrokeWidth = 512;

  /// 文字块字号上限（px）。
  static const double maxFontSize = 512;
}

/// 受预算约束的文档维度——**编码与解码共用同一枚举与同一 [limit]**。
///
/// 用枚举而非散落的常量做判定，是让「读写对称」可被机器检查的前提：
/// 不变式测试遍历 `values`，逐维度断言「恰好等于 [limit] 能完整往返、
/// 超出 1 条即被编码侧拒绝」。
enum DocumentBudgetDimension {
  /// 图层数量（`document.layers`）。
  layerCount('图层数量'),

  /// 单层笔画数量（`layer.strokes`）。
  strokesPerLayer('单层笔画数量'),

  /// 单笔采样点数量（`stroke.points`）。
  pointsPerStroke('单笔采样点数量'),

  /// 全文档笔画总数。
  totalStrokes('文档笔画总数'),

  /// 全文档采样点总数。
  totalPoints('文档采样点总数'),

  /// 标准形状数量。
  shapeCount('形状对象数量'),

  /// 受管图片对象数量。
  imageCount('图片对象数量'),

  /// 文字块数量。
  textCount('文字对象数量');

  const DocumentBudgetDimension(this.label);

  /// 中文维度名：**只用于异常 toString/日志**，不得进 UI——
  /// `SaveScheduler` 的可见化刻意只带 `errorCode()` 推成的类型代码
  /// （H-04 不泄漏内部结构；R50 起这里不再是 `runtimeType`）。
  final String label;

  /// 该维度的上限，取自 [DocumentBudgets]（读写两侧唯一来源）。
  int get limit => switch (this) {
    DocumentBudgetDimension.layerCount => DocumentBudgets.maxLayerCount,
    DocumentBudgetDimension.strokesPerLayer => DocumentBudgets
        .maxStrokesPerLayer,
    DocumentBudgetDimension.pointsPerStroke => DocumentBudgets
        .maxPointsPerStroke,
    DocumentBudgetDimension.totalStrokes => DocumentBudgets.maxTotalStrokes,
    DocumentBudgetDimension.totalPoints => DocumentBudgets.maxTotalPoints,
    DocumentBudgetDimension.shapeCount => DocumentBudgets.maxShapeCount,
    DocumentBudgetDimension.imageCount => DocumentBudgets.maxImageCount,
    DocumentBudgetDimension.textCount => DocumentBudgets.maxTextCount,
  };
}

/// 预算越界（类型化异常，同时用作「越界事实」的值记录）。
///
/// 两个用途：
/// 1. **编码侧拒绝**——`DocumentCodec.encode`/`snapshotOf` 在任一维度越界时
///    抛出，绝不再写出一个自己都读不回的文件；
/// 2. **解码侧上报**——`DocumentDecodeReport.budgetViolations` 逐条记录读回
///    时被截断的维度（那里不抛异常，因为宽容回读是既有语义）。
///
/// 携带：超了哪个维度、实际值、上限、文档 id、以及发生阶段（[stage]）。
class DocumentBudgetException implements Exception {
  const DocumentBudgetException({
    required this.dimension,
    required this.actual,
    required this.limit,
    required this.documentId,
    this.stage = DocumentBudgetStage.encode,
    this.note = '',
  });

  /// 越界的维度。
  final DocumentBudgetDimension dimension;

  /// 实际值（声明量）。
  final int actual;

  /// 该维度的上限（正常恒等于 `dimension.limit`；显式携带以便异常自证，
  /// 也允许记录历史文件的旧上限）。
  final int limit;

  /// 文档 id（越界归属；异常文本只进日志，不进 UI）。
  final String documentId;

  /// 发生阶段。
  final DocumentBudgetStage stage;

  /// 补充说明（图层/笔画序号等定位信息；同样只进日志）。
  final String note;

  @override
  String toString() =>
      'DocumentBudgetException($stage, ${dimension.name}: $actual>$limit, '
      'doc=$documentId${note.isEmpty ? '' : ', $note'})';
}

/// 预算越界发生的阶段。
enum DocumentBudgetStage {
  /// 编码侧（写路径）：拒绝落盘，抛异常。
  encode,

  /// 解码侧（读路径）：不抛异常，作为完整性上报的一部分。
  decode,
}

// ==========================================================================
// 解码完整性上报与不完整态写侧闸门。
//
// 为什么需要：`DocumentCodec.decode` 的防御性回读在超出 [DocumentBudgets] 时
// **静默截断**（截笔、整层丢弃、点列截短）。此前没有任何出口说明「恢复了什么、
// 丢了几笔/几层/几个对象」，调用方与用户都以为打开的就是文件的全部内容——而
// 5s 防抖自动保存紧接着就把这份截断态覆盖回正式文件。盘上的原件比内存更完整，
// 这是本批次要止的血。
//
// 语义边界（刻意不变的部分）：
// - 解码侧**继续宽容回读**——超预算/损坏条目单独丢弃、其余内容照常打开，既有
//   拒绝语义（高版本拒绝、100MB 入口预检、非法根结构/非法 ID 抛 FormatException）
//   逐条保留，本段只**增加**上报，不改变任何判定；
// - 写侧闸门只对**预算截断**生效（DocumentDecodeReport.isBudgetTruncated）：
//   被预算砍掉的是完全合法、编码器本可原样写出的内容，覆盖即真丢数据；而内容
//   损坏/重复 ID/危险几何被丢弃是既有「修复式回读」的设计意图（见
//   `DocumentCodec.decode` 文档注释），保存即修复，不在拦截范围。
//
// 本段与上面预算同处一个文件、不另立门户，是因为 `architecture_test` 规则3b
// 要求 core/storage 每文件 Martin instability ≤ 0.4：一个只被 1 个文件引用、
// 自己又出向依赖 1 条的新库当场 0.5。本文件因此必须保持**零项目内 import**。
// ==========================================================================

/// 一次解码的完整性统计。
///
/// 两组数字分得很清楚：
/// - `*ByBudget`——被 [DocumentBudgets] 的防御上限砍掉的量（合法内容，真丢）；
/// - `*Invalid*`——因内容损坏/重复 ID/越界取值被宽容回读剔除的量（既有语义）。
class DocumentDecodeReport {
  const DocumentDecodeReport({
    required this.documentId,
    required this.fileBytes,
    required this.layersRestored,
    required this.strokesRestored,
    required this.pointsRestored,
    required this.shapesRestored,
    required this.imagesRestored,
    required this.textItemsRestored,
    required this.layersDroppedByCountBudget,
    required this.layersDroppedByGlobalBudget,
    required this.strokesDroppedByLayerBudget,
    required this.strokesDroppedByGlobalBudget,
    required this.pointsDroppedByStrokeBudget,
    required this.pointsDroppedByGlobalBudget,
    required this.shapesDroppedByCountBudget,
    required this.imagesDroppedByCountBudget,
    required this.textItemsDroppedByCountBudget,
    required this.invalidLayersDropped,
    required this.invalidStrokesDropped,
    required this.invalidPointsDropped,
    required this.invalidShapesDropped,
    required this.invalidImagesDropped,
    required this.invalidTextItemsDropped,
    required this.budgetViolations,
  });

  final String documentId;

  /// 解码入口实际读到的字节数（100MB 预检后的量级，供日志判断文件规模）。
  final int fileBytes;

  // ---- 恢复到内存的量 ----

  /// 实际还原的图层数（不含「一个都没还原时补的空默认层」之外的合成层）。
  final int layersRestored;

  /// 实际还原的笔画数（全文档合计，已扣掉所有截断）。
  final int strokesRestored;

  /// 实际还原的采样点总数。
  final int pointsRestored;

  final int shapesRestored;
  final int imagesRestored;
  final int textItemsRestored;

  // ---- 被防御预算砍掉的量（合法内容，真丢数据）----

  /// 因 `maxLayerCount` 被截掉的图层数（文件声明的超出部分）。
  final int layersDroppedByCountBudget;

  /// 因全文档笔画/点预算而**整层丢弃**的图层数（含触发超限的那一层之后
  /// 尚未处理的其余图层）。
  final int layersDroppedByGlobalBudget;

  /// 因 `maxStrokesPerLayer` 被截掉的笔画数。
  final int strokesDroppedByLayerBudget;

  /// 因全局笔画预算被丢弃的笔画数。
  final int strokesDroppedByGlobalBudget;

  /// 因 `maxPointsPerStroke` 被截掉的采样点数。
  final int pointsDroppedByStrokeBudget;

  /// 因全局采样点预算被丢弃的采样点数。
  final int pointsDroppedByGlobalBudget;

  final int shapesDroppedByCountBudget;
  final int imagesDroppedByCountBudget;
  final int textItemsDroppedByCountBudget;

  // ---- 因内容损坏被剔除的量（既有宽容回读语义，保存即修复）----

  final int invalidLayersDropped;
  final int invalidStrokesDropped;

  /// 笔画内部被剔除的坏点（非坐标有限/超界的采样点）。
  final int invalidPointsDropped;

  final int invalidShapesDropped;
  final int invalidImagesDropped;
  final int invalidTextItemsDropped;

  /// 触发的预算越界明细（逐维度：维度/实际值/上限/文档 id）。
  ///
  /// 复用 [DocumentBudgetException] 作为值记录——它与编码侧抛出的异常同构，
  /// 只是 [DocumentBudgetException.stage] 为 [DocumentBudgetStage.decode]；
  /// 解码侧不抛异常（宽容回读是既有语义），但每一条都必须可被陈述。
  final List<DocumentBudgetException> budgetViolations;

  // ---- 聚合口径 ----

  /// 被防御预算丢弃的图层总数。
  int get layersDroppedByBudget =>
      layersDroppedByCountBudget + layersDroppedByGlobalBudget;

  /// 被防御预算丢弃的笔画总数。
  int get strokesDroppedByBudget =>
      strokesDroppedByLayerBudget + strokesDroppedByGlobalBudget;

  /// 被防御预算丢弃的采样点总数。
  int get pointsDroppedByBudget =>
      pointsDroppedByStrokeBudget + pointsDroppedByGlobalBudget;

  /// 被防御预算丢弃的「对象」（形状/图片/文字）总数。
  int get objectsDroppedByBudget =>
      shapesDroppedByCountBudget +
      imagesDroppedByCountBudget +
      textItemsDroppedByCountBudget;

  /// 因内容损坏被剔除的图层/笔画/对象总数（点另计，粒度不同）。
  int get invalidObjectsDropped =>
      invalidLayersDropped +
      invalidStrokesDropped +
      invalidShapesDropped +
      invalidImagesDropped +
      invalidTextItemsDropped;

  /// 本次打开是否被**防御预算**截断。
  ///
  /// 为 true 即「盘上的原件比内存更完整」⇒ 写侧必须拒绝覆盖
  /// （见 [IncompleteDocumentLoadGuard]）。
  bool get isBudgetTruncated =>
      layersDroppedByBudget > 0 ||
      strokesDroppedByBudget > 0 ||
      pointsDroppedByBudget > 0 ||
      objectsDroppedByBudget > 0;

  /// 本次打开是否**完全无损**（既无预算截断，也无损坏条目被剔除）。
  bool get isComplete =>
      !isBudgetTruncated &&
      invalidObjectsDropped == 0 &&
      invalidPointsDropped == 0;

  @override
  String toString() =>
      'DocumentDecodeReport($documentId, ${fileBytes}B, '
      'layers=$layersRestored strokes=$strokesRestored points=$pointsRestored '
      'shapes=$shapesRestored images=$imagesRestored texts=$textItemsRestored, '
      'budgetDropped{L$layersDroppedByBudget S$strokesDroppedByBudget '
      'P$pointsDroppedByBudget O$objectsDroppedByBudget} '
      'invalidDropped{$invalidObjectsDropped+$invalidPointsDropped} '
      'complete=$isComplete)';
}

/// [DocumentDecodeReport] 的可变累加器（仅供解码过程内部使用）。
///
/// 解码是单线程顺序遍历，字段直接自增即可；`toReport` 生成不可变对外快照。
/// 与报告的字段一一对应，新增计数器不会漏掉对外暴露（同名同义）。
class DocumentDecodeStats {
  DocumentDecodeStats();

  int layersRestored = 0;
  int strokesRestored = 0;
  int pointsRestored = 0;
  int shapesRestored = 0;
  int imagesRestored = 0;
  int textItemsRestored = 0;

  int layersDroppedByCountBudget = 0;
  int layersDroppedByGlobalBudget = 0;
  int strokesDroppedByLayerBudget = 0;
  int strokesDroppedByGlobalBudget = 0;
  int pointsDroppedByStrokeBudget = 0;
  int pointsDroppedByGlobalBudget = 0;
  int shapesDroppedByCountBudget = 0;
  int imagesDroppedByCountBudget = 0;
  int textItemsDroppedByCountBudget = 0;

  int invalidLayersDropped = 0;
  int invalidStrokesDropped = 0;
  int invalidPointsDropped = 0;
  int invalidShapesDropped = 0;
  int invalidImagesDropped = 0;
  int invalidTextItemsDropped = 0;

  final List<DocumentBudgetException> violations = <DocumentBudgetException>[];

  /// 记一条解码侧预算越界（不抛异常，只上报）。
  void violation(
    DocumentBudgetDimension dimension,
    int actual,
    String documentId, {
    String note = '',
  }) {
    violations.add(
      DocumentBudgetException(
        dimension: dimension,
        actual: actual,
        limit: dimension.limit,
        documentId: documentId,
        stage: DocumentBudgetStage.decode,
        note: note,
      ),
    );
  }

  DocumentDecodeReport toReport(String documentId, int fileBytes) =>
      DocumentDecodeReport(
        documentId: documentId,
        fileBytes: fileBytes,
        layersRestored: layersRestored,
        strokesRestored: strokesRestored,
        pointsRestored: pointsRestored,
        shapesRestored: shapesRestored,
        imagesRestored: imagesRestored,
        textItemsRestored: textItemsRestored,
        layersDroppedByCountBudget: layersDroppedByCountBudget,
        layersDroppedByGlobalBudget: layersDroppedByGlobalBudget,
        strokesDroppedByLayerBudget: strokesDroppedByLayerBudget,
        strokesDroppedByGlobalBudget: strokesDroppedByGlobalBudget,
        pointsDroppedByStrokeBudget: pointsDroppedByStrokeBudget,
        pointsDroppedByGlobalBudget: pointsDroppedByGlobalBudget,
        shapesDroppedByCountBudget: shapesDroppedByCountBudget,
        imagesDroppedByCountBudget: imagesDroppedByCountBudget,
        textItemsDroppedByCountBudget: textItemsDroppedByCountBudget,
        invalidLayersDropped: invalidLayersDropped,
        invalidStrokesDropped: invalidStrokesDropped,
        invalidPointsDropped: invalidPointsDropped,
        invalidShapesDropped: invalidShapesDropped,
        invalidImagesDropped: invalidImagesDropped,
        invalidTextItemsDropped: invalidTextItemsDropped,
        budgetViolations: List<DocumentBudgetException>.unmodifiable(
          violations,
        ),
      );
}

/// 「该文档本次是以不完整状态载入的」这一事实本身。
///
/// 从**写路径**抛出（`StorageService.save`），因此天然走 `SaveScheduler`
/// 既有的失败可见化链路（顶栏芯片 / 状态栏芯片 / snackbar 三处消费
/// `saveFailure`，`errorKind` 只带 `errorCode()` 推成的类型代码）——不新增任何 UI 面。
class DocumentIncompleteLoadException implements Exception {
  const DocumentIncompleteLoadException({
    required this.documentId,
    required this.report,
  });

  /// 以截断态载入的文档 id。
  final String documentId;

  /// 当时那次解码的完整性统计（丢了几笔/几层/几个对象）。
  final DocumentDecodeReport report;

  @override
  String toString() =>
      'DocumentIncompleteLoadException(doc=$documentId, '
      'budgetDropped layers=${report.layersDroppedByBudget} '
      'strokes=${report.strokesDroppedByBudget} '
      'points=${report.pointsDroppedByBudget} '
      'objects=${report.objectsDroppedByBudget})';
}

/// 以文档 id 为键的「不完整载入」登记表（批次 DN-003 的止血载体）。
///
/// 表达的命题：**该 id 的文档在本次会话中是以预算截断态打开的**，于是盘上
/// 的正式文件比内存中的文档更完整；任何覆盖写（自动保存 / 手动保存 / 退出
/// 兜底 flush）都会把静默截断固化成真实数据丢失。
///
/// 生命周期（何时失效）：
/// - **置位**：一次解码的 [DocumentDecodeReport.isBudgetTruncated] 为 true；
/// - **失效**：
///   1. 同一 id 再次解码且这次**没有**预算截断（[registerDecode] 覆盖语义）——
///      即「重新打开后」失效；
///   2. 文档被删除（[forget]）——文件已经不在了，命题不再成立；
///   3. 显式 [acknowledge]（「明确处置」出口）：调用方确认要放弃盘上更完整的
///      原件（未来的「另存为新文档 / 修复并覆盖」入口负责接线；本批不加 UI，
///      故生产路径下不会被自动调用）。
/// - **不失效**：保存成功。不完整态下保存一律被拒绝，本就不存在「保存成功后
///   解除」这条路——若哪天出现了，说明闸门被绕过，应当当作缺陷处理。
///
/// 内存中已做的编辑不会因拒绝而丢：`SaveScheduler` 保留脏标记（失败分支
/// 不清 `_dirty`，见其 `giveUp` 注释与既有回归断言），用户可以继续撤销/删除
/// 内容，或经 [acknowledge] 明确处置。
///
/// 线程模型：仅在主 isolate 使用（`StorageService` 门面内部），不做加锁。
class IncompleteDocumentLoadGuard {
  final Map<String, DocumentDecodeReport> _truncated =
      <String, DocumentDecodeReport>{};

  /// 记录一次解码结果：截断则置位，完整则解除该 id 的既有置位。
  void registerDecode(String documentId, DocumentDecodeReport report) {
    if (report.isBudgetTruncated) {
      _truncated[documentId] = report;
    } else {
      _truncated.remove(documentId);
    }
  }

  /// 该文档当前是否处于「以截断态载入」状态。
  bool isTruncated(String documentId) => _truncated.containsKey(documentId);

  /// 置位原因（当时的完整性统计）；未置位返回 null。
  DocumentDecodeReport? reportOf(String documentId) => _truncated[documentId];

  /// 处于不完整态的文档 id 集合（只读视图）。
  Iterable<String> get truncatedDocumentIds => _truncated.keys.toList();

  /// 是否有任何文档处于不完整态。
  bool get hasTruncatedDocuments => _truncated.isNotEmpty;

  /// 解除某文档的置位（删除文档 / 重新以完整态载入之外的显式处置）。
  void forget(String documentId) => _truncated.remove(documentId);

  /// **显式处置**：确认放弃盘上更完整的原件、允许后续覆盖写。
  ///
  /// 与 [forget] 分开的理由：语义上是「人已知情并决定覆盖」，必须是一道
  /// 显式动作，不能是任何自动路径的副产物。
  void acknowledge(String documentId) => _truncated.remove(documentId);
}

import '../../../core/domain/value_objects/geometry.dart';
import '../../drawing/domain/document.dart';
import '../../drawing/domain/shape_item.dart';
import '../../drawing/domain/text_item.dart';

export 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
export 'package:drawing_notes_app/features/drawing/domain/text_item.dart';
export 'package:drawing_notes_app/core/domain/value_objects/geometry.dart';

/// 页面创建模板。模板描述用户的真实记录任务，并映射为纸张与画布行为，
/// 使“新建”不再只是先创建空白页、再手动调整多项设置。
enum PageTemplate {
  blank,
  lined,
  grid,
  dot,
  meeting,
  cornell,
  planner,
  whiteboard,
}

extension PageTemplatePresentation on PageTemplate {
  String get label => switch (this) {
    PageTemplate.blank => '空白笔记',
    PageTemplate.lined => '横线笔记',
    PageTemplate.grid => '方格纸',
    PageTemplate.dot => '点阵笔记',
    PageTemplate.meeting => '会议记录',
    PageTemplate.cornell => '康奈尔笔记',
    PageTemplate.planner => '计划页',
    PageTemplate.whiteboard => '宽阔白板',
  };

  PaperType get paperType => switch (this) {
    PageTemplate.blank || PageTemplate.whiteboard => PaperType.blank,
    PageTemplate.lined || PageTemplate.meeting => PaperType.lined,
    PageTemplate.grid => PaperType.grid,
    PageTemplate.dot ||
    PageTemplate.cornell ||
    PageTemplate.planner => PaperType.dot,
  };

  bool get isInfinite => this == PageTemplate.whiteboard;
}

/// 页面上的图片块。
///
/// [filePath] 指向应用文档目录下的本地图片副本（绝对路径），
/// 插入时由存储层把所选图片复制进应用目录，保证离线可用、不丢文件。
class PageImageItem {
  PageImageItem({
    required this.id,
    required this.x,
    required this.y,
    required this.filePath,
    this.width = 200,
    this.height = 150,
    this.zOrder = 0,
    this.groupId,
    this.href,
    this.fractionalIndex,
  });

  final String id;
  double x;
  double y;
  String filePath;
  double width;
  double height;

  /// 图层顺序（借鉴 Excalidraw 图层操作）。
  int zOrder;

  /// 层级排序键（fractional indexing，参考 Excalidraw）：重排只需在相邻
  /// 键之间生成新键，无需重排其余元素。null = 旧文档，回退按 [zOrder] 排序。
  String? fractionalIndex;

  /// 元素分组（借鉴 Excalidraw groupIds）。
  String? groupId;

  /// 元素超链接（借鉴 Excalidraw hyperlink）：点击打开链接。
  String? href;

  FOffset get position => FOffset(x, y);

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'filePath': filePath,
    'width': width,
    'height': height,
    'zOrder': zOrder,
    if (groupId != null) 'groupId': groupId,
    if (href != null) 'href': href,
    if (fractionalIndex != null) 'fractionalIndex': fractionalIndex,
  };

  factory PageImageItem.fromJson(Map<String, dynamic> json) => PageImageItem(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    filePath: json['filePath'] as String,
    width: (json['width'] as num?)?.toDouble() ?? 200,
    height: (json['height'] as num?)?.toDouble() ?? 150,
    zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
    groupId: json['groupId'] as String?,
    href: json['href'] as String?,
    fractionalIndex: json['fractionalIndex'] as String?,
  );
}

/// 图表元素（借鉴 Excalidraw charts：粘贴数据自动生成柱状/折线图）。
enum ChartType { bar, line }

/// 页面上的图表（柱状图/折线图）。
class PageChartItem {
  PageChartItem({
    required this.id,
    required this.chartType,
    required this.data,
    this.labels = const [],
    this.x = 100,
    this.y = 100,
    this.width = 320,
    this.height = 200,
    this.color = 0xFF3A6EA5,
    this.zOrder = 0,
  });

  final String id;
  ChartType chartType;
  List<double> data;
  List<String> labels;
  double x;
  double y;
  double width;
  double height;
  int color;
  int zOrder;

  FOffset get position => FOffset(x, y);

  Map<String, dynamic> toJson() => {
    'id': id,
    'chartType': chartType.name,
    'data': data,
    'labels': labels,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'color': color,
    'zOrder': zOrder,
  };

  factory PageChartItem.fromJson(Map<String, dynamic> json) => PageChartItem(
    id: json['id'] as String,
    chartType: ChartType.values.firstWhere(
      (c) => c.name == json['chartType'],
      orElse: () => ChartType.bar,
    ),
    data: (json['data'] as List? ?? const [])
        .map((e) => (e as num).toDouble())
        .toList(),
    labels: (json['labels'] as List? ?? const [])
        .map((e) => e as String)
        .toList(),
    x: (json['x'] as num?)?.toDouble() ?? 100,
    y: (json['y'] as num?)?.toDouble() ?? 100,
    width: (json['width'] as num?)?.toDouble() ?? 320,
    height: (json['height'] as num?)?.toDouble() ?? 200,
    color: (json['color'] as num?)?.toInt() ?? 0xFF3A6EA5,
    zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
  );
}

/// 克隆引用（借鉴 Trilium 笔记克隆：一处修改多端生效，非复制粘贴）。
///
/// [notebookId] + [pageId] 指向源页面；克隆条目本身不存内容，
/// 打开时实时加载源页面，修改写回源页面，所有克隆端同步生效。
class CloneRef {
  const CloneRef({required this.notebookId, required this.pageId});

  final String notebookId;
  final String pageId;

  Map<String, dynamic> toJson() => {'notebookId': notebookId, 'pageId': pageId};

  factory CloneRef.fromJson(Map<String, dynamic> json) => CloneRef(
    notebookId: json['notebookId'] as String,
    pageId: json['pageId'] as String,
  );
}

/// 页面版本快照（C1：借鉴 nb 的"Git 即版本控制"——自动保存时保留历史）。
///
/// 保存 [time]（时间戳）与当时的画布/文字内容快照，可回溯恢复。
/// [summary] 为相对上一版的变更 diff 摘要（C2：笔画数/文字变更）。
class PageVersion {
  PageVersion({
    required this.time,
    required this.document,
    required this.textItems,
    List<PageImageItem>? imageItems,
    List<PageConnector>? connectors,
    List<PageShapeItem>? shapes,
    List<PageChartItem>? charts,
    this.summary = '',
  }) : imageItems = imageItems ?? [],
       connectors = connectors ?? [],
       shapes = shapes ?? [],
       charts = charts ?? [];

  final DateTime time;
  final DrawingDocument document;
  final List<PageTextItem> textItems;

  /// 版本必须覆盖全部可编辑内容。此前仅保存笔画和文字，恢复旧版后
  /// 会遗留后来新增的图片、形状、图表或连接线，形成不可预期的混合状态。
  final List<PageImageItem> imageItems;
  final List<PageConnector> connectors;
  final List<PageShapeItem> shapes;
  final List<PageChartItem> charts;
  final String summary;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'document': document.toJson(),
    'textItems': textItems.map((t) => t.toJson()).toList(),
    'imageItems': imageItems.map((i) => i.toJson()).toList(),
    'connectors': connectors.map((c) => c.toJson()).toList(),
    'shapes': shapes.map((s) => s.toJson()).toList(),
    'charts': charts.map((c) => c.toJson()).toList(),
    'summary': summary,
  };

  factory PageVersion.fromJson(Map<String, dynamic> json) => PageVersion(
    time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
    document: DrawingDocument.fromJson(
      json['document'] as Map<String, dynamic>,
    ),
    textItems: (json['textItems'] as List? ?? const [])
        .map((e) => PageTextItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    imageItems: (json['imageItems'] as List? ?? const [])
        .map((e) => PageImageItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    connectors: (json['connectors'] as List? ?? const [])
        .map((e) => PageConnector.fromJson(e as Map<String, dynamic>))
        .toList(),
    shapes: (json['shapes'] as List? ?? const [])
        .map((e) => PageShapeItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    charts: (json['charts'] as List? ?? const [])
        .map((e) => PageChartItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    summary: json['summary'] as String? ?? '',
  );
}

/// 画布元素连接线（D1：节点关联标注，借鉴 Relatum 连线）。
///
/// 在 [fromItemId] 与 [toItemId] 两个混排对象（文字/图片块）之间画连线。
class PageConnector {
  PageConnector({
    required this.id,
    required this.fromItemId,
    required this.toItemId,
    this.color = 0xFF42A5F5,
  });

  final String id;
  final String fromItemId;
  final String toItemId;
  final int color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromItemId': fromItemId,
    'toItemId': toItemId,
    'color': color,
  };

  factory PageConnector.fromJson(Map<String, dynamic> json) => PageConnector(
    id: json['id'] as String,
    fromItemId: json['fromItemId'] as String,
    toItemId: json['toItemId'] as String,
    color: (json['color'] as num?)?.toInt() ?? 0xFF42A5F5,
  );
}

/// 笔记本中的一页。
///
/// 一页 = 一张画布（[document]，承载手写/图层内容）
///      + 文字块列表 + 图片块列表（混排对象）。
class NotebookPage {
  NotebookPage({
    required this.id,
    required this.title,
    required this.document,
    List<PageTextItem>? textItems,
    List<PageImageItem>? imageItems,
    this.folder = '',
    this.cloneOf,
    List<String>? tags,
    List<PageVersion>? history,
    List<PageConnector>? connectors,
    List<PageShapeItem>? shapes,
    List<PageChartItem>? charts,
    this.template = PageTemplate.blank,
    this.favorite = false,
    this.lastOpenedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : textItems = textItems ?? [],
       imageItems = imageItems ?? [],
       tags = tags ?? [],
       history = history ?? [],
       connectors = connectors ?? [],
       shapes = shapes ?? [],
       charts = charts ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final DrawingDocument document;
  final List<PageTextItem> textItems;
  final List<PageImageItem> imageItems;

  /// 分组名（A1 层级：页面可按文件夹分组管理，空 = 根）。
  String folder;

  /// 克隆引用（A3：页面多笔记本挂载，内容实时来自源页面）。
  CloneRef? cloneOf;

  /// 标签（A2：全局标签体系，跨笔记本检索）。
  final List<String> tags;

  /// 版本历史（C1：自动保存快照，最多保留 [maxHistoryVersions] 版）。
  final List<PageVersion> history;

  /// 版本历史上限。
  static const int maxHistoryVersions = 8;

  /// 元素连接线（D1：节点关联标注，借鉴 Relatum 连线）。
  final List<PageConnector> connectors;

  /// 形状元素（矩形/椭圆/菱形/箭头/直线，借鉴 Excalidraw）。
  final List<PageShapeItem> shapes;

  /// 图表元素（柱状/折线，借鉴 Excalidraw charts）。
  final List<PageChartItem> charts;

  /// 创建时选定的工作流模板，用于在笔记库中识别页面类型并支持复用。
  PageTemplate template;

  /// 收藏/置顶标记，用于高频页面的快速访问。
  bool favorite;

  /// 最近一次进入编辑器的时间。用于“最近使用”排序，不等同于内容更新时间。
  DateTime? lastOpenedAt;

  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'document': document.toJson(),
    'textItems': textItems.map((t) => t.toJson()).toList(),
    'imageItems': imageItems.map((i) => i.toJson()).toList(),
    'folder': folder,
    if (cloneOf != null) 'cloneOf': cloneOf!.toJson(),
    'tags': tags,
    'history': history.map((h) => h.toJson()).toList(),
    'connectors': connectors.map((c) => c.toJson()).toList(),
    'shapes': shapes.map((s) => s.toJson()).toList(),
    'charts': charts.map((c) => c.toJson()).toList(),
    'template': template.name,
    'favorite': favorite,
    if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NotebookPage.fromJson(Map<String, dynamic> json) => NotebookPage(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名页面',
    document: DrawingDocument.fromJson(
      json['document'] as Map<String, dynamic>,
    ),
    textItems: (json['textItems'] as List? ?? const [])
        .map((e) => PageTextItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    imageItems: (json['imageItems'] as List? ?? const [])
        .map((e) => PageImageItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    folder: json['folder'] as String? ?? '',
    cloneOf: json['cloneOf'] != null
        ? CloneRef.fromJson(json['cloneOf'] as Map<String, dynamic>)
        : null,
    tags: (json['tags'] as List? ?? const []).map((e) => e.toString()).toList(),
    history: (json['history'] as List? ?? const [])
        .map((e) => PageVersion.fromJson(e as Map<String, dynamic>))
        .toList(),
    connectors: (json['connectors'] as List? ?? const [])
        .map((e) => PageConnector.fromJson(e as Map<String, dynamic>))
        .toList(),
    shapes: (json['shapes'] as List? ?? const [])
        .map((e) => PageShapeItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    charts: (json['charts'] as List? ?? const [])
        .map((e) => PageChartItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    template: PageTemplate.values.firstWhere(
      (template) => template.name == json['template'],
      orElse: () => PageTemplate.blank,
    ),
    favorite: json['favorite'] as bool? ?? false,
    lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? ''),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 笔记本：多个页面的集合，用于分类管理（Phase 5）。
class Notebook {
  Notebook({
    required this.id,
    required this.title,
    List<NotebookPage>? pages,
    this.encrypted = false,
    this.encryptionMode = EncryptionMode.password,
    this.encryptedPayload,
    this.recoveryEnvelope,
    this.searchSummary = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : pages = pages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<NotebookPage> pages;

  /// 是否启用加密（C3：敏感笔记本加密，借鉴 Joplin 加密）。
  /// 加密后 pages 以密文存储（见 NotebookStorage），打开需解锁。
  bool encrypted;

  /// 加密模式：记忆密码（password）或 U盘钥匙（keyfile）。
  /// keyfile 模式 = 密码盘（U盘即钥匙，见 docs/PASSWORD_DISK_DESIGN.md）。
  EncryptionMode encryptionMode;

  /// 加密后的页面载荷（AES-GCM 密文 JSON，由 EncryptionService 生成）。
  /// 加密笔记本的 pages 明文不落盘，仅存此字段；解锁后填充 pages。
  String? encryptedPayload;

  /// 恢复密钥信封（仅 keyfile 模式）：U 盘丢失时凭 24 位恢复密钥
  /// 解信封找回主密钥（EncryptionService.wrapMasterKey 产物）。
  String? recoveryEnvelope;

  /// 脱敏搜索摘要（搜索增强 2026-08-16）：加密笔记本的明文摘要（标题 +
  /// 文本块前 [searchSummaryMaxChars] 字符——不含敏感正文细节），供列表/
  /// 搜索展示——核心正文仍加密（51CTO titlePreview 权威模式）。
  String searchSummary;

  final DateTime createdAt;
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now();

  /// 脱敏摘要最大字符数（搜索增强 2026-08-16）。
  static const int searchSummaryMaxChars = 200;

  /// 构建脱敏搜索摘要（标题 + 文本块前若干字符——截断防敏感正文细节
  /// 全量暴露；纯函数——可独立单测；51CTO titlePreview 权威模式）。
  static String buildSearchSummary(Notebook notebook) {
    final buffer = StringBuffer(notebook.title);
    for (final page in notebook.pages) {
      for (final text in page.textItems) {
        if (buffer.length >= searchSummaryMaxChars) break;
        buffer.write(' ');
        buffer.write(text.text);
      }
    }
    final summary = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return summary.length > searchSummaryMaxChars
        ? summary.substring(0, searchSummaryMaxChars)
        : summary;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    // 加密笔记本不落盘明文页面，仅存密文载荷。
    'pages': encrypted ? const [] : pages.map((p) => p.toJson()).toList(),
    'encrypted': encrypted,
    'encryptionMode': encryptionMode.name,
    if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
    if (recoveryEnvelope != null) 'recoveryEnvelope': recoveryEnvelope,
    if (searchSummary.isNotEmpty) 'searchSummary': searchSummary,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名笔记本',
    pages: (json['pages'] as List? ?? const [])
        .map((e) => NotebookPage.fromJson(e as Map<String, dynamic>))
        .toList(),
    encrypted: json['encrypted'] as bool? ?? false,
    encryptionMode: EncryptionMode.values.firstWhere(
      (m) => m.name == json['encryptionMode'],
      orElse: () => EncryptionMode.password, // 向后兼容：旧数据视为密码模式
    ),
    encryptedPayload: json['encryptedPayload'] as String?,
    recoveryEnvelope: json['recoveryEnvelope'] as String?,
    searchSummary: json['searchSummary'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 笔记本加密模式。
enum EncryptionMode {
  /// 记忆密码：PBKDF2 派生密钥（现有 C3 方式）。
  password,

  /// U盘钥匙（密码盘）：256 位随机主密钥，仅存 U 盘 key.frogkey，
  /// 零知识架构（见 docs/PASSWORD_DISK_DESIGN.md）。
  keyfile,
}

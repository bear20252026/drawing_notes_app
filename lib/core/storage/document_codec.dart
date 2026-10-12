import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/core/documents/migration/document_migration_registry.dart';
import 'package:drawing_notes_app/core/storage/document_budgets.dart';
import 'package:drawing_notes_app/core/utils/time_serialization.dart';

// 批次 DN-003：预算与完整性上报随编解码器一并对外可见——消费方（StorageService
// 门面、测试、未来修复入口）经本文件即可拿到同一事实来源，不必各自新增 import
// （core/storage 的 Martin 稳定性指标也据此不再往上加出向依赖）。
export 'package:drawing_notes_app/core/storage/document_budgets.dart';

/// 文档编解码器：DrawingDocument <-> JSON 字符串（工程文件格式）。
///
/// 说明：工程文件使用 JSON 存储全部图层与笔画（矢量数据），
/// 不依赖第三方格式（如 PSD，按开发计划 Phase 1-7 不实现 PSD 导出）。
///
/// **读写对称纪律（批次 DN-003，2026-10-11）**：解码侧的防御预算见
/// [DocumentBudgets]，编码侧在 [validateSnapshotForEncoding] 用**同一组数字**
/// 做拒绝——写不出读不回来的文件比保存失败严重得多，保存失败至少有
/// `SaveScheduler.saveFailure` 的可见化，而「静默截断 + 自动覆盖」是无声丢数据。
///
/// 文件结构（v1）：
/// {
///   "version": 1,
///   "document": { "id","title","width","height","createdAt","updatedAt",
///                 "layers": [ {id,name,visible,opacity,strokes:[...]} ],
///                 "shapes": [...], "imageItems": [...], "textItems": [...] }
/// }
class DocumentCodec {
  const DocumentCodec();

  /// 当前支持的工程文件格式版本。
  ///
  /// 对齐 Saber SBN 的版本管理思路：写入固定 [version]，读取时若遇到
  /// 高于本值的文件（由新版本应用生成）则明确拒绝并提示升级，而不是
  /// 静默忽略未知字段造成数据损坏（政府审计项目严禁静默丢数据）。
  ///
  /// **v4（2026-10-12）**：形状新增两个可选样式键 `strokeStyle`（solid/dashed/dotted）
  /// 与 `fillStyle`（solid/hachure/crossHatch）。之所以升版本而不是「留在 v3 加可选键」：
  /// 留在 v3 时，旧版本读到带 dotted/crossHatch 的文件会**静默降级**成 dash/实心，
  /// 正是本文件上面那段注释禁止的行为；升到 v4 后旧版本明确拒绝并提示升级，
  /// 而 v3 及更早的文件由 `MigrationV3ToV4` 从旧布尔值补出等价显式键，照常打开。
  static const int latestVersion = 4;

  static const int _version = latestVersion;

  /// 序列化为 JSON 字节。
  ///
  /// 超出 [DocumentBudgets] 时抛 [DocumentBudgetException]（不落盘）。
  Uint8List encode(DrawingDocument doc) => encodeSnapshot(snapshotOf(doc));

  /// 主线程快照：把可变文档一次性读成纯 Dart Map。
  ///
  /// U2 优化（2026-09-02，P1-10）：保存路径先在主线程取不可变快照
  /// （保证语义与原同步 encode 相同——编辑器继续修改 doc 不影响队列中
  /// 的本次保存），随后把纯 Map 送入 isolate 编码，主线程不再承担
  /// jsonEncode + UTF-8 的大文档开销。
  ///
  /// 批次 DN-003：快照构建完成后立刻做预算校验——**在主线程、进入写尾队列
  /// 之前**失败，异常沿 `StorageService.save` 同步抛出，交给
  /// `SaveScheduler` 既有的失败可见化链路。
  static Map<String, dynamic> snapshotOf(DrawingDocument doc) {
    final snapshot = <String, dynamic>{
      'version': _version,
      'document': {
        'id': doc.id,
        'title': doc.title,
        'width': doc.width,
        'height': doc.height,
        'infinite': doc.infinite,
        'paperType': doc.paperType.name,
        'folder': doc.folder,
        'createdAt': timeToIso(doc.createdAt),
        'updatedAt': timeToIso(doc.updatedAt),
        'layers': doc.layers.map((l) => l.toJson()).toList(),
        'shapes': doc.shapes.map((shape) => shape.toJson()).toList(),
        'imageItems': doc.imageItems.map((item) => item.toJson()).toList(),
        // 独立画布的文字工具把文字写进 `document.textItems`
        // （editor_page_actions.dart:460「独立画布模式回退到 document.textItems」）。
        // 这一项此前在编码与解码两侧都不存在——画布上打的字「保存成功、重开就没」，
        // 属于政府审计项目明令禁止的静默丢数据。
        'textItems': doc.textItems.map((item) => item.toJson()).toList(),
      },
    };
    validateSnapshotForEncoding(snapshot);
    return snapshot;
  }

  /// 把快照 Map 编码为 JSON 字节。纯静态纯函数，可安全跑在 isolate 中。
  ///
  /// 编码侧预算校验的唯一落点（[snapshotOf] 的校验是同一判定的提前失败），
  /// 任何直接调用本方法的旁路都必须经过同一道门。
  static Uint8List encodeSnapshot(Map<String, dynamic> snapshot) {
    validateSnapshotForEncoding(snapshot);
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(snapshot)),
    );
  }

  /// 异步序列化：小文档直接主线程编码（避免 isolate 往返开销），
  /// 达到 [isolateEncodeThreshold] 笔画量的文档在 isolate 编码。
  ///
  /// 快照 [snapshot] 为纯 Map/List/String/num，可安全跨 isolate 传递。
  static Future<Uint8List> encodeSnapshotAsync(Map<String, dynamic> snapshot) {
    final doc = snapshot['document'];
    final layers = doc is Map ? doc['layers'] : null;
    final strokeCount = _countStrokes(layers);
    if (strokeCount < isolateEncodeThreshold) {
      return Future.value(encodeSnapshot(snapshot));
    }
    return Isolate.run(() => encodeSnapshot(snapshot));
  }

  /// isolate 编码阈值：低于该笔画量时 isolate 往返（拷贝 + spawn）
  /// 开销大于收益，直接主线程编码。
  static const int isolateEncodeThreshold = 2000;

  static int _countStrokes(Object? layers) {
    if (layers is! List) return 0;
    var total = 0;
    for (final layer in layers) {
      final strokes = layer is Map ? layer['strokes'] : null;
      if (strokes is List) total += strokes.length;
    }
    return total;
  }

  // ---- 编码侧预算校验（与解码侧共用 [DocumentBudgets]）----

  /// 快照越界即抛 [DocumentBudgetException]；在预算内则原样返回。
  ///
  /// 逐维度检查顺序 = [DocumentBudgetDimension] 声明顺序，第一个越界即抛
  /// （编码是「全有或全无」，没有解码侧那种部分恢复的余地）。
  ///
  /// 不校验取值域（线宽/字号/坐标）——那些仍是解码侧钳位，见
  /// [DocumentBudgets] 尾注；本批只闭合「数量」维度的读写不对称。
  static void validateSnapshotForEncoding(Map<String, dynamic> snapshot) {
    final documentValue = snapshot['document'];
    if (documentValue is! Map) return;
    final rawId = documentValue['id'];
    final documentId = rawId is String ? rawId : '';

    final layers = documentValue['layers'];
    var totalStrokes = 0;
    var totalPoints = 0;
    if (layers is List) {
      _assertWithinBudget(
        DocumentBudgetDimension.layerCount,
        layers.length,
        documentId,
      );
      for (var i = 0; i < layers.length; i++) {
        final layer = layers[i];
        if (layer is! Map) continue;
        final strokes = layer['strokes'];
        if (strokes is! List) continue;
        final note = 'layer#$i';
        _assertWithinBudget(
          DocumentBudgetDimension.strokesPerLayer,
          strokes.length,
          documentId,
          note: note,
        );
        totalStrokes += strokes.length;
        _assertWithinBudget(
          DocumentBudgetDimension.totalStrokes,
          totalStrokes,
          documentId,
          note: note,
        );
        for (var j = 0; j < strokes.length; j++) {
          final stroke = strokes[j];
          if (stroke is! Map) continue;
          final pointCount = declaredPointCount(stroke['points']);
          final strokeNote = '$note/stroke#$j';
          _assertWithinBudget(
            DocumentBudgetDimension.pointsPerStroke,
            pointCount,
            documentId,
            note: strokeNote,
          );
          totalPoints += pointCount;
          _assertWithinBudget(
            DocumentBudgetDimension.totalPoints,
            totalPoints,
            documentId,
            note: strokeNote,
          );
        }
      }
    }
    _assertWithinBudget(
      DocumentBudgetDimension.shapeCount,
      _declaredCount(documentValue['shapes']),
      documentId,
    );
    _assertWithinBudget(
      DocumentBudgetDimension.imageCount,
      _declaredCount(documentValue['imageItems']),
      documentId,
    );
    _assertWithinBudget(
      DocumentBudgetDimension.textCount,
      _declaredCount(documentValue['textItems']),
      documentId,
    );
  }

  static void _assertWithinBudget(
    DocumentBudgetDimension dimension,
    int actual,
    String documentId, {
    String note = '',
  }) {
    final limit = dimension.limit;
    if (actual <= limit) return;
    throw DocumentBudgetException(
      dimension: dimension,
      actual: actual,
      limit: limit,
      documentId: documentId,
      stage: DocumentBudgetStage.encode,
      note: note,
    );
  }

  /// 一条 `points` 数组声明的采样点数（读写两侧同一算法）。
  ///
  /// 新格式是扁平三元组 `[x0,y0,p0, ...]`（[Stroke.toJson]），旧格式是对象
  /// 数组 `[{x,y,p}, ...]`；解码侧按同样方式计数（扁平取 `length ~/ 3`，
  /// 与 `i + 2 < length` 的遍历边界一致）。
  static int declaredPointCount(Object? rawPoints) {
    if (rawPoints is! List || rawPoints.isEmpty) return 0;
    if (rawPoints.first is Map) return rawPoints.length;
    return rawPoints.length ~/ 3;
  }

  static int _declaredCount(Object? value) => value is List ? value.length : 0;

  /// 从 JSON 字节反序列化并执行防御性恢复。
  ///
  /// 根结构和文档 ID 损坏时抛出 [FormatException]；图层、笔画、形状和图片
  /// 属于可隔离对象，单个条目损坏不会阻止其余可靠内容打开。恢复阶段还会移除
  /// 重复 ID、危险几何和指向已不存在目标的箭头绑定，避免外部/旧版文件使渲染
  /// 或后续编辑陷入异常状态。
  ///
  /// 本方法**丢弃**完整性统计；需要知道「恢复了多少、被预算截掉了多少」的调用方
  /// 请用 [decodeDetailed]（批次 DN-003 的上报出口，`StorageService.load` 走它）。
  DrawingDocument decode(Uint8List bytes) => decodeDetailed(bytes).document;

  /// 解码并携带 [DocumentDecodeReport]（恢复了什么、丢了几笔/几层/几个对象）。
  ///
  /// 既有拒绝语义逐条保留、未放宽任何阈值：100MB 入口预检、高版本拒绝、
  /// 非法根结构/非法文档 ID 仍抛 [FormatException]；超预算仍是**静默截断而非
  /// 拒绝**（宽容回读是设计意图），只是不再无声——截断量进
  /// [DocumentDecodeReport.isBudgetTruncated]，由存储层据此拒绝覆盖原件。
  DecodedCanvasDocument decodeDetailed(Uint8List bytes) {
    // 入口大小预检（红蓝攻防 D-4 修复 2026-08-15）：拒绝超大文档，
    // 防恶意构造文件耗尽内存（OOM）。
    if (bytes.length > DocumentBudgets.maxFileBytes) {
      throw FormatException('文档过大（超过 100MB 限制），拒绝打开');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw FormatException('文档 JSON 格式无效');
    }
    if (decoded is! Map) {
      throw FormatException('文档根节点必须是对象');
    }
    // 版本只读降级（对齐 Saber SBN）：文件版本高于当前支持版本时，
    // 拒绝以旧逻辑解码（避免静默丢失新字段），提示用户升级应用。
    final fileVersionRaw = decoded['version'];
    if (fileVersionRaw is num && fileVersionRaw.toInt() > _version) {
      throw FormatException('文档版本过新（v$fileVersionRaw，当前支持 v$_version），请升级应用后再打开');
    }
    // 迁移管线（内核 P1-DOC-001，2026-10-10）：低于当前版本的文件按注册表
    // 逐级规范化（补缺键/回写版本号）；缺环节的文件保持原样交给下方宽容
    // 解码兜底——迁移层不新增拒绝路径。
    kDocumentMigrationRunner.migrateToCurrent(
      Map<String, dynamic>.from(decoded),
    );
    final documentValue = decoded['document'];
    if (documentValue is! Map) {
      throw FormatException('文档缺少 document 对象');
    }
    final document = Map<String, dynamic>.from(documentValue);
    final id = document['id'];
    if (id is! String || !_validDocumentId.hasMatch(id)) {
      throw FormatException('文档 ID 无效');
    }

    // 批次 DN-003：解码全过程的完整性累加器（截断不再无声）。
    final stats = DocumentDecodeStats();
    final layers = _restoreLayers(document['layers'], stats, id);
    final shapes = _restoreShapes(document['shapes'], stats, id);
    final imageItems = _restoreImageItems(document['imageItems'], stats, id);
    final textItems = _restoreTextItems(document['textItems'], stats, id);

    return DecodedCanvasDocument(
      document: DrawingDocument(
        id: id,
        title: document['title'] is String ? document['title'] as String : '',
        width: _restoreCanvasDimension(document['width'], 2048),
        height: _restoreCanvasDimension(document['height'], 1536),
        infinite: document['infinite'] == true,
        paperType: PaperType.values.firstWhere(
          (type) => type.name == document['paperType'],
          orElse: () => PaperType.blank,
        ),
        folder: document['folder'] is String ? document['folder'] as String : '',
        layers: layers,
        shapes: shapes,
        imageItems: imageItems,
        textItems: textItems,
        createdAt: timeFromIso(document['createdAt']),
        updatedAt: timeFromIso(document['updatedAt']),
      ),
      report: stats.toReport(id, bytes.length),
    );
  }

  static final RegExp _validDocumentId = RegExp(r'^[A-Za-z0-9_-]+$');

  // 防御预算（红蓝攻防 D-4 修复 2026-08-15 / 链 C / H-02 补全 / 军工审计）：
  // 防恶意 JSON 堆叠海量条目触发 OOM（拒绝服务），并防「写得出、读不回」的
  // 静默截断。数值本身**不在这里**——单一事实来源是
  // [DocumentBudgets]（批次 DN-003，2026-10-11），编码侧
  // [validateSnapshotForEncoding] 引用的是同一组常量，两侧不可能漂移。

  static int _restoreCanvasDimension(Object? value, int fallback) {
    if (value is! num || !value.toDouble().isFinite) return fallback;
    return value.toInt().clamp(16, 32768).toInt();
  }

  static List<Layer> _restoreLayers(
    Object? value,
    DocumentDecodeStats stats,
    String documentId,
  ) {
    final layers = <Layer>[];
    final ids = <String>{};
    // H-02 补全：全局笔画/点预算计数器。
    var totalStrokes = 0;
    var totalPoints = 0;
    if (value is List) {
      final limit = value.length.clamp(0, DocumentBudgets.maxLayerCount);
      if (value.length > limit) {
        stats.layersDroppedByCountBudget = value.length - limit;
        stats.violation(
          DocumentBudgetDimension.layerCount,
          value.length,
          documentId,
        );
      }
      for (var i = 0; i < limit; i++) {
        final entry = value[i];
        if (entry is! Map) {
          stats.invalidLayersDropped++;
          continue;
        }
        try {
          final json = Map<String, dynamic>.from(entry);
          final id = json['id'];
          if (id is! String || id.isEmpty || !ids.add(id)) {
            stats.invalidLayersDropped++;
            continue;
          }
          final opacity = json['opacity'];
          final safeOpacity = opacity is num && opacity.toDouble().isFinite
              ? opacity.toDouble().clamp(0.0, 1.0).toDouble()
              : 1.0;
          final strokes = _restoreStrokes(json['strokes'], stats, documentId);
          final layerPoints = strokes.fold(
            0,
            (sum, s) => sum + s.points.length,
          );
          // H-02 补全：全局笔画/点预算——超限跳过后续层（防 JSON 炸弹放大）。
          totalStrokes += strokes.length;
          totalPoints += layerPoints;
          final strokesOver =
              totalStrokes > DocumentBudgets.maxTotalStrokes;
          final pointsOver = totalPoints > DocumentBudgets.maxTotalPoints;
          if (strokesOver || pointsOver) {
            // 整层丢弃是**最重的一种静默截断**：本层与其后所有未处理层一条
            // 不剩。批次 DN-003 把它计入上报，并据此拒绝覆盖原件。
            stats.layersDroppedByGlobalBudget += limit - i;
            stats.strokesDroppedByGlobalBudget +=
                strokes.length + _declaredStrokesIn(value, i + 1, limit);
            stats.pointsDroppedByGlobalBudget +=
                layerPoints + _declaredPointsIn(value, i + 1, limit);
            stats.violation(
              strokesOver
                  ? DocumentBudgetDimension.totalStrokes
                  : DocumentBudgetDimension.totalPoints,
              strokesOver ? totalStrokes : totalPoints,
              documentId,
              note: 'layer#$i 起整层及后续层被丢弃',
            );
            break;
          }
          layers.add(
            Layer(
              id: id,
              name: json['name'] is String ? json['name'] as String : '图层',
              visible: json['visible'] is bool ? json['visible'] as bool : true,
              opacity: safeOpacity,
              strokes: strokes,
            ),
          );
          stats.layersRestored++;
          stats.strokesRestored += strokes.length;
          stats.pointsRestored += layerPoints;
        } catch (_) {
          // 局部对象损坏时继续恢复其余图层。
          stats.invalidLayersDropped++;
        }
      }
    }
    // 一个图层都没还原时补的默认空层不计入 restored（它不是文件内容）。
    return layers.isEmpty ? [Layer(id: 'layer_1', name: '')] : layers;
  }

  /// 尚未遍历到的层里声明的笔画数（整层丢弃时用于把丢弃量算准）。
  static int _declaredStrokesIn(List value, int from, int to) {
    var total = 0;
    for (var i = from; i < to; i++) {
      final entry = value[i];
      if (entry is! Map) continue;
      final strokes = entry['strokes'];
      if (strokes is List) total += strokes.length;
    }
    return total;
  }

  /// 尚未遍历到的层里声明的采样点数（同上，按 [declaredPointCount] 口径）。
  static int _declaredPointsIn(List value, int from, int to) {
    var total = 0;
    for (var i = from; i < to; i++) {
      final entry = value[i];
      if (entry is! Map) continue;
      final strokes = entry['strokes'];
      if (strokes is! List) continue;
      for (final stroke in strokes) {
        if (stroke is Map) total += declaredPointCount(stroke['points']);
      }
    }
    return total;
  }

  static List<Stroke> _restoreStrokes(
    Object? value,
    DocumentDecodeStats stats,
    String documentId,
  ) {
    final strokes = <Stroke>[];
    if (value is! List) return strokes;
    final limit = value.length.clamp(0, DocumentBudgets.maxStrokesPerLayer);
    if (value.length > limit) {
      stats.strokesDroppedByLayerBudget += value.length - limit;
      stats.violation(
        DocumentBudgetDimension.strokesPerLayer,
        value.length,
        documentId,
      );
    }
    for (var i = 0; i < limit; i++) {
      final entry = value[i];
      if (entry is! Map) {
        stats.invalidStrokesDropped++;
        continue;
      }
      try {
        final json = Map<String, dynamic>.from(entry);
        final rawPoints = json['points'];
        final color = json['color'];
        final width = json['width'];
        if (rawPoints is! List || color is! num || width is! num) {
          stats.invalidStrokesDropped++;
          continue;
        }
        final safeWidth = width.toDouble();
        if (!safeWidth.isFinite ||
            safeWidth <= 0 ||
            safeWidth > DocumentBudgets.maxStrokeWidth) {
          stats.invalidStrokesDropped++;
          continue;
        }
        final points = <StrokePoint>[];
        if (rawPoints.isNotEmpty && rawPoints.first is Map) {
          // 旧格式：对象数组 [{x,y,p}, ...]。
          for (var k = 0; k < rawPoints.length; k++) {
            if (points.length >= DocumentBudgets.maxPointsPerStroke) {
              stats.pointsDroppedByStrokeBudget += rawPoints.length - k;
              stats.violation(
                DocumentBudgetDimension.pointsPerStroke,
                rawPoints.length,
                documentId,
                note: 'stroke#$i',
              );
              break;
            }
            final pointValue = rawPoints[k];
            if (pointValue is! Map) {
              stats.invalidPointsDropped++;
              continue;
            }
            final point = StrokePoint.fromJson(
              Map<String, dynamic>.from(pointValue),
            );
            if (!_isSafeCoordinate(point.x) ||
                !_isSafeCoordinate(point.y) ||
                !point.pressure.isFinite) {
              stats.invalidPointsDropped++;
              continue;
            }
            points.add(
              StrokePoint(
                point.x,
                point.y,
                point.pressure.clamp(0.0, 1.0).toDouble(),
              ),
            );
          }
        } else {
          // 新格式（压缩点列）：扁平数值数组 [x0,y0,p0, x1,y1,p1, ...]。
          // 对齐 Saber SBN 二进制点列压缩思路，防御性恢复同步兼容。
          final flat = rawPoints.cast<num>();
          // 尾部不足三元组的残缺数据不会成点（对齐 `i + 2 < length` 的边界），
          // 计入「损坏剔除」而不是「预算截断」，两类丢弃在报告里永不混计。
          final remainder = flat.length % 3;
          if (remainder != 0) stats.invalidPointsDropped += remainder;
          for (var k = 0; k + 2 < flat.length; k += 3) {
            if (points.length >= DocumentBudgets.maxPointsPerStroke) {
              stats.pointsDroppedByStrokeBudget += (flat.length - k) ~/ 3;
              stats.violation(
                DocumentBudgetDimension.pointsPerStroke,
                flat.length ~/ 3,
                documentId,
                note: 'stroke#$i',
              );
              break;
            }
            final x = flat[k].toDouble();
            final y = flat[k + 1].toDouble();
            final p = flat[k + 2].toDouble();
            if (!_isSafeCoordinate(x) || !_isSafeCoordinate(y) || !p.isFinite) {
              stats.invalidPointsDropped++;
              continue;
            }
            points.add(StrokePoint(x, y, p.clamp(0.0, 1.0).toDouble()));
          }
        }
        if (points.isEmpty) {
          stats.invalidStrokesDropped++;
          continue;
        }
        final opacity = json['opacity'];
        strokes.add(
          Stroke(
            // id（格式 v3）：v2 及更早文件缺 id——迁移层（v2→v3）已补，
            // 此处宽容回读兜底（直构缺省时由构造器派生新 id）。
            id: json['id'] is String ? json['id'] as String : null,
            points: points,
            color: Color(color.toInt()),
            width: safeWidth,
            type: BrushType.values.firstWhere(
              (type) => type.name == json['type'],
              orElse: () => BrushType.pen,
            ),
            opacity: opacity is num && opacity.toDouble().isFinite
                ? opacity.toDouble().clamp(0.0, 1.0).toDouble()
                : 1.0,
            // 手写抖动种子与版本计数器必须回读：`Stroke.toJson` 一直在写这三项
            // （编码端无损），解码端漏掉就让每条笔画在重开时拿到**新的随机
            // seed**——同一张画重开后抖动/质感会变（用户眼中的「画面自己变了」），
            // 且 version/versionNonce 归零会让协作与增量同步的冲突检测失效。
            seed: _restoreNonNegativeInt(json['seed']),
            version: _restoreNonNegativeInt(json['version']) ?? 0,
            versionNonce: _restoreNonNegativeInt(json['versionNonce']) ?? 0,
          ),
        );
      } catch (_) {
        // 丢弃单条无法安全恢复的笔画。
        stats.invalidStrokesDropped++;
      }
    }
    return strokes;
  }

  static List<PageShapeItem> _restoreShapes(
    Object? value,
    DocumentDecodeStats stats,
    String documentId,
  ) {
    final shapes = <PageShapeItem>[];
    final ids = <String>{};
    if (value is List) {
      final limit = value.length.clamp(0, DocumentBudgets.maxShapeCount);
      if (value.length > limit) {
        stats.shapesDroppedByCountBudget += value.length - limit;
        stats.violation(
          DocumentBudgetDimension.shapeCount,
          value.length,
          documentId,
        );
      }
      for (var i = 0; i < limit; i++) {
        final entry = value[i];
        if (entry is! Map) {
          stats.invalidShapesDropped++;
          continue;
        }
        try {
          final shape = PageShapeItem.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (shape.id.isEmpty ||
              !ids.add(shape.id) ||
              !_isSafeCoordinate(shape.x) ||
              !_isSafeCoordinate(shape.y) ||
              !shape.width.isFinite ||
              !shape.height.isFinite ||
              shape.width <= 0 ||
              shape.height <= 0 ||
              shape.width > DocumentBudgets.maxObjectExtent ||
              shape.height > DocumentBudgets.maxObjectExtent ||
              !shape.rotation.isFinite) {
            stats.invalidShapesDropped++;
            continue;
          }
          shape.strokeWidth =
              shape.strokeWidth.isFinite &&
                  shape.strokeWidth > 0 &&
                  shape.strokeWidth <= DocumentBudgets.maxStrokeWidth
              ? shape.strokeWidth
              : 3;
          shapes.add(shape);
          stats.shapesRestored++;
        } catch (_) {
          // 丢弃单个无效形状，保留文档中其余对象。
          stats.invalidShapesDropped++;
        }
      }
    }

    final bindableIds = shapes
        .where(
          (shape) =>
              shape.shapeType == ShapeType.rect ||
              shape.shapeType == ShapeType.ellipse ||
              shape.shapeType == ShapeType.diamond,
        )
        .map((shape) => shape.id)
        .toSet();
    for (final shape in shapes) {
      if (shape.shapeType != ShapeType.arrow) {
        shape
          ..startBinding = null
          ..endBinding = null;
        continue;
      }
      if (!bindableIds.contains(shape.startBinding?.targetShapeId)) {
        shape.startBinding = null;
      }
      if (!bindableIds.contains(shape.endBinding?.targetShapeId)) {
        shape.endBinding = null;
      }
    }
    return shapes;
  }

  static List<DocumentImageItem> _restoreImageItems(
    Object? value,
    DocumentDecodeStats stats,
    String documentId,
  ) {
    final images = <DocumentImageItem>[];
    final ids = <String>{};
    if (value is! List) return images;
    final limit = value.length.clamp(0, DocumentBudgets.maxImageCount);
    if (value.length > limit) {
      stats.imagesDroppedByCountBudget += value.length - limit;
      stats.violation(
        DocumentBudgetDimension.imageCount,
        value.length,
        documentId,
      );
    }
    for (var i = 0; i < limit; i++) {
      final entry = value[i];
      if (entry is! Map) {
        stats.invalidImagesDropped++;
        continue;
      }
      try {
        final item = DocumentImageItem.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (item.id.isEmpty ||
            !ids.add(item.id) ||
            item.filePath.isEmpty ||
            !_isSafeCoordinate(item.x) ||
            !_isSafeCoordinate(item.y) ||
            !item.width.isFinite ||
            !item.height.isFinite ||
            item.width <= 0 ||
            item.height <= 0 ||
            item.width > DocumentBudgets.maxObjectExtent ||
            item.height > DocumentBudgets.maxObjectExtent) {
          stats.invalidImagesDropped++;
          continue;
        }
        images.add(item);
        stats.imagesRestored++;
      } catch (_) {
        // 图片文件是否存在由惰性解码层决定；只有模型无效时才隔离对象。
        stats.invalidImagesDropped++;
      }
    }
    return images;
  }

  /// 画布/页面文字块恢复（与 shapes/images 同一防御口径）：
  /// id 必填且不重复、坐标与字号必须有限且在范围内，非法项单独丢弃。
  /// 旧文档没有 `textItems` 键 → 返回空表，行为与修复前一致。
  static List<PageTextItem> _restoreTextItems(
    Object? value,
    DocumentDecodeStats stats,
    String documentId,
  ) {
    final texts = <PageTextItem>[];
    final ids = <String>{};
    if (value is! List) return texts;
    final limit = value.length.clamp(0, DocumentBudgets.maxTextCount);
    if (value.length > limit) {
      stats.textItemsDroppedByCountBudget += value.length - limit;
      stats.violation(
        DocumentBudgetDimension.textCount,
        value.length,
        documentId,
      );
    }
    for (var i = 0; i < limit; i++) {
      final entry = value[i];
      if (entry is! Map) {
        stats.invalidTextItemsDropped++;
        continue;
      }
      try {
        final item = PageTextItem.fromJson(Map<String, dynamic>.from(entry));
        if (item.id.isEmpty ||
            !ids.add(item.id) ||
            !_isSafeCoordinate(item.x) ||
            !_isSafeCoordinate(item.y) ||
            !item.fontSize.isFinite ||
            item.fontSize <= 0 ||
            item.fontSize > DocumentBudgets.maxFontSize) {
          stats.invalidTextItemsDropped++;
          continue;
        }
        texts.add(item);
        stats.textItemsRestored++;
      } catch (_) {
        // 单条文字无法安全恢复时隔离该条，其余内容照常可读。
        stats.invalidTextItemsDropped++;
      }
    }
    return texts;
  }

  static bool _isSafeCoordinate(double value) =>
      value.isFinite && value.abs() <= DocumentBudgets.maxCoordinateMagnitude;

  /// 恢复单调递增的整数（种子/版本号）：缺失、非数字、负数或不有限时返回
  /// null，让 `Stroke` 自己按旧文档语义生成——旧文件没有这些字段时行为不变。
  static int? _restoreNonNegativeInt(Object? value) {
    if (value is! num) return null;
    if (!value.isFinite || value < 0) return null;
    return value.toInt();
  }
}

/// 一次解码的产物：文档 + 完整性统计（批次 DN-003）。
///
/// 与 [DocumentCodec.decode] 的区别只在于**把截断量说清楚**，恢复语义完全一致。
class DecodedCanvasDocument {
  const DecodedCanvasDocument({
    required this.document,
    required this.report,
  });

  final DrawingDocument document;

  /// 「恢复了什么、丢了几笔/几层/几个对象」的量化上报。
  final DocumentDecodeReport report;
}

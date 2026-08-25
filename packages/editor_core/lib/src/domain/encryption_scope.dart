// editor_core——EncryptionScope 加密对象选择（用户需求——2026-08-22）。
//
// 加密对象选择：a) 对整个应用加密 b) 对单个笔记/画板加密。
// 加密后的笔记/画面不能在首页预览（EncryptionScopeService.filterForHomePreview）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
library;

/// 加密对象类型（用户需求：整个应用 or 单个笔记/画板）。
enum EncryptionScopeType {
  /// 应用级加密（加密整个应用——所有笔记/画板）。
  app,

  /// 笔记级加密（加密单个笔记/画板——其余不加密）。
  note,
}

/// 加密对象（不可变）。
class EncryptionScope {
  const EncryptionScope({
    required this.type,
    this.objectId = '',
    this.encrypted = false,
  });

  /// 加密对象类型（app/note）。
  final EncryptionScopeType type;

  /// 笔记/画板 ID（note 类型时——app 类型为空）。
  final String objectId;

  /// 是否加密。
  final bool encrypted;

  EncryptionScope copyWith({bool? encrypted}) {
    return EncryptionScope(
      type: type,
      objectId: objectId,
      encrypted: encrypted ?? this.encrypted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptionScope && type == other.type && objectId == other.objectId;

  @override
  int get hashCode => Object.hash(type, objectId);
}

/// 加密对象选择服务（用户需求——积木式纯 Dart）。
///
/// 功能：
/// - 应用级加密开关（setAppEncrypted——加密整个应用）
/// - 笔记级加密（setNoteEncrypted——加密单个笔记/画板）
/// - 查询（isEncrypted——加密状态）
/// - 首页预览过滤（filterForHomePreview——加密项不预览）
class EncryptionScopeService {
  const EncryptionScopeService({
    this.scopes = const [],
  });

  /// 已设置的加密对象列表。
  final List<EncryptionScope> scopes;

  /// 应用级加密是否开启。
  bool get appEncrypted =>
      scopes.any((s) => s.type == EncryptionScopeType.app && s.encrypted);

  /// 设置应用级加密（加密整个应用）。
  EncryptionScopeService setAppEncrypted(bool encrypted) {
    final others = scopes
        .where((s) => s.type != EncryptionScopeType.app)
        .toList();
    return EncryptionScopeService(scopes: [
      ...others,
      EncryptionScope(type: EncryptionScopeType.app, encrypted: encrypted),
    ]);
  }

  /// 设置单个笔记/画板加密。
  EncryptionScopeService setNoteEncrypted(String objectId, bool encrypted) {
    final others = scopes
        .where((s) => s.type != EncryptionScopeType.note || s.objectId != objectId)
        .toList();
    return EncryptionScopeService(scopes: [
      ...others,
      EncryptionScope(
        type: EncryptionScopeType.note,
        objectId: objectId,
        encrypted: encrypted,
      ),
    ]);
  }

  /// 查询加密状态（app 级加密则所有都加密；否则查单个笔记）。
  bool isEncrypted(String objectId) {
    if (appEncrypted) return true;
    return scopes.any((s) =>
        s.type == EncryptionScopeType.note &&
        s.objectId == objectId &&
        s.encrypted);
  }

  /// 已加密的笔记/画板 ID 列表。
  List<String> get encryptedNoteIds => scopes
      .where((s) => s.type == EncryptionScopeType.note && s.encrypted)
      .map((s) => s.objectId)
      .toList();

  /// 首页预览过滤（用户需求：加密笔记/画面不能在首页预览）。
  ///
  /// 输入所有笔记 ID——输出可预览的（排除加密项）。
  List<String> filterForHomePreview(List<String> allIds) {
    if (appEncrypted) return const []; // 应用级加密——全部不预览。
    final encrypted = encryptedNoteIds.toSet();
    return allIds.where((id) => !encrypted.contains(id)).toList();
  }

  int get count => scopes.length;

  EncryptionScopeService copyWith({List<EncryptionScope>? scopes}) {
    return EncryptionScopeService(scopes: scopes ?? this.scopes);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EncryptionScopeService && count == other.count;

  @override
  int get hashCode => count.hashCode;
}

// editor_core——EncryptionAccessService 加密访问控制（用户需求——2026-08-22）。
//
// 用户需求：密码盘创建后没起到加密作用——没有加密单一笔记本，
// 也没加密整个软件——应该靠用户选择；再次打开软件/笔记时需要密码。
//
// 框架级设计：访问控制（app 级/note 级——再次打开需密码——
// 会话解锁/锁定——接入 EncryptionScope 对象选择）。
// 纯 Dart 不可变——可独立测试——不搞崩。
library;

import 'encryption_scope.dart';

/// 加密访问状态（不可变——单一状态源）。
class EncryptionAccessState {
  const EncryptionAccessState({
    this.appEncrypted = false,
    this.appUnlocked = false,
    this.encryptedIds = const {},
    this.unlockedIds = const {},
  });

  /// 应用级加密（整个软件——用户选择）。
  final bool appEncrypted;

  /// 应用已解锁（本次会话——打开软件时验证）。
  final bool appUnlocked;

  /// 笔记级加密 ID 集合（用户选择——单个笔记/画板）。
  final Set<String> encryptedIds;

  /// 已解锁的笔记 ID（本次会话）。
  final Set<String> unlockedIds;

  EncryptionAccessState copyWith({
    bool? appEncrypted,
    bool? appUnlocked,
    Set<String>? encryptedIds,
    Set<String>? unlockedIds,
  }) {
    return EncryptionAccessState(
      appEncrypted: appEncrypted ?? this.appEncrypted,
      appUnlocked: appUnlocked ?? this.appUnlocked,
      encryptedIds: encryptedIds ?? this.encryptedIds,
      unlockedIds: unlockedIds ?? this.unlockedIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptionAccessState &&
          appEncrypted == other.appEncrypted &&
          appUnlocked == other.appUnlocked;

  @override
  int get hashCode => Object.hash(appEncrypted, appUnlocked);
}

/// 加密访问服务（框架级——对象选择 + 再次打开需密码）。
///
/// 用户需求实现：
/// 1. 用户选择加密对象（app 级/note 级——EncryptionScopeService）
/// 2. 再次打开软件/笔记——需密码（requiresPassword）
/// 3. 解锁后本次会话可用（unlockedIds/appUnlocked）
/// 4. 锁定/退出——清除解锁状态（再次打开需密码）
class EncryptionAccessService {
  const EncryptionAccessService();

  /// 从加密对象选择服务构建访问状态（用户需求：让用户选择）。
  static EncryptionAccessState fromScope(EncryptionScopeService scope) {
    return EncryptionAccessState(
      appEncrypted: scope.appEncrypted,
      encryptedIds: scope.encryptedNoteIds.toSet(),
    );
  }

  /// 打开应用/笔记——是否需要密码（用户需求：再次打开需密码）。
  ///
  /// [objectId]：null = 打开整个软件（app 级）；否则 = 打开单个笔记。
  bool requiresPassword(EncryptionAccessState state, {String? objectId}) {
    if (objectId == null) {
      // 打开整个软件——app 级加密且未解锁。
      return state.appEncrypted && !state.appUnlocked;
    }
    // 打开单个笔记——app 级加密（且未解锁）或笔记加密（且未解锁）。
    if (state.appEncrypted && !state.appUnlocked) return true;
    return state.encryptedIds.contains(objectId) &&
        !state.unlockedIds.contains(objectId);
  }

  /// 解锁整个应用（输入正确密码后）。
  EncryptionAccessState unlockApp(EncryptionAccessState state) {
    return state.copyWith(appUnlocked: true);
  }

  /// 解锁单个笔记。
  EncryptionAccessState unlockNote(EncryptionAccessState state, String objectId) {
    final unlocked = Set<String>.from(state.unlockedIds)..add(objectId);
    return state.copyWith(unlockedIds: unlocked);
  }

  /// 锁定（清除解锁状态——再次打开需密码）。
  EncryptionAccessState lock(EncryptionAccessState state) {
    return state.copyWith(appUnlocked: false, unlockedIds: const {});
  }

  /// 当前是否可访问（app 级/note 级——已解锁）。
  bool canAccess(EncryptionAccessState state, {String? objectId}) {
    return !requiresPassword(state, objectId: objectId);
  }
}

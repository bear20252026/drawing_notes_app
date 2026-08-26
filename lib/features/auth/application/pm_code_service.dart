import '../domain/value_objects/auth_result.dart';

/// PM 码服务 — Application 层。
///
/// 管理 PM 码（个人识别码）的验证逻辑。
/// PM 码用于敏感操作的二次确认（如删除笔记本、导出数据等）。
class PmCodeService {
  final String? _pmCode;

  const PmCodeService({String? pmCode}) : _pmCode = pmCode;

  /// 是否已设置 PM 码
  bool get isConfigured => _pmCode != null && _pmCode!.isNotEmpty;

  /// 验证 PM 码
  AuthResult verify(String input) {
    if (!isConfigured) {
      return const AuthFailure(reason: AuthFailureReason.notConfigured);
    }

    if (input == _pmCode) {
      return const AuthSuccess();
    }

    return const AuthFailure(
      reason: AuthFailureReason.invalidCredentials,
    );
  }
}

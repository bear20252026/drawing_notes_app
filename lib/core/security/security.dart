/// 安全模块入口 — 统一导出核心安全接口和常量。
///
/// 使用方式：
/// ```dart
/// import 'package:drawing_notes_app/core/security/security.dart';
/// ```
///
/// 本模块提供：
/// - 认证服务接口 ([AuthService])
/// - 会话服务接口 ([SessionService])
/// - 生物识别服务接口 ([BiometricService])
/// - PM码服务接口 ([PmCodeService])
/// - 安全常量 ([SecurityConstants])
/// - 安全领域模型 ([AuthToken], [SessionInfo])
library;

// ─── 接口 ──────────────────────────────────────────────────
export 'interfaces/auth_service.dart';
export 'interfaces/session_service.dart';
export 'interfaces/biometric_service.dart';
export 'interfaces/pm_code_service.dart';

// ─── 领域模型 ──────────────────────────────────────────────
export 'domain/auth_token.dart';
export 'domain/session.dart';

// ─── 常量 ──────────────────────────────────────────────────
export 'constants/security_constants.dart';

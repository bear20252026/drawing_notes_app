/// 会话服务抽象接口 — 管理应用生命周期相关的会话行为。
///
/// 职责：
/// - 监听应用前后台切换
/// - 根据策略自动锁定
/// - 会话超时管理
library;

import 'auth_service.dart';

/// 会话事件类型。
enum SessionEvent {
  /// 应用进入后台。
  paused,

  /// 应用回到前台。
  resumed,

  /// 应用被终止。
  terminated,
}

/// 会话服务抽象接口。
abstract class SessionService {
  /// 认证服务引用（用于锁定操作）。
  AuthService get authService;

  /// 当前是否处于活跃会话。
  bool get isActive;

  /// 上次活跃时间戳（毫秒）。
  int? get lastActiveAt;

  /// 会话事件流。
  Stream<SessionEvent> get onSessionEvent;

  /// 初始化会话服务（开始监听生命周期）。
  void initialize();

  /// 处置会话服务（停止监听）。
  void dispose();

  /// 手动标记活跃（重置超时计时器）。
  void markActive();

  /// 处理应用生命周期变更。
  void handleAppLifecycleState(String state);
}

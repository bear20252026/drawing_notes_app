// 纯逻辑部件：异步导入过期/取消守卫（drawing_notes_app）。
// 无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

/// 导入请求的生命周期状态。
enum ImportLifecycleState {
  /// 无进行中的导入。
  idle,

  /// 存在当前有效的导入请求。
  active,

  /// 当前请求已被显式取消。
  cancelled,

  /// 当前请求已过期（被新请求替代或页面退出）。
  stale,
}

/// 不可变的导入请求令牌。
///
/// 每次 [ImportGuard.beginImport] 调用生成一个严格递增 [generation] 的新
/// 令牌。旧令牌在生成新令牌后立即变为 stale，从而保证"旧请求晚返回覆盖
/// 新选择"的竞态被拦截。
class ImportRequestToken {
  const ImportRequestToken(this.generation);

  /// 严格递增的代次编号。0 保留为"无请求"哨兵值。
  final int generation;

  /// 当 guard 仍视此 token 为 current 时为 true。
  bool isCurrent(ImportGuard guard) => guard.isCurrent(this);

  /// 当 guard 已视此 token 为 stale 时为 true。
  bool isStale(ImportGuard guard) => guard.isStale(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportRequestToken &&
          runtimeType == other.runtimeType &&
          generation == other.generation;

  @override
  int get hashCode => generation.hashCode;

  @override
  String toString() => 'ImportRequestToken(generation: $generation)';
}

/// 纯逻辑导入守卫。
///
/// 职责：
/// - 通过 generation token 标记"当前有效"请求；
/// - 新请求自动使旧请求 stale；
/// - 页面退出时一键作废所有进行中请求；
/// - complete / cancel 仅在 token 仍 current 时生效。
///
/// 不触发 I/O、不持有 BuildContext、不调用 setState。
class ImportGuard {
  ImportGuard._(this._lastGeneration, _GuardState state) : _state = state;

  /// 创建处于 idle 状态的 guard。
  factory ImportGuard.initial() =>
      ImportGuard._(0, _GuardState(current: null, lifecycle: ImportLifecycleState.idle));

  /// 已发放的最大 generation，保证严格递增不回落。
  int _lastGeneration;

  _GuardState _state;

  /// 启动一次新导入，返回新 token。
  ///
  /// 若已有 current token，则将其标记为 stale；新 token 的 generation
  /// 严格递增。返回的 token 处于 active 状态。
  ImportRequestToken beginImport() {
    final nextGeneration = ++_lastGeneration;
    final token = ImportRequestToken(nextGeneration);
    _state = _GuardState(current: token, lifecycle: ImportLifecycleState.active);
    return token;
  }

  /// 完成一次导入。仅当 [token] 为 current 时生效并返回 true。
  ///
  /// 完成后 guard 回到 idle 状态。
  bool complete(ImportRequestToken token) {
    if (!isCurrent(token)) return false;
    _state = _GuardState(current: null, lifecycle: ImportLifecycleState.idle);
    return true;
  }

  /// 取消一次导入。仅当 [token] 为 current 时生效并返回 true。
  ///
  /// 取消后 guard 进入 cancelled 状态。
  bool cancel(ImportRequestToken token) {
    if (!isCurrent(token)) return false;
    _state = _GuardState(current: null, lifecycle: ImportLifecycleState.cancelled);
    return true;
  }

  /// 页面退出/销毁时调用，将所有进行中请求标记为 stale。
  void invalidateAll() {
    if (_state.current != null) {
      _state = _GuardState(current: null, lifecycle: ImportLifecycleState.stale);
    }
  }

  /// [token] 是否为当前有效请求。
  bool isCurrent(ImportRequestToken token) =>
      _state.lifecycle == ImportLifecycleState.active &&
      _state.current == token;

  /// [token] 是否已过期（stale）。
  ///
  /// 当 guard 已处于 stale 状态，或 token 的 generation 小于当前
  /// current token 的 generation 时返回 true。
  bool isStale(ImportRequestToken token) {
    if (_state.lifecycle == ImportLifecycleState.stale) return true;
    final current = _state.current;
    if (current == null) return true;
    return token.generation < current.generation;
  }

  /// 当前生命周期状态。
  ImportLifecycleState get lifecycle => _state.lifecycle;

  /// 当前 current token（可能为 null）。
  ImportRequestToken? get currentToken => _state.current;
}

/// Guard 内部不可变状态记录。
class _GuardState {
  const _GuardState({required this.current, required this.lifecycle});

  final ImportRequestToken? current;
  final ImportLifecycleState lifecycle;
}

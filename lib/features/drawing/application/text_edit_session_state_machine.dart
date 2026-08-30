/// 文字编辑会话的纯逻辑状态机。
///
/// 把散落在页面中的隐式分支（退出是否提交 / 失焦是否提交 / 取消是否生成
/// 历史 / 重复提交是否通知两次）收敛为确定性的状态迁移表。
///
/// 纯 Dart：无 Flutter / `dart:io` / `ui.Image` 依赖，不持有任何
/// controller / Widget / 领域实例 / 存储引用。持有且仅持有当前阶段
/// 作为唯一状态源；相同 (phase, event) 输入始终产生相同的
/// [TextEditSessionTransition] 输出。
library;

/// 文字编辑会话的阶段。
enum TextEditSessionPhase {
  /// 空闲：无进行中的编辑会话。
  idle,

  /// 编辑中：用户正在输入/编辑文字。
  editing,

  /// 提交中：正在执行提交（持久化 / 历史快照）。
  committing,

  /// 取消中：正在执行取消（丢弃编辑）。
  canceling,

  /// 已落定：一次编辑会话已结束（提交或取消完成），等待 reset。
  settled,
}

/// 文字编辑会话的输入事件。
enum TextEditSessionEvent {
  /// 开始一次编辑会话。
  begin,

  /// 用户请求提交（如点击完成按钮）。
  commitRequest,

  /// 用户请求取消（如点击取消按钮）。
  cancelRequest,

  /// 编辑框失焦。
  focusLost,

  /// 提交操作成功完成。
  commitSucceeded,

  /// 提交操作失败。
  commitFailed,

  /// 强制重置到 idle（如页面销毁 / 新建会话）。
  reset,
}

/// 状态机在一次迁移中声明的副作用意图。
///
/// 所有字段默认 `false`；仅声明，不执行。页面按意图执行对应动作。
class TextEditSessionSideEffects {
  const TextEditSessionSideEffects({
    this.shouldCommit = false,
    this.shouldCancel = false,
    this.shouldSnapshot = false,
    this.shouldNotify = false,
    this.shouldSuppressDuplicateCommit = false,
  });

  /// 是否应执行提交（写入文档 / 持久化）。
  final bool shouldCommit;

  /// 是否应执行取消（丢弃编辑内容）。
  final bool shouldCancel;

  /// 是否应生成历史快照（撤销 / 重做）。
  final bool shouldSnapshot;

  /// 是否应通知一次（如 UI toast / 变更回调）。
  final bool shouldNotify;

  /// 是否应抑制重复提交（已在提交中时再次收到提交请求）。
  final bool shouldSuppressDuplicateCommit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextEditSessionSideEffects &&
          other.shouldCommit == shouldCommit &&
          other.shouldCancel == shouldCancel &&
          other.shouldSnapshot == shouldSnapshot &&
          other.shouldNotify == shouldNotify &&
          other.shouldSuppressDuplicateCommit == shouldSuppressDuplicateCommit;

  @override
  int get hashCode => Object.hash(
    shouldCommit,
    shouldCancel,
    shouldSnapshot,
    shouldNotify,
    shouldSuppressDuplicateCommit,
  );
}

/// 一次状态迁移的结果：新阶段 + 副作用意图。
class TextEditSessionTransition {
  const TextEditSessionTransition({
    required this.phase,
    required this.sideEffects,
  });

  /// 迁移后的新阶段。
  final TextEditSessionPhase phase;

  /// 本次迁移声明的副作用意图。
  final TextEditSessionSideEffects sideEffects;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextEditSessionTransition &&
          other.phase == phase &&
          other.sideEffects == sideEffects;

  @override
  int get hashCode => Object.hash(phase, sideEffects);
}

/// 文字编辑会话的纯逻辑状态机。
///
/// 通过 [event] 接收输入事件，按当前阶段执行状态迁移，返回包含
/// 新阶段与副作用意图的 [TextEditSessionTransition]。
///
/// 约束：
/// - 纯 Dart，无 Flutter / `dart:io` / `ui.Image` 依赖。
/// - 不持有 controller / Widget / 领域实例 / 存储引用。
/// - 持有且仅持有当前阶段作为唯一状态源。
/// - 相同 (phase, event) 输入始终产生相同的输出（确定性）。
class TextEditSessionStateMachine {
  /// 创建状态机，初始阶段为 [TextEditSessionPhase.idle]。
  TextEditSessionStateMachine({
    TextEditSessionPhase initialPhase = TextEditSessionPhase.idle,
  }) : _phase = initialPhase;

  TextEditSessionPhase _phase;

  /// 当前阶段（只读）。
  TextEditSessionPhase get phase => _phase;

  /// 输入 [event]，按当前阶段执行状态迁移，返回
  /// [TextEditSessionTransition]。
  ///
  /// 迁移后状态机的 [phase] 更新为新阶段。
  TextEditSessionTransition event(TextEditSessionEvent event) {
    switch (_phase) {
      case TextEditSessionPhase.idle:
        return _onIdle(event);
      case TextEditSessionPhase.editing:
        return _onEditing(event);
      case TextEditSessionPhase.committing:
        return _onCommitting(event);
      case TextEditSessionPhase.canceling:
        return _onCanceling(event);
      case TextEditSessionPhase.settled:
        return _onSettled(event);
    }
  }

  TextEditSessionTransition _onIdle(TextEditSessionEvent event) {
    switch (event) {
      case TextEditSessionEvent.begin:
        _phase = TextEditSessionPhase.editing;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.editing,
          sideEffects: TextEditSessionSideEffects(),
        );
      case TextEditSessionEvent.reset:
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.idle,
          sideEffects: TextEditSessionSideEffects(),
        );
      default:
        // 非法迁移：保持当前阶段，无副作用。
        return TextEditSessionTransition(
          phase: _phase,
          sideEffects: const TextEditSessionSideEffects(),
        );
    }
  }

  TextEditSessionTransition _onEditing(TextEditSessionEvent event) {
    switch (event) {
      case TextEditSessionEvent.commitRequest:
        _phase = TextEditSessionPhase.committing;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.committing,
          sideEffects: TextEditSessionSideEffects(
            shouldCommit: true,
            shouldSnapshot: true,
            shouldNotify: true,
          ),
        );
      case TextEditSessionEvent.focusLost:
        // 失焦触发提交，与显式提交语义一致。
        _phase = TextEditSessionPhase.committing;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.committing,
          sideEffects: TextEditSessionSideEffects(
            shouldCommit: true,
            shouldSnapshot: true,
            shouldNotify: true,
          ),
        );
      case TextEditSessionEvent.cancelRequest:
        _phase = TextEditSessionPhase.canceling;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.canceling,
          sideEffects: TextEditSessionSideEffects(
            shouldCancel: true,
            shouldNotify: true,
            // shouldSnapshot 保持 false：取消不生成历史快照。
          ),
        );
      case TextEditSessionEvent.reset:
        _phase = TextEditSessionPhase.idle;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.idle,
          sideEffects: TextEditSessionSideEffects(),
        );
      default:
        return TextEditSessionTransition(
          phase: _phase,
          sideEffects: const TextEditSessionSideEffects(),
        );
    }
  }

  TextEditSessionTransition _onCommitting(TextEditSessionEvent event) {
    switch (event) {
      case TextEditSessionEvent.commitSucceeded:
        _phase = TextEditSessionPhase.settled;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.settled,
          sideEffects: TextEditSessionSideEffects(shouldNotify: true),
        );
      case TextEditSessionEvent.commitFailed:
        _phase = TextEditSessionPhase.editing;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.editing,
          sideEffects: TextEditSessionSideEffects(shouldNotify: true),
        );
      case TextEditSessionEvent.commitRequest:
        // 重复提交抑制：已在提交中，不再触发新的提交 / 通知。
        return TextEditSessionTransition(
          phase: _phase,
          sideEffects: const TextEditSessionSideEffects(
            shouldSuppressDuplicateCommit: true,
          ),
        );
      case TextEditSessionEvent.reset:
        _phase = TextEditSessionPhase.idle;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.idle,
          sideEffects: TextEditSessionSideEffects(),
        );
      default:
        return TextEditSessionTransition(
          phase: _phase,
          sideEffects: const TextEditSessionSideEffects(),
        );
    }
  }

  TextEditSessionTransition _onCanceling(TextEditSessionEvent event) {
    switch (event) {
      case TextEditSessionEvent.commitSucceeded:
        // 取消操作完成，进入 settled。
        _phase = TextEditSessionPhase.settled;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.settled,
          sideEffects: TextEditSessionSideEffects(shouldNotify: true),
        );
      case TextEditSessionEvent.commitFailed:
        // 取消失败，回到编辑状态。
        _phase = TextEditSessionPhase.editing;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.editing,
          sideEffects: TextEditSessionSideEffects(shouldNotify: true),
        );
      case TextEditSessionEvent.reset:
        _phase = TextEditSessionPhase.idle;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.idle,
          sideEffects: TextEditSessionSideEffects(),
        );
      default:
        return TextEditSessionTransition(
          phase: _phase,
          sideEffects: const TextEditSessionSideEffects(),
        );
    }
  }

  TextEditSessionTransition _onSettled(TextEditSessionEvent event) {
    switch (event) {
      case TextEditSessionEvent.reset:
        _phase = TextEditSessionPhase.idle;
        return const TextEditSessionTransition(
          phase: TextEditSessionPhase.idle,
          sideEffects: TextEditSessionSideEffects(),
        );
      default:
        // settled 后忽略所有非 reset 事件。
        return TextEditSessionTransition(
          phase: _phase,
          sideEffects: const TextEditSessionSideEffects(),
        );
    }
  }
}

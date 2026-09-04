// 首页置顶解锁按钮（一键直达解锁）。
//
// 原 `lib/fix/security_and_sync_fix.dart` PART 4（M1 目录迁移，行为零变化）。

import 'package:flutter/material.dart';

class HomeLockButton extends StatelessWidget {
  const HomeLockButton({
    super.key,
    required this.isUnlocked,
    required this.onUnlockRequested,
    this.onLockRequested,
  });

  final bool isUnlocked;
  final VoidCallback onUnlockRequested;
  final VoidCallback? onLockRequested;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isUnlocked ? '锁定' : '解锁',
      icon: Icon(
        isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
        color: isUnlocked
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      onPressed: isUnlocked
          ? (onLockRequested ?? onUnlockRequested)
          : onUnlockRequested,
    );
  }
}

/// 编辑器斜杠命令菜单状态控制器（C-04 交互状态机拆分）。
///
/// 纯逻辑 + ChangeNotifier：菜单开关、键盘 ↑↓ 高亮、提交后关闭。
/// 页面 part 文件经 getter/setter 代理本控制器，不再各自持有裸 bool/int。
library;

import 'package:flutter/foundation.dart';

/// 斜杠命令菜单的交互状态（V-08：↑↓/Enter/Esc 驱动）。
class EditorSlashMenuController extends ChangeNotifier {
  bool _open = false;
  int _highlight = 0;

  bool get open => _open;
  int get highlight => _highlight;

  /// 打开或关闭菜单；打开时高亮归零。
  void setOpen(bool value) {
    if (_open == value) return;
    _open = value;
    if (value) _highlight = 0;
    notifyListeners();
  }

  void close() => setOpen(false);

  /// 强制设置高亮（测试/装配用）。
  void setHighlight(int value) {
    if (_highlight == value) return;
    _highlight = value;
    notifyListeners();
  }

  /// 高亮重置到 0（菜单打开或重新计算命令列表时）。
  void resetHighlight() => setHighlight(0);

  /// 下一项（循环）。
  void moveNext(int itemCount) {
    if (itemCount <= 0) return;
    setHighlight((_highlight + 1) % itemCount);
  }

  /// 上一项（循环）。
  void movePrev(int itemCount) {
    if (itemCount <= 0) return;
    setHighlight((_highlight - 1 + itemCount) % itemCount);
  }

  /// 取当前高亮项；越界时回退到 0 或 null。
  T? selected<T>(List<T> items) {
    if (items.isEmpty) return null;
    return items[_highlight.clamp(0, items.length - 1)];
  }
}

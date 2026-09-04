// 由 Claude 团队生成 | Drawing Notes App
// Edgeless 命令面板（⌘K / Ctrl+K）：AFFiNE「画布命令面板 / 画布内搜索」的 1:1 等价物。
//
// 职责：把画布上的常用操作（编辑/视图/选择/跳转帧）收敛为一个可搜索的命令列表，
// 并以一个模态底部面板（悬浮搜索）触发。纯展示层，只依赖 controller + domain。
//
// 分层：presentation →（只 import features/notes 内部）domain；不 import drawing/chart
// 实现层（架构规则 3）。命令模型、构建、搜索均为纯函数，可独立单测。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_controller.dart';
import '../../../core/theme/apple_design.dart';

/// 一条可执行命令。
class EdgelessCommand {
  const EdgelessCommand({
    required this.id,
    required this.label,
    required this.group,
    required this.icon,
    required this.run,
    this.hint,
    this.enabled = true,
    this.keyword = '',
  });

  final String id;
  final String label;

  /// 分组名（编辑/视图/选择/跳转），用于结果列表的分组标题。
  final String group;

  final IconData icon;

  /// 执行动作（已捕获 controller / 视图回调，无需再传参）。
  final VoidCallback run;

  /// 次要说明文本（如「需 ≥2 帧」）。
  final String? hint;

  /// 命令是否可执行（如「编组」仅在多选 ≥2 时可用）。
  final bool enabled;

  /// 额外检索关键词（拼音等价物、别名），用于模糊搜索。
  final String keyword;
}

/// 帧的展示标题：以内部文档标题为名，无标题显示「未命名 N」。
String edgelessFrameTitle(String title, int index) {
  final t = title.trim();
  return t.isEmpty ? '未命名　${index + 1}' : t;
}

/// 构建画布命令列表（含通用操作 + 每个帧的「跳转到帧」）。
///
/// [onFitContent] / [onFitSelection] 由页面提供（需要 viewport 尺寸）；
/// 传入 null 时对应「适应」命令被禁用。
List<EdgelessCommand> buildEdgelessCommands(
  EdgelessController c, {
  VoidCallback? onFitContent,
  VoidCallback? onFitSelection,
}) {
  final frames = c.doc.frames;
  final hasSelection = c.selectedFrameIds.isNotEmpty;
  final multiSelect = c.multiSelectMode;
  final connect = c.connectMode;
  final primary = c.primarySelectedFrameId;

  final commands = <EdgelessCommand>[
    // ── 编辑 ──────────────────────────────────────────────
    EdgelessCommand(
      id: 'add-note',
      label: '新建便签',
      group: '编辑',
      icon: Icons.note_add_outlined,
      keyword: 'note add 新建 便签 帧 空白',
      run: () => c.addFrame(
        // id 用时间戳确保唯一。
        NoteBlockDoc.empty('new_${DateTime.now().microsecondsSinceEpoch}'),
      ),
    ),
    EdgelessCommand(
      id: 'toggle-connect',
      label: connect ? '取消连线' : '连线模式',
      group: '编辑',
      icon: Icons.route_outlined,
      keyword: 'connector 连线 连接 线条',
      enabled: true,
      run: () {
        if (c.connectMode) {
          c.cancelConnect();
        } else {
          final sel = c.primarySelectedFrameId;
          if (sel == null) return;
          c.beginConnect(sel);
        }
      },
    ),
    EdgelessCommand(
      id: 'group-selection',
      label: '编组所选',
      group: '编辑',
      icon: Icons.group_work_outlined,
      keyword: 'group 编组 分组 集合',
      hint: '需 ≥2 帧',
      enabled: c.selectedFrameIds.length >= 2,
      run: () => c.groupSelection(),
    ),

    // ── 视图 ──────────────────────────────────────────────
    EdgelessCommand(
      id: 'fit-content',
      label: '适应内容',
      group: '视图',
      icon: Icons.fit_screen,
      keyword: 'fit 适应 内容 全部',
      enabled: onFitContent != null && frames.isNotEmpty,
      run: () => onFitContent?.call(),
    ),
    EdgelessCommand(
      id: 'fit-selection',
      label: '适应所选',
      group: '视图',
      icon: Icons.center_focus_strong_outlined,
      keyword: 'fit selection 适应 所选',
      enabled: onFitSelection != null && hasSelection,
      run: () => onFitSelection?.call(),
    ),
    EdgelessCommand(
      id: 'zoom-in',
      label: '放大',
      group: '视图',
      icon: Icons.zoom_in,
      keyword: 'zoom in 放大 拉近',
      run: () => c.zoomAt(1.2),
    ),
    EdgelessCommand(
      id: 'zoom-out',
      label: '缩小',
      group: '视图',
      icon: Icons.zoom_out,
      keyword: 'zoom out 缩小 拉远',
      run: () => c.zoomAt(1 / 1.2),
    ),
    EdgelessCommand(
      id: 'toggle-multiselect',
      label: multiSelect ? '退出多选' : '进入多选',
      group: '视图',
      icon: Icons.done_all,
      keyword: 'multi select 多选 框选',
      run: () => c.toggleMultiSelectMode(),
    ),

    // ── 选择 ──────────────────────────────────────────────
    EdgelessCommand(
      id: 'clear-selection',
      label: '清空所选',
      group: '选择',
      icon: Icons.select_all,
      keyword: 'clear selection 清空 取消 所选',
      enabled: hasSelection,
      run: () => c.removeSelection(),
    ),
    EdgelessCommand(
      id: 'focus-selection',
      label: '聚焦所选',
      group: '选择',
      icon: Icons.center_focus_strong_outlined,
      keyword: 'focus 聚焦 置顶 所选',
      enabled: hasSelection,
      run: () {
        if (primary == null) return;
        c.focusFrame(primary);
      },
    ),

    // ── 跳转（每个帧）───────────────────────────────────────
    for (var i = 0; i < frames.length; i++)
      EdgelessCommand(
        id: 'goto-frame-${frames[i].id}',
        label: '跳转到「${edgelessFrameTitle(frames[i].doc.title, i)}」',
        group: '跳转',
        icon: Icons.search_outlined,
        keyword: 'goto frame 跳转 定位',
        hint: frames[i].id,
        enabled: frames[i].id.isNotEmpty,
        run: () => c.selectFrame(frames[i].id),
      ),
  ];

  return commands;
}

/// 命令搜索：空 query 返回原列表；否则按 label / keyword / group / hint 做
/// 不区分大小写的子串匹配。结果保持原顺序（分组顺序不变），供面板分组显示。
List<EdgelessCommand> searchEdgelessCommands(
  List<EdgelessCommand> commands,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return commands;
  return commands
      .where(
        (cmd) =>
            cmd.label.toLowerCase().contains(q) ||
            cmd.keyword.toLowerCase().contains(q) ||
            cmd.group.toLowerCase().contains(q) ||
            (cmd.hint?.toLowerCase().contains(q) ?? false),
      )
      .toList();
}

/// 弹出 ⌘K 命令面板（模态底部面板）。返回面板执行后是否关闭。
Future<void> showEdgelessCommandPalette(
  BuildContext context, {
  required EdgelessController controller,
  VoidCallback? onFitContent,
  VoidCallback? onFitSelection,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _EdgelessPaletteSheet(
      controller: controller,
      onFitContent: onFitContent,
      onFitSelection: onFitSelection,
    ),
  );
}

/// 面板内部：搜索输入框 + 分组命令列表（支持键盘 ↑/↓/Enter）。
class _EdgelessPaletteSheet extends StatefulWidget {
  const _EdgelessPaletteSheet({
    required this.controller,
    this.onFitContent,
    this.onFitSelection,
  });

  final EdgelessController controller;
  final VoidCallback? onFitContent;
  final VoidCallback? onFitSelection;

  @override
  State<_EdgelessPaletteSheet> createState() => _EdgelessPaletteSheetState();
}

class _EdgelessPaletteSheetState extends State<_EdgelessPaletteSheet> {
  final TextEditingController _query = TextEditingController();
  late List<EdgelessCommand> _all;
  List<EdgelessCommand> _visible = const [];
  int _selectedIndex = 0;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _all = buildEdgelessCommands(
      widget.controller,
      onFitContent: widget.onFitContent,
      onFitSelection: widget.onFitSelection,
    );
    _visible = _all;
  }

  void _rebuild(String text) {
    final hits = searchEdgelessCommands(_all, text);
    setState(() {
      _visible = hits;
      _selectedIndex = hits.isEmpty ? 0 : 0;
    });
  }

  void _run(EdgelessCommand cmd) {
    if (!cmd.enabled) return;
    cmd.run();
    Navigator.of(context).pop();
  }

  void _move(int delta) {
    if (_visible.isEmpty) return;
    final n = _visible.length;
    setState(() => _selectedIndex = (_selectedIndex + delta) % n);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 把可见命令按 group 分组，保持组之间出现顺序稳定。
    final groups = <String, List<EdgelessCommand>>{};
    for (final cmd in _visible) {
      (groups[cmd.group] ??= []).add(cmd);
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.62,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _query,
              focusNode: _focus,
              autofocus: true,
              onChanged: _rebuild,
              decoration: InputDecoration(
                hintText: '搜索命令或跳转到帧…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppleRadius.md),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          Expanded(
            child: _visible.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的命令',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  )
                : CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                          _move(1),
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                          _move(-1),
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        if (_selectedIndex < _visible.length) {
                          _run(_visible[_selectedIndex]);
                        }
                      },
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          Navigator.of(context).pop(),
                    },
                    child: Focus(
                      focusNode: _focus,
                      child: ListView(
                        key: const PageStorageKey('edgeless-palette-list'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            for (final cmd in entry.value)
                              _EdgelessPaletteTile(
                                command: cmd,
                                selected:
                                    _visible.indexOf(cmd) == _selectedIndex,
                                onTap: () => _run(cmd),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }
}

/// 单条命令行。
class _EdgelessPaletteTile extends StatelessWidget {
  const _EdgelessPaletteTile({
    required this.command,
    required this.selected,
    required this.onTap,
  });

  final EdgelessCommand command;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(AppleRadius.md),
      child: ListTile(
        dense: true,
        leading: Icon(
          command.icon,
          color: command.enabled ? colorScheme.onSurface : colorScheme.outline,
        ),
        title: Text(command.label),
        subtitle: command.hint == null
            ? null
            : Text(
                command.hint!,
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
        trailing: !command.enabled
            ? Icon(Icons.lock_outline, size: 16, color: colorScheme.outline)
            : null,
        onTap: onTap,
      ),
    );
  }
}

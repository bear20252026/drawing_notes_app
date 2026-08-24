import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

import '../../../core/theme/text_scale_helper.dart';

/// 键盘快捷键系统
///
/// 参考 Excalidraw shortcuts.ts 的设计理念实现
/// 包含平台自适应、分类组织、帮助界面等功能
///
/// Copyright (c) 2024 - Inspired by Excalidraw shortcuts.ts patterns
/// Copyright (c) Excalidraw contributors - MIT License
/// Pattern adapted for Flutter/Dart implementation
class ShortcutRegistry {
  ShortcutRegistry._();

  /// 所有注册的快捷键条目
  static final List<ShortcutEntry> shortcuts = [
    // ============================
    // 编辑类
    // ============================
    ShortcutEntry(
      key: LogicalKeyboardKey.keyZ,
      control: true,
      meta: true,
      actionId: 'undo',
      description: '撤销',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyZ,
      control: true,
      shift: true,
      meta: true,
      actionId: 'redo_shift',
      description: '重做 (Shift+Z)',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyY,
      control: true,
      meta: true,
      actionId: 'redo_y',
      description: '重做 (Y)',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyC,
      control: true,
      meta: true,
      actionId: 'copy',
      description: '复制',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyV,
      control: true,
      meta: true,
      actionId: 'paste',
      description: '粘贴',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyC,
      control: true,
      shift: true,
      meta: true,
      actionId: 'copy_style',
      description: '复制样式',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyV,
      control: true,
      shift: true,
      meta: true,
      actionId: 'paste_style',
      description: '粘贴样式',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyD,
      control: true,
      meta: true,
      actionId: 'duplicate_offset',
      description: '复制并偏移',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.delete,
      actionId: 'delete',
      description: '删除选中',
      category: '编辑',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.backspace,
      actionId: 'delete_back',
      description: '删除选中 (Backspace)',
      category: '编辑',
    ),

    // ============================
    // 视图类
    // ============================
    ShortcutEntry(
      key: LogicalKeyboardKey.digit0,
      control: true,
      meta: true,
      actionId: 'reset_zoom',
      description: '重置缩放',
      category: '视图',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.equal,
      control: true,
      meta: true,
      actionId: 'zoom_in',
      description: '放大',
      category: '视图',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.add,
      control: true,
      meta: true,
      actionId: 'zoom_in_numpad',
      description: '放大 (小键盘+)',
      category: '视图',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.minus,
      control: true,
      meta: true,
      actionId: 'zoom_out',
      description: '缩小',
      category: '视图',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.digit1,
      control: true,
      meta: true,
      actionId: 'fit_to_screen',
      description: '适应屏幕',
      category: '视图',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyH,
      control: true,
      shift: true,
      meta: true,
      actionId: 'flip_view',
      description: '水平翻转视图',
      category: '视图',
    ),

    // ============================
    // 工具类 (单字母键，无修饰符)
    // ============================
    ShortcutEntry(
      key: LogicalKeyboardKey.keyV,
      actionId: 'tool_select',
      description: '选择工具',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyP,
      actionId: 'tool_pen',
      description: '画笔',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyE,
      actionId: 'tool_eraser',
      description: '橡皮擦',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyT,
      actionId: 'tool_text',
      description: '文字',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyR,
      actionId: 'tool_rectangle',
      description: '矩形',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyO,
      actionId: 'tool_ellipse',
      description: '椭圆',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyA,
      actionId: 'tool_arrow',
      description: '箭头',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyL,
      actionId: 'tool_line',
      description: '直线',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyI,
      actionId: 'tool_eyedropper',
      description: '吸管',
      category: '工具',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyH,
      actionId: 'tool_hand',
      description: '手型',
      category: '工具',
    ),

    // ============================
    // 文件类
    // ============================
    ShortcutEntry(
      key: LogicalKeyboardKey.keyS,
      control: true,
      meta: true,
      actionId: 'save',
      description: '保存',
      category: '文件',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyS,
      control: true,
      shift: true,
      meta: true,
      actionId: 'save_as',
      description: '另存为',
      category: '文件',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyN,
      control: true,
      meta: true,
      actionId: 'new_file',
      description: '新建',
      category: '文件',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyO,
      control: true,
      meta: true,
      actionId: 'open_file',
      description: '打开',
      category: '文件',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyE,
      control: true,
      meta: true,
      actionId: 'export',
      description: '导出',
      category: '文件',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyP,
      control: true,
      meta: true,
      actionId: 'print',
      description: '打印',
      category: '文件',
    ),

    // ============================
    // 其他
    // ============================
    ShortcutEntry(
      key: LogicalKeyboardKey.keyK,
      control: true,
      meta: true,
      actionId: 'command_palette',
      description: '命令面板',
      category: '其他',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.slash,
      control: true,
      meta: true,
      actionId: 'shortcut_help',
      description: '快捷键帮助',
      category: '其他',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.escape,
      actionId: 'escape',
      description: '取消选中/退出工具',
      category: '其他',
    ),
    ShortcutEntry(
      key: LogicalKeyboardKey.keyF,
      control: true,
      shift: true,
      meta: true,
      actionId: 'fullscreen',
      description: '全屏',
      category: '其他',
    ),
  ];

  /// 获取所有唯一的分类
  static List<String> get categories =>
      shortcuts.map((s) => s.category).toSet().toList();

  /// 根据分类获取快捷键
  static List<ShortcutEntry> getByCategory(String category) =>
      shortcuts.where((s) => s.category == category).toList();

  /// 根据 actionId 查找快捷键
  static List<ShortcutEntry> findByAction(String actionId) =>
      shortcuts.where((s) => s.actionId == actionId).toList();

  /// 查找匹配按键事件的快捷键
  static ShortcutEntry? findMatch(KeyEvent event) {
    for (final shortcut in shortcuts) {
      if (PlatformShortcutAdapter.matches(event, shortcut)) {
        return shortcut;
      }
    }
    return null;
  }

  /// 分组快捷键（按分类）
  static Map<String, List<ShortcutEntry>> get groupedByCategory {
    final grouped = <String, List<ShortcutEntry>>{};
    for (final shortcut in shortcuts) {
      grouped.putIfAbsent(shortcut.category, () => []).add(shortcut);
    }
    return grouped;
  }
}

/// 快捷键条目
///
/// 表示一个键盘快捷键的完整信息，包含按键、修饰符、动作ID、描述和分类
class ShortcutEntry {
  /// 快捷键按下的逻辑按键
  final LogicalKeyboardKey key;

  /// 是否需要按下 Ctrl 键 (Windows/Linux)
  final bool control;

  /// 是否需要按下 Cmd 键 (macOS)
  final bool meta;

  /// 是否需要按下 Shift 键
  final bool shift;

  /// 是否需要按下 Alt 键
  final bool alt;

  /// 动作标识符，映射到 CommandRegistry
  final String actionId;

  /// 中文描述，显示在快捷键帮助中
  final String description;

  /// 分类，用于分组显示
  final String category;

  const ShortcutEntry({
    required this.key,
    this.control = false,
    this.meta = false,
    this.shift = false,
    this.alt = false,
    required this.actionId,
    required this.description,
    required this.category,
  });

  /// 格式化显示快捷键字符串
  ///
  /// 根据当前平台显示相应的修饰符（macOS显示Cmd，Windows/Linux显示Ctrl）
  String get displayKey {
    final modifiers = <String>[];
    final isMac = PlatformShortcutAdapter.isMacOS;

    if (shift) modifiers.add('Shift');
    if (isMac && meta) {
      modifiers.add('Cmd');
    } else if (!isMac && control) {
      modifiers.add('Ctrl');
    }
    if (isMac && control) modifiers.add('Ctrl');
    if (!isMac && meta) modifiers.add('Cmd');
    if (alt) modifiers.add('Alt');

    final keyName = _keyToDisplayName(key);
    if (modifiers.isEmpty) return keyName;
    return '${modifiers.join('+')}+$keyName';
  }

  /// 将逻辑按键转换为显示名称
  String _keyToDisplayName(LogicalKeyboardKey key) {
    // 使用 keyLabel 或回退到 keyId 名称解析
    final label = key.keyLabel;
    if (label != null && label.isNotEmpty) return label;

    // 回退：从 keyId 解析名称
    final keyId = key.keyId;
    // 字母键范围: 0x00000061 (keyA) 到 0x0000007A (keyZ)
    if (keyId >= 0x61 && keyId <= 0x7A) {
      return String.fromCharCode(keyId - 0x61 + 65); // A-Z
    }
    // 数字键范围: 0x00000030 (digit0) 到 0x00000039 (digit9)
    if (keyId >= 0x30 && keyId <= 0x39) {
      return String.fromCharCode(keyId); // 0-9
    }

    // 常见特殊键的显示名称映射
    const keyNames = <int, String>{
      0x00100000301: 'Esc',
      0x00100000302: 'Delete',
      0x00100000303: 'Backspace',
      0x00100000304: 'Enter',
      0x00100000305: 'Tab',
      0x00100000306: 'Space',
      0x00100000056: '-',
      0x00100000057: '=',
      0x00100000058: '/',
      0x00100000059: '.',
      0x00100000060: ',',
      0x001000000E0: 'Ctrl',
      0x001000000E3: 'Cmd',
      0x001000000E1: 'Shift',
      0x001000000E2: 'Alt',
      0x00100000050: '←',
      0x00100000051: '→',
      0x00100000052: '↑',
      0x00100000053: '↓',
    };
    return keyNames[keyId] ?? key.toString().split('.').last;
  }

  @override
  String toString() =>
      'ShortcutEntry(${displayKey} -> $actionId [$category]: $description)';
}

/// 平台自适应快捷键适配器
///
/// 检测当前平台并提供平台特定的快捷键匹配逻辑：
/// - macOS: 使用 Cmd (meta) 作为主要修饰符
/// - Windows/Linux: 使用 Ctrl 作为主要修饰符
class PlatformShortcutAdapter {
  PlatformShortcutAdapter._();

  /// 检测当前是否为 macOS
  static bool get isMacOS {
    try {
      return Platform.isMacOS;
    } catch (e) {
      // 测试或不支持的平台环境
      return false;
    }
  }

  /// 检测当前是否为 Windows
  static bool get isWindows {
    try {
      return Platform.isWindows;
    } catch (e) {
      return false;
    }
  }

  /// 检测当前是否为 Linux
  static bool get isLinux {
    try {
      return Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  /// 获取平台名称
  static String get platformName {
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    return 'Unknown';
  }

  /// 检查按键事件是否匹配快捷键条目
  ///
  /// 平台感知逻辑：
  /// - macOS: Cmd (meta) 等效于 Windows/Linux 的 Ctrl
  /// - 在匹配时自动处理平台差异
  ///
  /// 返回 true 如果按键事件匹配快捷键
  static bool matches(KeyEvent event, ShortcutEntry shortcut) {
    // 必须按下指定的主键
    if (event.logicalKey != shortcut.key) {
      return false;
    }

    // 检查修饰符组合
    final bool requiredShift = shortcut.shift;
    final bool requiredAlt = shortcut.alt;

    // 平台特定的主修饰符检查
    final bool requiredPrimaryModifier;
    if (isMacOS) {
      requiredPrimaryModifier = shortcut.meta || shortcut.control;
    } else {
      requiredPrimaryModifier = shortcut.control || shortcut.meta;
    }

    final bool hasShift = HardwareKeyboard.instance.isShiftPressed;
    final bool hasAlt = HardwareKeyboard.instance.isAltPressed;
    final bool hasMeta = HardwareKeyboard.instance.isMetaPressed;
    final bool hasControl = HardwareKeyboard.instance.isControlPressed;

    final bool hasPrimaryModifier = hasMeta || hasControl;

    // 检查主修饰符
    if (requiredPrimaryModifier && !hasPrimaryModifier) {
      return false;
    }
    if (!requiredPrimaryModifier && hasPrimaryModifier) {
      return false;
    }

    // 检查 Shift 修饰符
    if (requiredShift && !hasShift) {
      return false;
    }
    if (!requiredShift && hasShift) {
      return false;
    }

    // 检查 Alt 修饰符
    if (requiredAlt && !hasAlt) {
      return false;
    }
    if (!requiredAlt && hasAlt) {
      return false;
    }

    return true;
  }

  /// 获取当前平台的主修饰符键描述
  static String get primaryModifierName =>
      isMacOS ? 'Cmd' : 'Ctrl';
}

/// 快捷键帮助界面
///
/// 以对话框形式展示所有快捷键，按分类分组
/// 支持搜索、键盘导航等功能
class ShortcutHelpWidget extends StatefulWidget {
  /// 可选的标题
  final String title;

  /// 可选的快捷键列表（为空则使用全局快捷键表）
  final List<ShortcutEntry>? shortcuts;

  /// 对话框宽度
  final double width;

  /// 对话框高度
  final double height;

  const ShortcutHelpWidget({
    super.key,
    this.title = '快捷键帮助',
    this.shortcuts,
    this.width = 700,
    this.height = 500,
  });

  /// 显示快捷键帮助对话框
  ///
  /// 返回一个显示对话框的 Future
  static Future<void> show(
    BuildContext context, {
    String title = '快捷键帮助',
    List<ShortcutEntry>? shortcuts,
    double width = 700,
    double height = 500,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ShortcutHelpWidget(
        title: title,
        shortcuts: shortcuts,
        width: width,
        height: height,
      ),
    );
  }

  @override
  State<ShortcutHelpWidget> createState() => _ShortcutHelpWidgetState();
}

class _ShortcutHelpWidgetState extends State<ShortcutHelpWidget> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = widget.shortcuts ?? ShortcutRegistry.shortcuts;
    final grouped = _groupByCategory(shortcuts);

    return Dialog(
      child: Container(
        width: widget.width,
        height: widget.height,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(
                  Icons.keyboard,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 搜索框
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索快捷键...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 快捷键列表
            Expanded(
              child: _buildShortcutList(grouped),
            ),
          ],
        ),
      ),
    );
  }

  /// 按分类分组快捷键
  Map<String, List<ShortcutEntry>> _groupByCategory(
      List<ShortcutEntry> shortcuts) {
    final grouped = <String, List<ShortcutEntry>>{};
    for (final shortcut in shortcuts) {
      grouped.putIfAbsent(shortcut.category, () => []).add(shortcut);
    }
    return grouped;
  }

  /// 构建快捷键列表
  Widget _buildShortcutList(Map<String, List<ShortcutEntry>> grouped) {
    if (_searchQuery.isNotEmpty) {
      return _buildSearchResults();
    }

    return ListView(
      children: grouped.entries.map((entry) {
        return _buildCategorySection(entry.key, entry.value);
      }).toList(),
    );
  }

  /// 构建搜索结果
  Widget _buildSearchResults() {
    final shortcuts = widget.shortcuts ?? ShortcutRegistry.shortcuts;
    final results = shortcuts.where((s) {
      final query = _searchQuery.toLowerCase();
      return s.description.toLowerCase().contains(query) ||
          s.actionId.toLowerCase().contains(query) ||
          s.category.toLowerCase().contains(query) ||
          s.displayKey.toLowerCase().contains(query);
    }).toList();

    if (results.isEmpty) {
      return const Center(
        child: Text(
          '未找到匹配的快捷键',
          style: TextStyle(fontSize: TextScaleHelper.scaled(context, 14), color: Colors.grey),
        ),
      );
    }

    return ListView(
      children: results.map((shortcut) {
        return _buildShortcutTile(shortcut);
      }).toList(),
    );
  }

  /// 构建分类部分
  Widget _buildCategorySection(
      String category, List<ShortcutEntry> shortcuts) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category,
              style: TextStyle(
                fontSize: TextScaleHelper.scaled(context, 14),
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            ...shortcuts.map((shortcut) => _buildShortcutTile(shortcut)),
          ],
        ),
      ),
    );
  }

  /// 构建单个快捷键项
  Widget _buildShortcutTile(ShortcutEntry shortcut) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // 快捷键显示
          Expanded(
            flex: 2,
            child: _buildKeyChips(shortcut),
          ),
          // 描述
          Expanded(
            flex: 3,
            child: Text(
              shortcut.description,
              style: TextStyle(
                fontSize: TextScaleHelper.scaled(context, 14),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建按键芯片显示
  Widget _buildKeyChips(ShortcutEntry shortcut) {
    final keys = shortcut.displayKey.split('+');
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: keys.map((key) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.grey[400]!,
              width: 1,
            ),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: TextScaleHelper.scaled(context, 12),
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 快捷键帮助按钮
///
/// 点击显示快捷键帮助对话框
class ShortcutHelpButton extends StatelessWidget {
  /// 按钮大小
  final double size;

  /// 图标颜色
  final Color? color;

  /// 可选的快捷键列表
  final List<ShortcutEntry>? shortcuts;

  const ShortcutHelpButton({
    super.key,
    this.size = 24,
    this.color,
    this.shortcuts,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.help_outline,
        size: size,
        color: color ?? Theme.of(context).iconTheme.color,
      ),
      tooltip: '快捷键帮助 (Ctrl+/)',
      onPressed: () {
        ShortcutHelpWidget.show(
          context,
          shortcuts: shortcuts,
        );
      },
    );
  }
}

/// 快捷键指示器组件
///
/// 用于在界面中显示某个操作的快捷键提示
class ShortcutIndicator extends StatelessWidget {
  /// 快捷键条目
  final ShortcutEntry shortcut;

  /// 显示模式
  final ShortcutIndicatorStyle style;

  /// 文本大小
  final double fontSize;

  const ShortcutIndicator({
    super.key,
    required this.shortcut,
    this.style = ShortcutIndicatorStyle.chips,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case ShortcutIndicatorStyle.chips:
        return _buildChipsStyle(context);
      case ShortcutIndicatorStyle.text:
        return _buildTextStyle(context);
      case ShortcutIndicatorStyle.compact:
        return _buildCompactStyle(context);
    }
  }

  Widget _buildChipsStyle(BuildContext context) {
    final keys = shortcut.displayKey.split('+');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: keys.map((key) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.grey[200],
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.grey[400]!,
              width: 0.5,
            ),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: fontSize,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextStyle(BuildContext context) {
    return Text(
      shortcut.displayKey,
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w500,
        color: Colors.grey[600],
      ),
    );
  }

  Widget _buildCompactStyle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        shortcut.displayKey.replaceAll('+', ' '),
        style: TextStyle(
          fontSize: fontSize - 2,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
        ),
      ),
    );
  }
}

/// 快捷键指示器样式枚举
enum ShortcutIndicatorStyle {
  /// 芯片样式（每个按键单独显示）
  chips,

  /// 文本样式（组合显示）
  text,

  /// 紧凑样式（小号文本）
  compact,
}

/// 快捷键工具提示组件
///
/// 在工具按钮上显示快捷键提示
class ShortcutTooltip extends StatelessWidget {
  /// 子组件
  final Widget child;

  /// 快捷键条目
  final ShortcutEntry shortcut;

  /// 提示消息（可选，为空则自动生成）
  final String? message;

  const ShortcutTooltip({
    super.key,
    required this.child,
    required this.shortcut,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = message ??
        '${shortcut.description}\n快捷键: ${shortcut.displayKey}';

    return Tooltip(
      message: tooltipMessage,
      child: child,
    );
  }
}

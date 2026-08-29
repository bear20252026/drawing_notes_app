// M9-3 全部文档工作台：左侧工作区面板。
//
// 纯展示：所有数据由父 widget 注入或硬编码占位（Demo Workspace 风格）。
// 不 import 任何存储/服务实现。

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 左侧工作区导航面板（AFFiNE 风格）。
///
/// 组成：
/// - 工作区头：头像 + 名称 + 快速搜索框
/// - 主导航：全部文档(选中) / Journals / 提醒 / Intelligence / 设置
/// - 分组区：收藏夹 / 组织 / 标签 / 精选 / 其他 → 回收站 / 导入 / 邀请成员 / 模板 / 了解更多
class AllDocsSidebar extends StatelessWidget {
  const AllDocsSidebar({
    super.key,
    this.workspaceName = '画记',
    this.searchQuery = '',
    this.onSearchChanged,
    this.selectedNavIndex = 0,
    this.onNavSelected,
  });

  /// 工作区名称（占位：Demo Workspace 风格，默认「画记」）。
  final String workspaceName;

  /// 当前搜索词（受控）。
  final String searchQuery;

  /// 搜索词变更回调。
  final ValueChanged<String>? onSearchChanged;

  /// 当前选中导航项索引。
  final int selectedNavIndex;

  /// 导航选中回调。
  final ValueChanged<int>? onNavSelected;

  static const _navItems = <_NavItem>[
    _NavItem(Icons.dashboard_rounded, '全部文档'),
    _NavItem(Icons.auto_stories_outlined, 'Journals'),
    _NavItem(Icons.notifications_none_rounded, '提醒'),
    _NavItem(Icons.auto_awesome_outlined, 'Intelligence'),
    _NavItem(Icons.settings_outlined, '设置'),
  ];

  static const _groupHeader = '分组';

  static const _groupItems = <_NavItem>[
    _NavItem(Icons.star_rounded, '收藏夹'),
    _NavItem(Icons.folder_rounded, '组织'),
    _NavItem(Icons.label_rounded, '标签'),
    _NavItem(Icons.featured_play_list_outlined, '精选'),
  ];

  static const _otherHeader = '其他';

  static const _otherItems = <_NavItem>[
    _NavItem(Icons.delete_outline, '回收站'),
    _NavItem(Icons.file_download_outlined, '导入'),
    _NavItem(Icons.person_add_alt_rounded, '邀请成员'),
    _NavItem(Icons.dashboard_customize_outlined, '模板'),
    _NavItem(Icons.help_outline, '了解更多'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppleColor.canvansDark : AppleColor.parchment;
    final surface = isDark ? AppleColor.surfaceDark : AppleColor.surfaceWhite;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);

    return Container(
      width: 248,
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 工作区头
          _WorkspaceHeader(
            name: workspaceName,
            surface: surface,
            onSurface: onSurface,
          ),
          const SizedBox(height: 8),
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '快速搜索',
                  hintStyle: TextStyle(color: muted, fontSize: 13),
                  prefixIcon: Icon(Icons.search, size: 18, color: muted),
                  filled: true,
                  fillColor: surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 主导航
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                ..._buildNavGroup(context, _navItems, 0),
                const SizedBox(height: 16),
                _SectionHeader(label: _groupHeader, muted: muted),
                ..._buildNavGroup(context, _groupItems, _navItems.length),
                const SizedBox(height: 16),
                _SectionHeader(label: _otherHeader, muted: muted),
                ..._buildNavGroup(
                  context,
                  _otherItems,
                  _navItems.length + _groupItems.length,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNavGroup(
    BuildContext context,
    List<_NavItem> items,
    int baseIndex,
  ) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);
    final accent = theme.colorScheme.primary;

    return List.generate(items.length, (i) {
      final globalIndex = baseIndex + i;
      final selected = globalIndex == selectedNavIndex;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onNavSelected?.call(globalIndex),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    items[i].icon,
                    size: 18,
                    color: selected ? accent : muted,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    items[i].label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? accent : onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.name,
    required this.surface,
    required this.onSurface,
  });

  final String name;
  final Color surface;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
      child: Row(
        children: [
          // 工作区头像
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF0066CC),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name.characters.first : 'W',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: onSurface.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.muted});

  final String label;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: muted,
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

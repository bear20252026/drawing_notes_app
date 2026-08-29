// M9-3 全部文档工作台：左侧工作区面板。
//
// M11 产品清晰化：只保留真实可达的导航项（全部文档/收藏夹/标签），
// 移除无实现的 AFFiNE 装饰性占位（Journals/提醒/Intelligence/回收站等）。
// 纯展示：所有数据由父 widget 注入。不 import 任何存储/服务实现。

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 左侧工作区导航面板（AFFiNE 风格）。
///
/// 组成：
/// - 工作区头：头像 + 名称
/// - 搜索框：快速过滤文档列表
/// - 主导航：全部文档 / 收藏夹 / 标签（与右侧 Tab 一一对应）
class AllDocsSidebar extends StatelessWidget {
  const AllDocsSidebar({
    super.key,
    this.workspaceName = '画记',
    this.searchQuery = '',
    this.onSearchChanged,
    this.selectedNavIndex = 0,
    this.onNavSelected,
  });

  /// 工作区名称（默认「画记」）。
  final String workspaceName;

  /// 当前搜索词（受控）。
  final String searchQuery;

  /// 搜索词变更回调。
  final ValueChanged<String>? onSearchChanged;

  /// 当前选中导航项索引（与右侧 Tab 一致）。
  final int selectedNavIndex;

  /// 导航选中回调。
  final ValueChanged<int>? onNavSelected;

  static const _navItems = <_NavItem>[
    _NavItem(Icons.dashboard_rounded, '全部文档'),
    _NavItem(Icons.star_rounded, '收藏夹'),
    _NavItem(Icons.label_rounded, '标签'),
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
              children: _buildNavGroup(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNavGroup(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);
    final accent = theme.colorScheme.primary;

    return List.generate(_navItems.length, (i) {
      final selected = i == selectedNavIndex;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onNavSelected?.call(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _navItems[i].icon,
                    size: 18,
                    color: selected ? accent : muted,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _navItems[i].label,
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
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

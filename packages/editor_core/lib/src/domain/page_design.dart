// editor_core——MenuItem 菜单项（AFFiNE Root Application Sidebar 借鉴——2026-08-21）。
//
// AFFiNE 页面设计核心模式本地化——菜单项/快速搜索/侧边栏容器/标签页。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// AFFiNE 原版参考：
// - Root Application Sidebar（左侧边栏——菜单/搜索/工作区/拖拽）
// - MenuItem（图标/文本/快捷键/操作/分组）
// - QuickSearchInput（快速搜索框——模糊匹配/键盘导航）
// - SidebarContainer（可折叠/可排序容器）
// - AppTabsHeader（多文档标签切换）
// - AddPageButton（新建页面按钮）
library;

/// 菜单项类型（AFFiNE MenuItem 借鉴）。
enum MenuItemType {
  /// 普通菜单项（点击执行操作）。
  action,

  /// 分组标题（不可点击——只显示分组名）。
  groupHeader,

  /// 分隔线（视觉分隔）。
  divider,

  /// 子菜单（展开子项）。
  submenu,
}

/// 菜单项（AFFiNE MenuItem 本地化——不可变）。
///
/// AFFiNE 页面设计核心组件——左侧边栏每个导航项。
/// 支持：图标/文本/快捷键/操作/分组/禁用/选中状态。
class MenuItem {
  const MenuItem({
    required this.id,
    required this.label,
    this.icon = '',
    this.shortcut = '',
    this.type = MenuItemType.action,
    this.group = '',
    this.badge = '',
    this.enabled = true,
    this.selected = false,
    this.children = const [],
    this.action = '',
  });

  final String id;
  final String label;
  final String icon;
  final String shortcut;
  final MenuItemType type;
  final String group;
  final String badge; // 角标（未读数/状态标记）。
  final bool enabled;
  final bool selected;
  final List<MenuItem> children; // 子菜单项。
  final String action; // 操作标识。

  /// 是否有快捷键。
  bool get hasShortcut => shortcut.isNotEmpty;

  /// 是否有角标。
  bool get hasBadge => badge.isNotEmpty;

  /// 是否有子菜单。
  bool get hasChildren => children.isNotEmpty;

  /// 是否可点击。
  bool get isClickable => type == MenuItemType.action && enabled;

  MenuItem copyWith({
    String? label,
    String? icon,
    String? shortcut,
    MenuItemType? type,
    String? group,
    String? badge,
    bool? enabled,
    bool? selected,
    List<MenuItem>? children,
    String? action,
  }) {
    return MenuItem(
      id: id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      shortcut: shortcut ?? this.shortcut,
      type: type ?? this.type,
      group: group ?? this.group,
      badge: badge ?? this.badge,
      enabled: enabled ?? this.enabled,
      selected: selected ?? this.selected,
      children: children ?? this.children,
      action: action ?? this.action,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MenuItem && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 快速搜索配置（AFFiNE QuickSearchInput 借鉴——不可变）。
class QuickSearchConfig {
  const QuickSearchConfig({
    this.placeholder = 'Search...',
    this.maxResults = 10,
    this.debounceMs = 200,
    this.showRecentSearches = true,
    this.searchFields = const ['title', 'content', 'tags'],
  });

  final String placeholder;
  final int maxResults;
  final int debounceMs;
  final bool showRecentSearches;
  final List<String> searchFields;

  QuickSearchConfig copyWith({
    String? placeholder,
    int? maxResults,
    int? debounceMs,
    bool? showRecentSearches,
    List<String>? searchFields,
  }) {
    return QuickSearchConfig(
      placeholder: placeholder ?? this.placeholder,
      maxResults: maxResults ?? this.maxResults,
      debounceMs: debounceMs ?? this.debounceMs,
      showRecentSearches: showRecentSearches ?? this.showRecentSearches,
      searchFields: searchFields ?? this.searchFields,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QuickSearchConfig && placeholder == other.placeholder;

  @override
  int get hashCode => placeholder.hashCode;
}

/// 搜索结果项（AFFiNE QuickSearch 结果本地化——不可变）。
class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.icon = '',
    this.matchScore = 0.0,
    this.matchRanges = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final double matchScore; // 匹配分数（0~1——越高越相关）。
  final List<({int start, int end})> matchRanges; // 匹配高亮范围。

  SearchResult copyWith({String? title, String? subtitle, double? matchScore}) {
    return SearchResult(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon,
      matchScore: matchScore ?? this.matchScore,
      matchRanges: matchRanges,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SearchResult && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 侧边栏容器（AFFiNE SidebarContainer 借鉴——不可变）。
///
/// 可折叠/可排序的侧边栏分组容器。
class SidebarContainer {
  const SidebarContainer({
    required this.id,
    required this.title,
    this.icon = '',
    this.items = const [],
    this.collapsed = false,
    this.order = 0,
    this.showHeader = true,
  });

  final String id;
  final String title;
  final String icon;
  final List<MenuItem> items;
  final bool collapsed;
  final int order; // 排序序号。
  final bool showHeader;

  /// 项目数量。
  int get itemCount => items.length;

  /// 是否为空。
  bool get isEmpty => items.isEmpty;

  /// 切换折叠状态（不可变——返回新实例）。
  SidebarContainer toggleCollapsed() {
    return copyWith(collapsed: !collapsed);
  }

  /// 添加菜单项。
  SidebarContainer addItem(MenuItem item) {
    return copyWith(items: [...items, item]);
  }

  /// 移除菜单项。
  SidebarContainer removeItem(String itemId) {
    return copyWith(items: items.where((i) => i.id != itemId).toList());
  }

  /// 更新菜单项。
  SidebarContainer updateItem(MenuItem item) {
    return copyWith(items: items.map((i) => i.id == item.id ? item : i).toList());
  }

  SidebarContainer copyWith({
    String? title,
    String? icon,
    List<MenuItem>? items,
    bool? collapsed,
    int? order,
    bool? showHeader,
  }) {
    return SidebarContainer(
      id: id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      items: items ?? this.items,
      collapsed: collapsed ?? this.collapsed,
      order: order ?? this.order,
      showHeader: showHeader ?? this.showHeader,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SidebarContainer && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 标签页（AFFiNE AppTabsHeader 借鉴——不可变）。
///
/// 多文档标签切换——每个标签对应一个文档/页面。
class TabItem {
  const TabItem({
    required this.id,
    required this.title,
    this.icon = '',
    this.modified = false,
    this.closable = true,
    this.active = false,
  });

  final String id;
  final String title;
  final String icon;
  final bool modified; // 是否有未保存修改（显示小圆点）。
  final bool closable;
  final bool active;

  TabItem copyWith({String? title, bool? modified, bool? active}) {
    return TabItem(
      id: id,
      title: title ?? this.title,
      icon: icon,
      modified: modified ?? this.modified,
      closable: closable,
      active: active ?? this.active,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TabItem && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 标签栏管理器（AFFiNE AppTabsHeader 本地化——积木式纯 Dart）。
class TabBar {
  const TabBar({this.tabs = const [], this.activeTabId = ''});

  final List<TabItem> tabs;
  final String activeTabId;

  /// 当前活动标签。
  TabItem? get activeTab => tabs.where((t) => t.id == activeTabId).firstOrNull;

  /// 添加标签。
  TabBar addTab(TabItem tab) {
    return TabBar(
      tabs: [...tabs, tab],
      activeTabId: tab.id,
    );
  }

  /// 关闭标签。
  TabBar closeTab(String tabId) {
    final remaining = tabs.where((t) => t.id != tabId).toList();
    final newActive = activeTabId == tabId
        ? (remaining.isNotEmpty ? remaining.last.id : '')
        : activeTabId;
    return TabBar(tabs: remaining, activeTabId: newActive);
  }

  /// 切换标签。
  TabBar switchTo(String tabId) {
    if (!tabs.any((t) => t.id == tabId)) return this;
    return TabBar(tabs: tabs, activeTabId: tabId);
  }

  /// 更新标签。
  TabBar updateTab(TabItem tab) {
    return TabBar(
      tabs: tabs.map((t) => t.id == tab.id ? tab : t).toList(),
      activeTabId: activeTabId,
    );
  }

  /// 标记标签为已修改。
  TabBar markModified(String tabId) {
    return updateTab(TabItem(
      id: tabId,
      title: tabs.firstWhere((t) => t.id == tabId).title,
      modified: true,
    ));
  }

  int get count => tabs.length;
  bool get isEmpty => tabs.isEmpty;

  TabBar copyWith({List<TabItem>? tabs, String? activeTabId}) {
    return TabBar(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TabBar && count == other.count;

  @override
  int get hashCode => count.hashCode;
}

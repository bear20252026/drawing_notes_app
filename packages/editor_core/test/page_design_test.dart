import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——MenuItem/QuickSearch/SidebarContainer/TabBar 测试（纯逻辑——不搞崩）。
void main() {
  group('MenuItem', () {
    test('默认值 + isClickable + hasShortcut + hasBadge', () {
      const item = MenuItem(id: 'm1', label: 'New Page', icon: '📄', shortcut: 'Ctrl+N');
      expect(item.type, MenuItemType.action);
      expect(item.isClickable, true);
      expect(item.hasShortcut, true);
      expect(item.hasBadge, false);
      expect(item.hasChildren, false);
      expect(item.enabled, true);
      expect(item.selected, false);
    });

    test('分组标题（不可点击）', () {
      const header = MenuItem(id: 'g1', label: 'Recent', type: MenuItemType.groupHeader);
      expect(header.isClickable, false);
    });

    test('copyWith 不可变', () {
      const item = MenuItem(id: 'm1', label: 'Page');
      final updated = item.copyWith(label: 'New Page', selected: true, badge: '3');
      expect(item.label, 'Page'); // 原实例不变。
      expect(updated.label, 'New Page');
      expect(updated.selected, true);
      expect(updated.badge, '3');
    });

    test('子菜单', () {
      const item = MenuItem(id: 'm1', label: 'File', children: [
        MenuItem(id: 'm1a', label: 'New'),
        MenuItem(id: 'm1b', label: 'Open'),
      ]);
      expect(item.hasChildren, true);
      expect(item.children.length, 2);
    });
  });

  group('QuickSearchConfig', () {
    test('默认值 + copyWith 不可变', () {
      const config = QuickSearchConfig();
      expect(config.placeholder, 'Search...');
      expect(config.maxResults, 10);
      expect(config.debounceMs, 200);
      expect(config.showRecentSearches, true);
      final updated = config.copyWith(maxResults: 20, placeholder: '搜索...');
      expect(config.maxResults, 10); // 原实例不变。
      expect(updated.maxResults, 20);
      expect(updated.placeholder, '搜索...');
    });
  });

  group('SearchResult', () {
    test('默认值 + copyWith 不可变', () {
      const result = SearchResult(id: 'r1', title: 'My Note');
      expect(result.matchScore, 0.0);
      expect(result.matchRanges, isEmpty);
      final updated = result.copyWith(matchScore: 0.95);
      expect(result.matchScore, 0.0); // 原实例不变。
      expect(updated.matchScore, 0.95);
    });
  });

  group('SidebarContainer', () {
    test('默认值 + toggleCollapsed', () {
      const container = SidebarContainer(id: 's1', title: 'Favorites');
      expect(container.collapsed, false);
      expect(container.itemCount, 0);
      expect(container.isEmpty, true);
      final toggled = container.toggleCollapsed();
      expect(toggled.collapsed, true);
      expect(container.collapsed, false); // 原实例不变。
    });

    test('addItem/removeItem/updateItem', () {
      const container = SidebarContainer(id: 's1', title: 'Favorites');
      final withItem = container.addItem(const MenuItem(id: 'm1', label: 'Page 1'));
      expect(withItem.itemCount, 1);
      final updated = withItem.updateItem(const MenuItem(id: 'm1', label: 'New Page 1'));
      expect(updated.items.first.label, 'New Page 1');
      final removed = withItem.removeItem('m1');
      expect(removed.itemCount, 0);
    });

    test('copyWith 不可变', () {
      const container = SidebarContainer(id: 's1', title: 'Favorites');
      final renamed = container.copyWith(title: 'Starred', order: 5);
      expect(container.title, 'Favorites'); // 原实例不变。
      expect(renamed.title, 'Starred');
      expect(renamed.order, 5);
    });
  });

  group('TabItem + TabBar', () {
    test('TabItem 默认值 + copyWith', () {
      const tab = TabItem(id: 't1', title: 'Document 1');
      expect(tab.modified, false);
      expect(tab.closable, true);
      expect(tab.active, false);
      final modified = tab.copyWith(modified: true, active: true);
      expect(tab.modified, false); // 原实例不变。
      expect(modified.modified, true);
      expect(modified.active, true);
    });

    test('TabBar：addTab/closeTab/switchTo', () {
      const bar = TabBar();
      final withTab = bar.addTab(const TabItem(id: 't1', title: 'Doc 1'));
      expect(withTab.count, 1);
      expect(withTab.activeTabId, 't1');
      expect(withTab.activeTab!.title, 'Doc 1');
      final withTwo = withTab.addTab(const TabItem(id: 't2', title: 'Doc 2'));
      expect(withTwo.count, 2);
      final switched = withTwo.switchTo('t1');
      expect(switched.activeTabId, 't1');
      final closed = withTwo.closeTab('t2');
      expect(closed.count, 1);
      expect(closed.activeTabId, 't1'); // 自动切换到剩余标签。
    });

    test('TabBar：markModified', () {
      final bar = const TabBar().addTab(const TabItem(id: 't1', title: 'Doc'));
      final modified = bar.markModified('t1');
      expect(modified.activeTab!.modified, true);
      expect(bar.tabs.first.modified, false); // 原实例不变。
    });

    test('MenuItemType/枚举', () {
      expect(MenuItemType.values.length, 4);
    });
  });
}

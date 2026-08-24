// editor_v2——EditorV2Sidebar（AFFiNE 页面设计借鉴——2026-08-21）。
//
// 侧边栏页面导航（AFFiNE 左侧边栏借鉴——不大幅变动目前风格——
// 页面列表 + 新建/切换/删除——现有工具栏/画布保留）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/paged_canvas_viewmodel.dart';

/// AFFiNE 侧边栏页面导航（左侧边栏借鉴——PageV2 列表）。
///
/// 设计（AFFiNE 页面设计——不大幅变动）：
/// - 页面列表（PageV2——当前页高亮）
/// - 新建页面（addPage）
/// - 切换页面（setCurrentPage）
/// - 删除页面（deletePage）
class EditorV2Sidebar extends ConsumerWidget {
  const EditorV2Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pagedCanvasNotifierProvider);
    final notifier = ref.read(pagedCanvasNotifierProvider.notifier);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 侧边栏头（AFFiNE 风格——当前文档名）。
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '页面管理',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // 页面列表（可滚动）。
            Expanded(
              child: ListView.builder(
                itemCount: state.pages.length,
                itemBuilder: (context, index) {
                  final page = state.pages[index];
                  return ListTile(
                    selected: index == state.currentPageIndex,
                    selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                    leading: const Icon(Icons.description_outlined),
                    title: Text('页面 ${page.index + 1}'),
                    onTap: () {
                      notifier.setCurrentPage(index);
                      Navigator.pop(context); // 选择后收起侧边栏。
                    },
                  );
                },
              ),
            ),
            // 操作区（新建/删除页面——AFFiNE 页面管理）。
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('新建'),
                      onPressed: () {
                        notifier.addPage();
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                      onPressed: state.pages.length > 1
                          ? () {
                              notifier.deletePage(state.currentPageIndex);
                              Navigator.pop(context);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

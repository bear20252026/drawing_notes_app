// editor_v2——EditorV2Sidebar（AFFiNE 页面设计借鉴——2026-08-21）。
//
// 侧边栏页面导航（AFFiNE 左侧边栏借鉴——不大幅变动目前风格——
// 页面列表 + 新建/切换/删除——现有工具栏/画布保留）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/responsive.dart';
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

    final isMobile = context.isMobile;
    final basePadding = context.responsiveScale(16.0); // responsive padding
    return Drawer(
      width: isMobile ? 280 : 360,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 侧边栏头（AFFiNE 风格——当前文档名）。
            Padding(
              padding: EdgeInsets.all(basePadding),
              child: Text(
                '页面管理',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: context.responsiveFont(mobile: 16, desktop: 20),
                    ),
              ),
            ),
            // 页面列表（可滚动）。
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: basePadding * 0.5),
                itemCount: state.pages.length,
                itemBuilder: (context, index) {
                  final page = state.pages[index];
                  final isSelected = index == state.currentPageIndex;
                  return GestureDetector(
                    onTap: () {
                      notifier.setCurrentPage(index);
                      Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      padding: EdgeInsets.symmetric(
                        horizontal: context.responsiveFont(mobile: 12, desktop: 16),
                        vertical: context.responsiveFont(mobile: 10, desktop: 14),
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF0066CC).withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 20,
                            color: isSelected
                                ? const Color(0xFF0066CC)
                                : const Color(0xFF8E8E93),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '页面 ${page.index + 1}',
                            style: TextStyle(
                              fontSize: context.responsiveFont(mobile: 14, desktop: 16),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected
                                  ? const Color(0xFF0066CC)
                                  : const Color(0xFF1D1D1F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // 操作区（新建/删除页面——AFFiNE 页面管理）。
            Padding(
              padding: EdgeInsets.all(context.responsiveFont(mobile: 6, desktop: 10)),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(
                        '新建',
                        style: TextStyle(fontSize: context.responsiveFont(mobile: 13, desktop: 15)),
                      ),
                      onPressed: () {
                        notifier.addPage();
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  SizedBox(width: context.responsiveFont(mobile: 6, desktop: 10)),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        '删除',
                        style: TextStyle(fontSize: context.responsiveFont(mobile: 13, desktop: 15)),
                      ),
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

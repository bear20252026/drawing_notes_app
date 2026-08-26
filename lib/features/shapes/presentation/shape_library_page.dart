import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_design.dart';
import '../application/shape_library_notifier.dart';
import '../domain/shape_template.dart';

/// 形状库页面 — 管理可复用的自定义形状。
///
/// 通过 [ShapeLibraryNotifier] 获取形状列表（Application 层）
/// 通过 [ShapeRepository] 持久化（Infrastructure 层，由 DI 注入）
class ShapeLibraryPage extends ConsumerWidget {
  const ShapeLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 通过 Application 层状态管理器获取形状列表
    final shapesAsync = ref.watch(shapeLibraryNotifierProvider);

    return Scaffold(
      backgroundColor: isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor:
                isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 12,
              ),
              title: Text(
                '形状库',
                style: AppDesign.displayMd.copyWith(
                  color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(
              top: AppDesign.spacingLg,
              bottom: AppDesign.spacingSection,
            ),
            sliver: SliverToBoxAdapter(
              child: shapesAsync.when(
                data: (shapes) => _buildContent(context, ref, shapes),
                loading: () => _buildLoading(context),
                error: (e, _) => _buildError(context, e),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建主内容（有数据时）
  Widget _buildContent(
      BuildContext context, WidgetRef ref, List<ShapeTemplate> shapes) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (shapes.isEmpty) {
      return _buildEmptyState(context);
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.category_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: AppDesign.spacingLg),
          Text(
            '形状库',
            style: AppDesign.displayLg.copyWith(
              color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
            ),
          ),
          const SizedBox(height: AppDesign.spacingXs),
          Text(
            '共 ${shapes.length} 个形状模板',
            style: AppDesign.caption.copyWith(
              color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
            ),
          ),
          const SizedBox(height: AppDesign.spacingLg),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('导入形状'),
            onPressed: () => _showImportDialog(context, ref),
          ),
        ],
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.category_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: AppDesign.spacingLg),
          Text(
            '形状库为空',
            style: AppDesign.displayLg.copyWith(
              color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
            ),
          ),
          const SizedBox(height: AppDesign.spacingXs),
          Text(
            '导入自定义形状模板',
            style: AppDesign.caption.copyWith(
              color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
            ),
          ),
          const SizedBox(height: AppDesign.spacingLg),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('导入形状'),
            onPressed: () {
              // TODO: 实现形状导入
            },
          ),
        ],
      ),
    );
  }

  /// 构建加载中状态
  Widget _buildLoading(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppDesign.spacingLg),
          Text(
            '加载中...',
            style: AppDesign.caption.copyWith(
              color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建错误状态
  Widget _buildError(BuildContext context, Object error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppDesign.spacingLg),
          Text(
            '加载失败',
            style: AppDesign.displayLg.copyWith(
              color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
            ),
          ),
          const SizedBox(height: AppDesign.spacingXs),
          Text(
            error.toString(),
            style: AppDesign.caption.copyWith(
              color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示导入形状对话框
  void _showImportDialog(BuildContext context, WidgetRef ref) {
    // TODO: 实现形状导入对话框
    // 可通过 ref.read(shapeLibraryNotifierProvider.notifier).importShape(...) 导入
  }
}

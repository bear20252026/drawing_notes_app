import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_design.dart';
import '../../../shared/widgets/ambient_background.dart';

/// 形状库页面 — 管理可复用的自定义形状。
class ShapeLibraryPage extends StatelessWidget {
  const ShapeLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
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
              child: Center(
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
                      style: AppDesign.headlineMedium.copyWith(
                        color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
                      ),
                    ),
                    const SizedBox(height: AppDesign.spacingXs),
                    Text(
                      '管理自定义形状模板',
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

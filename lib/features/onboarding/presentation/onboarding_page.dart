import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_design.dart';
import '../../../shared/widgets/ambient_background.dart';
import '../../../shared/widgets/glass_surface.dart';

/// 引导页 — 首次启动时展示应用功能介绍。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingData(
      icon: Icons.draw,
      title: '自由绘画',
      description: '使用画笔、形状、图表在画布上自由创作，支持多种颜色和粗细。',
    ),
    _OnboardingData(
      icon: Icons.note_alt,
      title: '富文本笔记',
      description: '创建富文本笔记，支持文本、图片、链接等多种内容。',
    ),
    _OnboardingData(
      icon: Icons.lock,
      title: '端到端加密',
      description: '使用 ChaCha20 + AES-256-GCM 三层加密保护您的数据安全。',
    ),
    _OnboardingData(
      icon: Icons.folder,
      title: '密码盘',
      description: '通过密码盘机制保护您的文件，只有输入正确密码才能访问。',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _finishOnboarding() {
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 跳过按钮
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    onPressed: _finishOnboarding,
                    child: const Text('跳过'),
                  ),
                ),
              ),

              // 页面内容
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    final data = _pages[index];
                    return Padding(
                      padding: const EdgeInsets.all(AppDesign.spacingLg),
                      child: GlassSurface(
                        padding: const EdgeInsets.all(AppDesign.spacingLg),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(data.icon, size: 96, color: theme.colorScheme.primary),
                            const SizedBox(height: AppDesign.spacingXl),
                            Text(
                              data.title,
                              style: AppDesign.tagline.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppDesign.spacingMd),
                            Text(
                              data.description,
                              style: AppDesign.body.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 页面指示器
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (i) => AnimatedContainer(
                    duration: AppDesign.quickMotion,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _currentPage ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppDesign.roundedPill),
                      color: i == _currentPage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),

              // 下一步按钮
              Padding(
                padding: const EdgeInsets.all(AppDesign.spacingLg),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _nextPage,
                    child: Text(
                      _currentPage < _pages.length - 1 ? '下一步' : '开始使用',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingData {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

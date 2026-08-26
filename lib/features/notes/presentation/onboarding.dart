import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' hide showDialog, Icons, Theme;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/widgets/ios_dialog.dart';
import '../../../l10n/app_localizations.dart';

/// 首次启动引导（Phase 7）。
///
/// 功能：第一次打开 App 时展示一次简单的操作提示，可跳过；
/// 通过 shared_preferences 记录"已看过"状态，之后不再弹出。
///
/// 说明：只做"能看懂基本操作"级别的轻量提示（符合开发计划
/// "简单的首次启动引导提示（可跳过）"要求），不做过重的教程流程。
class OnboardingService {
  OnboardingService([this._prefs]);

  static const String _seenKey = 'onboarding_seen_v1';

  SharedPreferences? _prefs;

  Future<bool> hasSeen() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      return _prefs!.getBool(_seenKey) ?? false;
    } catch (_) {
      // 存储不可用时默认视为已看过，避免每次启动都弹窗。
      return true;
    }
  }

  /// 标记引导已看过。
  Future<void> markSeen() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_seenKey, true);
    } catch (_) {
      // 持久化失败不影响使用。
    }
  }

  /// 若首次启动，弹出引导对话框；否则什么都不做。
  /// 2026-08-25 修复：改用 showIosDialog 保持一致性。
  Future<void> showIfFirstLaunch(BuildContext context) async {
    if (await hasSeen()) return;
    if (!context.mounted) return;
    final l = AppLocalizations.of(context);
    await showIosDialog<void>(
      context,
      title: l?.onboardingTitle ?? '欢迎使用绘图笔记',
      contentWidget: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TipRow(icon: Icons.brush_rounded, text: l?.onboardingBrush ?? '画笔 / 橡皮擦 / 吸管：顶部工具条切换，拖动鼠标或手指绘画'),
            _TipRow(icon: Icons.palette_outlined, text: l?.onboardingColor ?? '颜色与粗细：工具条右侧圆形色块与粗细滑块'),
            _TipRow(
              icon: Icons.layers_outlined,
              text: l?.onboardingLayers ?? '图层面板在右侧：新建、显隐、透明度、顺序、合并',
            ),
            _TipRow(
              icon: Icons.crop_square_rounded,
              text: l?.onboardingSelect ?? '选区工具：框选后可移动 / 缩放 / 旋转 / 复制 / 删除',
            ),
            _TipRow(
              icon: Icons.text_fields_rounded,
              text: l?.onboardingText ?? '笔记页支持文字与图片：文字工具点击画布输入，图片按钮插入',
            ),
            _TipRow(icon: Icons.pinch_rounded, text: l?.onboardingPinch ?? '双指捏合缩放画布、双指旋转画布（触屏设备）'),
            _TipRow(icon: Icons.fullscreen_rounded, text: l?.onboardingFullscreen ?? '右上角全屏按钮：隐藏工具栏只看画布'),
            _TipRow(
              icon: Icons.save_outlined,
              text: l?.onboardingSave ?? '内容自动保存，无需手动保存；可随时导出为 PNG',
            ),
          ],
        ),
      ),
      actions: [
        IosDialogAction(
          label: l?.onboardingStart ?? '开始使用',
          isDefault: true,
        ),
      ],
    );
    await markSeen();
  }
}

/// 引导条目：图标 + 说明文字。
class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

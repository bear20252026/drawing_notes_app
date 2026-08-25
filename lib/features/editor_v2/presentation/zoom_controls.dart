// editor_v2——ZoomControls 缩放控件（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw 右下角缩放控件本地化——积木式独立 Widget。
// 缩放滑块/重置/适应窗口/百分比显示——与 InfiniteCanvasNotifier 集成。
// 不修改现有功能——保证现有功能正常——不搞崩。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/infinite_canvas_notifier.dart';

/// Excalidraw 缩放控件（积木式独立 Widget——右下角浮动）。
///
/// 功能：
/// - 缩放滑块（0.1x ~ 10x）
/// - 百分比显示（当前缩放比）
/// - 缩小/放大按钮（-/+/fit）
/// - 重置按钮（1x）
/// - 适应窗口按钮（fit to screen）
///
/// 设计：积木式——独立 Widget——不耦合其他组件——可插拔。
class ZoomControls extends ConsumerWidget {
  const ZoomControls({super.key, this.onFitToScreen});

  /// 适应窗口回调（外部提供——可选）。
  final VoidCallback? onFitToScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewport = ref.watch(infiniteCanvasProvider);
    final notifier = ref.read(infiniteCanvasProvider.notifier);
    final percentage = (viewport.scale * 100).round();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 缩小按钮（-）。
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              onPressed: () {
                final newScale = (viewport.scale * 0.8).clamp(0.1, 10.0);
                notifier.zoom(newScale / viewport.scale, 0, 0);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: '缩小',
            ),
            // 百分比显示 + 缩放滑块。
            SizedBox(
              width: 100,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.grey.shade300,
                  thumbColor: Colors.blue,
                ),
                child: Slider(
                  value: viewport.scale.clamp(0.1, 10.0),
                  min: 0.1,
                  max: 10.0,
                  onChanged: (value) {
                    final delta = value / viewport.scale;
                    notifier.zoom(delta, 0, 0);
                  },
                ),
              ),
            ),
            // 放大按钮（+）。
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () {
                final newScale = (viewport.scale * 1.25).clamp(0.1, 10.0);
                notifier.zoom(newScale / viewport.scale, 0, 0);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: '放大',
            ),
            // 百分比文字。
            SizedBox(
              width: 44,
              child: Text(
                '$percentage%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            // 重置按钮（1x）。
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () {
                notifier.reset();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: '重置 (1x)',
            ),
            // 适应窗口按钮（fit）。
            IconButton(
              icon: const Icon(Icons.fit_screen, size: 18),
              onPressed: onFitToScreen,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: '适应窗口',
            ),
          ],
        ),
      ),
    );
  }
}

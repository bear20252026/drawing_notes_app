import 'dart:io';

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/theme/apple_motion.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/vfs/vault_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/shared/widgets/encrypted_file_image.dart';

/// 幻灯片演示模式（对齐 Excalidraw presentation）。
///
/// 全屏黑色背景，按元素列表逐个居中展示（文字/图片/形状），
/// ←/→ 切换、Esc 或点击退出。适用于汇报/演示场景。
class PresentationPage extends StatefulWidget {
  const PresentationPage({
    super.key,
    required this.textItems,
    required this.imageItems,
    required this.shapes,
    required this.mediaCrypto,
    this.vaultService,
  });

  final List<PageTextItem> textItems;
  final List<PageImageItem> imageItems;
  final List<PageShapeItem> shapes;

  /// 媒体会话解密服务（C-06，审计 2026-09-27 构造注入）：页面图片
  /// （EncryptedFileImage）解密依赖由 NotebookViewPage 传线——不再直取
  /// 全局单例。
  final MediaCryptoService mediaCrypto;

  /// VFS 媒体仓库（可选——'vfs:' 对象读回；沿 NotebookStorage 透传）。
  final VaultService? vaultService;

  @override
  State<PresentationPage> createState() => _PresentationPageState();
}

class _PresentationPageState extends State<PresentationPage> {
  int _index = 0;

  /// 全部元素（按加入顺序），空元素跳过。
  List<Widget> get _elements {
    final items = <Widget>[];
    for (final t in widget.textItems) {
      items.add(
        Text(
          t.text,
          textAlign: TextAlign.center,
          // 演示模式大字：梯子 lead 28px。
          style: AppleTypeScale.of(AppleTypeScale.lead, Colors.white).copyWith(
            fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }
    for (final i in widget.imageItems) {
      items.add(
        ClipRRect(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          // 批次①c：裸 Image.file 改 EncryptedFileImage——DNV/DAN 密文
          // 解密渲染；保险库锁定/损坏显示占位色块（fail-closed）。
          child: i.filePath.isNotEmpty
              ? Image(
                  // C-06（审计 2026-09-27）：解密/VFS 依赖传线。
                  image: EncryptedFileImage(
                    File(i.filePath),
                    mediaCrypto: widget.mediaCrypto,
                    vaultService: widget.vaultService,
                  ),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: AppleColor.inkSubtle),
                )
              : const ColoredBox(color: AppleColor.inkSubtle),
        ),
      );
    }
    for (final s in widget.shapes) {
      items.add(
        Icon(
          switch (s.shapeType) {
            ShapeType.rect => Icons.crop_square,
            ShapeType.ellipse => Icons.circle_outlined,
            ShapeType.diamond => Icons.diamond_outlined,
            ShapeType.arrow => Icons.arrow_forward,
            ShapeType.line => Icons.remove,
          },
          size: 120,
          color: Colors.white,
        ),
      );
    }
    return items.whereType<Widget>().toList();
  }

  void _next() {
    if (_index < _elements.length - 1) {
      setState(() => _index++);
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final elements = _elements;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _next();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _prev();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          button: true,
          label: AppLocalizations.of(context)?.presNextSlide ?? '下一页（长按退出）',
          child: GestureDetector(
            onTap: _next,
            onLongPress: () => Navigator.of(context).pop(),
            child: Stack(
              children: [
                // 当前元素居中展示。
                Center(
                  child: AnimatedSwitcher(
                    duration: AppleMotion.modal,
                    child: KeyedSubtree(
                      key: ValueKey(_index),
                      child: Padding(
                        // D-10（审计 2026-09-27）：40 离档，归一 AppleSpacing.xl。
                        padding: const EdgeInsets.all(AppleSpacing.xl),
                        child: elements.isEmpty
                            ? Text(
                                AppLocalizations.of(context)?.presNoContent ??
                                    '没有可演示的内容',
                                // D-15：Material 白系捷径改令牌——等价
                                // surfaceWhite 54%（0x8AFFFFFF）。
                                style: TextStyle(
                                  color: AppleColor.surfaceWhite.withValues(
                                    alpha: 0.54,
                                  ),
                                ),
                              )
                            : elements[_index],
                      ),
                    ),
                  ),
                ),
                // 底部进度指示（V-07 审计 2026-09-27）：补上一页/下一页
                // 图标按钮对——此前上一页仅键盘 ← 可达，触屏/鼠标无回退。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip:
                              AppLocalizations.of(context)?.presPrevSlide ??
                              '上一页',
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            // D-15：白系捷径 → AppleColor.surfaceWhite 令牌。
                            color: AppleColor.surfaceWhite.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          onPressed: _index > 0 ? _prev : null,
                        ),
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.presIndicator(_index + 1, elements.length) ??
                              '${_index + 1} / ${elements.length} · 点击或 → 下一页，Esc 退出',
                          style: AppleType.controlStyle(
                            AppleColor.surfaceWhite.withValues(alpha: 0.38),
                            weight: FontWeight.w400,
                          ),
                        ),
                        IconButton(
                          tooltip:
                              AppLocalizations.of(context)?.presNextSlide ??
                              '下一页（长按退出）',
                          icon: Icon(
                            Icons.arrow_forward_rounded,
                            color: AppleColor.surfaceWhite.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          onPressed: _index < elements.length - 1 ? _next : null,
                        ),
                      ],
                    ),
                  ),
                ),
                // 左上角退出按钮。
                Positioned(
                  left: 12,
                  top: 12,
                  child: IconButton(
                    tooltip: AppLocalizations.of(context)?.presExit ?? '退出演示',
                    icon: Icon(
                      Icons.close,
                      // D-15：白系捷径 → AppleColor.surfaceWhite 令牌。
                      color: AppleColor.surfaceWhite.withValues(alpha: 0.7),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

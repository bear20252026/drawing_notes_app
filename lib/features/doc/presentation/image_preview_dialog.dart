/// 图片全屏预览弹窗。
///
/// 支持手势缩放（InteractiveViewer）与点击/滑动关闭。
/// 无外部依赖，仅使用 Flutter 内置组件。
library;

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/utils/safe_url.dart';
import 'package:drawing_notes_app/shared/utils/image_decode_cap.dart';
import '../../../core/theme/apple_design.dart';
import '../../../core/theme/apple_motion.dart';

/// 显示图片全屏预览弹窗。
///
/// [src] 为图片 URL（网络图）。[caption] 可选说明文案。
/// 若 [src] 为空或未通过 [sanitizeImageSrc]（非 https/无 host/含 userinfo/
/// 超长）则不弹出并返回 null（不发起任何请求——fail-closed）。
Future<void> showImagePreviewDialog(
  BuildContext context, {
  required String src,
  String? caption,
}) async {
  final safeSrc = sanitizeImageSrc(src);
  if (safeSrc == null) return;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context)?.close ?? '关闭',
    barrierColor: Colors.black87,
    // M-07（审计 2026-09-27）：全屏沉浸预览属模态，时长对齐同族
    // unlock_sheets 的 modal 档（原用 dropdown，同族不一致）。
    transitionDuration: AppleMotion.modal,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _ImagePreviewPage(src: safeSrc, caption: caption);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppleMotion.easeOut),
        child: child,
      );
    },
  );
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.src, this.caption});

  final String src;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 中央可缩放图片
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              // P-11（审计 2026-09-27）：全屏预览按屏宽量化解码——此前
              // 无 cacheWidth，数千万像素照片整幅进图像缓存。量化档位与
              // 嵌入图同源（ImageDecodeCap，2048 封顶）；1:1 满屏物理像素
              // 内清晰，InteractiveViewer 4x 内放大由 GPU 上采样补足。
              child: Image.network(
                src,
                fit: BoxFit.contain,
                cacheWidth: ImageDecodeCap.quantizedCacheWidth(
                  MediaQuery.sizeOf(context).width,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  // 刻意保留 spinner（审计二-6 分类裁决）：图片传输
                  // **进度**反馈（沉浸式黑底查看器），非布局骨架场景。
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 64,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)?.embImageFailed ??
                              '图片加载失败',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // 顶部关闭按钮
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),

          // 底部说明文案
          if (caption != null && caption!.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(AppleRadius.sm),
                  ),
                  child: Text(
                    caption!,
                    style: AppleTypeScale.of(
                      AppleTypeScale.caption,
                      Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

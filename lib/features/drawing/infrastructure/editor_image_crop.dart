/// 编辑器图片裁剪域（C-04 第五批，自 presentation 迁入）。
///
/// 裁剪的几何换算（[EditorImageCropGeometry]）与磁盘写回
/// （[EditorImageCropWriter]）同属图片裁剪域：几何只做画布矩形 ↔ 原图
/// 像素矩形的确定性换算；写回管线负责解码（兼容 DNV 密文）、重采样、
/// PNG 编码、按原密文状态重新密封与原子落盘。两者都不持有 Widget /
/// 交互状态 / 通知回调。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

// ── 裁剪几何 ─────────────────────────────────────────────────

/// 图片裁剪框的四个角手柄。
///
/// 以命名语义取代页面内按局部 [Offset] 比较的隐式分派，使裁剪几何的
/// 输入和输出可独立测试。
enum EditorImageCropHandle { topLeft, topRight, bottomLeft, bottomRight }

/// 编辑器图片裁剪的纯几何计算。
///
/// 本类只处理画布矩形与原图像素矩形的确定性换算，不读取文件、不解码
/// 图像、不修改交互状态，也不通知或保存。
abstract final class EditorImageCropGeometry {
  static const double minCropExtent = 10;

  /// 按四角手柄和画布增量计算新的裁剪矩形。
  ///
  /// [imageBounds] 是图片在画布上的完整边界。输出始终限制在该边界内，
  /// 且沿两个轴均保持现有的最小 10 画布单位尺寸规则。
  static Rect resizeCropRect({
    required Rect cropRect,
    required Rect imageBounds,
    required EditorImageCropHandle handle,
    required Offset canvasDelta,
  }) {
    return switch (handle) {
      EditorImageCropHandle.topLeft => Rect.fromLTRB(
        (cropRect.left + canvasDelta.dx)
            .clamp(imageBounds.left, cropRect.right - minCropExtent)
            .toDouble(),
        (cropRect.top + canvasDelta.dy)
            .clamp(imageBounds.top, cropRect.bottom - minCropExtent)
            .toDouble(),
        cropRect.right,
        cropRect.bottom,
      ),
      EditorImageCropHandle.topRight => Rect.fromLTRB(
        cropRect.left,
        (cropRect.top + canvasDelta.dy)
            .clamp(imageBounds.top, cropRect.bottom - minCropExtent)
            .toDouble(),
        (cropRect.right + canvasDelta.dx)
            .clamp(cropRect.left + minCropExtent, imageBounds.right)
            .toDouble(),
        cropRect.bottom,
      ),
      EditorImageCropHandle.bottomLeft => Rect.fromLTRB(
        (cropRect.left + canvasDelta.dx)
            .clamp(imageBounds.left, cropRect.right - minCropExtent)
            .toDouble(),
        cropRect.top,
        cropRect.right,
        (cropRect.bottom + canvasDelta.dy)
            .clamp(cropRect.top + minCropExtent, imageBounds.bottom)
            .toDouble(),
      ),
      EditorImageCropHandle.bottomRight => Rect.fromLTRB(
        cropRect.left,
        cropRect.top,
        (cropRect.right + canvasDelta.dx)
            .clamp(cropRect.left + minCropExtent, imageBounds.right)
            .toDouble(),
        (cropRect.bottom + canvasDelta.dy)
            .clamp(cropRect.top + minCropExtent, imageBounds.bottom)
            .toDouble(),
      ),
    };
  }

  /// 将画布裁剪矩形映射为原始图片像素矩形。
  ///
  /// 保持编辑器已有的 `sourceExtent / (canvasExtent + 1)` 比例与钳制规则，
  /// 避免职责迁移造成单像素范围的行为变化。
  static Rect sourceRectForCrop({
    required Rect cropRect,
    required Rect imageBounds,
    required Size sourceSize,
  }) {
    final scaleX = sourceSize.width / (imageBounds.width + 1);
    final scaleY = sourceSize.height / (imageBounds.height + 1);
    return Rect.fromLTWH(
      (cropRect.left - imageBounds.left)
              .clamp(0, imageBounds.width)
              .toDouble() *
          scaleX,
      (cropRect.top - imageBounds.top).clamp(0, imageBounds.height).toDouble() *
          scaleY,
      cropRect.width.clamp(0, imageBounds.width).toDouble() * scaleX,
      cropRect.height.clamp(0, imageBounds.height).toDouble() * scaleY,
    );
  }
}

// ── 写回管线 ─────────────────────────────────────────────────

/// 裁剪写回结果（UI 据此映射提示文案；意外异常不吞，直接抛出）。
enum EditorImageCropWriteOutcome {
  /// 已重写磁盘文件，等待调用方更新画布对象与位图缓存。
  success,

  /// 原图文件不存在。
  sourceMissing,

  /// PNG 编码失败（toByteData 返回 null）。
  encodeFailed,

  /// 原文件是 DNV 密文但保险库已锁定——fail-closed 拒绝写回。
  vaultLocked,
}

/// 图片裁剪的字节写回管线（对齐 Excalidraw 图片裁剪）。
///
/// 输入画布侧的裁剪矩形与图片边界；内部完成解码 → 几何换算 → 重采样 →
/// PNG 编码 → 密封（如原文件为 DNV 密文）→ 原图 `.bak` 备份 → tmp+rename
/// 原子写。GPU 纹理
/// 在 finally 释放（H-05：toImage/toByteData 抛错的异常路径不泄漏
/// src/out/Codec）；意外异常向上抛出，由调用方统一兜底提示。
class EditorImageCropWriter {
  const EditorImageCropWriter();

  Future<EditorImageCropWriteOutcome> writeCrop({
    required File file,
    required Rect cropRect,
    required Rect imageBounds,
  }) async {
    Image? srcImage;
    Image? outImage;
    Codec? srcCodec;
    try {
      if (!file.existsSync()) {
        return EditorImageCropWriteOutcome.sourceMissing;
      }
      // 批次①c：DNV 密文 → 解密后裁剪；写回时按原密文状态重新密封，
      // 防止裁剪把明文覆盖到原密文文件上（锁定时拒绝裁剪——fail-closed）。
      final raw = await file.readAsBytes();
      final wasSealed = VaultFileCodec.isEncrypted(raw);
      final bytes = wasSealed ? await VaultFileCodec.readImageBytes(file) : raw;
      srcCodec = await instantiateImageCodec(bytes);
      final frame = await srcCodec.getNextFrame();
      srcImage = frame.image;
      final src = srcImage;
      // 裁剪矩形（画布坐标）映射为原图像素坐标；纯几何不触碰文件或状态。
      final srcRect = EditorImageCropGeometry.sourceRectForCrop(
        cropRect: cropRect,
        imageBounds: imageBounds,
        sourceSize: Size(src.width.toDouble(), src.height.toDouble()),
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        srcRect,
        Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      outImage = await picture.toImage(
        srcRect.width.round().clamp(1, 10000),
        srcRect.height.round().clamp(1, 10000),
      );
      final out = outImage;
      final data = await out.toByteData(format: ImageByteFormat.png);
      if (data == null) {
        return EditorImageCropWriteOutcome.encodeFailed;
      }
      final outBytes = data.buffer.asUint8List();
      final Uint8List payload;
      if (wasSealed) {
        // 原文件是 DNV 密文：写回前重新密封（密钥锁定 → 拒绝保存）。
        final key = VaultKeyService.sharedMasterKeyOrNull;
        if (key == null) {
          return EditorImageCropWriteOutcome.vaultLocked;
        }
        payload = await VaultFileCodec.encrypt(
          outBytes,
          key,
          aadContext: VaultFileCodec.contextForPath(file.path),
        );
      } else {
        payload = outBytes;
      }
      // A-01（审计 2026-09-27）：原地 writeAsBytes 非原子——写入中断
      // （崩溃/断电）会截断唯一原图。改走 tmp + rename + 失败清理
      // （同 NotebookStorage._writeNotebookBytes 单一出口纪律）。
      //
      // 修复 2（审计 2026-10-04）：覆盖前把原图逐字保留为 `.bak` 可恢复
      // 副本（本仓崩溃恢复惯例——storage_write_pipeline.writeSealedBytes /
      // note_block_doc_store 同纪律）。直接覆盖唯一原图不可逆，用户误裁
      // 一次即永久丢失。
      //
      // 为何选 `.bak` 而非「新路径 + 成功后切换引用」：
      // 1) 切换 img.filePath 属页面侧（editor_page.dart，非本模块所有权），
      //    会把「文档几何更新」与「磁盘写入」拆成两次不成对更新；
      // 2) DNV 密文 AAD 绑定文件基名（VaultFileCodec.contextForPath 取基名）——
      //    逐字复制原密文信封到 `X.bak` 后改存新基名会破坏 AAD 绑定，恢复须
      //    把 `X.bak` 改回原名（彼时基名一致、解密正常）；
      // 3) UI 读图只按精确在档路径取字节（encrypted_file_image /
      //    document_image_cache），从不自动读 `.bak`，故副本不会被误当在档图，
      //    也不影响按魔数嗅探的加密等级判定；backup_service 亦排除 `*.bak`。
      // 备份先于 rename：任一步失败在档文件完好、无半成品（沿用原子纪律）。
      final tmp = File('${file.path}.${LocalIdGenerator.next('write')}.tmp');
      try {
        await tmp.writeAsBytes(payload, flush: true);
        await file.copy('${file.path}.bak');
        try {
          await tmp.rename(file.path);
        } on FileSystemException {
          if (!file.existsSync()) rethrow;
          await file.delete();
          await tmp.rename(file.path);
        }
      } catch (_) {
        try {
          if (tmp.existsSync()) await tmp.delete();
        } catch (_) {
          // 清理失败不覆盖原始写入异常。
        }
        rethrow;
      }
      return EditorImageCropWriteOutcome.success;
    } finally {
      srcImage?.dispose();
      outImage?.dispose();
      srcCodec?.dispose();
    }
  }
}

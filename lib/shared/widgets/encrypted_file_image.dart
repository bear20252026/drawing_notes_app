import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:drawing_notes_app/core/security/notebook_media_keys.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/storage/vfs/vault_service.dart';
import 'package:drawing_notes_app/shared/utils/image_decode_cap.dart';

/// 加密媒体图片渲染（H-03 双端接入 2026-08-15）。
///
/// ImageProvider.loadBuffer 官方 API（PR #103496）：读取媒体文件字节 →
/// [NotebookMediaKeys.openMedia]（DAN 密文按笔记本 K_note 解密 / 明文
/// 兼容——未加密笔记本）→ 解码渲染。与 storeImage 加密写入成对（双端同步）。
///
/// 框架级收口（2026-11-15）：解密依赖从「媒体原语服务」改为**取钥权威
/// 编排器**——LRU 逐出后自动经 ensure 重解包（不再渲染空白），回锁/
/// 无会话密码 fail-closed。shared 层不直取任何 `.instance`（生产由组合根
/// 沿页面构造链传线）。可空字段为测试直构保留既有 fail-closed 语义：
/// - [mediaKeys] 为 null：DAN 密文抛「会话密钥未注入」StateError、
///   明文原样返回；
/// - [vaultService] 为 null：'vfs:' 对象抛「VaultService 未初始化」
///   StateError（与全局单例未 configure 时逐字一致）。
/// 缓存键 = 路径 + scale + notebookId（M-1：跨本引用不得命中同一缓存
/// 绕过 AAD 校验）；服务实例不参与键（一次会话内恒为同一单例）。
@immutable
class EncryptedFileImage extends ImageProvider<EncryptedFileImage> {
  const EncryptedFileImage(
    this.file, {
    this.scale = 1.0,
    this.mediaKeys,
    this.vaultService,
    this.notebookId,
  }) : _path = null;

  /// 路径构造（H1 架构修复 2026-11）：表现层不再直接 `import 'dart:io'`
  /// 构造 `File`——由本 provider 内部从路径派生，presentation 只传字符串。
  ///
  /// 与 [EncryptedFileImage] 等价（同一解密链、同一缓存键语义）；文件对象
  /// 在 provider 内部创建，调用方（features/*/presentation/**）因此无需触碰
  /// dart:io。Web 平台可用性：路径字符串不依赖 dart:io，渲染路径与
  /// [file] 构造完全一致。
  const EncryptedFileImage.fromPath(
    String path, {
    this.scale = 1.0,
    this.mediaKeys,
    this.vaultService,
    this.notebookId,
  }) : file = null,
       _path = path;

  /// 媒体文件（可能为 DAN 密文或明文）。
  final File? file;

  /// 路径构造下的本地文件路径（[EncryptedFileImage.fromPath]）。
  /// 与 [file] 互斥：file 非空时本字段为 null。
  final String? _path;

  /// 实际参与读取/缓存键的文件路径（[filePath] 的私有来源）。
  String get filePath => file?.path ?? _path ?? '';

  final double scale;

  /// 媒体密钥编排器（框架级收口 2026-11-15 构造注入——组合根沿页面
  /// 构造链传线）：DAN 解密唯一入口，LRU 逐出自动重解包、回锁 fail-closed。
  final NotebookMediaKeys? mediaKeys;

  /// VFS 媒体仓库（可选——'vfs:' 前缀对象读回用；媒体读取双轨）。
  final VaultService? vaultService;

  /// 所属笔记本 ID（K_note 接线 2026-11-16）：DAN 密文按笔记本密钥解密、
  /// AAD 绑定笔记本。null 时 DAN 密文 fail-closed（明文/VFS/DNV 不受影响）。
  /// **参与 ==/hashCode**（M-1：缓存键含笔记本维度，防跨本命中绕过 AAD）。
  final String? notebookId;

  @override
  Future<EncryptedFileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<EncryptedFileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    EncryptedFileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.filePath,
    );
  }

  Future<ui.Codec> _loadAsync(
    EncryptedFileImage key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final clear = await _readClearBytes(key);
    if (clear.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('$file 无法加载为图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(clear);
    // U2 降采样（P1-13）：长边超限时经 getTargetSize 让解码器直接产出
    // 目标尺寸位图（只缩不放大），原图不再全分辨率进内存。
    return decode(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        final target = ImageDecodeCap.targetSize(
          intrinsicWidth,
          intrinsicHeight,
          ImageDecodeCap.defaultMaxLongEdge,
        );
        return ui.TargetImageSize(width: target.width, height: target.height);
      },
    );
  }

  /// 三通道读明文字节（U2 重构抽取，行为与原实现逐字节一致）。
  Future<Uint8List> _readClearBytes(EncryptedFileImage key) async {
    // 媒体 VFS 双轨（2026-08-16）：'vfs:' 前缀对象（新媒体——VaultService
    // 解密明文）→ 直接渲染；否则文件路径（旧媒体——DAN 检测兼容——
    // s3-encryption-gateway 双读窗口模式）。
    final path = key.filePath;
    if (path.startsWith('vfs:')) {
      // C-06：仓库实例构造注入；null 时保持既有「未 configure」语义。
      final vault = key.vaultService;
      if (vault == null) {
        throw StateError('VaultService 未初始化（解锁时 configure）');
      }
      final clear = await vault.getObject(path.substring(4));
      return clear;
    }
    final file = key.file ?? File(path);
    final bytes = await file.readAsBytes();
    // 批次①c 三级嗅探：DNV 信封（保险库主密钥）→ 解密（锁定抛
    // [VaultFileLockException]——fail-closed）；DAN 密文 → 解密；
    // 明文（旧数据/未加密）→ 原样返回。
    if (VaultFileCodec.isEncrypted(bytes)) {
      return VaultFileCodec.readImageBytes(file);
    }
    // 框架级收口（2026-11-15）：DAN 解密经取钥权威编排器——LRU 逐出
    // 自动重解包（M-2）、回锁 fail-closed；null（测试直构未注入）时 DAN
    // 抛 StateError、明文放行（既有语义）。
    final keys = key.mediaKeys;
    if (keys == null) {
      // DAN 嗅探不依赖编排器实例（静态魔数检测）。
      if (bytes.length >= 4 &&
          bytes[0] == 0x44 &&
          bytes[1] == 0x41 &&
          bytes[2] == 0x4E) {
        throw StateError('会话密钥未注入（请先解锁）');
      }
      return bytes;
    }
    return keys.openMedia(key.notebookId, bytes);
  }

  @override
  bool operator ==(Object other) =>
      other is EncryptedFileImage &&
      other.filePath == filePath &&
      other.scale == scale &&
      other.notebookId == notebookId;

  @override
  int get hashCode => Object.hash(filePath, scale, notebookId);

  @override
  String toString() => 'EncryptedFileImage("$filePath", scale: $scale)';
}

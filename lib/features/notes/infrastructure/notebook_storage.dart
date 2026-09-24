import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/storage/vfs/vault_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_repository.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';

// O1 域分权（F9，2026-09-24）：IO/编码落盘两域私有助手 part。
// 新增同域私有逻辑请落对应 part；public API、字段与静态成员留在本体。
part 'notebook_storage_io.dart';
part 'notebook_storage_codec.dart';

/// 笔记本本地存储服务。
///
/// 目录结构（应用文档目录下）：
///   `appDir/notebooks/`
///     `notebookId.json` —— 笔记本工程文件（含全部页面、画布、文字/图片块）
///   `appDir/notebook_images/`
///     `pageId_xxx.png` —— 插入页面中的图片副本
///
/// 与 [StorageService] 一样：全部本地操作、无网络请求；
/// 图片以副本方式保存进应用目录，保证离线可用且原文件删除不影响笔记。
///
/// 密码保护（C3/C5）：启用加密的笔记本以 AES-GCM 密文存储页面内容，
/// 明文不落盘；打开时需输入密码解密（见 [encryptNotebook]/[decryptNotebook]）。
///
/// 已通过 [NotebookRepository] 接口抽象（见 repository.dart），
/// 未来替换为云同步实现时无需改动上层逻辑。
class NotebookStorage
    implements NotebookRepository, INotebookAccessor, SessionSecretsHolder {
  NotebookStorage({
    this.directoryProvider,
    this.vaultService,
    this.keyProvider,
  }) {
    // P1 修复 M-09：注册会话机密清理——切后台回锁时笔记本口令一并失效。
    SessionSecrets.register(this);
  }

  /// 主密钥提供者（加密底座批次①c）：返回解锁态主密钥时，笔记本工程文件
  /// JSON 以 DNV 信封落盘（AAD 绑定 `nb:<id>`）、页面图片以 DNV 信封落盘
  /// （AAD 绑定 `file:<basename>`）；null 时保持既有行为明文/DAN 兼容。
  final Future<Uint8List?> Function()? keyProvider;

  /// VFS 媒体仓库（可选——解锁时注入——新媒体写 VFS 对象——双轨：
  /// s3-encryption-gateway 双读窗口模式——旧媒体 DAN 文件兼容读）。
  VaultService? vaultService;

  /// 写成功回调（首页刷新修复①）：笔记本保存/删除落盘成功后触发，由装配层
  /// 注入（AppServices.bumpDataVersion）。所有保存路径（save/encryptAndSave）
  /// 均汇入 _writeNotebook 单一出口，此处通知即全覆盖。
  void Function()? onWrite;

  // ---- INotebookAccessor 跨功能契约适配（S4b：NotebookStorage 直接实现契约）----

  @override
  Future<List<NotebookSearchDocument>> listSearchDocuments() async {
    final notebooks = await listAll();
    return [
      // 锁定占位不进搜索（N2 口径：锁定内容跳过索引）。
      for (final notebook in notebooks)
        if (!notebook.isLockedPlaceholder)
          NotebookSearchDocument(
            id: notebook.id,
            title: notebook.title,
            searchSummary: notebook.searchSummary,
            pages: [
              for (final page in notebook.pages)
                NotebookSearchPage(
                  id: page.id,
                  title: page.title,
                  textContents: [
                    for (final textItem in page.textItems) textItem.text,
                  ],
                ),
            ],
          ),
    ];
  }

  @override
  bool get isStorageAvailable => true;

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  static const EncryptionService _encryption = EncryptionService();

  Directory? _notebooksDir;
  Directory? _imagesDir;

  /// 按笔记本 ID 隔离的落盘队列：同一笔记本保序，不同笔记本不共享临时文件。
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  /// 公开的图片目录提供（供编辑器粘贴图片保存用，包装私有实现）。
  Future<Directory> ensureImagesDir() => _ensureImagesDir();

  /// 校验 ID 是否安全（仅允许字母、数字、下划线）。
  ///
  /// 安全说明：ID 直接拼入文件路径，若允许 `../` 等字符会造成路径遍历。
  /// 所有合法 ID 由 [newId] 生成；此校验作为防御性边界。
  /// 链 9 修复（军工审计 2026-08-15）：允许 '-'（与 StorageService/
  /// DocumentCodec 一致——'-' 无路径遍历风险）。
  static bool isValidId(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  /// H-03 部分落地（专家审计 2026-08-15）：图片源文件大小上限。
  static const int _maxImageSourceBytes = 50 * 1024 * 1024; // 50MB

  /// 把快照 Map 编码为**紧凑** JSON 字节（jsonEncode 无缩进，utf8.encode
  /// 直接产出 Uint8List；性能优化：去掉旧 JsonEncoder.withIndent('  ')
  /// 的主线程全量 pretty 编码——内容语义不变，仅排版空白差异）。
  /// 纯静态纯函数，可安全跑在 isolate 中。
  static Uint8List _encodeSnapshot(Map<String, dynamic> snapshot) =>
      utf8.encode(jsonEncode(snapshot));

  /// isolate 编码阈值：低于该元素量时 isolate 往返（拷贝 + spawn）开销
  /// 大于收益，直接主线程编码（对齐 DocumentCodec.isolateEncodeThreshold
  /// 的取舍，量级按笔记本的「页面内容元素」折算）。
  static const int _isolateEncodeThreshold = 2000;

  /// 异步编码：小笔记本主线程直编，达到 [_isolateEncodeThreshold] 元素量
  /// 的笔记本移入 [Isolate.run] 编码。快照为纯数据，可安全跨 isolate 传递。
  static Future<Uint8List> _encodeSnapshotAsync(Map<String, dynamic> snapshot) {
    if (_countContentElements(snapshot) < _isolateEncodeThreshold) {
      return Future.value(_encodeSnapshot(snapshot));
    }
    return Isolate.run(() => _encodeSnapshot(snapshot));
  }

  /// 轻量估算快照的内容元素量（笔画/文字/图片/形状/图表/连线计数），
  /// 供 isolate 分流决策；只读 List.length，不触几何数据。
  static int _countContentElements(Map<String, dynamic> snapshot) {
    final pages = snapshot['pages'];
    if (pages is! List) return 0;
    var total = 0;
    for (final page in pages) {
      if (page is! Map) continue;
      final document = page['document'];
      if (document is Map) {
        final layers = document['layers'];
        if (layers is List) {
          for (final layer in layers) {
            final strokes = layer is Map ? layer['strokes'] : null;
            if (strokes is List) total += strokes.length;
          }
        }
      }
      for (final key in const [
        'textItems',
        'imageItems',
        'shapes',
        'charts',
        'connectors',
      ]) {
        final value = page[key];
        if (value is List) total += value.length;
      }
    }
    return total;
  }

  /// 加载笔记本。不存在返回 null，损坏抛出异常。
  ///
  /// 批次①c：DNV 密文 → 解锁解密 / 锁定抛 [VaultFileLockException]；
  /// 明文+解锁 → 懒迁移（备份回退路径不迁移，避免覆盖主文件）。
  @override
  Future<Notebook?> load(String id) async {
    await _ensureNotebooksDir();
    final file = File(await _pathFor(id));
    final backup = File('${file.path}.bak');
    if (!file.existsSync() && !backup.existsSync()) return null;
    try {
      final bytes = await (file.existsSync() ? file : backup).readAsBytes();
      final prepared = await _prepareNotebookBytes(id, bytes);
      return Notebook.fromJson(
        jsonDecode(utf8.decode(prepared)) as Map<String, dynamic>,
      );
    } on VaultFileLockException {
      rethrow; // 锁定不回退备份——备份同为密文，fail-closed
    } catch (e) {
      // B12 修复（审计 2026-09-07）：主文件解析失败先试备份回退；主备均
      // 失败（或无备份可回退）时，裸 TypeError（jsonDecode 强转/字段类型
      // 不符）包成 FormatException——调用方按「笔记本数据损坏」统一处理，
      // 原始异常带在消息里（Dart FormatException 无 cause 槽位）。
      if (backup.existsSync()) {
        try {
          final bytes = await backup.readAsBytes();
          final prepared = await _prepareNotebookBytes(
            id,
            bytes,
            migrate: false,
          );
          return Notebook.fromJson(
            jsonDecode(utf8.decode(prepared)) as Map<String, dynamic>,
          );
        } on VaultFileLockException {
          rethrow; // 备份锁定：保留锁定语义（fail-closed），不当损坏处理。
        } catch (e2) {
          if (e2 is TypeError) {
            throw FormatException('笔记本数据损坏：$e2');
          }
          rethrow;
        }
      }
      if (e is TypeError) {
        throw FormatException('笔记本数据损坏：$e');
      }
      rethrow;
    }
  }

  /// 列出所有笔记本（按更新时间倒序）。
  ///
  /// 批次①c：DNV 密文 → 解锁解密（明文懒迁移）/ 锁定 → 占位条目
  /// （fail-closed 可见性，与 N2 块文档列表占位同口径——标题不泄露，
  /// [Notebook.isLockedPlaceholder] 供下游识别；内容仍不可读）。
  /// 损坏文件仍跳过（不中断列表）。
  @override
  Future<List<Notebook>> listAll() async {
    await _ensureNotebooksDir();
    final result = <Notebook>[];
    await for (final entity in (await _ensureNotebooksDir()).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final name = entity.uri.pathSegments.last;
        final id = name.substring(0, name.length - '.json'.length);
        // D16 修复（审计 2026-09-07）：文件名截出的 id 先过 isValidId——
        // 畸形文件名（含路径遍历字符等）不进入结果（load/delete 入口
        // 同口径防护）。
        if (!isValidId(id)) continue;
        final raw = await entity.readAsBytes();
        if (VaultFileCodec.isEncrypted(raw)) {
          final key = await _currentKey();
          if (key == null) {
            // 锁定——占位（不静默跳过：条目可见，内容 fail-closed）。
            final mtime = await _fileMtime(entity);
            result.add(
              Notebook(
                id: id,
                title: '加密分页画布',
                encrypted: true,
                createdAt: mtime,
                updatedAt: mtime,
              ),
            );
            continue;
          }
        }
        final bytes = await _prepareNotebookBytes(id, raw);
        result.add(
          Notebook.fromJson(
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // 跳过损坏文件，不中断列表。
        continue;
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  /// 删除笔记本（同时清理其关联图片副本）。返回是否删除成功。
  ///
  /// E-18 修复（审计 2026-09-07）：整个删除流程挂入与保存相同的 per-id
  /// 写尾队列——在途保存与删除交错会让已删笔记本复活（保存排队在前、
  /// 删文件在后 → 队列中的保存在删除完成后又写出正式文件）。
  @override
  Future<bool> delete(String id) => _runExclusive(id, () => _deleteLocked(id));

  /// 保存页面图片副本，返回副本的绝对路径。
  ///
  /// [sourcePath] 为用户选择的图片原路径；[pageId] 用于文件名分组。
  @override
  Future<String> storeImage(String sourcePath, String pageId) async {
    if (!isValidId(pageId)) {
      throw ArgumentError('非法 pageId: $pageId');
    }
    // 媒体 VFS 双轨（2026-08-16）：新媒体写入 VFS 对象（'vfs:' 标记——
    // 解锁会话内 VaultService 注入——s3-encryption-gateway 双读窗口模式）；
    // 旧媒体 DAN 文件保持兼容读。
    final vfs = vaultService;
    if (vfs != null && vfs.hasKey) {
      final src = File(sourcePath);
      if (!src.existsSync()) {
        throw FileSystemException('源图片不存在', sourcePath);
      }
      final id = 'media/${pageId}_${DateTime.now().microsecondsSinceEpoch}';
      await vfs.putObject(id, plain: await src.readAsBytes(), type: 'media');
      return 'vfs:$id';
    }
    final src = File(sourcePath);
    if (!src.existsSync()) throw FileSystemException('源图片不存在', sourcePath);
    // H-03 部分落地（专家审计 2026-08-15）：源文件大小配额（防超大图片
    // 资产入库；完整媒体加密——每笔记 DEK + 渲染解密——评估为数据保密
    // 重构专项，涉及渲染管线跨域改造，见 Inqrypt/heritage 分层加密模式）。
    if (await src.length() > _maxImageSourceBytes) {
      throw FileSystemException('图片源文件过大（超过 50MB 限制）', sourcePath);
    }
    // 扩展名白名单：只接受常见图片格式，防止任意文件以图片身份入库。
    final ext = sourcePath.contains('.')
        ? sourcePath.split('.').last.toLowerCase()
        : '';
    const allowed = {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'svg',
      'heic',
      'heif',
      'tif',
      'tiff',
    };
    final safeExt = allowed.contains(ext) ? ext : 'png';
    final dir = await _ensureImagesDir();
    final target = File(
      '${dir.path}${Platform.pathSeparator}${pageId}_${DateTime.now().microsecondsSinceEpoch}.$safeExt',
    );
    try {
      // H-03 双端接入（专家审计 2026-08-15）+ 批次①c 三级加密封支：
      // ① 会话密钥已注入（加密笔记本解锁场景）→ DAN 文件头加密；
      // ② 保险库解锁 → DNV 信封（AAD 绑定 file:<basename>）；
      // ③ 均未解锁 → 明文写入（旧数据兼容，读取时懒迁移）。
      final bytes = await src.readAsBytes();
      final Uint8List stored;
      if (MediaCryptoService.instance.isActive) {
        stored = await MediaCryptoService.instance.encryptFile(bytes);
      } else {
        final key = await _currentKey();
        stored = key == null
            ? bytes
            : await VaultFileCodec.encrypt(
                bytes,
                key,
                aadContext: VaultFileCodec.contextForPath(target.path),
              );
      }
      // E-19 修复（审计 2026-09-07）：`target.writeAsBytes` 直写非原子——
      // 写入中断留下半张图片（下一次读取按损坏处理但文件占位）。改走
      // _writeNotebookBytes 的 tmp + rename + 失败清理（同 _writeNotebook
      // 单一出口纪律；目标文件名含微秒时间戳，唯一无覆盖场景）。
      await _writeNotebookBytes(target, stored);
      return target.path;
    } catch (_) {
      // 不让加密或写入异常留下可被清理器误认为有效媒体的半成品。
      try {
        if (target.existsSync()) await target.delete();
      } catch (_) {
        // 清理失败不覆盖原始异常。
      }
      rethrow;
    }
  }

  /// 旧明文媒体迁移（H-03 专家审计 2026-08-15）：解锁后批量重加密——
  /// payload-plugins 批量加密器模式（幂等——已 DAN 密文跳过）。
  /// 返回迁移的文件数；未解锁（会话密钥未注入）返回 0。
  Future<int> migrateLegacyMedia() async {
    final service = MediaCryptoService.instance;
    if (!service.isActive) return 0; // 未解锁——不迁移
    final dir = await _ensureImagesDir();
    var migrated = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final bytes = await entity.readAsBytes();
        if (MediaCryptoService.isEncryptedFile(bytes)) continue;
        await entity.writeAsBytes(
          await service.encryptFile(bytes),
          flush: true,
        );
        migrated++;
      } catch (_) {
        // 单个迁移失败忽略（后续解锁再试——幂等）。
      }
    }
    return migrated;
  }

  /// 全局媒体加密盐（H-03 方案 B 2026-08-15）：密码模式媒体加密的派生
  /// 盐——明文持久（盐无需保密），跨会话一致（解密媒体重派生同 key）。
  Future<List<int>> ensureMediaSalt() async {
    final base = await _baseDir();
    final file = File('${base.path}${Platform.pathSeparator}media_crypto_salt');
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      if (bytes.length >= 16) return bytes.take(16).toList();
    }
    final salt = MediaCryptoService.generateSalt();
    await file.writeAsBytes(salt, flush: true);
    return salt;
  }

  /// 启用密码保护并保存：把页面内容 AES-GCM 加密为载荷，明文不落盘。
  ///
  /// N4 批 3：加密走 v5 双保护器载荷（随机 DEK + 密码槽 + 可选重置盘槽）；
  /// 已是 v5 时复用信封内的 DEK 与重置盘槽位（续写不失效已绑定槽位——
  /// LUKS 槽位语义），仅重生成 payload 密文。
  /// [usbKey] 为重置密码盘钥匙（可选——设密/改密时当场插盘绑定）。
  Future<String> encryptAndSave(
    Notebook notebook,
    String password, {
    List<int>? usbKey,
  }) async {
    // 第一步合规（2026-08-16 专家审计最优先行动②）：加密笔记本不生成
    // 明文 searchSummary——"废除默认明文 searchSummary"。未来 K_note
    // 密钥层级落地后摘要可加密存储（解锁会话内搜索——安全）。
    final payloadJson = jsonEncode({
      'pages': notebook.pages.map((p) => p.toJson()).toList(),
    });
    final existing = notebook.encryptedPayload;
    if (existing != null &&
        EncryptionService.isDualProtectorEnvelope(existing)) {
      // v5 续写：密码解出 DEK → 复用槽位组，仅重生成 payload。
      final map = jsonDecode(existing) as Map<String, dynamic>;
      final dek = await _encryption.unwrapPasswordSlotForRewrap(
        notebookId: notebook.id,
        encryptedJson: existing,
        password: password,
      );
      if (dek == null) {
        throw const FormatException('会话密码与当前信封不匹配');
      }
      final newPayload = await _encryption.rewrapPayloadV5(
        notebookId: notebook.id,
        map: map,
        dek: dek,
        plaintext: payloadJson,
      );
      notebook.encryptedPayload = newPayload;
    } else {
      notebook.encryptedPayload = await _encryption.encryptWithPasswordV5(
        notebookId: notebook.id,
        plaintext: payloadJson,
        password: password,
        usbKey: usbKey,
      );
    }
    notebook.encrypted = true;
    _cacheNotebookPassword(notebook.id, password);
    // 直接原子写入（toJson 中 encrypted 时 pages 序列化为空，仅存密文载荷）。
    // 注意：不能走 save()——save 对"加密且内存有明文页面"会抛 StateError
    // （这是编辑会话的守卫），而加密保存时内存本来就有明文页面。
    return _writeNotebook(notebook);
  }

  /// 校验分页画布文件密码（正确即入会话缓存——解锁一次本会话免重复输入）。
  Future<bool> verifyNotebookPassword(String id, String password) async {
    final nb = await load(id);
    if (nb == null || nb.encryptedPayload == null) return false;
    try {
      await _encryption.decryptWithPasswordAad(
        notebookId: id,
        encryptedJson: nb.encryptedPayload!,
        password: password,
      );
    } on FormatException {
      return false;
    }
    _cacheNotebookPassword(id, password);
    return true;
  }

  /// 修改分页画布文件密码（N4 批 3）。
  ///
  /// v5 信封：仅重绕密码槽（payload 与重置盘槽位原样保留——LUKS 语义）。
  /// v4/v3/v2 旧信封：解密后整体升级为 v5（可选顺带绑定重置盘）。
  /// 旧密码错误抛 [FormatException]。
  Future<void> changeNotebookPassword(
    String id,
    String oldPassword,
    String newPassword, {
    List<int>? usbKey,
  }) async {
    final nb = await load(id);
    final payload = nb?.encryptedPayload;
    if (nb == null || payload == null) {
      throw StateError('该分页画布未设置文件密码');
    }
    String newPayload;
    if (EncryptionService.isDualProtectorEnvelope(payload)) {
      newPayload = await _encryption.changeNotebookPasswordV5(
        notebookId: id,
        encryptedJson: payload,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      if (usbKey != null && !EncryptionService.hasUsbSlotV5(payload)) {
        newPayload = await _encryption.bindNotebookUsbSlotV5(
          notebookId: id,
          encryptedJson: newPayload,
          password: newPassword,
          usbKey: usbKey,
        );
      }
    } else {
      // 旧格式升级：解密出明文 → v5 重加密（顺带完成格式升级）。
      final clear = await _encryption.decryptWithPasswordAad(
        notebookId: id,
        encryptedJson: payload,
        password: oldPassword,
      );
      newPayload = await _encryption.encryptWithPasswordV5(
        notebookId: id,
        plaintext: clear,
        password: newPassword,
        usbKey: usbKey,
      );
    }
    nb.encryptedPayload = newPayload;
    _cacheNotebookPassword(id, newPassword);
    await save(nb);
  }

  /// 该分页画布是否已绑定重置密码盘（v5 且含 USB 槽位）。
  Future<bool> hasNotebookUsbSlot(String id) async {
    final nb = await load(id);
    final payload = nb?.encryptedPayload;
    if (payload == null) return false;
    return EncryptionService.hasUsbSlotV5(payload);
  }

  /// 事后绑定重置密码盘（v5 信封；旧格式自动升级 v5）。
  /// 密码错误抛 [FormatException]；已绑定抛 [FormatException]。
  Future<void> bindNotebookUsbSlot(
    String id,
    String password,
    List<int> usbKey,
  ) async {
    final nb = await load(id);
    final payload = nb?.encryptedPayload;
    if (nb == null || payload == null) {
      throw StateError('该分页画布未设置文件密码');
    }
    String newPayload;
    if (EncryptionService.isDualProtectorEnvelope(payload)) {
      newPayload = await _encryption.bindNotebookUsbSlotV5(
        notebookId: id,
        encryptedJson: payload,
        password: password,
        usbKey: usbKey,
      );
    } else {
      final clear = await _encryption.decryptWithPasswordAad(
        notebookId: id,
        encryptedJson: payload,
        password: password,
      );
      newPayload = await _encryption.encryptWithPasswordV5(
        notebookId: id,
        plaintext: clear,
        password: password,
        usbKey: usbKey,
      );
    }
    nb.encryptedPayload = newPayload;
    await save(nb);
  }

  /// 用重置密码盘重置分页画布文件密码（N4 批 3）。
  ///
  /// 前提：v5 信封且已绑定重置密码盘。重置 = U 盘钥匙解出 DEK → 新盐
  /// 重绕密码槽，payload 密文不动。成功后会话密码已缓存（可直接解锁）。
  /// 返回 false = 未绑定/盘不匹配/非 v5（fail-closed）。
  Future<bool> resetNotebookPasswordWithUsb(
    String id,
    List<int> usbKey,
    String newPassword,
  ) async {
    final nb = await load(id);
    final payload = nb?.encryptedPayload;
    if (nb == null || payload == null) return false;
    final newPayload = await _encryption.resetNotebookPasswordWithUsbV5(
      notebookId: id,
      encryptedJson: payload,
      usbKey: usbKey,
      newPassword: newPassword,
    );
    if (newPayload == null) return false;
    nb.encryptedPayload = newPayload;
    _cacheNotebookPassword(id, newPassword);
    await save(nb);
    return true;
  }

  // ---- 会话密码缓存（与 StorageService._sessionFilePasswords 同语义：
  // 仅内存、解锁成功后缓存、本会话免重复输入）----

  final Map<String, String> _sessionNotebookPasswords = <String, String>{};

  /// 该分页画布本会话内是否已解锁文件密码。
  String? notebookPasswordFor(String id) => _sessionNotebookPasswords[id];

  void _cacheNotebookPassword(String id, String password) {
    _sessionNotebookPasswords[id] = password;
  }

  /// 清除会话密码（移除文件密码 / 文档删除后调用）。
  void forgetNotebookPassword(String id) {
    _sessionNotebookPasswords.remove(id);
  }

  /// P1 修复 M-09：清空全部会话笔记本口令（切后台回锁联动）。
  /// String 不可擦除——移出 map 即不可达；幂等、永不抛错。
  @override
  void clearAllSessionSecrets() {
    try {
      _sessionNotebookPasswords.clear();
    } catch (_) {
      /* 幂等清理：会话口令清空尽力而为（切后台回锁热路径），失败不外抛 */
    }
  }

  /// 用密码解密加密笔记本的页面内容（密码错误抛 [FormatException]）。
  /// 成功后将页面填充回 [notebook.pages] 并返回 true。
  ///
  /// 注意：解密后**保留** [encryptedPayload]（密文仍是持久化的唯一内容源），
  /// 否则后续保存会把 `pages: []` 写入磁盘、永久丢失全部加密内容
  /// （评审发现 P1）。
  Future<bool> decryptNotebook(Notebook notebook, String password) async {
    final payload = notebook.encryptedPayload;
    if (payload == null) return false;
    // 密码模式 v4（H-06 补全）：AAD 绑定 notebook.id——v4 优先，v3 旧数据
    // 回退（兼容期新旧并存）。
    final clear = await _encryption.decryptWithPasswordAad(
      notebookId: notebook.id,
      encryptedJson: payload,
      password: password,
    );
    final map = jsonDecode(clear) as Map<String, dynamic>;
    final pages = (map['pages'] as List? ?? const [])
        .map((e) => NotebookPage.fromJson(e as Map<String, dynamic>))
        .toList();
    notebook.pages
      ..clear()
      ..addAll(pages);
    // 解锁成功——缓存会话密码（本会话免重复输入；重置流直接续用）。
    _cacheNotebookPassword(notebook.id, password);
    // 保留 encryptedPayload：密文仍是持久化的唯一副本；
    // 修改加密笔记本时由调用方重新加密（见 save 的重加密逻辑）。
    return true;
  }

  /// 保存笔记本：加密笔记本不落盘明文 pages（评审发现 P1 修复）。
  ///
  /// - 非加密：直接原子写入；
  /// - 加密且未修改（pages 为空、密文仍在）：保留原密文写入，避免覆盖为空；
  /// - 加密且内存有明文页面：需要密钥才能重加密——若无密钥则拒绝保存
  ///   （防止静默清空磁盘内容），由调用方走 [encryptAndSave]。
  @override
  Future<String> save(Notebook notebook) async {
    if (notebook.encrypted) {
      final payload = notebook.encryptedPayload;
      if (payload != null && notebook.pages.isEmpty) {
        // 解密后未修改：保留原密文，避免覆盖为空。
        return _writeNotebook(notebook);
      }
      throw StateError('加密笔记本需要会话密码才能保存，请使用 encryptAndSave');
    }
    return _writeNotebook(notebook);
  }

  /// 生成唯一 ID。
  static String newId(String prefix) => LocalIdGenerator.next(prefix);
}

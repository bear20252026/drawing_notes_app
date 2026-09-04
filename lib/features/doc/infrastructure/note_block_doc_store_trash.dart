/// 块文档存储门面——回收站域（L-03 拆分，行为零变化）。
///
/// 软删除/恢复/彻底删除/过期清理与回收站编解码，共享主库的私有成员
/// （写链/目录/信封/DEK 缓存/onWrite），通过 part 同库访问。

part of 'note_block_doc_store.dart';

  /// 读回收站条目内容（批次①c）：激活区 rename 进来的文件可能是密文，
  /// 解密后返回文本；锁定/损坏返回 null（调用方跳过——fail-closed）。
  Future<String?> _readTrashContent(File f) async {
    var raw = await f.readAsBytes();
    if (VaultFileCodec.isEncrypted(raw)) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json')) return null;
      final id = name.substring(0, name.length - '.json'.length);
      final key = await _currentKey();
      if (key == null) return null;
      try {
        raw = await VaultFileCodec.decrypt(raw, key, aadContext: 'block:$id');
      } catch (_) {
        return null;
      }
    }
    // N2：v5 文件密码信封——会话已解锁解密；未解锁返回 null（fail-closed）。
    final text = utf8.decode(raw);
    if (EncryptionService.isDualProtectorEnvelope(text)) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json')) return null;
      final id = name.substring(0, name.length - '.json'.length);
      final dek = _sessionDeks[id];
      if (dek == null) return null;
      try {
        return await _encryption.decryptBlockDocPayloadWithDek(
          docId: id,
          encryptedJson: text,
          dek: dek,
        );
      } catch (_) {
        return null;
      }
    }
    return text;
  }

  /// 删除指定 ID 的块文档（M12.6：软删除——移入回收站，30 天保留，
  /// 可经 [restoreDocument] 恢复；与画布 StorageService 的 M-06 策略一致）。
  ///
  /// P0-H3：原子化——先写 sidecar 元数据（删除时间），再把激活文件
  /// **rename** 到回收站（同卷单次原子操作），不再有「写 trash 与删激活
  /// 之间可被自动保存插入」的窗口；rename 失败时回退旧 envelope 流程。
  /// 返回是否实际移动了文件。
  Future<bool> deleteDocument(String pageId) =>
      _enqueue(pageId, () => _deleteDocumentLocked(pageId));

  Future<bool> _deleteDocumentLocked(String pageId) async {
    final active = File(await _pathFor(pageId));
    if (!await active.exists()) return false;
    final trashFile = await _trashPathFor(pageId);
    final metaFile = File('$trashFile.meta.json');
    final metaTmp = File('$trashFile.meta.tmp');
    await metaTmp.writeAsString(
      jsonEncode({'deletedAt': DateTime.now().toIso8601String()}),
      flush: true,
    );
    await metaTmp.rename(metaFile.path);
    try {
      await active.rename(trashFile);
    } on FileSystemException {
      // 回退：读内容→写 envelope→删激活（非原子，仅 rename 不可用时）
      final doc = await loadDocument(pageId);
      if (doc == null) return false;
      final tmp = File('$trashFile.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'deletedAt': DateTime.now().toIso8601String(),
          'document': doc.toJson(),
        }),
        flush: true,
      );
      await tmp.rename(trashFile);
      await _removeActiveFiles(pageId);
      onWrite?.call();
      return true;
    }
    await _removeBak(pageId);
    forgetBlockDocPassword(pageId); // N2：删除后清会话 DEK
    onWrite?.call();
    return true;
  }

  Future<void> _removeBak(String pageId) async {
    try {
      final backup = File('${await _pathFor(pageId)}.bak');
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      // 备份删除失败忽略
    }
  }

  /// 彻底删除（不经回收站）：删除笔记页时联动清理迁移副本使用。
  Future<bool> purgeDocument(String pageId) =>
      _enqueue(pageId, () => _purgeDocumentLocked(pageId));

  Future<bool> _purgeDocumentLocked(String pageId) async {
    await _removeActiveFiles(pageId);
    forgetBlockDocPassword(pageId); // N2：删除后清会话 DEK
    try {
      final trashFile = await _trashPathFor(pageId);
      final f = File(trashFile);
      if (await f.exists()) await f.delete();
      final meta = File('$trashFile.meta.json');
      if (await meta.exists()) await meta.delete();
    } catch (_) {
      // 回收站文件不存在时忽略。
    }
    onWrite?.call();
    return true;
  }

  Future<void> _removeActiveFiles(String pageId) async {
    final path = await _pathFor(pageId);
    final file = File(path);
    if (await file.exists()) await file.delete();
    try {
      final backup = File('$path.bak');
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      // 备份删除失败忽略
    }
  }

  /// 解码回收站条目：兼容两种格式——
  /// 旧 envelope（{deletedAt, document}）与 M12.6b 原子格式
  /// （裸文档 json + `<id>.meta.json` sidecar；meta 缺失时用文件修改时间）。
  ///
  /// U5b（审计 P1-18）：meta 读取由 existsSync/readAsStringSync/
  /// lastModifiedSync 改为异步——打开回收站在 UI isolate 上执行，
  /// 同步 IO 会在条目多时卡列表。
  Future<({NoteBlockDoc doc, DateTime deletedAt})?> _decodeTrashEntry(
    String content,
    File source,
  ) async {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      final docRaw = decoded['document'];
      if (docRaw is Map<String, dynamic>) {
        final deletedAt = DateTime.tryParse(
          decoded['deletedAt'] as String? ?? '',
        );
        if (deletedAt == null) return null;
        return (doc: NoteBlockDoc.fromJson(docRaw), deletedAt: deletedAt);
      }
      final doc = NoteBlockDoc.fromJson(decoded);
      final meta = File('${source.path}.meta.json');
      var deletedAt = DateTime.tryParse(
        (await meta.exists()) ? await meta.readAsString() : '',
      );
      deletedAt ??= await source.lastModified();
      return (doc: doc, deletedAt: deletedAt);
    } catch (_) {
      return null;
    }
  }

  /// 列出回收站条目（按删除时间倒序）。
  ///
  /// N2：受密且未解锁的条目给「加密笔记」占位（fail-closed 不泄露标题，
  /// 与 listDocHeaders 同口径；仍可恢复——restore 对信封条目是纯 rename）。
  Future<List<({NoteBlockDoc doc, DateTime deletedAt})>> listTrash() async {
    final dir = await _ensureTrashDir();
    final entries = <({NoteBlockDoc doc, DateTime deletedAt})>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.endsWith('.meta.json')) continue;
      try {
        final content = await _readTrashContent(entity);
        if (content == null) {
          final name = entity.uri.pathSegments.last;
          final id = name.substring(0, name.length - '.json'.length);
          if (!isValidId(id)) continue;
          final meta = File('${entity.path}.meta.json');
          var deletedAt = DateTime.tryParse(
            (await meta.exists()) ? await meta.readAsString() : '',
          );
          deletedAt ??= await entity.lastModified();
          entries.add((
            doc: NoteBlockDoc(
              id: id,
              title: '加密笔记',
              createdAt: deletedAt,
              updatedAt: deletedAt,
            ),
            deletedAt: deletedAt,
          ));
          continue;
        }
        final entry = await _decodeTrashEntry(content, entity);
        if (entry != null) entries.add(entry);
      } catch (_) {
        continue; // 损坏条目跳过
      }
    }
    entries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return entries;
  }

  /// 从回收站恢复（若激活区已存在同 ID 文档则拒绝，返回 false）。
  Future<bool> restoreDocument(String pageId) =>
      _enqueue(pageId, () => _restoreDocumentLocked(pageId));

  Future<bool> _restoreDocumentLocked(String pageId) async {
    final trashFile = await _trashPathFor(pageId);
    final f = File(trashFile);
    if (!await f.exists()) return false;
    final active = File(await _pathFor(pageId));
    if (await active.exists()) return false; // 同 ID 已存在，拒绝覆盖
    // N2：v5 文件密码信封条目——恢复是纯文件移动（rename 回激活区），
    // 不解密、不要求会话解锁；激活区内容仍受密（打开路径有解锁拦截）。
    try {
      final raw = await f.readAsBytes();
      if (!VaultFileCodec.isEncrypted(raw) &&
          EncryptionService.isDualProtectorEnvelope(
            utf8.decode(raw, allowMalformed: true),
          )) {
        await f.rename(active.path);
        // P1 修复：同步 IO（existsSync/deleteSync）阻塞 UI isolate——
        // 改异步 + try/catch（TOCTOU 下删除竞态不抛错）。
        final meta = File('$trashFile.meta.json');
        if (await meta.exists()) {
          try {
            await meta.delete();
          } catch (_) {}
        }
        onWrite?.call();
        return true;
      }
    } on FormatException {
      // 非文本内容（主密钥信封等）——走下方通用流程。
    }
    final entry = await _decodeTrashEntry(await _readTrashContent(f) ?? '', f);
    if (entry == null) {
      // 旧 envelope 格式：恢复内部文档对象
      try {
        final content = await _readTrashContent(f);
        if (content == null) return false;
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic> &&
            decoded['document'] is Map<String, dynamic>) {
          await saveDocument(
            NoteBlockDoc.fromJson(decoded['document'] as Map<String, dynamic>),
          );
          await f.delete();
          return true;
        }
      } catch (_) {
        return false;
      }
      return false;
    }
    // 新原子格式：rename 回激活区
    await f.rename(active.path);
    final meta = File('$trashFile.meta.json');
    if (await meta.exists()) {
      try {
        await meta.delete();
      } catch (_) {}
    }
    onWrite?.call();
    return true;
  }

  /// 从回收站彻底删除单条。
  Future<bool> purgeFromTrash(String pageId) =>
      _enqueue(pageId, () => _purgeFromTrashLocked(pageId));

  Future<bool> _purgeFromTrashLocked(String pageId) async {
    final trashFile = await _trashPathFor(pageId);
    final f = File(trashFile);
    if (!await f.exists()) return false;
    await f.delete();
    final meta = File('$trashFile.meta.json');
    if (await meta.exists()) {
      try {
        await meta.delete();
      } catch (_) {}
    }
    onWrite?.call();
    return true;
  }

  /// 清理过期回收站条目（默认 30 天，与画布 M-06 策略一致）。
  /// 返回清理条数。listIds 会自动触发（惰性清理）。
  Future<int> purgeExpiredTrash({int retainDays = 30}) =>
      _enqueue('trash:$retainDays', () async {
        final dir = await _ensureTrashDir();
        var purged = 0;
        final cutoff = DateTime.now().subtract(Duration(days: retainDays));
        await for (final entity in dir.list()) {
          if (entity is! File || !entity.path.endsWith('.json')) continue;
          if (entity.path.endsWith('.meta.json')) continue;
          try {
            final entry = await _decodeTrashEntry(
              await _readTrashContent(entity) ?? '',
              entity,
            );
            if (entry != null && entry.deletedAt.isBefore(cutoff)) {
              await entity.delete();
              final meta = File('${entity.path}.meta.json');
              if (await meta.exists()) {
                try {
                  await meta.delete();
                } catch (_) {}
              }
              purged++;
            }
          } catch (_) {
            continue;
          }
        }
        return purged;
      });

  Directory? _trashDir;

  Future<Directory> _ensureTrashDir() async {
    if (_trashDir != null) return _trashDir!;
    final base = await _baseDir();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}blockdocs_trash',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    _trashDir = dir;
    return dir;
  }

  Future<String> _trashPathFor(String id) async {
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', '非法 ID（路径遍历防护）');
    }
    return '${(await _ensureTrashDir()).path}${Platform.pathSeparator}$id.json';
  }

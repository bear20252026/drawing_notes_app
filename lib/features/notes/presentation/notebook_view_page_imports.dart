part of 'notebook_view_page.dart';

// 笔记页导入/加密/历史域（O1 拆分）：文本/PDF 导入、密码盘与
// keyfile 加密、版本历史方法从 notebook_view_page.dart 移出为
// extension；行为零变化。

/// 笔记页导入/加密/历史域（拆分自 notebook_view_page.dart）。
extension _NotebookPageImports on _NotebookViewPageState {
  Future<void> _importText() async {
    const typeGroup = XTypeGroup(
      label: 'Markdown / 文本',
      extensions: ['md', 'txt'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    try {
      final content = await File(file.path).readAsString();
      if (content.trim().isEmpty) {
        _showSnack('文件内容为空');
        return;
      }
      // 按空行分段，每段生成一个文字块（首个段落作为标题）。
      final paragraphs = content
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (paragraphs.isEmpty) {
        _showSnack('未解析到文本内容');
        return;
      }
      final title = paragraphs.first.length > 30
          ? paragraphs.first.substring(0, 30)
          : paragraphs.first;
      final page = NotebookPage(
        id: NotebookStorage.newId('pg'),
        title: '导入·$title',
        document: _newDocument(),
      );
      // 可用性修复：y 增量按段落行数估算（原 `40 + 段长/2` 对长段落
      // 会迅速超出画布 3508 高度，文字块落到画布外用户看不到）。
      // 行高 28px + 段间距 12px，且钳制在画布高度内。
      final doc = page.document;
      var y = 60.0;
      final maxY = doc.height - 120.0;
      for (final p in paragraphs) {
        final lines = (p.length / 24).ceil().clamp(1, 40);
        page.textItems.add(
          PageTextItem(
            id: NotebookStorage.newId('txt'),
            x: 60,
            y: y.clamp(0.0, maxY),
            text: p,
            fontSize: p.length > 60 ? 22 : 26,
          ),
        );
        y += lines * 28 + 12;
      }
      _applyState(() => _notebook.pages.add(page));
      await _save();
      _showSnack('已导入 ${paragraphs.length} 段文字');
    } catch (e) {
      _showSnack('导入失败：$e');
    }
  }

  /// 导入 PDF：每一页渲染为一张独立分页笔记的底图，手写内容仍保存在
  /// 页面自己的矢量图层中，因此创建、批注、保存和重开构成完整闭环。
  Future<void> _importPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF 文档', extensions: ['pdf']);
    final selected = await openFile(acceptedTypeGroups: [typeGroup]);
    if (selected == null) return;
    try {
      final importId = NotebookStorage.newId('pdf');
      final rendered = await PdfImportService.renderPages(
        sourcePath: selected.path,
        outputDirectory: await widget.storage.ensureImagesDir(),
        importId: importId,
      );
      if (rendered.isEmpty) {
        _showSnack('PDF 没有可导入的页面');
        return;
      }
      final sourceName = selected.path
          .split(Platform.pathSeparator)
          .last
          .replaceFirst(RegExp(r'\\.pdf$', caseSensitive: false), '');
      final created = <NotebookPage>[];
      for (final pageImage in rendered) {
        final pageId = NotebookStorage.newId('pg');
        final document = DrawingDocument(
          id: StorageService.newId(),
          title: '$sourceName · ${pageImage.pageNumber}',
          width: pageImage.width,
          height: pageImage.height,
          paperType: PaperType.blank,
        );
        created.add(
          NotebookPage(
            id: pageId,
            title: '$sourceName · 第 ${pageImage.pageNumber} 页',
            document: document,
            imageItems: [
              PageImageItem(
                id: NotebookStorage.newId('pdfimg'),
                x: 0,
                y: 0,
                width: pageImage.width.toDouble(),
                height: pageImage.height.toDouble(),
                filePath: pageImage.filePath,
                // 永远处于笔记对象下方，作为 PDF 批注底图而非普通插图。
                zOrder: -100000,
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      _applyState(() => _notebook.pages.addAll(created));
      await _save();
      _showSnack('已导入 PDF 共 ${created.length} 页；打开任一页面即可手写批注');
    } catch (error) {
      _showSnack('导入 PDF 失败：$error');
    }
  }

  /// 宏：批量移动页面到指定分组（B1，借鉴 Trilium 脚本自动化）。
  ///
  /// 选择目标分组后，把当前标签筛选范围内的页面（或全部页面）批量移动。
  Future<void> _macroMovePages() async {
    if (_notebook.pages.isEmpty) return;
    final folder = await showDialog<String>(
      context: context,
      builder: (ctx) => const _PageNameDialog(title: '移动到的分组名（留空=根）'),
    );
    if (folder == null || !mounted) return;
    final target = folder.trim();
    _applyState(() {
      for (final p in _notebook.pages) {
        p.folder = target;
      }
    });
    await _save();
    _showSnack(
      '已批量移动 ${_notebook.pages.length} 页到分组「${target.isEmpty ? '根' : target}」',
    );
  }

  /// 设置笔记本加密：选择"记忆密码"或"U盘钥匙（密码盘）"两种模式。
  Future<void> _setPassword() async {
    // 第一步：选择加密模式。
    final mode = await showDialog<EncryptionMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择加密方式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(EncryptionMode.password),
            child: const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('记忆密码'),
              subtitle: Text('设置密码，打开时输入密码解密'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(EncryptionMode.keyfile),
            child: const ListTile(
              leading: Icon(Icons.usb),
              title: Text('U盘钥匙（密码盘）'),
              subtitle: Text('U盘即钥匙：插入 U 盘解锁，拔盘即锁（零知识）'),
            ),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    if (mode == EncryptionMode.password) {
      await _enablePasswordEncryption();
    } else {
      await _enableKeyfileEncryption();
    }
  }

  /// 密码模式加密。
  Future<void> _enablePasswordEncryption() async {
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          const _PasswordDialog(title: '设置密码保护', hint: '设置后页面内容将加密存储，打开需输入密码'),
    );
    if (password == null || password.isEmpty) return;
    try {
      await widget.storage.encryptAndSave(_notebook, password);
      // 记录会话密码：设置后本页内编辑可重加密保存（修复"无法保存"问题）。
      _sessionPassword = password;
      _sessionMasterKey = null;
      if (mounted) {
        _applyState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已启用密码保护（页面内容加密存储）')));
      }
    } catch (e) {
      _showSnack('设置密码失败：$e');
    }
  }

  /// U盘钥匙（keyfile）模式加密：选择/创建密码盘 → 读取主密钥 →
  /// 生成并展示 24 位恢复密钥 → 加密保存。
  Future<void> _enableKeyfileEncryption() async {
    final disk = createPasswordDisk();
    final dir = await disk.pickDirectory();
    if (dir == null || !mounted) return;

    // 若目录下还没有密码盘，则先创建。
    if (!await disk.validateKeyFile(dir)) {
      final ok = await disk.createKeyFile(dir);
      if (!ok) {
        _showSnack('创建密码盘失败');
        return;
      }
    }
    final masterKey = await disk.readKey(dir);
    if (masterKey == null) {
      _showSnack('无法读取密码盘密钥');
      return;
    }
    // 生成 24 位恢复密钥并展示（U 盘丢失时找回主密钥）。
    final recoveryKey = generateRecoveryKey();
    await _showRecoveryKeyWarning(recoveryKey);
    if (!mounted) return;

    try {
      await widget.storage.encryptAndSaveWithKey(
        _notebook,
        masterKey,
        recoveryKey,
      );
      // 会话主密钥：本页内编辑可重加密保存。
      _sessionMasterKey = masterKey;
      _sessionPassword = null;
      if (mounted) {
        _applyState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已启用 U盘钥匙加密（拔盘即锁）')));
      }
    } catch (e) {
      _showSnack('启用 U盘钥匙加密失败：$e');
    }
  }


  /// 展示恢复密钥（警示必须抄写）。
  Future<void> _showRecoveryKeyWarning(String recoveryKey) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存您的恢复密钥（非常重要！）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recoveryKey,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ 请抄写或截图保存到安全处。\n'
              'U 盘丢失或损坏时，凭此密钥可恢复主密钥。\n'
              '本应用不存储任何密钥，忘记恢复密钥将永久无法恢复！',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我已抄写'),
          ),
        ],
      ),
    );
  }

  /// 查看并回溯页面版本历史（C1）。
  Future<void> _showHistory(NotebookPage page) async {
    if (page.history.isEmpty) {
      _showSnack('该页面暂无历史版本');
      return;
    }
    final version = await showDialog<PageVersion>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('「${page.title}」版本历史'),
        children: [
          for (var i = 0; i < page.history.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(page.history[i]),
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '#${page.history.length - i} · ${_formatTime(page.history[i].time)}',
                ),
                subtitle: page.history[i].summary.isNotEmpty
                    ? Text(
                        page.history[i].summary,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
    if (version == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复该版本？'),
        content: Text('将用所选版本覆盖当前页面内容（当前内容会先存入历史）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _applyState(() {
      // 先把当前内容以深拷贝存入历史，再恢复所选完整版本。
      page.history.insert(
        0,
        PageVersion(
          time: DateTime.now(),
          document: DrawingDocument.fromJson(page.document.toJson()),
          textItems: page.textItems
              .map((item) => PageTextItem.fromJson(item.toJson()))
              .toList(),
          imageItems: page.imageItems
              .map((item) => PageImageItem.fromJson(item.toJson()))
              .toList(),
          connectors: page.connectors
              .map((item) => PageConnector.fromJson(item.toJson()))
              .toList(),
          shapes: page.shapes
              .map((item) => PageShapeItem.fromJson(item.toJson()))
              .toList(),
          charts: page.charts
              .map((item) => PageChartItem.fromJson(item.toJson()))
              .toList(),
          summary: '恢复前自动备份',
        ),
      );
      final current = page.document;
      final restoreDoc = version.document;
      current.layers
        ..clear()
        ..addAll(restoreDoc.layers);
      current.title = restoreDoc.title;
      page.textItems
        ..clear()
        ..addAll(
          version.textItems.map((item) => PageTextItem.fromJson(item.toJson())),
        );
      page.imageItems
        ..clear()
        ..addAll(
          version.imageItems.map(
            (item) => PageImageItem.fromJson(item.toJson()),
          ),
        );
      page.connectors
        ..clear()
        ..addAll(
          version.connectors.map(
            (item) => PageConnector.fromJson(item.toJson()),
          ),
        );
      page.shapes
        ..clear()
        ..addAll(
          version.shapes.map((item) => PageShapeItem.fromJson(item.toJson())),
        );
      page.charts
        ..clear()
        ..addAll(
          version.charts.map((item) => PageChartItem.fromJson(item.toJson())),
        );
      page.updatedAt = DateTime.now();
    });
    await _save();
    if (mounted) _applyState(() {});
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

part of 'notebook_view_page.dart';

// 笔记页导入/加密/历史域（O1 拆分）：文本/PDF 导入、密码保护、
// 版本历史方法从 notebook_view_page.dart 移出为 extension；行为零变化。
// （keyfile「U盘钥匙」加密已随重置密码盘定案删除——2026-09-02。）

/// 笔记页导入/加密/历史域（拆分自 notebook_view_page.dart）。
extension _NotebookPageImports on _NotebookViewPageState {
  /// 任务#3（专家审计 2026-08-15）：文本导入文件大小上限（51CTO
  /// ImportSession 模式："文本长度不设上限是错误"——readAsString 无
  /// 限制会加载超大文件）。
  static const int _maxTextImportBytes = 20 * 1024 * 1024; // 20MB

  Future<void> _importText() async {
    // 策略门禁（专家审计最优先④——2026-08-16）：默认拒绝——白名单操作
    // 才允许（deny 时提示拒绝，不执行——fail-closed）。
    if (!const PolicyEngine().check('note.import.text').isAllowed) {
      _showSnack('操作被策略拒绝（note.import.text）');
      return;
    }
    const typeGroup = XTypeGroup(
      label: 'Markdown / 文本',
      extensions: ['md', 'txt'],
    );
    // 会话守卫豁免（专家审计最优先③——2026-08-16）：文件选择器运行期间
    // 不触发锁定（防导入误锁——private_notes_light filePickerRunning 模式）。
    _sessionGuard.setFilePickerActive(true);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    _sessionGuard.setFilePickerActive(false);
    if (file == null) return;
    try {
      // 任务#3（专家审计 2026-08-15）：文本导入大小配额——防超大文件
      // 一次性 readAsString 加载（内存/卡顿）。
      if (await File(file.path).length() > _maxTextImportBytes) {
        _showSnack('文本文件过大（超过 20MB 限制），拒绝导入');
        return;
      }
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
        document: NotebookPageTemplateStrategy.createDocument(
          id: StorageService.newId(),
          title: '未命名页面',
        ),
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
      _showSnack('导入失败，请重试');
    }
  }

  /// 导入 PDF：每一页渲染为一张独立分页笔记的底图，手写内容仍保存在
  /// 页面自己的矢量图层中，因此创建、批注、保存和重开构成完整闭环。
  Future<void> _importPdf() async {
    // 策略门禁（专家审计最优先④）：PDF 导入白名单判定（deny 时拒绝执行）。
    if (!const PolicyEngine().check('note.import.pdf').isAllowed) {
      _showSnack('操作被策略拒绝（note.import.pdf）');
      return;
    }
    const typeGroup = XTypeGroup(label: 'PDF 文档', extensions: ['pdf']);
    _sessionGuard.setFilePickerActive(true);
    final selected = await openFile(acceptedTypeGroups: [typeGroup]);
    _sessionGuard.setFilePickerActive(false);
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
        final document = NotebookPageTemplateStrategy.createDocument(
          id: StorageService.newId(),
          title: '$sourceName · ${pageImage.pageNumber}',
          width: pageImage.width,
          height: pageImage.height,
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
      _showSnack('导入 PDF 失败，请重试');
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

  /// 设置笔记本密码保护（密码模式）。
  Future<void> _setPassword() async {
    await _enablePasswordEncryption();
  }

  /// 密码模式加密/改密（N4 批 3：v5 双保护器——改密=重绕密码槽）。
  Future<void> _enablePasswordEncryption() async {
    final isChange = _notebook.encrypted;
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => _PasswordDialog(
        title: isChange ? '修改密码保护' : '设置密码保护',
        hint: isChange ? '修改后打开需输入新密码' : '设置后页面内容将加密存储，打开需输入密码',
      ),
    );
    if (password == null || password.isEmpty) return;
    // 批次②：≠开屏密码强制——哈希加盐不可直接比对，verify 探测
    // （能通过开屏锁校验即同码），同码会削弱两层独立的保护边界。
    if (await AppLockService.matchesAppLockPin(password)) {
      _showSnack('密码不能与开屏密码相同');
      return;
    }
    try {
      if (isChange) {
        // v5 改密：旧密码解出 DEK → 重绕密码槽（payload 与重置盘槽位不动）。
        // 旧格式信封自动升级 v5。会话密码在则直接用，否则先验证当前密码。
        final old = _effectivePassword;
        if (old == null || old.isEmpty) {
          _showSnack('请重新输入密码解锁后再修改');
          return;
        }
        await widget.storage.changeNotebookPassword(
          _notebook.id,
          old,
          password,
        );
      } else {
        await widget.storage.encryptAndSave(_notebook, password);
      }
      // 记录会话密码：设置后本页内编辑可重加密保存（修复"无法保存"问题）。
      _sessionPassword = password;
      // H-03 密码模式媒体加密（方案 B）：全局盐派生注入（storeImage 加密
      // 写入 + EncryptedFileImage 渲染解密用——跨会话同盐重派生 key 一致）。
      final mediaSalt = await widget.storage.ensureMediaSalt();
      await MediaCryptoService.instance.setSessionPassword(password, mediaSalt);
      if (mounted) {
        _applyState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isChange ? '密码已修改' : '已启用密码保护（页面内容加密存储）',
            ),
          ),
        );
      }
      // N4 批 3：未绑定重置密码盘时询问是否当场插盘绑定（可跳过，事后
      // 在菜单「绑定重置密码盘」中补绑）。
      await _offerUsbBinding(password);
    } catch (e) {
      _showSnack('${isChange ? '修改密码' : '设置密码'}失败，请重试');
    }
  }

  /// N4 批 3：设密后询问绑定重置密码盘。
  Future<void> _offerUsbBinding(String password) async {
    if (!mounted) return;
    if (await widget.storage.hasNotebookUsbSlot(_notebook.id)) return;
    if (!mounted) return;
    final bind = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('绑定重置密码盘？'),
        content: const Text(
          '绑定后忘记密码时，插入 U 盘即可重置新密码。\n\n'
          '可以稍后在菜单「绑定重置密码盘」中补绑。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('插盘绑定'),
          ),
        ],
      ),
    );
    if (bind != true || !mounted) return;
    await _bindUsbDisk(password);
  }

  /// N4 批 3：选盘读钥匙并绑定（菜单入口与设密后询问共用）。
  Future<void> _bindUsbDisk(String password) async {
    final dir = await ResetDiskFile.pickDirectory();
    if (dir == null || !mounted) return;
    final usbKey = await ResetDiskFile.readFrom(dir);
    if (usbKey == null) {
      _showSnack('未找到有效的重置密码盘文件（password_reset_disk.key）');
      return;
    }
    try {
      await widget.storage.bindNotebookUsbSlot(_notebook.id, password, usbKey);
      _showSnack('已绑定重置密码盘');
    } catch (e) {
      _showSnack('绑定失败，请重试');
    }
  }

  /// N4 批 3：菜单「绑定重置密码盘」入口（须已解锁——会话密码可用）。
  Future<void> _startBindUsb() async {
    if (await widget.storage.hasNotebookUsbSlot(_notebook.id)) {
      _showSnack('已绑定重置密码盘');
      return;
    }
    final pw = _effectivePassword;
    if (pw == null || pw.isEmpty) {
      _showSnack('请先输入密码解锁后再绑定');
      return;
    }
    await _bindUsbDisk(pw);
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
      // 聚合负责捕获恢复前的独立快照、裁剪历史，以及用深拷贝恢复完整载荷。
      page.addVersion(time: DateTime.now(), summary: '恢复前自动备份');
      page.restoreVersion(version);
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

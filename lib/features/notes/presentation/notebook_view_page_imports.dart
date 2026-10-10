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
      _showSnack(
        AppLocalizations.of(context)?.docPolicyDenied('note.import.text') ??
            '操作被策略拒绝（note.import.text）',
      );
      return;
    }
    final typeGroup = XTypeGroup(
      label: AppLocalizations.of(context)?.impMarkdownText ?? 'Markdown / 文本',
      extensions: const ['md', 'txt'],
    );
    // 会话守卫豁免（专家审计最优先③——2026-08-16）：文件选择器运行期间
    // 不触发锁定（防导入误锁——private_notes_light filePickerRunning 模式）。
    // P0 修复：作用域式豁免——openFile 抛异常也不会泄漏永久豁免。
    final file = await _sessionGuard.runWithExemption(
      () => openFile(acceptedTypeGroups: [typeGroup]),
    );
    if (file == null) return;
    try {
      // 任务#3（专家审计 2026-08-15）：文本导入大小配额——防超大文件
      // 一次性 readAsString 加载（内存/卡顿）。
      if (await File(file.path).length() > _maxTextImportBytes) {
        _showSnack(_l10nSafe?.impTextTooLarge ?? '文本文件过大（超过 20MB 限制），拒绝导入');
        return;
      }
      final content = await File(file.path).readAsString();
      if (content.trim().isEmpty) {
        _showSnack(_l10nSafe?.impEmptyFile ?? '文件内容为空');
        return;
      }
      // 按空行分段，每段生成一个文字块（首个段落作为标题）。
      // 解析移入 isolate：20MB 文本的 split/trim 正则分段在主 isolate
      // 上会卡多帧（storage_service 等存储层已同款纪律走 Isolate.run）。
      final paragraphs = await Isolate.run(() {
        return content
            .split(RegExp(r'\n\s*\n'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
      });
      if (paragraphs.isEmpty) {
        _showSnack(_l10nSafe?.impNoText ?? '未解析到文本内容');
        return;
      }
      final title = paragraphs.first.length > 30
          ? paragraphs.first.substring(0, 30)
          : paragraphs.first;
      final page = NotebookPage(
        id: NotebookStorage.newId('pg'),
        // L-09（审计 2026-09-27）：标题拼句走占位键。
        title: _l10nSafe?.impTextPageTitle(title) ?? '导入·$title',
        document: NotebookPageTemplateStrategy.createDocument(
          id: StorageService.newId(),
          title: _l10nSafe?.nbUntitledPage ?? '未命名页面',
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
      _showSnack(
        _l10nSafe?.impImportedParagraphs(paragraphs.length) ??
            '已导入 ${paragraphs.length} 段文字',
      );
    } catch (e) {
      _showSnack(_l10nSafe?.impFailed ?? '导入失败，请重试');
    }
  }

  /// 导入 PDF：每一页渲染为一张独立分页笔记的底图，手写内容仍保存在
  /// 页面自己的矢量图层中，因此创建、批注、保存和重开构成完整闭环。
  Future<void> _importPdf() async {
    // 策略门禁（专家审计最优先④）：PDF 导入白名单判定（deny 时拒绝执行）。
    if (!const PolicyEngine().check('note.import.pdf').isAllowed) {
      _showSnack(
        AppLocalizations.of(context)?.docPolicyDenied('note.import.pdf') ??
            '操作被策略拒绝（note.import.pdf）',
      );
      return;
    }
    final typeGroup = XTypeGroup(
      label: AppLocalizations.of(context)?.impPdfTypeGroup ?? 'PDF 文档',
      extensions: const ['pdf'],
    );
    // P0 修复：同上，作用域式豁免防异常泄漏。
    final selected = await _sessionGuard.runWithExemption(
      () => openFile(acceptedTypeGroups: [typeGroup]),
    );
    if (selected == null) return;
    try {
      final importId = NotebookStorage.newId('pdf');
      final rendered = await PdfImportService.renderPages(
        sourcePath: selected.path,
        outputDirectory: await widget.storage.ensureImagesDir(),
        importId: importId,
        // S-01（审计 2026-09-27）：页面 PNG 落盘前走与 storeImage 同款三级
        // 密封分支——保险库/加密笔记本开启时不再明文残留磁盘。
        sealBytes: widget.storage.sealMediaBytesForPath,
      );
      if (rendered.isEmpty) {
        _showSnack(_l10nSafe?.impPdfNoPages ?? 'PDF 没有可导入的页面');
        return;
      }
      final sourceName = selected.path
          .split(Platform.pathSeparator)
          .last
          .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
      final created = <NotebookPage>[];
      for (final pageImage in rendered) {
        final pageId = NotebookStorage.newId('pg');
        // L-09（审计 2026-09-27）：页/文档标题拼句走 impPdfPageTitle 占位键。
        final pageTitle =
            _l10nSafe?.impPdfPageTitle(sourceName, pageImage.pageNumber) ??
            '$sourceName · 第 ${pageImage.pageNumber} 页';
        final document = NotebookPageTemplateStrategy.createDocument(
          id: StorageService.newId(),
          title: pageTitle,
          width: pageImage.width,
          height: pageImage.height,
        );
        created.add(
          NotebookPage(
            id: pageId,
            title: pageTitle,
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
      _showSnack(
        _l10nSafe?.impPdfDone(created.length) ??
            '已导入 PDF 共 ${created.length} 页；打开任一页面即可手写批注',
      );
    } catch (error) {
      _showSnack(_l10nSafe?.impPdfFailed ?? '导入 PDF 失败，请重试');
    }
  }

  /// 宏：批量移动页面到指定分组（B1，借鉴 Trilium 脚本自动化）。
  ///
  /// 选择目标分组后，把当前标签筛选范围内的页面（或全部页面）批量移动。
  Future<void> _macroMovePages() async {
    if (_notebook.pages.isEmpty) return;
    final folder = await GlassDialog.show<String>(
      context: context,
      // L-09（审计 2026-09-27）：弹层标题写死 → 走 l10n。
      builder: (ctx) => _PageNameDialog(
        title:
            AppLocalizations.of(context)?.nbMoveFolderDialogTitle ?? '移动到文件夹',
      ),
    );
    if (folder == null || !mounted) return;
    final target = folder.trim();
    // 与列表过滤同口径：筛选生效时只移动命中页，无筛选才动全部——
    // 此前无条件遍历全部页面，"移动筛选范围"承诺名不副实。
    final inScope = _tagFilter.isEmpty
        ? _notebook.pages.toList()
        : _notebook.pages
              .where((p) => p.tags.any((t) => t.contains(_tagFilter)))
              .toList();
    if (inScope.isEmpty) return;
    _applyState(() {
      for (final p in inScope) {
        p.folder = target;
      }
    });
    await _save();
    // 空 target 即根分组，名字也走 l10n，不再内联中文。
    final folderLabel = target.isEmpty
        ? (_l10nSafe?.nbRootFolder ?? '根')
        : target;
    _showSnack(
      _l10nSafe?.nbMovedPagesTo(inScope.length, folderLabel) ??
          '已批量移动 ${inScope.length} 页到分组「$folderLabel」',
    );
  }

  /// 设置笔记本密码保护（密码模式）。
  Future<void> _setPassword() async {
    await _enablePasswordEncryption();
  }

  /// 密码模式加密/改密（N4 批 3：v5 双保护器——改密=重绕密码槽）。
  ///
  /// C-14 兑现（2026-10-03）：设/改密统一走 shared UnlockFlow——文本模式
  /// 随 flexible 自动开启，移动端九宫格可切字母键盘，任意字符密码双端
  /// 可设可解（此前 _PasswordDialog 设的字母密码在数字-only 解锁链路上
  /// 无法输入，存在自锁面）。新增**两遍确认**对齐 doc/重置流家族
  /// （obscured 输入误敲无法察觉）；改密的「会话密码免验旧密码」语义
  /// 不变——两遍只收集新密码。原 impSetHint/impChangeHint 的结果性信息
  /// 由成功 snack（impPasswordEnabled/impPasswordChanged）承载。
  Future<void> _enablePasswordEncryption() async {
    final isChange = _notebook.encrypted;
    final title = isChange
        ? AppLocalizations.of(context)?.impChangePasswordProtect ?? '修改密码保护'
        : AppLocalizations.of(context)?.impSetPasswordProtect ?? '设置密码保护';
    final password = await UnlockFlow.show(
      context,
      title: title,
      flexible: true,
    );
    if (password == null || password.isEmpty) return;
    if (!mounted) return;
    final confirm = await UnlockFlow.show(
      context,
      title: AppLocalizations.of(context)?.impConfirmPasswordProtect ?? '确认新密码',
      flexible: true,
    );
    if (confirm != password) {
      _showSnack(_l10nSafe?.impPasswordMismatch ?? '两次输入不一致，请重试');
      return;
    }
    // 批次②：≠开屏密码强制——哈希加盐不可直接比对，用**只读探测**
    // （同 home/doc/reset 三处口径：旧实现走 verify 会把「正常设密」记成
    // 开屏密码猜错，累计即触发防爆破冷却）。同码会削弱两层独立的保护边界。
    final sameAsLock = await AppLockService.probeMatchesAppLockPin(password);
    if (sameAsLock == true) {
      _showSnack(_l10nSafe?.impPasswordSameAsLock ?? '密码不能与开屏密码相同');
      return;
    }
    if (sameAsLock == null) {
      // P2 fail-closed：判定不了（多为开屏锁防爆破冷却中）——拒绝本次设密
      // 并提示稍后重试，绝不静默放行「与开屏密码同码」。
      _showSnack(_l10nSafe?.lockTemporarilyLocked ?? '为防止暴力猜测，密码验证已暂时锁定');
      return;
    }
    if (!mounted) return; // 探测为异步操作，跨缺口守卫
    try {
      if (isChange) {
        // v5 改密：旧密码解出 DEK → 重绕密码槽（payload 与重置盘槽位不动）。
        // 旧格式信封自动升级 v5。会话密码在则直接用，否则先验证当前密码。
        final old = _effectivePassword;
        if (old == null || old.isEmpty) {
          _showSnack(_l10nSafe?.impRelockNeeded ?? '请重新输入密码解锁后再修改');
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
      // C-06（审计 2026-09-27）：媒体服务构造注入（注入语义不变）。
      final mediaSalt = await widget.storage.ensureMediaSalt();
      await widget.mediaCrypto.setSessionPassword(password, mediaSalt);
      if (mounted) {
        _applyState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isChange
                  ? AppLocalizations.of(context)?.impPasswordChanged ?? '密码已修改'
                  : AppLocalizations.of(context)?.impPasswordEnabled ??
                        '已启用密码保护（页面内容加密存储）',
            ),
          ),
        );
      }
      // N4 批 3：未绑定重置密码盘时询问是否当场插盘绑定（可跳过，事后
      // 在菜单「绑定重置密码盘」中补绑）。
      await _offerUsbBinding(password);
    } catch (e) {
      _showSnack(
        isChange
            ? _l10nSafe?.impChangeFailed ?? '修改密码失败，请重试'
            : _l10nSafe?.impSetFailed ?? '设置密码失败，请重试',
      );
    }
  }

  /// N4 批 3：设密后询问绑定重置密码盘。
  Future<void> _offerUsbBinding(String password) async {
    if (!mounted) return;
    if (await widget.storage.hasNotebookUsbSlot(_notebook.id)) return;
    if (!mounted) return;
    final bind = await GlassDialog.confirm(
      context,
      title:
          AppLocalizations.of(context)?.docBindDiskConfirmTitle ?? '绑定重置密码盘？',
      content:
          AppLocalizations.of(context)?.impBindAskContent ??
          '绑定后忘记密码时，插入 U 盘即可重置新密码。\n\n'
              '可以稍后在菜单「绑定重置密码盘」中补绑。',
      confirmText: AppLocalizations.of(context)?.docBindDiskConfirm ?? '插盘绑定',
      cancelText: AppLocalizations.of(context)?.docNotNow ?? '暂不',
    );
    if (!bind || !mounted) return;
    await _bindUsbDisk(password);
  }

  /// N4 批 3：选盘读钥匙并绑定（菜单入口与设密后询问共用）。
  Future<void> _bindUsbDisk(String password) async {
    // 选 U 盘目录 = 原生对话框抢焦点 → 桌面投 inactive。AppLockGate 现对
    // inactive 全量锁定，须走豁免窗口（runWithExemption 委托进程级
    // LockExemption，同时按住 SessionGuard 媒体锁 + 开屏锁），否则绑盘时假锁。
    final dir = await _sessionGuard.runWithExemption(
      ResetDiskFile.pickDirectory,
    );
    if (dir == null || !mounted) return;
    final usbKey = await ResetDiskFile.readFrom(dir);
    if (usbKey == null) {
      _showSnack(
        _l10nSafe?.impDiskNotFound ?? '未找到有效的重置密码盘文件（password_reset_disk.key）',
      );
      return;
    }
    try {
      await widget.storage.bindNotebookUsbSlot(_notebook.id, password, usbKey);
      _showSnack(_l10nSafe?.impBound ?? '已绑定重置密码盘');
    } catch (e) {
      _showSnack(_l10nSafe?.impBindFailed2 ?? '绑定失败，请重试');
    }
  }

  /// N4 批 3：菜单「绑定重置密码盘」入口（须已解锁——会话密码可用）。
  Future<void> _startBindUsb() async {
    if (await widget.storage.hasNotebookUsbSlot(_notebook.id)) {
      _showSnack(_l10nSafe?.impBound ?? '已绑定重置密码盘');
      return;
    }
    final pw = _effectivePassword;
    if (pw == null || pw.isEmpty) {
      _showSnack(_l10nSafe?.impUnlockFirst ?? '请先输入密码解锁后再绑定');
      return;
    }
    await _bindUsbDisk(pw);
  }

  /// 查看并回溯页面版本历史（C1）。
  Future<void> _showHistory(NotebookPage page) async {
    if (page.history.isEmpty) {
      _showSnack(AppLocalizations.of(context)?.impNoVersions ?? '该页面暂无历史版本');
      return;
    }
    final version = await GlassDialog.show<PageVersion>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          AppLocalizations.of(context)?.nbVersionHistoryOf(page.title) ??
              '「${page.title}」版本历史',
        ),
        children: [
          for (var i = 0; i < page.history.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(page.history[i]),
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '#${page.history.length - i} · ${formatSmartTime(page.history[i].time)}',
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
    final ok = await GlassDialog.confirm(
      context,
      title: AppLocalizations.of(context)?.impRestoreConfirmTitle ?? '恢复该版本？',
      content:
          AppLocalizations.of(context)?.impRestoreConfirmContent ??
          '将用所选版本覆盖当前页面内容（当前内容会先存入历史）。',
      confirmText: AppLocalizations.of(context)?.impRestore ?? '恢复',
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
}

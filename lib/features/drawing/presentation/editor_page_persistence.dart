part of 'editor_page.dart';

// 编辑器保存域（O1 拆分；R1 归并 2026-11-17 后导出方法群移往
// editor_page_actions）：定时自动保存、重命名、裁剪确认。

/// 编辑器保存域（拆分自 editor_page.dart）。
extension _EditorPagePersistence on _EditorPageState {
  /// setState 的 lint 友好包装（extension 无法直接调用受保护成员）。
  void notify() {
    // ignore: invalid_use_of_protected_member
    setState(() {});
  }

  void _scheduleAutosave() {
    _viewModel.scheduleAutosave();
  }

  // 保存状态可视化：extension 不能声明实例字段，故字段留在 State、这里只放读它们建 UI 的方法。

  /// v1.17.20：保存链飞行状态由调度器统一驱动（覆盖手动/退出兜底保存路径）。
  void _onSavingStateChanged() {
    if (!mounted) return;
    _canvasSaving = _saveScheduler.savingState.value;
    notify();
  }

  /// 保存失败的用户可见通知（2026-10-06）：状态栏芯片常驻显示「保存失败」
  /// （一次性 snackbar 会被划走，而风险一直在），`giveUp` 时把措辞升级成
  /// 「请手动保存」。
  void _onSaveFailureChanged() {
    if (!mounted) return;
    final notice = _saveScheduler.saveFailure.value;
    _canvasSaveFailure = notice;
    notify();
    if (notice == null) {
      _snackedForCurrentEpisode = false;
      return;
    }
    // DN-003：截断态下不弹「保存失败，请重试」——常驻说明条才是这一态的出口。
    if (_writeBlockedByTruncation) return;
    if (_snackedForCurrentEpisode && !notice.gaveUp) return;
    _snackedForCurrentEpisode = true;
    _showSaveFailureSnackBar(notice);
  }

  void _showSaveFailureSnackBar(SaveFailureNotice notice) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(saveFailureLabel(AppLocalizations.of(context), notice)),
        // H2（UI/UX 规范修复）：6s → AppleMotion.toastVisible（2s）。
        // 保存失败详情由顶栏常驻芯片承载，Toast 只作「已发生」回执。
        duration: AppleMotion.toastVisible,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 顶栏那颗芯片的措辞：截断态 > 失败 > 保存中 > 未保存 > 已保存 HH:mm。
  String get _canvasStatusLabel {
    final l10n = AppLocalizations.of(context);
    // DN-003：截断态优先——那颗芯片此刻说的是「为什么存不进去」，而不是
    // 一句没有解释的「保存失败，请重试」（用户按它重试一万次也不会成功）。
    if (_writeBlockedByTruncation) {
      return l10n?.budgetTruncatedChip ?? '已停写覆盖：请先处置上方说明';
    }
    // 失败优先于「保存中/未保存」：这三态互斥地挤在同一个芯片位上，
    // 而只有「没落盘」是用户必须立刻知道的。
    final notice = _canvasSaveFailure;
    if (notice != null) return saveFailureLabel(l10n, notice);
    if (_canvasSaving) return l10n?.saveStateSaving ?? '保存中…';
    final t = _canvasLastSavedAt;
    if (_controller.isDirty) return l10n?.saveStateUnsaved ?? '未保存';
    if (t == null) return l10n?.saveStateSaved ?? '已保存';
    return l10n?.saveStateSavedAt(formatClock(t)) ?? '已保存 ${formatClock(t)}';
  }

  Color get _canvasStatusColor {
    if (_writeBlockedByTruncation || _canvasSaveFailure != null) {
      return AppleColor.errorRed;
    }
    if (_canvasSaving) return AppleColor.actionBlue;
    if (_controller.isDirty) return AppleColor.favourite;
    return AppleColor.noteGreen;
  }

  /// 主体 + （仅截断态才有的）常驻说明条（DN-003）。
  ///
  /// 说明条在 Scaffold.body 顶端、内容层内：扁平实色、不用玻璃；全屏模式同样
  /// 可见——它要解释的正是「为什么存不进去」，藏进非全屏才出现的角落里等于没做。
  Widget _buildBodyWithNotice() {
    final body = _buildBody();
    final report = _budgetTruncation;
    if (report == null) return body;
    return Column(
      children: [
        EditorBudgetTruncationBanner(
          report: report,
          onOverride: () => unawaited(_overrideBudgetTruncation()),
        ),
        Expanded(child: body),
      ],
    );
  }

  /// **唯一的**破坏性处置入口（DN-003）：用户显式确认「用当前内容覆盖原文件」
  /// 之后，才解除闸门并立即补一次真实落盘。
  ///
  /// 刻意保持显式：它不是任何自动路径的副产物，也没有「以后不再提示」——批量或
  /// 静默调用 `acknowledgeBudgetTruncation` 等于把本批修的 P0 重新打开。
  Future<void> _overrideBudgetTruncation() async {
    final report = _budgetTruncation;
    final storage = widget.docStorage;
    if (report == null || storage == null) return;
    // 确认文案重复会丢失的笔数并写明不可恢复；取消（危险档下的默认焦点）不动闸门。
    if (!await confirmBudgetTruncationOverride(context, report)) return;
    storage.acknowledgeBudgetTruncation(report.documentId);
    if (!mounted) return;
    // extension 里不能直接碰受保护的 setState——走本域既有的 notify() 薄包装。
    _budgetTruncation = null;
    notify();
    // 放行即写：不等 5s 防抖，让用户当场看到「已保存」或失败措辞回到芯片上。
    await _viewModel.saveNow();
  }

  /// 保存当前画作：独立画布 → 工程文件 + 缩略图；笔记本页面 → 由上级回调落盘。
  ///
  /// 只负责“执行落盘”，失败时把异常向上抛出（交给 SaveScheduler 的重试/退避/
  /// 放弃策略处理）；防抖、串行化（飞行中补写）、退出兜底、通知合并在
  /// [SaveScheduler]（P0-3b）统一编排，此处不再内联“正在保存/补写”标记。
  Future<void> _persistArtwork() async {
    // 笔记本页面模式：onChanged 已由 NotebookViewPage 负责保存。
    if (widget.session != null) return;
    final storage = widget.docStorage;
    final doc = _controller.document;
    if (storage == null) return;
    // 「保存中」状态由 SaveScheduler.savingState 统一驱动（v1.17.20），
    // 覆盖手动保存与退出兜底路径，此处不再手工置位。
    // StorageService 在调用时立即编码不可变快照；后续笔画不会改写此版本。
    //
    // 修复 3（审计 2026-10-04）：裁剪磁盘写入「飞行中」不得取快照——先等它
    // 落定（成功保新矩形 / 失败回滚旧矩形）再编码，落盘的文档矩形与磁盘图像
    // 字节只会同向，不会留下「文档裁剪后 + 图像裁剪前」的中间态。
    final cropGate = _cropWriteInFlight;
    if (cropGate != null) {
      // 上限 5s：写盘极端卡死不得长期堵死整条文档保存链（宁可留一次可由
      // `.bak` 复原的中间态，也不让无关笔画丢掉）。
      await cropGate.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    await storage.saveAndLog(doc, _controller.operationLog);
    // 文档 JSON 是数据完整性的第一优先级。关闭中控制器可能已释放，
    // 因此只跳过可再生的缩略图，不跳过正文保存。
    if (!_closingEditor) {
      // 缩略图长边限 1024（内存治理 2026-09-07）：首页网格最多 ~256px
      // 显示，1024 已留足余量；无限画布内容包围盒 × 0.2 仍可能达数千
      // 像素（~48MB 瞬时分配），画画期间每 5s 自动保存都会重放一次。
      final png = await _controller.renderToPng(scale: 0.2, maxLongEdge: 1024);
      if (png != null) await storage.saveThumbnail(doc.id, png);
    } else {
      // v1.17.20 退出路径缩略图后台补渲：退出只等文档 JSON 落盘（快），
      // 缩略图由后台队列按快照独立渲染，不再阻塞 pop。
      ThumbnailBackfill.submit(doc, storage);
    }
    if (mounted && !_closingEditor) {
      _canvasLastSavedAt = DateTime.now();
      notify();
    }
  }

  /// 重命名画布：更新标题并走自动保存调度（M12 命名持久化）。
  Future<void> _renameCanvas() async {
    final current = _controller.document.title;
    // controller 提到 builder 外创建、finally 统一释放（builder 内创建会
    // 随每次重建泄漏一个）。对话框返回（pop 即完成）后退出动画仍在跑，
    // 动画期间 TextField 重建会触碰 controller；捕获路由完全退出的时机，
    // 动画结束再释放。
    final controller = TextEditingController(text: current);
    var routeExited = Future<void>.value();
    String? name;
    try {
      name = await GlassDialog.show<String>(
        context: context,
        builder: (ctx) {
          routeExited = ModalRoute.of(ctx)!.completed;
          return AlertDialog(
            title: Text(
              AppLocalizations.of(context)?.renameCanvasTitle ?? '重命名画布',
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            actions: AppleDialog.actions([
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: Text(
                  AppLocalizations.of(context)?.commonConfirm ?? '确定',
                ),
              ),
            ]),
          );
        },
      );
      await routeExited;
    } finally {
      controller.dispose();
    }
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == current) return;
    _controller.document.title = trimmed;
    _controller.notifyChanged();
    _scheduleAutosave();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    AppSnack.show(context, message);
  }

  /// 确认裁剪：按裁剪矩形重新编码图片并写回文件（对齐 Excalidraw 图片裁剪）。
  ///
  /// C-04 第五批：解码/几何换算/密封/原子写管线整体迁
  /// infrastructure/editor_image_crop.dart；本页只做守卫、结果映射与画布
  /// 状态更新（提示文案逐条对应）。
  ///
  /// 修复 3（审计 2026-10-04）：旧时序「await 落盘 → `if (!mounted) return`
  /// → 才改 rect」把「文档几何更新」与「磁盘写入」拆成不成对的两步——写盘
  /// await 期间退出页面就留下「磁盘裁剪后像素 + 文档裁剪前矩形」的永久错位。
  /// 现交 [commitCropPairing] 成对提交，本页只保留守卫与文案映射。
  Future<void> _confirmCrop() async {
    final img = _cropItem;
    final rect = _cropRect;
    if (img == null || rect == null || rect.width < 10 || rect.height < 10) {
      _showSnack(AppLocalizations.of(context)?.cropInvalid ?? '裁剪区域无效');
      return;
    }
    // 写盘飞行中忽略重复确认（旧实现会在同一矩形上二次裁剪）。
    if (_cropWriteInFlight != null) return;
    final filePath = img.filePath;
    final imageId = img.id;
    final EditorCropCommitResult result;
    try {
      result = await commitCropPairing(
        sourceBounds: Rect.fromLTWH(img.x, img.y, img.width, img.height),
        cropRect: rect,
        writeToDisk: (crop, bounds) => const EditorImageCropWriter()
            .writeCropFromPath(
          path: filePath,
          cropRect: crop,
          imageBounds: bounds,
        ),
        // 文档几何更新（内存对象，不看 mounted——页面卸载也必须成对更新）。
        applyRect: (target) {
          img
            ..x = target.left
            ..y = target.top
            ..width = target.width
            ..height = target.height;
          // 磁盘文件被重写（或被回滚）后都要失效 DocumentImageCache 的旧位图，
          // 否则画布仍把「裁剪前的全尺寸位图」拉伸进新矩形（审计 2026-09-06）。
          _controller.invalidateDocumentImage(imageId);
          // 标脏：由既有 5s 防抖自动保存 / 退出兜底 flush 持久化（见闸门注释）。
          _notifyChanged();
          if (mounted) notify();
        },
        endCrop: () {
          _canvasInteraction.clearCrop();
          if (mounted) notify();
        },
        writeGate: (inFlight) => _cropWriteInFlight = inFlight,
        reportError: (e) {
          // R-02（审计 2026-09-27）：$e 含文件路径/加密封包内部细节——按 H-04
          // 脱敏口径 UI 只给固定文案，错误类型进审计日志。
          AuditLogger.log(
            'editor.crop.save_failed',
            success: false,
            detail: errorCode(e),
          );
        },
      );
    } catch (e) {
      // 兜底（对齐旧实现的整体 try/catch）：几何/通知回调意外抛不得成为
      // 未处理异步异常；快照闸门已在 commitCropPairing 的 finally 里解除。
      AuditLogger.log(
        'editor.crop.save_failed',
        success: false,
        detail: errorCode(e),
      );
      _showSnack(_l10nSafe?.cropFailed ?? '裁剪失败，请重试');
      return;
    }
    // 提示文案逐条沿用原实现（_showSnack 自带 mounted 守卫）。
    switch (result) {
      case EditorCropCommitResult.committed:
        _showSnack(_l10nSafe?.cropDone ?? '已裁剪图片');
      case EditorCropCommitResult.sourceMissing:
        _showSnack(_l10nSafe?.cropSourceMissing ?? '原图文件不存在');
      case EditorCropCommitResult.encodeFailed:
        _showSnack(_l10nSafe?.cropEncodeFail ?? '裁剪编码失败');
      case EditorCropCommitResult.vaultLocked:
        _showSnack(_l10nSafe?.cropVaultLocked ?? '保险库已锁定，无法保存裁剪');
      case EditorCropCommitResult.failed:
        _showSnack(_l10nSafe?.cropFailed ?? '裁剪失败，请重试');
    }
  }
}

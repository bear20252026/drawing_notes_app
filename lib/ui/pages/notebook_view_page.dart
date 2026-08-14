import 'dart:async';
import 'dart:convert';

import '../../app_design.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../engine/ink_layer_painter.dart';
import '../../engine/shape_renderer.dart';
import '../../models/document.dart';
import '../../models/notebook.dart';
import '../../storage/notebook_storage.dart';
import '../../storage/password_disk.dart';
import '../../storage/pdf_import_service.dart';
import '../../storage/storage_service.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_surface.dart';
import 'editor_page.dart';

part 'notebook_view_page_widgets.dart';

/// 笔记本内页面管理页（Phase 5）。
///
/// 能力：
/// - 查看笔记本所有页面（缩略图 + 标题）
/// - 新建页面（默认空白，复用画布能力）
/// - 删除页面（二次确认）
/// - 点击页面进入编辑器（手写 + 文字 + 图片混排）
///
/// [onChanged] 用于通知首页刷新列表。
class NotebookViewPage extends StatefulWidget {
  const NotebookViewPage({
    super.key,
    required this.notebook,
    required this.storage,
    this.onChanged,
    this.sessionPassword,
    this.sessionMasterKey,
  });

  final Notebook notebook;
  final NotebookStorage storage;
  final VoidCallback? onChanged;

  /// 会话内密码（仅内存持有，不落盘）：解密密码模式笔记本后传入，
  /// 使保存时可重加密最新内容（修复"编辑后无法保存"的致命问题）。
  final String? sessionPassword;

  /// 会话内 U盘主密钥（仅内存持有，不落盘）：解锁 keyfile 模式笔记本后
  /// 传入，使保存时可重加密最新内容（零知识架构）。
  final List<int>? sessionMasterKey;

  @override
  State<NotebookViewPage> createState() => _NotebookViewPageState();
}

class _NotebookViewPageState extends State<NotebookViewPage> {
  NotebookStorage? get storage => widget.storage;
  late Notebook _notebook;
  bool _saving = false;
  bool _saveQueued = false;
  Completer<void>? _saveCompletion;

  /// 标签筛选关键词（A2：输入标签后只显示带该标签的页面）。
  String _tagFilter = '';

  /// 会话内密码（设置密码时记录；保存加密笔记本时用于重加密最新内容）。
  String? _sessionPassword;

  /// 会话内 U盘主密钥（keyfile 模式解锁后记录，仅内存；保存时重加密）。
  List<int>? _sessionMasterKey;

  /// 当前生效的会话密码（优先用本页设置过的，其次用打开时传入的）。
  String? get _effectivePassword => _sessionPassword ?? widget.sessionPassword;

  /// 当前生效的 U盘主密钥（优先用本页设置/解锁的，其次用打开时传入的）。
  List<int>? get _effectiveMasterKey =>
      _sessionMasterKey ?? widget.sessionMasterKey;

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
  }

  /// 保存笔记本到本地（每次变更后调用）。
  ///
  /// 版本历史（C1，对齐 nb"每次修改自动 commit"）：保存前为每个页面
  /// 记录当前内容快照（最多 [NotebookPage.maxHistoryVersions] 版），
  /// 供回溯恢复。
  Future<void> _save() async {
    if (_saving) {
      _saveQueued = true;
      return _saveCompletion?.future ?? Future<void>.value();
    }
    _saving = true;
    final completion = Completer<void>();
    _saveCompletion = completion;
    try {
      do {
        _saveQueued = false;
        _notebook.touch();
        // 自动记录版本快照（C1 + C2 diff 摘要）。
        for (final page in _notebook.pages) {
          if (page.cloneOf != null) continue; // 克隆页不存本地快照（内容在源）
          // 可用性修复：内容未变化时不记录快照（否则每次保存——包括
          // 新建空页面、打开未修改就返回——都会堆叠"内容微调"空白快照，
          // 污染版本历史）。比较笔画数 + 文字数 + 文本内容。
          if (_hasContentChanged(page)) {
            // C2：相对上一版计算变更 diff 摘要（笔画数/文字数）。
            final prev = page.history.isNotEmpty ? page.history.first : null;
            final summary = _diffSummary(page, prev);
            // 版本快照必须**深拷贝**（评审发现 P2）：page.document/textItems 是
            // 编辑器实时修改的同一对象，若存引用则所有版本都指向当前状态，
            // 无法回溯、diff 恒为 0、文件里重复序列化当前内容。
            page.history.insert(
              0,
              PageVersion(
                time: DateTime.now(),
                document: DrawingDocument.fromJson(page.document.toJson()),
                textItems: page.textItems
                    .map((t) => PageTextItem.fromJson(t.toJson()))
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
                summary: summary,
              ),
            );
            if (page.history.length > NotebookPage.maxHistoryVersions) {
              page.history.removeRange(
                NotebookPage.maxHistoryVersions,
                page.history.length,
              );
            }
          }
        }
        // 加密笔记本：用会话密钥重加密最新内容后保存（评审发现 P1 修复 +
        // 可用性修复：编辑后保存不再抛 StateError，内容不会丢失）。
        // 未加密：普通原子写入。
        if (_notebook.encrypted &&
            _notebook.encryptionMode == EncryptionMode.keyfile) {
          final mk = _effectiveMasterKey;
          if (mk != null) {
            await widget.storage.saveWithKey(_notebook, mk);
          } else {
            await widget.storage.save(_notebook);
          }
        } else {
          final pw = _effectivePassword;
          if (_notebook.encrypted && pw != null) {
            await widget.storage.encryptAndSave(_notebook, pw);
          } else {
            await widget.storage.save(_notebook);
          }
        }
        widget.onChanged?.call();
      } while (_saveQueued);
      completion.complete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      _saving = false;
      if (identical(_saveCompletion, completion)) _saveCompletion = null;
    }
  }

  /// 页面内容是否相比上一版本有变化。
  ///
  /// 版本回溯必须覆盖所有可编辑对象，不能只按笔画数与文字数量判断；
  /// 否则图片、形状、图表或连接线变更会被静默漏存，恢复会产生混合状态。
  bool _hasContentChanged(NotebookPage page) {
    final prev = page.history.isNotEmpty ? page.history.first : null;
    if (prev == null) return _pageHasContent(page);
    return _contentSignature(
          document: page.document,
          textItems: page.textItems,
          imageItems: page.imageItems,
          connectors: page.connectors,
          shapes: page.shapes,
          charts: page.charts,
        ) !=
        _contentSignature(
          document: prev.document,
          textItems: prev.textItems,
          imageItems: prev.imageItems,
          connectors: prev.connectors,
          shapes: prev.shapes,
          charts: prev.charts,
        );
  }

  bool _pageHasContent(NotebookPage page) =>
      page.document.layers.any((layer) => layer.strokes.isNotEmpty) ||
      page.textItems.isNotEmpty ||
      page.imageItems.isNotEmpty ||
      page.connectors.isNotEmpty ||
      page.shapes.isNotEmpty ||
      page.charts.isNotEmpty;

  String _contentSignature({
    required DrawingDocument document,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageConnector> connectors,
    required List<PageShapeItem> shapes,
    required List<PageChartItem> charts,
  }) => jsonEncode({
    'document': document.toJson(),
    'textItems': textItems.map((item) => item.toJson()).toList(),
    'imageItems': imageItems.map((item) => item.toJson()).toList(),
    'connectors': connectors.map((item) => item.toJson()).toList(),
    'shapes': shapes.map((item) => item.toJson()).toList(),
    'charts': charts.map((item) => item.toJson()).toList(),
  });

  /// 计算页面相对上一版的变更 diff 摘要（C2，借鉴 GenOffice 快照 diff 思路）。
  String _diffSummary(NotebookPage page, PageVersion? prev) {
    if (prev == null) return '首次保存';
    final strokesNow = page.document.layers.fold<int>(
      0,
      (sum, l) => sum + l.strokes.length,
    );
    final strokesPrev = prev.document.layers.fold<int>(
      0,
      (sum, l) => sum + l.strokes.length,
    );
    final parts = <String>[];
    final ds = strokesNow - strokesPrev;
    if (ds != 0) parts.add('笔画${ds > 0 ? '+' : ''}$ds');
    if (page.textItems.length != prev.textItems.length) {
      parts.add(
        '文字${page.textItems.length > prev.textItems.length ? '+' : ''}'
        '${page.textItems.length - prev.textItems.length}',
      );
    }
    // 文字内容是否被修改（数量相同但文本有变化）。
    var textChanged = false;
    if (page.textItems.length == prev.textItems.length) {
      for (var i = 0; i < page.textItems.length; i++) {
        if (page.textItems[i].text != prev.textItems[i].text) {
          textChanged = true;
          break;
        }
      }
    }
    if (textChanged) parts.add('文字修改');
    final imageDiff = page.imageItems.length - prev.imageItems.length;
    final shapeDiff = page.shapes.length - prev.shapes.length;
    final chartDiff = page.charts.length - prev.charts.length;
    final connectorDiff = page.connectors.length - prev.connectors.length;
    if (imageDiff != 0) parts.add('图片${imageDiff > 0 ? '+' : ''}$imageDiff');
    if (shapeDiff != 0) parts.add('形状${shapeDiff > 0 ? '+' : ''}$shapeDiff');
    if (chartDiff != 0) parts.add('图表${chartDiff > 0 ? '+' : ''}$chartDiff');
    if (connectorDiff != 0) {
      parts.add('连线${connectorDiff > 0 ? '+' : ''}$connectorDiff');
    }
    return parts.isEmpty ? '内容微调' : parts.join(' · ');
  }

  /// 导入 Markdown/文本文件，按段落生成文字块（C4，借鉴 nb 导入）。
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
      setState(() => _notebook.pages.add(page));
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
      setState(() => _notebook.pages.addAll(created));
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
    setState(() {
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
        setState(() {});
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
    final recoveryKey = _generateRecoveryKey();
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
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已启用 U盘钥匙加密（拔盘即锁）')));
      }
    } catch (e) {
      _showSnack('启用 U盘钥匙加密失败：$e');
    }
  }

  /// 生成 24 位恢复密钥（去易混字符 0/O/1/I）。
  String _generateRecoveryKey() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = math.Random();
    final sb = StringBuffer();
    for (var i = 0; i < 24; i++) {
      if (i > 0 && i % 4 == 0) sb.write('-');
      sb.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return sb.toString();
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
    setState(() {
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
    if (mounted) setState(() {});
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  /// 新建页面并进入编辑器。模板在创建时就决定纸张与初始结构，
  /// 避免用户先得到空白页、再手动寻找多项设置。
  Future<void> _createPage() async {
    final request = await showDialog<_NewPageRequest>(
      context: context,
      builder: (ctx) => const _CreatePageDialog(),
    );
    if (request == null || request.title.trim().isEmpty) return;

    final page = NotebookPage(
      id: NotebookStorage.newId('pg'),
      title: request.title.trim(),
      document: _newDocument(template: request.template),
      template: request.template,
      textItems: _templateTextItems(request.template),
    );
    setState(() => _notebook.pages.add(page));
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorPage(
          notebook: _notebook,
          page: page,
          storage: widget.storage,
          onChanged: _save,
        ),
      ),
    );
    setState(() {}); // 返回后刷新
  }

  /// 生成新页面的默认画布文档。
  ///
  /// 必须返回真实文档（非 null）：页面保存/进入编辑器都依赖 [NotebookPage.document]，
  /// 若为 null 会导致保存时抛空指针异常、无法跳转（曾出现过的严重缺陷）。
  DrawingDocument _newDocument({PageTemplate template = PageTemplate.blank}) {
    // 使用与独立画作一致的默认尺寸（A4 比例 210:297 近似）。
    // “无限白板”不在此处承诺为真实无限画布；当前渲染器仍是固定坐标纸面。
    return DrawingDocument(
      id: StorageService.newId(),
      title: '未命名页面',
      width: 2480,
      height: 3508,
      paperType: template.paperType,
    );
  }

  List<PageTextItem> _templateTextItems(PageTemplate template) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    PageTextItem item(
      String id,
      double x,
      double y,
      String text, {
      double size = 24,
      bool bold = false,
    }) => PageTextItem(
      id: id,
      x: x,
      y: y,
      text: text,
      fontSize: size,
      bold: bold,
    );

    switch (template) {
      case PageTemplate.meeting:
        return [
          item(
            NotebookStorage.newId('txt'),
            110,
            90,
            '会议主题',
            size: 38,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            170,
            '日期：$date    参与者：',
            size: 22,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            310,
            '议题',
            size: 28,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            1060,
            '决策',
            size: 28,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            1810,
            '行动项（负责人 / 截止日）',
            size: 28,
            bold: true,
          ),
        ];
      case PageTemplate.cornell:
        return [
          item(
            NotebookStorage.newId('txt'),
            110,
            90,
            '主题 / 课程',
            size: 34,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            220,
            '线索与问题',
            size: 24,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            720,
            220,
            '笔记',
            size: 24,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            2920,
            '总结',
            size: 24,
            bold: true,
          ),
        ];
      case PageTemplate.planner:
        return [
          item(
            NotebookStorage.newId('txt'),
            110,
            90,
            '本周计划',
            size: 38,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            240,
            '最重要的三件事',
            size: 26,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            1280,
            '日程与待办',
            size: 26,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            2450,
            '复盘与下周准备',
            size: 26,
            bold: true,
          ),
        ];
      case PageTemplate.blank:
      case PageTemplate.lined:
      case PageTemplate.grid:
      case PageTemplate.dot:
      case PageTemplate.whiteboard:
        return const [];
    }
  }

  Future<void> _toggleFavorite(NotebookPage page) async {
    setState(() => page.favorite = !page.favorite);
    await _save();
  }

  /// 打开已有页面。
  ///
  /// 克隆引用页面（[NotebookPage.cloneOf] 非空）：实时加载源笔记本的源页面，
  /// 以源页面打开编辑器，修改写回源页面——一处修改，所有克隆端同步生效
  /// （借鉴 Trilium 笔记克隆，非复制粘贴）。
  Future<void> _openPage(NotebookPage page) async {
    final ref = page.cloneOf;
    if (ref != null) {
      final srcNotebook = await widget.storage.load(ref.notebookId);
      if (srcNotebook == null || !mounted) return;
      final srcPage = srcNotebook.pages
          .where((p) => p.id == ref.pageId)
          .firstOrNull;
      if (srcPage == null) {
        _showSnack('引用的源页面不存在（可能已被删除）');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorPage(
            notebook: srcNotebook,
            page: srcPage,
            storage: widget.storage,
            onChanged: () => widget.storage.save(srcNotebook),
          ),
        ),
      );
      setState(() {});
      return;
    }

    setState(() => page.lastOpenedAt = DateTime.now());
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorPage(
          notebook: _notebook,
          page: page,
          storage: widget.storage,
          onChanged: _save,
        ),
      ),
    );
    setState(() {});
  }

  /// 从其他笔记本引入页面（创建克隆引用，借鉴 Trilium 笔记克隆）。
  Future<void> _importPage() async {
    final notebooks = await widget.storage.listAll();
    if (!mounted) return;
    final others = notebooks.where((nb) => nb.id != _notebook.id).toList();
    if (others.isEmpty) {
      _showSnack('暂没有其他笔记本可引入');
      return;
    }
    // 第一步：选择源笔记本。
    final srcNb = await showDialog<Notebook>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择源笔记本'),
        children: [
          for (final nb in others)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(nb),
              child: Text(nb.title),
            ),
        ],
      ),
    );
    if (srcNb == null || !mounted) return;
    if (srcNb.pages.isEmpty) {
      _showSnack('该笔记本还没有页面');
      return;
    }
    // 第二步：选择页面。
    final srcPage = await showDialog<NotebookPage>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要引入的页面'),
        children: [
          for (final p in srcNb.pages)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Text(p.title),
            ),
        ],
      ),
    );
    if (srcPage == null || !mounted) return;

    // 创建克隆引用条目（不复制内容）。
    setState(() {
      _notebook.pages.add(
        NotebookPage(
          id: NotebookStorage.newId('pg'),
          title: '↪ ${srcPage.title}',
          document: _newDocument(), // 占位，实际内容从源实时加载
          cloneOf: CloneRef(notebookId: srcNb.id, pageId: srcPage.id),
        ),
      );
    });
    await _save();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onNotebookMenuSelected(_NotebookMenuItem item) {
    switch (item) {
      case _NotebookMenuItem.importPage:
        _importPage();
      case _NotebookMenuItem.importText:
        _importText();
      case _NotebookMenuItem.importPdf:
        _importPdf();
      case _NotebookMenuItem.security:
        _setPassword();
      case _NotebookMenuItem.organize:
        _macroMovePages();
    }
  }

  /// 删除页面（二次确认）。
  Future<void> _deletePage(NotebookPage page) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除页面'),
        content: Text('确定删除页面「${page.title}」吗？其中的手写与文字内容将一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _notebook.pages.removeWhere((p) => p.id == page.id));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _notebook.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: _createPage,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建页面'),
            ),
          ),
          PopupMenuButton<_NotebookMenuItem>(
            tooltip: '笔记本操作',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: _onNotebookMenuSelected,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _NotebookMenuItem.importPage,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded),
                  title: Text('从其他笔记本引入页面'),
                ),
              ),
              const PopupMenuItem(
                value: _NotebookMenuItem.importText,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_rounded),
                  title: Text('导入 Markdown 或文本'),
                ),
              ),
              const PopupMenuItem(
                value: _NotebookMenuItem.importPdf,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('导入 PDF 并逐页批注'),
                ),
              ),
              PopupMenuItem(
                value: _NotebookMenuItem.security,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _notebook.encrypted
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                  ),
                  title: Text(_notebook.encrypted ? '修改密码保护' : '设置密码保护'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _NotebookMenuItem.organize,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_move_outlined),
                  title: Text('批量整理页面'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AmbientBackground(
        child: Column(
          children: [
            // 标签筛选（A2：按标签过滤页面）
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.pagePadding,
                8,
                AppDesign.pagePadding,
                8,
              ),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(14),
                sigma: 8,
                padding: const EdgeInsets.all(4),
                child: TextField(
                  onChanged: (v) => setState(() => _tagFilter = v.trim()),
                  decoration: const InputDecoration(
                    hintText: '筛选标签或关键词',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildPages()),
          ],
        ),
      ),
    );
  }

  Widget _buildPages() {
    // 标签筛选后的页面列表（A2）。
    final pages =
        (_tagFilter.isEmpty
                ? _notebook.pages
                : _notebook.pages
                      .where((p) => p.tags.any((t) => t.contains(_tagFilter)))
                      .toList())
            .toList()
          ..sort((a, b) {
            if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
            final aTime = a.lastOpenedAt ?? a.updatedAt;
            final bTime = b.lastOpenedAt ?? b.updatedAt;
            return bTime.compareTo(aTime);
          });
    if (_notebook.pages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_add_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('这个笔记本还没有页面，点击右上角新建'),
          ],
        ),
      );
    }
    if (pages.isEmpty) {
      return const Center(
        child: Text('没有匹配该标签的页面', style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.pagePadding,
        8,
        AppDesign.pagePadding,
        96,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 224,
        childAspectRatio: 0.74,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: pages.length,
      itemBuilder: (context, i) {
        final page = pages[i];
        return _PageCard(
          page: page,
          onTap: () => _openPage(page),
          onDelete: () => _deletePage(page),
          onHistory: () => _showHistory(page),
          onToggleFavorite: () => _toggleFavorite(page),
        );
      },
    );
  }
}

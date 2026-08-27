part of 'editor_page.dart';

// 编辑器主菜单/杂项动作域（O1 拆分）：主菜单处理、导出、图表、
// 演示、统计、命令面板、复制粘贴、样式与快捷键方法从 editor_page.dart
// 移出为 extension；行为零变化。

/// 编辑器主菜单/杂项动作域（拆分自 editor_page.dart）。
extension _EditorPageActions on _EditorPageState {
  void _onMainMenuSelected(_MainMenuItem item) {
    switch (item) {
      case _MainMenuItem.clearCanvas:
        _controller.clearAll();
      case _MainMenuItem.copyPng:
        _copyPngToClipboard();
      case _MainMenuItem.exportPng:
        _exportPng();
      case _MainMenuItem.exportSvg:
        _exportSvg();
      case _MainMenuItem.exportPdf:
        _exportPdf();
      case _MainMenuItem.exportJson:
        _exportJson();
      case _MainMenuItem.exportPptx:
        _exportPptx();
      case _MainMenuItem.exportText:
        _exportText();
      case _MainMenuItem.exportWord:
        _exportWordCompatibleRtf();
      case _MainMenuItem.commandPalette:
        _showCommandPalette();
      case _MainMenuItem.chart:
        _createChart();
      case _MainMenuItem.presentation:
        _startPresentation();
      case _MainMenuItem.stats:
        _showStats();
      case _MainMenuItem.library:
        _openShapeLibrary();
      case _MainMenuItem.shortcuts:
        _showShortcutHelp();
      case _MainMenuItem.toggleInfinite:
        _toggleInfiniteCanvas();
    }
  }

  /// 切换无限画布模式（问题8）：开启后画布尺寸随内容动态扩展，
  /// 元素可超出默认 A4 边界；关闭后回到固定纸张。仅独立画布可用，
  /// 笔记本页由页面模板决定纸张，不提供运行时切换。
  void _toggleInfiniteCanvas() {
    final doc = _controller.document;
    _applyState(() {
      doc.infinite = !doc.infinite;
      _viewportInitialized = false;
      _gridVisible = doc.infinite ? true : _gridVisible;
    });
    _controller.document.touch();
    _controller.tickFrame();
    _showSnack(doc.infinite ? '已切换为无限画布（可无限延展）' : '已切回固定纸张');
    _notifyChanged();
  }

  /// 导出画布为 PPTX（委托给 [EditorExporter]）。
  Future<void> _exportPptx() => _exporter.exportPptx();

  /// 导出画布为 JSON（委托给 [EditorExporter]）。
  Future<void> _exportJson() => _exporter.exportJson();

  /// 图表生成（借鉴 Excalidraw charts）：粘贴数值（逗号/空格/换行分隔），
  /// 自动生成柱状图/折线图元素并放入画布中心。
  Future<void> _createChart() async {
    final page = widget.session;
    if (page == null) {
      _showSnack('仅笔记本页面支持图表');
      return;
    }
    final input = TextEditingController();
    var chartType = ChartType.bar;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('生成图表'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<ChartType>(
                  segments: const [
                    ButtonSegment(
                      value: ChartType.bar,
                      label: Text('柱状图'),
                      icon: Icon(Icons.bar_chart),
                    ),
                    ButtonSegment(
                      value: ChartType.line,
                      label: Text('折线图'),
                      icon: Icon(Icons.show_chart),
                    ),
                  ],
                  selected: {chartType},
                  onSelectionChanged: (v) =>
                      setDialogState(() => chartType = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  autofocus: true,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText:
                        AppLocalizations.of(context)?.editorPasteValues ??
                        '粘贴数值，用逗号/空格/换行分隔，例如：10, 25, 18, 42, 30',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('ok'),
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    // 解析数值（逗号/空格/换行分隔）。
    final data = input.text
        .split(RegExp(r'[, ]+'))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => double.tryParse(e.trim()))
        .whereType<double>()
        .toList();
    if (data.isEmpty) {
      _showSnack('未解析到有效数值');
      return;
    }
    final center = _controller.document.size.center(Offset.zero);
    _applyState(() {
      page.charts.add(
        PageChartItem(
          id: LocalIdGenerator.next('cht'),
          chartType: chartType,
          data: data,
          x: center.dx - 160,
          y: center.dy - 100,
        ),
      );
      _selectedItemId = page.charts.last.id;
    });
    _notifyChanged();
    _showSnack('已生成图表（${data.length} 个数据点）');
  }

  /// 幻灯片演示（对齐 Excalidraw presentation）：全屏逐元素展示。
  void _startPresentation() {
    final page = widget.session;
    if (page == null) {
      _showSnack('仅笔记本页面支持幻灯片演示');
      return;
    }
    if (page.textItems.isEmpty &&
        page.imageItems.isEmpty &&
        page.shapes.isEmpty) {
      _showSnack('本页还没有可演示的内容');
      return;
    }
    final onOpen = widget.openPresentation;
    if (onOpen == null) {
      _showSnack('演示功能不可用');
      return;
    }
    unawaited(onOpen(context));
  }

  /// 统计面板（对齐 Excalidraw Stats）：显示元素数量/类型统计。
  Future<void> _showStats() async {
    final page = widget.session;
    final doc = _controller.document;
    var strokes = 0;
    for (final layer in doc.layers) {
      strokes += layer.strokes.length;
    }
    final textN = page?.textItems.length ?? 0;
    final imgN = page?.imageItems.length ?? 0;
    final shapeN = page?.shapes.length ?? 0;
    final chartN = page?.charts.length ?? 0;
    final total = textN + imgN + shapeN + chartN + strokes;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('画布统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statRow('手写笔画', strokes),
            _statRow('文字块', textN),
            _statRow('图片', imgN),
            _statRow('形状', shapeN),
            _statRow('图表', chartN),
            const Divider(),
            _statRow('合计元素', total),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 统计面板行。
  Widget _statRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 形状库/图书馆（对齐 Excalidraw libraries）：浏览/检索/插入形状。
  /// 个人收藏（收藏到库）保存在会话内。
  Future<void> _openShapeLibrary() async {
    final page = widget.session;
    if (page == null) {
      _showSnack('仅笔记本页面支持形状库');
      return;
    }
    final library = _shapeLibrary;
    await showDialog<void>(
      context: context,
      builder: (ctx) => ShapeLibraryDialog(
        library: library,
        onInsert: (template) {
          // 插入到画布中心（带偏移，避免与库预览重叠）。
          final center = _controller.document.size.center(Offset.zero);
          final shape = PageShapeItem.fromJson(template.toJson())
            ..x = center.dx - template.width / 2
            ..y = center.dy - template.height / 2;
          _applyState(() {
            page.shapes.add(shape);
            _selectedItemId = shape.id;
          });
          _notifyChanged();
          _showSnack('已插入「${shapeTypeName(shape.shapeType)}」');
        },
      ),
    );
  }

  /// 命令面板（Ctrl/Cmd+K，对齐 Excalidraw CommandPalette）。
  ///
  /// 条目完全来自统一命令注册表；只显示当前可执行的动作，并按类别、
  /// 关键词和最近执行状态组织。这样不会再出现菜单中展示无法完成的命令。
  ///
  /// 对话框本体为自管理生命周期的 [_CommandPaletteDialog]（见
  /// editor_page_dialogs.dart），确保搜索框 TextEditingController 在对话框
  /// 完全退出后才释放，避免关闭动画期间重建访问已释放对象。
  Future<void> _showCommandPalette() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _CommandPaletteDialog(
        registry: _commands,
        initialLastCommandId: _lastCommandId,
      ),
    );
    if (result == null) return;
    if (_commands.run(result)) {
      _applyState(() => _lastCommandId = result);
    }
  }

  /// 复制选中元素（文字/图片/形状，借鉴 Excalidraw 元素复制）。
  void _copySelectedElement() {
    final page = widget.session;
    if (page == null) return;
    _copiedElements = [];
    // 多选优先，其次单选。
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    for (final t in page.textItems) {
      if (ids.contains(t.id)) {
        _copiedElements.add({'kind': 'text', 'data': t.toJson()});
      }
    }
    for (final i in page.imageItems) {
      if (ids.contains(i.id)) {
        _copiedElements.add({'kind': 'image', 'data': i.toJson()});
      }
    }
    for (final s in page.shapes) {
      if (ids.contains(s.id)) {
        _copiedElements.add({'kind': 'shape', 'data': s.toJson()});
      }
    }
    if (_copiedElements.isNotEmpty) {
      _showSnack('已复制 ${_copiedElements.length} 个元素');
    } else {
      _showSnack('请先选中要复制的元素');
    }
  }

  /// 粘贴复制的元素（偏移 24px，避免与原位置重叠，借鉴 Excalidraw）。
  void _pasteCopiedElement() {
    final page = widget.session;
    if (page == null || _copiedElements.isEmpty) {
      _showSnack('请先复制元素（Ctrl+C）');
      return;
    }
    _applyState(() {
      final pastedIds = <String>[];
      for (final entry in _copiedElements) {
        final kind = entry['kind'] as String;
        final data = entry['data'] as Map<String, dynamic>;
        final dx = 24.0, dy = 24.0;
        if (kind == 'text') {
          final t = PageTextItem.fromJson(data);
          t.x += dx;
          t.y += dy;
          page.textItems.add(t);
          pastedIds.add(t.id);
        } else if (kind == 'image') {
          final img = PageImageItem.fromJson(data);
          img.x += dx;
          img.y += dy;
          page.imageItems.add(img);
          pastedIds.add(img.id);
        } else if (kind == 'shape') {
          final s = PageShapeItem.fromJson(data);
          s.x += dx;
          s.y += dy;
          page.shapes.add(s);
          pastedIds.add(s.id);
        }
      }
      _canvasInteraction.replaceMultiSelection(pastedIds);
    });
    _notifyChanged();
    _showSnack('已粘贴 ${_copiedElements.length} 个元素');
  }

  /// 快捷键：切到画笔工具。
  void _selectBrushTool() => _selectWritingTool(BrushType.pen);

  /// 快捷键：切到橡皮擦工具。
  void _selectEraserTool() => _selectWritingTool(BrushType.eraser);

  /// 快捷键：切到矩形选区工具。
  void _selectRectSelectTool() {
    _applyState(() {
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _viewModel.setSelectionDone(false);
      _controller.selectionTool = SelectionTool.rect;
    });
  }

  /// 快捷键：切到文字工具。
  void _selectTextTool() {
    _applyState(() {
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(true);
    });
  }

  /// Alt+方向键微调：选中元素按画布像素微移（对齐 Excalidraw nudge）。
  void _nudgeSelected(double dx, double dy) {
    final page = widget.session;
    if (page == null) return;
    final id = _selectedItemId;
    if (id == null) return;
    _applyState(() {
      for (final t in page.textItems) {
        if (t.id == id) {
          t.x += dx;
          t.y += dy;
        }
      }
      for (final i in page.imageItems) {
        if (i.id == id) {
          i.x += dx;
          i.y += dy;
        }
      }
      for (final sh in page.shapes) {
        if (sh.id == id) {
          sh.x += dx;
          sh.y += dy;
        }
      }
    });
    _notifyChanged();
  }

  /// 复制选中元素样式（文字块或形状，借鉴 Excalidraw 样式刷）。
  void _copySelectedStyle() {
    final page = widget.session;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final t = page.textItems.where((x) => x.id == id).firstOrNull;
    if (t != null) {
      _copiedStyle = {
        'kind': 'text',
        'color': t.color,
        'fontSize': t.fontSize,
        'bold': t.bold,
        'italic': t.italic,
        'underline': t.underline,
        'strikethrough': t.strikethrough,
      };
      _showSnack('已复制文字样式');
      return;
    }
    final s = page.shapes.where((x) => x.id == id).firstOrNull;
    if (s != null) {
      _copiedStyle = {
        'kind': 'shape',
        'color': s.color,
        'fillColor': s.fillColor,
        'strokeWidth': s.strokeWidth,
      };
      _showSnack('已复制形状样式');
      return;
    }
    _showSnack('请先选中文字块或形状');
  }

  /// 粘贴样式到选中元素（借鉴 Excalidraw 样式刷）。
  void _pasteStyleToSelected() {
    final style = _copiedStyle;
    final page = widget.session;
    final id = _selectedItemId;
    if (style == null || page == null || id == null) {
      _showSnack('请先复制样式（Ctrl+Shift+C）再粘贴');
      return;
    }
    _applyState(() {
      final t = page.textItems.where((x) => x.id == id).firstOrNull;
      if (t != null && style['kind'] == 'text') {
        t.color = style['color'] as int;
        t.fontSize = style['fontSize'] as double;
        t.bold = style['bold'] as bool;
        t.italic = style['italic'] as bool;
        t.underline = style['underline'] as bool;
        t.strikethrough = style['strikethrough'] as bool;
      }
      final s = page.shapes.where((x) => x.id == id).firstOrNull;
      if (s != null && style['kind'] == 'shape') {
        s.color = style['color'] as int;
        s.fillColor = style['fillColor'] as int?;
        s.strokeWidth = style['strokeWidth'] as double;
      }
    });
    _notifyChanged();
    _showSnack('已粘贴样式');
  }

  /// 剪贴板智能粘贴（借鉴 Excalidraw 粘贴识别）：
  /// 文本内容创建文字块，PNG 图片创建图片块，置于画布中心。
  Future<void> _pasteFromClipboard() async {
    final page = widget.session;
    if (page == null) {
      _showSnack('仅笔记本页面支持粘贴');
      return;
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.trim().isNotEmpty) {
        // 文本 -> 文字块（画布中心）。
        final center = _controller.document.size.center(Offset.zero);
        _applyState(() {
          page.textItems.add(
            PageTextItem(
              id: LocalIdGenerator.next('txt'),
              x: center.dx - text.length * 3,
              y: center.dy - 12,
              text: text.trim(),
            ),
          );
          _selectedItemId = page.textItems.last.id;
        });
        _notifyChanged();
        return;
      }
      // 图片：当前 Flutter 桌面端 ClipboardData 无图片字段，
      // 图片粘贴需平台通道（后续增强），此处明确提示。
      _showSnack('剪贴板没有可粘贴的文本');
    } catch (e) {
      _showSnack('粘贴失败：$e');
    }
  }

  /// 切换选中文字块的加粗状态。
  void _toggleSelectedTextBold() {
    final item = _selectedTextItem;
    if (item == null) return;
    _applyState(() => item.bold = !item.bold);
    _notifyChanged();
  }

  /// 切换选中文字块的斜体状态。
  void _toggleSelectedTextItalic() {
    final item = _selectedTextItem;
    if (item == null) return;
    _applyState(() => item.italic = !item.italic);
    _notifyChanged();
  }

  /// 循环切换选中文字块的对齐方式。
  void _cycleSelectedTextAlign() {
    final item = _selectedTextItem;
    if (item == null) return;
    _applyState(() {
      item.align = TextAlignType
          .values[(item.align.index + 1) % TextAlignType.values.length];
    });
    _notifyChanged();
  }

  /// 快捷键帮助对话框（B2：从命令注册表自动生成，借鉴 Notes 快捷键文档化）。
  void _showShortcutHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('快捷键'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in _commands.commands)
                if (c.shortcut.isNotEmpty)
                  ShortcutRow(shortcut: c.shortcut, action: c.label),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

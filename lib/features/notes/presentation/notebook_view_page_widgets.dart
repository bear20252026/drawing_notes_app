part of 'notebook_view_page.dart';

/// 页面卡片：缩略图 + 标题 + 收藏/历史/删除操作。
class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.page,
    required this.onTap,
    required this.onDelete,
    this.onHistory,
    this.onToggleFavorite,
  });

  final NotebookPage page;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onHistory;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 页面缩略图（以画布尺寸比例显示白纸 + 内容占位）
            Expanded(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(4),
                child: _PageThumbnail(page: page),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          page.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        // 分组徽标（A1 层级）与克隆标记（A3）
                        if (page.folder.isNotEmpty || page.cloneOf != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if (page.folder.isNotEmpty) '📁 ${page.folder}',
                                if (page.cloneOf != null) '🔗 引用',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: page.favorite ? '取消收藏' : '收藏页面',
                    icon: Icon(
                      page.favorite ? Icons.star : Icons.star_border,
                      size: 18,
                    ),
                    visualDensity: VisualDensity.compact,
                    color: page.favorite ? Colors.amber.shade800 : null,
                    onPressed: onToggleFavorite,
                  ),
                  IconButton(
                    tooltip: '版本历史',
                    icon: const Icon(Icons.history, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onHistory,
                  ),
                  IconButton(
                    tooltip: '删除页面',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    color: scheme.error,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页面缩略图：以真实页面坐标绘制手写、文字、图片占位与形状。
///
/// 预览不解码原始大图，避免页面列表滚动时产生大量 I/O；图片位置和比例仍按
/// 真实元素绘制。手写则复用正式的高亮笔合成器，因此缩略图与编辑器视觉一致。
class _PageThumbnail extends StatelessWidget {
  const _PageThumbnail({required this.page});

  final NotebookPage page;

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: CustomPaint(painter: _PageThumbnailPainter(page)));
}

class _PageThumbnailPainter extends CustomPainter {
  const _PageThumbnailPainter(this.page);

  final NotebookPage page;

  @override
  void paint(Canvas canvas, Size size) {
    final doc = page.document;
    final source = Size(doc.width.toDouble(), doc.height.toDouble());
    final scale = math.min(
      size.width / source.width,
      size.height / source.height,
    );
    final offset = Offset(
      (size.width - source.width * scale) / 2,
      (size.height - source.height * scale) / 2,
    );
    final bounds = Offset.zero & source;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    // 纸张边界和手写：高亮笔仍以同色不叠加合成呈现。
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFFFFFFF));
    for (final layer in doc.layers) {
      if (!layer.visible || layer.opacity <= 0) continue;
      if (layer.opacity < 1) {
        canvas.saveLayer(
          bounds,
          Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity),
        );
        InkLayerPainter.paintStrokes(canvas, bounds, layer.strokes);
        canvas.restore();
      } else {
        InkLayerPainter.paintStrokes(canvas, bounds, layer.strokes);
      }
    }

    // 图片采用低成本块预览，保持真实布局而不在滚动列表中解码文件。
    for (final image in page.imageItems) {
      final rect = Rect.fromLTWH(image.x, image.y, image.width, image.height);
      canvas.drawRect(rect, Paint()..color = const Color(0xFFCFD8DC));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / scale
          ..color = const Color(0xFF607D8B),
      );
      canvas.drawLine(
        rect.topLeft,
        rect.bottomRight,
        Paint()
          ..strokeWidth = 1 / scale
          ..color = const Color(0x66546E7A),
      );
    }

    // 文字仅按实际坐标和字框表示，不调用昂贵文字排版。
    for (final text in page.textItems) {
      final width = text.width ?? math.max(text.fontSize * 2, 80).toDouble();
      final height = math.max(text.fontSize * 0.72, 10).toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(text.x, text.y, width, height),
          Radius.circular(2 / scale),
        ),
        Paint()..color = Color(text.color).withValues(alpha: 0.72),
      );
    }
    for (final shape in page.shapes) {
      ShapeRenderer.drawDocumentShape(canvas, shape);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PageThumbnailPainter oldDelegate) =>
      oldDelegate.page != page || oldDelegate.page.updatedAt != page.updatedAt;
}

enum _NotebookMenuItem { importPage, importText, importPdf, security, organize }

/// 新建页面请求：名称与模板必须一起提交，避免创建后再进行多处设置。
class _NewPageRequest {
  const _NewPageRequest({required this.title, required this.template});

  final String title;
  final PageTemplate template;
}

/// 页面模板选择与命名对话框。
class _CreatePageDialog extends StatefulWidget {
  const _CreatePageDialog();

  @override
  State<_CreatePageDialog> createState() => _CreatePageDialogState();
}

class _CreatePageDialogState extends State<_CreatePageDialog> {
  final TextEditingController _controller = TextEditingController();
  PageTemplate _template = PageTemplate.blank;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建页面'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '页面名称',
                  hintText: '例如：产品评审 08-14',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.of(context).pop(
                  _NewPageRequest(title: _controller.text, template: _template),
                ),
              ),
              const SizedBox(height: 20),
              Text('选择模板', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final template in PageTemplate.values)
                    ChoiceChip(
                      label: Text(template.label),
                      selected: _template == template,
                      onSelected: (_) => setState(() => _template = template),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _template == PageTemplate.meeting
                    ? '包含议题、决策和行动项的起始结构。'
                    : _template == PageTemplate.cornell
                    ? '包含线索、笔记和总结区域的起始结构。'
                    : _template == PageTemplate.planner
                    ? '包含重点、日程与复盘的起始结构。'
                    : _template == PageTemplate.whiteboard
                    ? '使用宽阔空白画布模式；当前版本仍采用固定坐标纸面。'
                    : '纸张背景会随模板设置并保存到页面。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_NewPageRequest(title: _controller.text, template: _template)),
          child: const Text('创建并开始记录'),
        ),
      ],
    );
  }
}

/// 页面名称输入对话框。
class _PageNameDialog extends StatefulWidget {
  const _PageNameDialog({this.title = '新建页面'});

  final String title;

  @override
  State<_PageNameDialog> createState() => _PageNameDialogState();
}

class _PageNameDialogState extends State<_PageNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '请输入页面名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 密码输入对话框（C3 加密设置/解锁用）。
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, this.hint = ''});

  final String title;
  final String hint;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.hint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '请输入密码',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

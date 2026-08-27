part of 'home_page.dart';

// 首页内嵌组件拆分（2026-08-15 大文件清理）：缩略图卡片/占位/名称与
// 密码对话框从 home_page.dart 移出为 part（沿用 editor_page 拆分先例）；
// 行为零变化——同库 extension/类可访问私有成员，共享主文件 imports。

/// 无限画布卡片：缩略图 + 标题 + 删除按钮。
class _DrawingCard extends StatefulWidget {
  const _DrawingCard({
    required this.meta,
    required this.documentStorage,
    required this.onTap,
    required this.onDelete,
  });

  final DocumentMeta meta;
  final StorageService documentStorage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_DrawingCard> createState() => _DrawingCardState();
}

class _DrawingCardState extends State<_DrawingCard> {
  String? _thumbPath;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    // 读取缩略图文件路径（缩略图由编辑器自动保存时生成）。
    try {
      final path = await widget.documentStorage.thumbnailPath(widget.meta.id);
      if (mounted && path != null) {
        setState(() => _thumbPath = path);
      }
    } catch (_) {
      // 缩略图缺失不影响列表展示。
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDesign.quickMotion;
    return Semantics(
      button: true,
      label: '打开无限画布 ${widget.meta.title}',
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1,
        duration: motion,
        curve: Curves.easeOutCubic,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (value) {
              if (_hovered != value) setState(() => _hovered = value);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _thumbPath != null && File(_thumbPath!).existsSync()
                      ? AnimatedOpacity(
                          opacity: 1,
                          duration: motion,
                          child: Image.file(
                            File(_thumbPath!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const _ThumbPlaceholder(),
                          ),
                        )
                      : const _ThumbPlaceholder(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.meta.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '删除无限画布',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                        ),
                        color: scheme.error,
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 缩略图占位（无缩略图时显示）。
class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      child: Center(
        child: Icon(
          Icons.draw_outlined,
          size: 38,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.52),
        ),
      ),
    );
  }
}

/// 通用名称输入对话框。
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title});

  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
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
          hintText: '请输入名称',
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

/// 密码输入对话框（C3 加密笔记本解锁用）。
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title});

  final String title;

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
      content: TextField(
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

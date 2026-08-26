part of 'home_page.dart';

// 首页内嵌组件拆分（2026-08-15 大文件清理）：缩略图卡片/占位/名称与
// 密码对话框从 home_page.dart 移出为 part（沿用 editor_page 拆分先例）；
// 行为零变化——同库 extension/类可访问私有成员，共享主文件 imports。

/// 无限画布卡片：缩略图 + 标题 + 删除按钮。
class _DrawingCard extends StatefulWidget {
  const _DrawingCard({
    required this.meta,
    required this.onTap,
    required this.onDelete,
  });

  final DocumentMeta meta;
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
      final storage = StorageService();
      final path = await storage.thumbnailPath(widget.meta.id);
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
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
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
                          style: AppDesign.bodyStrong.copyWith(
                            fontSize: 14,
                          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 270,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoTextField(
                controller: _controller,
                autofocus: true,
                placeholder: '请输入名称',
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: dividerColor),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
            ),
            const SizedBox(height: 16),
            // Divider
            Container(height: 0.5, color: dividerColor),
            // Actions
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0066CC),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(fontSize: 17),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                Container(width: 0.5, height: 44, color: dividerColor),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(_controller.text),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0066CC),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('确定'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 270,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoTextField(
                controller: _controller,
                obscureText: _obscure,
                autofocus: true,
                placeholder: '请输入密码',
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: dividerColor),
                ),
                suffix: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minSize: 0,
                  onPressed: () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    size: 18,
                    color: const Color(0xFF8E8E93),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
            ),
            const SizedBox(height: 16),
            // Divider
            Container(height: 0.5, color: dividerColor),
            // Actions
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0066CC),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(fontSize: 17),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                Container(width: 0.5, height: 44, color: dividerColor),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(_controller.text),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0066CC),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('确定'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

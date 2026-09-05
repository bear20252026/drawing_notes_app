part of 'home_page.dart';

// 首页内嵌组件拆分（2026-08-15 大文件清理）：缩略图卡片/占位/名称与
// 密码对话框从 home_page.dart 移出为 part（沿用 editor_page 拆分先例）；
// 行为零变化——同库 extension/类可访问私有成员，共享主文件 imports。

/// 无限画布卡片：缩略图 + 标题 + 密码按钮 + 删除按钮。
class _DrawingCard extends StatefulWidget {
  const _DrawingCard({
    required this.meta,
    required this.documentStorage,
    required this.onTap,
    required this.onDelete,
    required this.onPasswordAction,
  });

  final DocumentMeta meta;
  final StorageService documentStorage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 批次②：打开单文件密码管理 sheet（设置/修改/移除）。
  final VoidCallback onPasswordAction;

  @override
  State<_DrawingCard> createState() => _DrawingCardState();
}

class _DrawingCardState extends State<_DrawingCard> {
  /// 缩略图字节（批次①c：缩略图可能为 DNV 密文——存储层解密后以内存
  /// 字节渲染，不再经 Image.file 直读磁盘路径）。
  Uint8List? _thumbBytes;
  bool _hovered = false;

  /// 上一次加载缩略图时对应的画布更新时间（首页刷新修复③：
  /// 按 updatedAt 缓存键比较，画布变更才重新加载）。
  DateTime? _loadedThumbAt;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(_DrawingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 首页刷新修复③（2026-09-01）：IndexedStack 保活下卡片 State 不销毁，
    // 列表刷新带来更新的 meta 时按 updatedAt 失效缩略图，避免显示旧图。
    if (widget.meta.updatedAt != _loadedThumbAt) _loadThumb();
  }

  Future<void> _loadThumb() async {
    _loadedThumbAt = widget.meta.updatedAt;
    // 读取缩略图字节（批次①c：存储层 thumbnailBytes 自动解密 DNV 密文；
    // 保险库锁定返回 null——显示占位符，不泄露缩略图内容）。
    try {
      final bytes = await widget.documentStorage.thumbnailBytes(widget.meta.id);
      if (!mounted) return;
      setState(() => _thumbBytes = bytes);
    } catch (_) {
      // 缩略图缺失不影响列表展示。
    }
  }

  /// U4a：卡片上下文菜单（桌面右键 / 触屏长按共用）。
  ///
  /// 只聚合既有功能入口（打开 / 独立密码 / 删除——删除走原有
  /// [widget.onDelete] 的二次确认链路），不新增业务动作。
  Future<void> _showContextMenu(Offset globalPosition) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: const [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new_rounded, size: 18),
              SizedBox(width: 10),
              Text('打开'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'password',
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18),
              SizedBox(width: 10),
              Text('独立密码…'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18),
              SizedBox(width: 10),
              Text('删除'),
            ],
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        widget.onTap();
      case 'password':
        widget.onPasswordAction();
      case 'delete':
        widget.onDelete();
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
          // U4a：InkWell 不带 onLongPressStart——长按经 GestureDetector 承接。
          child: GestureDetector(
            onLongPressStart: (details) =>
                _showContextMenu(details.globalPosition),
            child: InkWell(
              onTap: widget.onTap,
              onHover: (value) {
                if (_hovered != value) setState(() => _hovered = value);
              },
              // U4a：桌面右键 → 上下文菜单（聚合既有功能入口）。
              onSecondaryTapUp: (details) =>
                  _showContextMenu(details.globalPosition),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _thumbBytes != null
                            ? AnimatedOpacity(
                                opacity: 1,
                                duration: motion,
                                // U4（审计三-10）：缩略图按显示密度解码降采样——
                                // 存储的 PNG 是画布 scale 0.2 产物，大画布仍可达
                                // 上千像素；卡片只需 ~300 逻辑像素。
                                // 审计四-2（2026-09-06）：目标宽取整到
                                // 256/512/1024 档位，窗口连续 resize 不再在
                                // 图像缓存里堆多档位图。
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final width = constraints.maxWidth;
                                    final int? cacheWidth =
                                        width.isFinite && width > 0
                                        ? ImageDecodeCap.quantizedCacheWidth(
                                            width,
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ),
                                          )
                                        : null;
                                    return Image.memory(
                                      _thumbBytes!,
                                      fit: BoxFit.contain,
                                      cacheWidth: cacheWidth,
                                      errorBuilder: (_, _, _) =>
                                          const _ThumbPlaceholder(),
                                    );
                                  },
                                ),
                              )
                            : const _ThumbPlaceholder(),
                        // 批次②：独立密码锁定徽标（缩略图已删，占位 + 锁形）。
                        if (widget.meta.locked)
                          const Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.lock_rounded,
                                size: 18,
                                color: Colors.white,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black54),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
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
                          tooltip: '独立密码',
                          icon: Icon(
                            widget.meta.locked
                                ? Icons.lock_rounded
                                : Icons.lock_outline_rounded,
                            size: 19,
                          ),
                          color: widget.meta.locked
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          onPressed: widget.onPasswordAction,
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
      color: AppleColor.panelOf(scheme),
      child: Center(
        child: Icon(
          Icons.draw_outlined,
          size: 38,
          color: AppleColor.subtleOf(scheme),
        ),
      ),
    );
  }
}

/// 画布 tab 区段标题（W1 归位：无限画布 / 分页画布两分组）。
class _CanvasSectionHeader extends StatelessWidget {
  const _CanvasSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesign.pagePadding, 16, 16, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// 分页画布卡片（W1 归位：整本粒度——图标 + 标题 + 页数/锁态副标题）。
/// 打开走 shell 统一解锁链路；页级管理与删除在分页画布页内进行。
class _NotebookCard extends StatelessWidget {
  const _NotebookCard({
    required this.notebook,
    required this.subtitle,
    required this.onTap,
  });

  final Notebook notebook;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked =
        notebook.isLockedPlaceholder ||
        (notebook.encrypted && notebook.pages.isEmpty);
    return Semantics(
      button: true,
      label: '打开分页画布 ${notebook.title}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 22,
                      color: scheme.primary,
                    ),
                    if (locked) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.lock_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                Text(
                  notebook.title.isEmpty ? '未命名' : notebook.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
        decoration: InputDecoration(
          hintText: '请输入名称',
          filled: true,
          border: OutlineInputBorder(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: AppleColor.actionBlue, width: 1.5),
          ),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: AppleDialog.actions([
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ]),
    );
  }
}


part of 'editor_page.dart';

/// 文字输入对话框的返回结果（文本 + 字号）。
class _TextDialogResult {
  const _TextDialogResult({required this.text, required this.fontSize});

  final String text;
  final double fontSize;
}

/// 文字输入对话框（支持字号选择，用于创建"特殊标签"）。
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog();

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final TextEditingController _controller = TextEditingController();
  double _fontSize = 28;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入文字'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '请输入文字内容',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // 字号调节滑块
          Row(
            children: [
              const Icon(Icons.format_size, size: 18),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 8,
                  max: 200,
                  label: _fontSize.round().toString(),
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${_fontSize.round()}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_TextDialogResult(text: _controller.text, fontSize: _fontSize)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 右键上下文菜单动作。
enum _CtxAction {
  copyStyle,
  group,
  ungroup,
  link,
  delete,
  bringToFront,
  sendToBack,
}

/// 右上角主菜单项（对齐 Excalidraw main-menu）。
enum _MainMenuItem {
  clearCanvas,
  copyPng,
  exportPng,
  exportSvg,
  exportPdf,
  exportJson,
  exportPptx,
  exportText,
  exportWord,
  commandPalette,
  chart,
  presentation,
  library,
  stats,
  shortcuts,
}

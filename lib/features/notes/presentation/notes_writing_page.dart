import 'package:material_ui/material_ui.dart';

/// 纯笔记页（导航目的地 4）：直接打字的笔记页面。
///
/// 设计说明：
/// - 当前为占位骨架；
/// - 后续在此接入富文本 / 块式笔记编辑（对齐 AFFiNE 的「文档 = 笔记」模型）。
class NotesWritingPage extends StatelessWidget {
  const NotesWritingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('笔记')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_outlined, size: 64),
            SizedBox(height: 12),
            Text('纯笔记（待完善）'),
          ],
        ),
      ),
    );
  }
}

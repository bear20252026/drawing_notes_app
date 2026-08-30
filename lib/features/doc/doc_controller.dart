// M12 笔记页文档控制器：持久化由宿主（组合根）注入，页面零存储依赖。
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// 笔记页控制器：把 DocPage 的保存动作转发到宿主注入的持久化回调。
class DocController {
  DocController({required this.onSave});

  /// 持久化回调（通常接 NoteBlockDocStore.saveDocument）。
  final void Function(NoteBlockDoc doc) onSave;

  bool _dirty = false;

  /// 是否有未持久化的改动。
  bool get dirty => _dirty;

  /// 保存文档。
  void save(NoteBlockDoc doc) {
    onSave(doc);
    _dirty = false;
  }

  /// 标记脏状态（供宿主退出确认等场景使用）。
  void markDirty() => _dirty = true;
}

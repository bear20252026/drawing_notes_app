/// 块文档全文搜索访问器实现（notes 侧）。
///
/// 实现 core 契约 `IBlockDocSearchAccessor`，用 `NoteBlockDocStore` 枚举全部
/// 块文档 + `NoteBlockDocSearchIndex` 做块级检索（多 token AND、每块 snippet、
/// 标题命中置标），再把块级命中收敛为文档级 `BlockDocSearchHit`。
///
/// 满足架构方向：features→shared→core（本实现位于 features/notes，仅 import
/// core 契约 + 自身 domain/infrastructure），shared 不反向依赖 notes。
library;

import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_search.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';

/// 块文档搜索访问器。
class BlockDocSearchAccessorImpl implements IBlockDocSearchAccessor {
  /// 创建访问器，可注入 [NoteBlockDocStore]（测试用临时目录/生产用默认）。
  BlockDocSearchAccessorImpl({NoteBlockDocStore? store})
    : _store = store ?? NoteBlockDocStore();

  final NoteBlockDocStore _store;

  @override
  Future<List<BlockDocSearchHit>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final ids = await _store.listIds();
    final results = <BlockDocSearchHit>[];
    for (final id in ids) {
      // N2：受密未解锁的笔记不进搜索结果（fail-closed——不泄露内容）。
      final NoteBlockDoc? doc;
      try {
        doc = await _store.loadDocument(id);
      } on BlockDocLockedException {
        continue;
      }
      if (doc == null) continue;

      final index = NoteBlockDocSearchIndex();
      index.indexDocument(doc);
      final blockHits = index.search(query);
      if (blockHits.isEmpty) continue;

      // 标题命中优先：给出更直接的文档级代表片段。
      final best = blockHits.firstWhere(
        (h) => h.matchedTitle,
        orElse: () => blockHits.first,
      );
      results.add(
        BlockDocSearchHit(
          docId: id,
          title: doc.title,
          snippet: best.matchedTitle ? '文档标题' : best.snippet,
          matchedTitle: best.matchedTitle,
        ),
      );
    }
    return results;
  }
}

// DN-008 加固回归锁（解码侧结构闸门）：NoteBlockDoc.fromJson 的规模预算。
//
// 为什么字节闸门不能替代它：传输层的分档上限只管「WebDAV 响应读进来多少」，
// 而 fromJson 还吃着本地文件（NoteBlockDocStore）、备份恢复与 isolate 解码
// 路径——这些都不过网络。反过来本预算也管不了远端体积，两者是两道闸。
//
// 位置说明：本批文件所有权只放开 test/core/storage/ 与 test/features/notes/，
// 故与传输层闸门同批落在这里（被测类在 core/documents）。
//
// 正反两向都钉：超限确实被拒（FormatException，构造前拦）/ 正常规模不误伤。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';

Map<String, dynamic> _block(
  String id, {
  List<dynamic>? children,
  Map<String, dynamic>? props,
}) => {
  'id': id,
  'type': 'text',
  'text': 'x',
  'props': ?props,
  'children': ?children,
};

Map<String, dynamic> _docJson(List<dynamic> body, {List<dynamic>? tags}) => {
  'id': 'doc-budget',
  'title': 't',
  'body': body,
  'tags': ?tags,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

void main() {
  group('解码结构预算：超限方向', () {
    test('顶层块数越界 → FormatException，且不构造任何块', () {
      final body = [
        for (var i = 0; i <= NoteBlockDoc.maxBodyBlockCount; i++) _block('b$i'),
      ];
      expect(
        () => NoteBlockDoc.fromJson(_docJson(body)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('正文块数超限'),
          ),
        ),
      );
    });

    test('节点总数越界（块数仍在上限内）→ 由节点预算拦下', () {
      // 60 个块 × 2000 个 props 键值 ≈ 24 万节点，越过 20 万预算，
      // 但顶层块数完全合法 ⇒ 证明这不是块数档在起作用。
      final body = [
        for (var i = 0; i < 60; i++)
          _block(
            'b$i',
            props: {for (var k = 0; k < 2000; k++) 'k$k': 'v'},
          ),
      ];
      expect(body.length, lessThan(NoteBlockDoc.maxBodyBlockCount));
      late Object thrown;
      try {
        NoteBlockDoc.fromJson(_docJson(body));
        fail('节点越界必须被拒');
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<FormatException>());
      expect((thrown as FormatException).message, contains('节点数超限'));
    });

    test('嵌套深度越界 → 先于递归解码被拒（爆栈防护）', () {
      // 造一条 400 层 children 链：NoteBlock.fromJson 是递归实现，
      // 深度闸门必须在那之前拒绝（否则是进程级栈溢出，连异常都拿不到）。
      dynamic leaf = _block('leaf');
      for (var i = 0; i < 400; i++) {
        leaf = _block('n$i', children: [leaf]);
      }
      expect(
        () => NoteBlockDoc.fromJson(_docJson([leaf])),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('嵌套深度超限'),
          ),
        ),
      );
    });

    test('预算常量与既有同类量级自洽（审读用）', () {
      expect(NoteBlockDoc.maxBodyBlockCount, 20000);
      expect(NoteBlockDoc.maxTotalJsonNodes, 200000);
      expect(NoteBlockDoc.maxBlockNestingDepth, 128);
      // 顶层满额 + 每块 3 个键值对的节点量（≈6/块）必须落在节点预算内，
      // 否则两档自相矛盾（满额块数永远读不出来）。
      expect(
        NoteBlockDoc.maxBodyBlockCount * 6,
        lessThanOrEqualTo(NoteBlockDoc.maxTotalJsonNodes),
      );
    });
  });

  group('解码结构预算：放行方向', () {
    test('满额 2 万块的长笔记不被误伤（逐块保留、内容等价）', () {
      final body = [
        for (var i = 0; i < NoteBlockDoc.maxBodyBlockCount; i++) _block('b$i'),
      ];
      final doc = NoteBlockDoc.fromJson(_docJson(body));
      expect(doc.body, hasLength(NoteBlockDoc.maxBodyBlockCount));
      expect(doc.body.first.id, 'b0');
      expect(doc.body.last.id, 'b19999');
    });

    test('普通笔记（含嵌套子块与标签）往返不变', () {
      final original = NoteBlockDoc(
        id: 'doc-1',
        title: '会议记录',
        body: [
          NoteBlock.textBlock('b0', text: '第一条'),
          NoteBlock(
            id: 'b1',
            type: NoteBlockType.bullet,
            text: '父项',
            children: [
              NoteBlock.textBlock('b1a', text: '子项'),
              NoteBlock(
                id: 'b1b',
                type: NoteBlockType.text,
                text: '孙项',
                children: [NoteBlock.textBlock('b1b1', text: '再下一层')],
              ),
            ],
            props: const {'color': 'red'},
          ),
        ],
        tags: const ['t1', 't2'],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final roundTrip = NoteBlockDoc.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.body, hasLength(2));
      expect(roundTrip.body[1].children, hasLength(2));
      expect(roundTrip.body[1].children[1].text, '孙项');
      expect(roundTrip.body[1].children[1].children.single.text, '再下一层');
      expect(roundTrip.tags, ['t1', 't2']);
      expect(roundTrip, original);
    });

    test('既有宽容语义未被收紧：缺 body / 畸形块仍按原样降级', () {
      final doc = NoteBlockDoc.fromJson({
        'id': 'doc-x',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'body': [
          _block('ok'),
          'not-a-map',
          42,
        ],
      });
      expect(doc.body, hasLength(1));
      expect(doc.body.single.id, 'ok');

      final noBody = NoteBlockDoc.fromJson({
        'id': 'doc-y',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(noBody.body, isEmpty);
      expect(noBody.hasBlocks, isFalse);
    });
  });
}

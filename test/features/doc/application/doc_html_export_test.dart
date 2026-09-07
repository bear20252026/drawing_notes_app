// HTML 导出（doc_html_export.dart）单测：
// XSS 转义（<script> 注入 / 属性引号 / & 符号）/ 中文保留 / 空标题回退 /
// 空段落 / 标题层级钳制 / 嵌套子块递归。

import 'package:drawing_notes_app/features/doc/application/doc_html_export.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:flutter_test/flutter_test.dart';

NoteBlockDoc _doc(
  String title,
  List<NoteBlock> body, {
  String id = 'd',
}) =>
    NoteBlockDoc(
      id: id,
      title: title,
      body: body,
      createdAt: DateTime(2026, 9, 7),
      updatedAt: DateTime(2026, 9, 7),
    );

void main() {
  group('escapeHtml 转义', () {
    test('<script> 注入：标签符号全部转义，无原始标签残存', () {
      final out = escapeHtml('<script>alert(1)</script>');

      expect(out, '&lt;script&gt;alert(1)&lt;/script&gt;');
      expect(out, isNot(contains('<script')));
      expect(out, isNot(contains('</script')));
    });

    test('属性引号转义：双引号变 &quot;（防属性逃逸）', () {
      expect(escapeHtml('onload="x"'), 'onload=&quot;x&quot;');
      expect(escapeHtml("'"), "'", reason: '单引号不在转义集内（双引号属性场景安全）');
    });

    test('& 符号最先转义：不产生双转义', () {
      // '&' 必须在其他实体替换之前处理，否则 '&amp;' 会变成 '&amp;amp;'。
      expect(escapeHtml('a & b'), 'a &amp; b');
      expect(escapeHtml('&lt;'), '&amp;lt;');
      expect(escapeHtml('a<b>c&d"e>f'), 'a&lt;b&gt;c&amp;d&quot;e&gt;f');
    });

    test('中文与常规字符原样保留', () {
      const raw = '你好，画板笔记 Hello World 123！';
      expect(escapeHtml(raw), raw);
    });
  });

  group('noteBlockDocToHtml 文档级导出', () {
    test('标题中的 <script> 注入被转义（<title> 与 <h1> 双处）', () {
      final html = noteBlockDocToHtml(
        _doc('<script>alert("标题注入")</script>', const []),
      );

      expect(html, isNot(contains('<script')));
      expect(html, contains('&lt;script&gt;'));
      // <title> 与 <h1> 两处都已消毒。
      expect(html.indexOf('&lt;script&gt;'), isNonNegative);
      expect(html, contains('<h1>&lt;script&gt;'));
    });

    test('正文文本转义：引号与 & 均消毒，中文保留', () {
      final html = noteBlockDocToHtml(_doc('转义测试', [
        NoteBlock.textBlock('p1', text: '引用 "词" 与 & 符号 —— 中文内容'),
      ]));

      expect(html, contains('&quot;词&quot;'));
      expect(html, contains('&amp; 符号'));
      expect(html, contains('中文内容'));
      expect(html, isNot(contains('"词"')));
    });

    test('空标题回退为「未命名」（转义路径一致）', () {
      final html = noteBlockDocToHtml(_doc('   ', const []));

      expect(html, contains('<title>未命名</title>'));
      expect(html, contains('<h1>未命名</h1>'));
    });

    test('空文本段落渲染为 <p><br></p>；非空段落为普通 <p>', () {
      final html = noteBlockDocToHtml(_doc('段落', [
        NoteBlock.textBlock('empty', text: ''),
        NoteBlock.textBlock('filled', text: '有内容'),
      ]));

      expect(html, contains('<p><br></p>'));
      expect(html, contains('<p>有内容</p>'));
    });

    test('标题层级钳制到 1-6；代码块用 <pre><code> 包裹', () {
      final html = noteBlockDocToHtml(_doc('层级', [
        NoteBlock(id: 'h9', type: NoteBlockType.heading, text: '越界层级', props: {
          'level': 99,
        }),
        NoteBlock(id: 'h0', type: NoteBlockType.heading, text: '零级', props: {
          'level': 0,
        }),
        NoteBlock(id: 'hno', type: NoteBlockType.heading, text: '缺省层级'),
        NoteBlock.codeBlock('c1', text: 'x < y'),
      ]));

      expect(html, contains('<h6>越界层级</h6>'));
      expect(html, contains('<h1>零级</h1>'));
      expect(html, contains('<h1>缺省层级</h1>'));
      expect(html, contains('<pre><code>x &lt; y</code></pre>'));
    });

    test('嵌套子块递归导出（父块之后紧跟子块）', () {
      final html = noteBlockDocToHtml(_doc('嵌套', [
        NoteBlock(
          id: 'parent',
          type: NoteBlockType.bullet,
          text: '父项',
          children: [
            NoteBlock(id: 'child', type: NoteBlockType.bullet, text: '子项'),
          ],
        ),
      ]));

      final parent = html.indexOf('<li>父项</li>');
      final child = html.indexOf('<li>子项</li>');
      expect(parent, isNonNegative);
      expect(child, greaterThan(parent), reason: '子块渲染在父块之后');
    });

    test('待办块勾选态差异：checked 带禁用勾选框与删除线', () {
      final html = noteBlockDocToHtml(_doc('待办', [
        NoteBlock.todoBlock('done', text: '已完成', checked: true),
        NoteBlock.todoBlock('open', text: '未完成', checked: false),
      ]));

      expect(html, contains('<input type="checkbox" disabled checked>'));
      expect(html, contains('<s>已完成</s>'));
      expect(html, contains('<input type="checkbox" disabled> '));
      expect(html, isNot(contains('<s>未完成</s>')));
    });
  });
}

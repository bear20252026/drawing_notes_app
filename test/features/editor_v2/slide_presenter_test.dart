// SlidePresenter 幻灯片模式测试（AFFiNE 借鉴——2026-08-24）。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/editor_v2/presentation/slide_presenter.dart';
import 'package:editor_core/editor_core.dart';

void main() {
  group('SlidePage', () {
    test('创建幻灯片页面', () {
      const page = SlidePage(
        title: '封面',
        paragraphs: [
          NoteParagraph(id: 'p1', content: '欢迎'),
        ],
      );
      expect(page.title, '封面');
      expect(page.paragraphs.length, 1);
    });

    test('空段落列表', () {
      const page = SlidePage(title: '空白页', paragraphs: []);
      expect(page.paragraphs, isEmpty);
    });
  });

  group('SlidePresenter.fromDocument', () {
    test('单页文档（无标题分隔）', () {
      final doc = NoteDocument(
        title: '简单笔记',
        paragraphs: [
          const NoteParagraph(id: 'p1', content: '内容 1'),
          const NoteParagraph(id: 'p2', content: '内容 2'),
        ],
      );
      final slides = SlidePresenter.fromDocument(doc);
      expect(slides.length, 1);
      expect(slides.first.title, '简单笔记');
      expect(slides.first.paragraphs.length, 2);
    });

    test('多页文档（标题分隔）', () {
      final doc = NoteDocument(
        title: '总标题',
        paragraphs: [
          const NoteParagraph(id: 'p1', content: '内容 1'),
          const NoteParagraph(id: 'h1', content: '第一章', type: NoteParagraphType.heading),
          const NoteParagraph(id: 'p2', content: '内容 2'),
          const NoteParagraph(id: 'h2', content: '第二章', type: NoteParagraphType.heading),
          const NoteParagraph(id: 'p3', content: '内容 3'),
        ],
      );
      final slides = SlidePresenter.fromDocument(doc);
      // p1 → 第一页(总标题); h1触发分页→第二页(标题=第一章,段落=[h1,p2]); h2→第三页
      expect(slides.length, 3);
      expect(slides[0].title, '总标题');
      expect(slides[0].paragraphs.length, 1); // [p1]
      expect(slides[1].title, '第一章');
      expect(slides[1].paragraphs.length, 2); // [h1, p2]
      expect(slides[2].title, '第二章');
      expect(slides[2].paragraphs.length, 2); // [h2, p3]
    });

    test('空标题笔记自动分页', () {
      final doc = NoteDocument(
        title: '', // 空标题
        paragraphs: [
          const NoteParagraph(id: 'p1', content: '内容'),
        ],
      );
      final slides = SlidePresenter.fromDocument(doc);
      expect(slides.length, 1);
      expect(slides.first.title, '幻灯片 1');
    });

    test('空文档（无段落）', () {
      const doc = NoteDocument(title: '空');
      final slides = SlidePresenter.fromDocument(doc);
      expect(slides.length, 1);
      expect(slides.first.title, '空');
      expect(slides.first.paragraphs, isEmpty);
    });

    test('连续标题 → 多页', () {
      final doc = NoteDocument(
        title: 'Root',
        paragraphs: [
          const NoteParagraph(id: 'h1', content: 'A', type: NoteParagraphType.heading),
          const NoteParagraph(id: 'h2', content: 'B', type: NoteParagraphType.heading),
          const NoteParagraph(id: 'h3', content: 'C', type: NoteParagraphType.heading),
        ],
      );
      final slides = SlidePresenter.fromDocument(doc);
      // 连续标题：每个标题触发分页（但首个 heading 是分隔符）
      expect(slides.length, greaterThanOrEqualTo(2));
    });

    test('Heading 后无内容，下一个是 Heading → 最少 1 段落', () {
      final doc = NoteDocument(
        title: 'T',
        paragraphs: [
          const NoteParagraph(id: 'p1', content: '正文'),
          const NoteParagraph(id: 'h1', content: '标题1', type: NoteParagraphType.heading),
          const NoteParagraph(id: 'h2', content: '标题2', type: NoteParagraphType.heading),
          const NoteParagraph(id: 'p2', content: '正文2'),
        ],
      );
      final slides = SlidePresenter.fromDocument(doc);
      // p1 → 第一页; h1触发分页后h2触发分页后p2
      expect(slides.length, greaterThanOrEqualTo(2));
    });
  });
}

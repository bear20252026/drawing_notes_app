// 全文搜索补充测试：
// 1) 混合匹配正确性 —— 中文子串、仅标题、仅 OCR 命中（倒排分词覆盖不到的场景）；
// 2) 性能基准 —— 1000 笔记单次检索 <100ms（任务验收指标）。
//
// 说明：倒排索引按空白/标点分词，中文句子会整体成 token，
// 因此「今天天气真好」用「天气」查询必须走子串扫描兜底。
import 'dart:math';

import 'package:drawing_notes_app/core/search/search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('混合匹配：中文子串 / 标题 / OCR 兜底', () {
    test('中文正文子串命中（倒排整句分词无法覆盖的场景）', () {
      final index = SearchIndex();
      index.indexDocument(
        docId: 'd1',
        title: '日记',
        text: '今天天气真好，我们去公园散步。',
      );

      final hits = index.search('天气');
      expect(hits, isNotEmpty, reason: '中文子串必须可搜');
      expect(hits.first.noteId, 'd1');
      expect(hits.first.matchedText.contains('天气'), isTrue);
    });

    test('仅标题命中的文档出现在结果中（画作标题检索场景）', () {
      final index = SearchIndex();
      index.indexDocument(docId: 'drawing-x', title: '购物清单草图', text: '');

      final hits = index.search('清单');
      expect(hits, isNotEmpty);
      expect(hits.first.noteId, 'drawing-x');
    });

    test('仅 OCR 命中的文档可见且标记 isOcrMatch（手写搜索）', () {
      final index = SearchIndex();
      index.indexDocument(
        docId: 'p1',
        title: '会议记录',
        text: '正文只有打印体内容。',
        ocrText: '手写批注：明天交报告',
      );

      final hits = index.search('交报告');
      expect(hits, isNotEmpty, reason: '纯 OCR 命中必须可达');
      expect(hits.first.noteId, 'p1');
      expect(hits.first.isOcrMatch, isTrue);
    });

    test('正文与 OCR 同时命中时优先正文片段', () {
      final index = SearchIndex();
      index.indexDocument(
        docId: 'p2',
        title: 'T',
        text: 'apple pie recipe',
        ocrText: 'apple handwriting',
      );

      final hits = index.search('apple');
      expect(hits, hasLength(1));
      expect(hits.first.isOcrMatch, isFalse);
      expect(hits.first.matchedText.toLowerCase(), contains('pie'));
    });

    test('拉丁多词 AND 语义不回归', () {
      final index = SearchIndex();
      index.indexDocument(docId: 'a', title: 'A', text: 'hello brave new world');
      index.indexDocument(docId: 'b', title: 'B', text: 'hello world');

      expect(
        index.search('hello world').map((r) => r.noteId),
        containsAll(['a', 'b']),
      );
      expect(index.search('brave world').map((r) => r.noteId), ['a']);
    });

    test('removeDocument 后子串不再命中', () {
      final index = SearchIndex();
      index.indexDocument(docId: 'd9', title: 'x', text: '独特关键词abc');
      expect(index.search('独特关键'), isNotEmpty);

      index.removeDocument('d9');
      expect(index.search('独特关键'), isEmpty);
    });

    test('空查询与纯空白查询返回空', () {
      final index = SearchIndex();
      index.indexDocument(docId: 'd', title: 't', text: 'some text');
      expect(index.search(''), isEmpty);
      expect(index.search('   '), isEmpty);
    });
  });

  group('性能基准：1000 笔记检索 <100ms', () {
    test('1000 篇混合中英文笔记，所有查询均低于 100ms', () {
      final rnd = Random(42); // 固定种子保证可复现
      const noteCount = 1000;
      final index = SearchIndex();

      const cjkWords = [
        '天气', '会议纪要', '设计稿', '手写笔记', '购物清单',
        '项目计划', '灵感速记', '读书摘记', '周报总结', '待办事项',
      ];
      const latinWords = [
        'meeting', 'design', 'sketch', 'handwriting', 'plan',
        'review', 'todo', 'summary', 'project', 'idea',
      ];

      for (var i = 0; i < noteCount; i++) {
        final sb = StringBuffer();
        for (var j = 0; j < 40; j++) {
          sb.write(
            rnd.nextBool()
                ? cjkWords[rnd.nextInt(cjkWords.length)]
                : latinWords[rnd.nextInt(latinWords.length)],
          );
          // 中英混排、部分无空格分隔，模拟真实手写/输入文本。
          sb.write(rnd.nextBool() ? ' ' : '');
        }
        index.indexDocument(
          docId: 'nb:nb$i|pg$i', // 与 SearchDocIds.notebook 编码一致
          title: '笔记本 ${i % 50} / 页面 $i',
          text: sb.toString(),
        );
      }
      expect(index.documentCount, noteCount);

      // JIT 预热（不计入测量）。
      index.search('天气');
      index.search('meeting');

      const queries = [
        '天气', '会议', '手写', '购物清单', '读书摘记',
        'meeting', 'handwriting', 'todo summary', '不存在的查询词zzz',
        '页面 777',
      ];
      var slowest = 0;
      var slowestQuery = '';
      for (final q in queries) {
        final sw = Stopwatch()..start();
        index.search(q);
        sw.stop();
        if (sw.elapsedMilliseconds > slowest) {
          slowest = sw.elapsedMilliseconds;
          slowestQuery = q;
        }
      }

      // 验收指标：目标 <100ms / 1000 笔记。
      // ignore: avoid_print
      print('搜索基准：$noteCount 篇笔记 · ${queries.length} 次查询 · 最慢 ${slowest}ms');
      expect(slowest, lessThan(100),
          reason: '查询「$slowestQuery」耗时 ${slowest}ms，超出 100ms 目标');
    });
  });
}

// CUJ-01 契约的**执行侧**（TST2-04，第四轮台账 §23 判「成立」那条）。
//
// `integration_test/contracts/cuj01.json` 声明了五条断言名，`cuj_01_test.dart:106-107`
// 的注释声称它们「由真实存储往返验证」——但**全仓没有任何代码读那份 json**（`grep cuj01.json`
// 只命中那句注释本身）。集成用例那边能给的是 `painter isNotNull`，而画布只要装配了就有
// painter，与笔画有没有保留无关 ⇒ 恒真断言 + 空承诺，正是 §4 第 1 条的形状。
//
// 本文件把声明变成执行：走真实 `StorageService`（临时数据根）save → load，**按 json 里的名字**
// 逐条跑。两侧名字必须完全相等：
//  · json 加一条没实现的名字 ⇒ 红（声明不能悬空）；
//  · 本文件实现一条 json 没声明的名字 ⇒ 也红（免得判据又出现第二份真相）。
// 集成侧那条恒真断言**没有**在这里顺手改：它只有真机能跑、CI 从不跑 `integration_test`，
// 改完无法当场验证 ⇒ 按口径留给业主决定（台账 §28 记着）。
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir_cleanup.dart';

const String _contractPath = 'integration_test/contracts/cuj01.json';

/// 固定种子的笔画：往返比较不该被手绘抖动随机源牵动。
Stroke _stroke(String id, List<List<double>> xy) => Stroke(
  id: id,
  points: [for (final p in xy) StrokePoint(p[0], p[1], 1.0)],
  color: const Color(0xFF101010),
  width: 3,
  type: BrushType.pen,
  seed: 12345,
);

/// 「绘制完成」那一版：三条笔画（最后一条是返回前补画的那笔）。
DrawingDocument _document(DateTime updatedAt, {String id = 'cuj01_doc'}) =>
    DrawingDocument(
      id: id,
      title: 'CUJ-01 画作',
      width: 320,
      height: 240,
      createdAt: DateTime.utc(2026, 10, 17, 3),
      updatedAt: updatedAt,
      layers: [
        Layer(
          id: 'layer_1',
          name: '',
          strokes: [
            _stroke('str_cuj_a', [
              [10, 10],
              [22, 15],
              [30, 40],
            ]),
            _stroke('str_cuj_b', [
              [50, 60],
              [70, 66],
              [92, 88],
              [110, 120],
            ]),
            _stroke('str_cuj_c', [
              [200, 30],
              [210, 45],
            ]),
          ],
        ),
      ],
    );

/// 点集包围盒（`[minX, minY, maxX, maxY]`，用 double 列表比，避免 Rect 相等性依赖实现细节）。
List<double> _box(Stroke s) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final p in s.points) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  return [minX, minY, maxX, maxY];
}

List<String> _ids(DrawingDocument d) => [
  for (final l in d.layers)
    for (final s in l.strokes) s.id,
];

List<int> _pointCounts(DrawingDocument d) => [
  for (final l in d.layers)
    for (final s in l.strokes) s.points.length,
];

List<List<double>> _boxes(DrawingDocument d) => [
  for (final l in d.layers)
    for (final s in l.strokes) _box(s),
];

/// 落盘-重开一次的结果。
class _Trip {
  _Trip({
    required this.saved,
    required this.reloaded,
    required this.revisionFirstSave,
    required this.revisionSecondSave,
  });

  final DrawingDocument saved; // 最后一次落盘的那版
  final DrawingDocument reloaded; // 重开读到的
  final int revisionFirstSave;
  final int revisionSecondSave;
}

/// 真实存储路径往返：存 → 改一笔再存 → **换一个 StorageService 实例**读回。
///
/// 换实例是照 json 里那五步的 `terminate` + `reopen` 来的：同一个实例读自己刚写的东西
/// 可能命中进程内缓存，那就不叫「重开」。顺带也就钉住了「返回值确实是盘上读回来的，
/// 不是把我手里那个对象原样递回去」。
Future<_Trip> _roundTrip(Directory dir, {String id = 'cuj01_doc'}) async {
  final storage = StorageService(directoryProvider: () async => dir);
  final first = _document(DateTime.utc(2026, 10, 17, 4), id: id);
  await storage.save(first);
  // 本仓 revision 口径 = `doc.updatedAt` 毫秒（storage_service.dart:159，取在 save 之前）。
  final revisionFirstSave = first.updatedAt.millisecondsSinceEpoch;

  final second = _document(DateTime.utc(2026, 10, 17, 4, 30), id: id);
  await storage.save(second);
  final revisionSecondSave = second.updatedAt.millisecondsSinceEpoch;

  final reopened = StorageService(directoryProvider: () async => dir);
  final reloaded = await reopened.load(id);
  expect(reloaded, isNotNull, reason: '重开读不到自己刚存的两版 ⇒ 下面五条无从谈起');
  expect(
    identical(reloaded, second),
    isFalse,
    reason: '读回来的必须是另一个对象图，否则「往返」是自说自话',
  );
  expect(
    identical(reloaded!.layers.first, second.layers.first),
    isFalse,
    reason: '连 Layer 都还是同一个实例 ⇒ 根本没经过磁盘',
  );
  return _Trip(
    saved: second,
    reloaded: reloaded,
    revisionFirstSave: revisionFirstSave,
    revisionSecondSave: revisionSecondSave,
  );
}

/// 声明名 → 执行体。名字与 json 的 `assertions` 一一对应。
final Map<String, void Function(_Trip t)> _checks = {
  'same_document_id': (t) => expect(t.reloaded.id, t.saved.id),
  'same_stroke_id': (t) => expect(_ids(t.reloaded), _ids(t.saved)),
  'same_point_count': (t) {
    expect(_pointCounts(t.reloaded), _pointCounts(t.saved));
    expect(
      _pointCounts(t.reloaded).fold<int>(0, (a, b) => a + b),
      9,
      reason: '三条笔画各 3/4/2 点：总数也要对上，不是只比长度序列',
    );
  },
  'same_bounds': (t) {
    expect(
      [t.reloaded.width, t.reloaded.height],
      [t.saved.width, t.saved.height],
    );
    expect(_boxes(t.reloaded), _boxes(t.saved));
  },
  'revision_increases_once': (t) {
    // 两次保存各推进一次（不跳两格、不原地不动），重开读到的是最后一版的 revision。
    expect(t.revisionSecondSave, greaterThan(t.revisionFirstSave));
    expect(
      t.reloaded.updatedAt.millisecondsSinceEpoch,
      t.revisionSecondSave,
      reason: '重开后读到的必须是最后一次落盘那一版的时间戳',
    );
  },
};

List<String> _declaredAssertions() {
  final file = File(_contractPath);
  // 「清单读不出来」不许答成「没有要求」——本仓头号复发族（§4 第 1 条）。
  expect(file.existsSync(), isTrue, reason: '$_contractPath 不见了：声明侧与执行侧会同时瞎');
  final map =
      jsonDecode(utf8.decode(file.readAsBytesSync())) as Map<String, dynamic>;
  return [for (final a in (map['assertions'] as List)) a as String];
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cuj01_contract');
  });
  tearDown(() async {
    if (tempDir.existsSync()) await deleteTempDirWithRetry(tempDir);
  });

  test('分母：契约清单读得出、条目数没塌', () {
    final declared = _declaredAssertions();
    expect(
      declared.length,
      greaterThanOrEqualTo(5),
      reason: 'cuj01.json 声明五条断言；读出个位数以下说明文件被改坏或被清空（空清单=恒过）',
    );
  });

  test('CUJ-01 契约：声明侧与执行侧名字集合完全相等', () {
    final declared = _declaredAssertions().toSet();
    expect(
      _checks.keys.toSet(),
      declared,
      reason:
          'json 里有而本文件没实现 ⇒ 那句注释是空承诺；本文件实现了而 json 没声明 ⇒ '
          '判据又长了第二份真相。两个方向都要红。',
    );
  });

  test('CUJ-01 契约：真实存储往返按声明的名字逐条跑', () async {
    final trip = await _roundTrip(tempDir);
    for (final name in _checks.keys) {
      _checks[name]!(trip);
    }
  });

  test('自证：五条断言各能被对应的那一种破坏抓到（执行体不许恒过）', () async {
    // 每条断言配一个**只破坏它**的现场。少了这条，`_checks` 里任何一句写成恒真都不会被发现
    // ——那正是 cuj_01_test 那条 `painter isNotNull` 的复发形状。
    Future<void> check(String name, Future<_Trip> broken) async {
      final t = await broken;
      expect(
        () => _checks[name]!(t),
        throwsA(isA<TestFailure>()),
        reason: '$name 抓不到对应的破坏 ⇒ 这条执行体是空的',
      );
    }

    Future<_Trip> fresh({String id = 'cuj01_doc'}) =>
        _roundTrip(tempDir, id: id);
    final trip = await fresh();
    final other = await fresh(id: 'cuj01_other');

    // ① 身份：换成另一篇文档的落盘结果。
    await check('same_document_id', () async {
      final x = await fresh();
      return _Trip(
        saved: x.saved,
        reloaded: other.reloaded,
        revisionFirstSave: x.revisionFirstSave,
        revisionSecondSave: x.revisionSecondSave,
      );
    }());

    // ② 笔画 id：少一条笔画。
    await check('same_stroke_id', () async {
      final x = await fresh();
      x.reloaded.layers.first.strokes.removeLast();
      return x;
    }());

    // ③ 点数：某条笔画少一个采样点。
    await check('same_point_count', () async {
      final x = await fresh();
      x.reloaded.layers.first.strokes.first.points.removeLast();
      return x;
    }());

    // ④ 包围盒：**点数保持不变**、只挪动一个坐标——证明 same_bounds 不是 same_point_count 的附赠。
    await check('same_bounds', () async {
      final x = await fresh();
      x.reloaded.layers.first.strokes.first.points[0] = const StrokePoint(
        9999,
        9999,
        1.0,
      );
      return x;
    }());

    // ⑤ revision 两半：两次保存给出同一个 revision（保存没推进），
    //    以及读回来的不是最后一版的时间戳（盘上落后一版）。
    await check(
      'revision_increases_once',
      Future.value(
        _Trip(
          saved: trip.saved,
          reloaded: trip.reloaded,
          revisionFirstSave: trip.revisionFirstSave,
          revisionSecondSave: trip.revisionFirstSave,
        ),
      ),
    );
    await check(
      'revision_increases_once',
      Future.value(
        _Trip(
          saved: trip.saved,
          reloaded: _document(DateTime.utc(2026, 10, 17, 4)),
          revisionFirstSave: trip.revisionFirstSave,
          revisionSecondSave: trip.revisionSecondSave,
        ),
      ),
    );
  });
}

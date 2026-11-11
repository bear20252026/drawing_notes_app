// 由 Claude 团队生成 | Drawing Notes App

/// CTL-03 解锁第②步的门禁（2026-11）。
///
/// 一句话：`--obfuscate` 之前，`lib/` 的**落盘路径**上不允许再读枚举的 `.name`，
/// 也不允许 `values.byName()`。理由与第①步（`error_code_coverage_gate_test.dart`）
/// 同源：Flutter 文档对枚举的原话是「Enum names are not obfuscated **currently**」
/// ——"currently" 不是承诺；而 `flutter test` 与 `-d windows` 的 smoke 跑的都是
/// **非混淆**编译 ⇒ 这类失效 CI 天生看不见，只有装到用户机器上才现形。
///
/// ## 判据分两层
///
/// **契约层**（第一组）：每个落盘枚举都实现 [WireEnum]，`wireName` 与今天的
/// `.name` 逐字相同，且 `wireEnumOf` 往返成立。wire 名等于现格式 ⇒ 磁盘零迁移，
/// 这条相等关系就是「零迁移」的自我证明——哪天有人改了 wire 名，这里当场红。
///
/// **源码层**（第二组起）：`lib/` 里五种「落盘形状」不许再出现。
/// 为什么是源码判据而不是行为判据：落盘形状散在 14 处 encode + 4 处 prefs 里，
/// 行为测试只能覆盖「今天写到的那条路」，而回归恰恰长在新写的那条路上。
///
/// ## 为什么有一份「非枚举接收者」名单
///
/// `.name` 这个形状在 Dart 里同时被**枚举**和 **String 属性**使用
/// （`Tag.name` / `NoteField.name` / `File.name` / `Layer.name`…），门禁分不出类型。
/// 名单把「今天已逐个核过不是枚举」的那几处钉住，其余同名形状一律红——
/// 名单里每一条都必须写理由，加了就等于宣称「这处可以读标识符」。
///
/// ## 不在本门禁管辖内的
///
/// `toString()` / 异常 message / 日志里的 `${x.name}` 属于**展示面**：混淆后它变成
/// 随机串只是不好看，不会让数据读不回来。那是 CTL-03 ① 的同类问题（诊断面），
/// 有意留给 ① 的判据与台账，本门禁不重复管。
library;

import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/all_doc.dart' show AllDocKind;
import 'package:drawing_notes_app/core/canvas_model/document.dart' show PaperType;
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart'
    show ChartType;
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart'
    show FillStyle, ShapeType, StrokeStyle;
import 'package:drawing_notes_app/core/canvas_model/stroke.dart' show BrushType;
import 'package:drawing_notes_app/core/canvas_model/text_item.dart'
    show TextAlignType;
import 'package:drawing_notes_app/core/documents/note_attachment.dart'
    show AttachmentKind;
import 'package:drawing_notes_app/core/documents/note_block.dart'
    show NoteBlockType;
import 'package:drawing_notes_app/core/theme/app_design.dart'
    show themeModeFromWire, themeModeWire;
import 'package:drawing_notes_app/core/utils/single_instance.dart'
    show SingleInstanceStatus;
import 'package:drawing_notes_app/core/utils/wire_enum.dart';
import 'package:drawing_notes_app/features/doc/domain/note_database.dart'
    show DatabaseViewType, NoteFieldType;
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart'
    show EraserMode;
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart'
    show EncryptionMode;
import 'package:drawing_notes_app/features/notes/domain/page_template.dart'
    show PageTemplate;

// ==== 登记簿 ====

/// 落盘枚举登记簿：`(枚举名, values)`。
///
/// 名单即判据的一部分——**新增落盘枚举必须同时进这里**，否则「它有没有 wire 名」
/// 这件事没有人判。最后那条「源码对账」判据会强制这件事。
List<(String, List<WireEnum>)> persistedEnums() => [
  ('ShapeType', ShapeType.values),
  ('StrokeStyle', StrokeStyle.values),
  ('FillStyle', FillStyle.values),
  ('PaperType', PaperType.values),
  ('TextAlignType', TextAlignType.values),
  ('BrushType', BrushType.values),
  ('ChartType', ChartType.values),
  ('AttachmentKind', AttachmentKind.values),
  ('NoteBlockType', NoteBlockType.values),
  ('EncryptionMode', EncryptionMode.values),
  ('PageTemplate', PageTemplate.values),
  ('NoteFieldType', NoteFieldType.values),
  ('DatabaseViewType', DatabaseViewType.values),
  ('EraserMode', EraserMode.values),
  ('AllDocKind', AllDocKind.values),
  ('SingleInstanceStatus', SingleInstanceStatus.values),
];

/// 所有 [WireEnum] 实现者都是 `enum`（接口不能是别的形态），所以这里取 `.name`
/// 是安全的——它读的是**改造前那套名字**，用来与 wire 名逐字对账。
String _sourceName(WireEnum value) => (value as Enum).name;

// ==== 非枚举接收者名单 ====

/// 已逐个核过**不是枚举**的 `.name` 接收者（每条都要写理由）。
///
/// 不写理由的条目会被下面的「名单自证」判据拦下——名单不能变成
/// 「看不清就先放行」的地方。
const Map<String, String> _nonEnumReceivers = {
  'f': 'File.name（备份条目的文件名）与 NoteField.name（字段名），都不是枚举',
  't': 'Tag.name（标签名），不是枚举',
};

// ==== 扫描器 ====

/// 注释行不算命中（trap 56 那一族：文档注释里写着同形文本是在**解释**）。
final RegExp _comment = RegExp(r'^\s*(//|///|\*)');

/// 形状一：`values.byName(...)` —— 混淆后必炸的 API，没有第二种解释。
final RegExp _byName = RegExp(r'\.byName\s*\(');

/// 形状二：`setString(key, x.name)` —— prefs 写入仍由标识符派生。
final RegExp _prefsWrite = RegExp(r'setString\([^)]*\.name\b');

/// 形状三：map 字面量的**值**位置放 `.name` —— JSON 编码仍由标识符派生。
/// （键位置不算：`'name': x` 是字段名叫 name，不是读 `.name`。）
final RegExp _mapValue = RegExp(r"'[^']+'\s*:\s*([A-Za-z_][\w.]*)\.name\b");

/// 形状四：拿 `.name` 与原始串比较 —— 解码仍由标识符派生。
final RegExp _nameCompare = RegExp(r'([A-Za-z_][\w.]*)\.name\s*==');

/// 形状五：枚举 map 的**键**仍由 `.name` 派生（`for (final x in X.values) x.name: …`）。
final RegExp _nameKey = RegExp(r'\.name\s*:');

/// 扫 `lib/`（或自证用的合成源）。返回 `(位置, 行文本, 接收者或 null)`。
///
/// 接收者只对形状三/四有意义（它们带捕获组）；其余形状返回 null。
List<(String, String, String?)> _scan([Map<String, String>? sources]) {
  final hits = <(String, String, String?)>[];
  void scan(String label, String line) {
    if (_comment.hasMatch(line)) return;
    if (_byName.hasMatch(line) ||
        _prefsWrite.hasMatch(line) ||
        _nameKey.hasMatch(line)) {
      hits.add((label, line, null));
      return;
    }
    for (final re in <RegExp>[_mapValue, _nameCompare]) {
      final m = re.firstMatch(line);
      if (m != null) {
        hits.add((label, line, m.group(1)));
        return;
      }
    }
  }

  if (sources != null) {
    sources.forEach((file, text) {
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        scan('$file:${i + 1}', lines[i]);
      }
    });
    return hits;
  }
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      scan('${entity.path.replaceAll(r'\', '/')}:${i + 1}', lines[i]);
    }
  }
  return hits;
}

/// 全量命中（**不**过名单）——分母下限用，防「扫描器抽塌后空集通过」。
List<(String, String, String?)> rawNameReads([Map<String, String>? sources]) =>
    _scan(sources);

/// 判据命中 = 全量 − 已核过不是枚举的那几处。
List<(String, String)> forbiddenNameReads([
  Map<String, String>? sources,
]) => [
  for (final (label, line, receiver) in _scan(sources))
    if (receiver == null || !_nonEnumReceivers.containsKey(receiver))
      (label, line),
];

/// 从 `lib/` 源码里抽 `enum X implements WireEnum`，与登记簿对账。
List<String> declaredWireEnums() {
  final out = <String>[];
  final decl = RegExp(r'^enum\s+(\w+)\s+implements\s+WireEnum\b');
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final line in entity.readAsLinesSync()) {
      final m = decl.firstMatch(line);
      if (m != null) out.add(m.group(1)!);
    }
  }
  return out..sort();
}

/// 登记簿里缺 `wireName` 的枚举（防「加了枚举忘加 getter」——漏一个取值
/// 编译器会拦，但整个枚举一个 getter 都没写时编译器只会说 `@override` 无效）。
List<String> missingWireNameGetter() {
  final out = <String>[];
  for (final (name, _) in persistedEnums()) {
    // `values` 的静态类型是 `List<WireEnum>`，能编译过就说明 `implements` 在；
    // 这里再从源码侧确认 getter 存在，避免「接口在、getter 被删」。
    final declared = File('lib/${_pathOfEnum(name)}');
    if (!declared.existsSync() ||
        !declared.readAsLinesSync().any((l) => l.contains('String get wireName'))) {
      out.add(name);
    }
  }
  return out;
}

/// 枚举 → 声明文件（只覆盖本登记簿里这 16 个，实测路径）。
///
/// 用查表而不是全局搜索：本仓 `lib/` 里 `enum X` 的声明行格式统一，
/// 但同名前缀（`NoteBlockType` vs `NoteBlock`）会让宽松搜索对错人。
String _pathOfEnum(String name) => switch (name) {
  'ShapeType' ||
  'StrokeStyle' ||
  'FillStyle' => 'core/canvas_model/shape_item.dart',
  'PaperType' => 'core/canvas_model/document.dart',
  'TextAlignType' => 'core/canvas_model/text_item.dart',
  'BrushType' => 'core/canvas_model/stroke.dart',
  'ChartType' => 'core/canvas_model/page_chart_item.dart',
  'AllDocKind' => 'core/all_doc.dart',
  'SingleInstanceStatus' => 'core/utils/single_instance.dart',
  'AttachmentKind' => 'core/documents/note_attachment.dart',
  'NoteBlockType' => 'core/documents/note_block.dart',
  'EraserMode' => 'features/drawing/application/eraser_mode.dart',
  'EncryptionMode' => 'features/notes/domain/notebook_entity.dart',
  'PageTemplate' => 'features/notes/domain/page_template.dart',
  'NoteFieldType' || 'DatabaseViewType' => 'features/doc/domain/note_database.dart',
  _ => throw StateError('登记簿里的 $name 没有对应路径'),
};

void main() {
  group('分母下限（扫不到就当场红，别让空集通过）', () {
    test('登记簿非空，且总量对得上（抽塌了后面几条会一起假绿）', () {
      expect(persistedEnums().length, greaterThanOrEqualTo(16));
      final total = persistedEnums().fold<int>(0, (n, e) => n + e.$2.length);
      expect(total, greaterThanOrEqualTo(50), reason: '实测 60+ 个取值');
    });

    test('扫描器真的在 `lib/` 里扫到了东西（放过名单后仍剩 3 处良性命中）', () {
      // 实测 2026-11：`t.name ==` × 2（Tag）+ `{'entry': f.name}` × 1（File）。
      expect(rawNameReads().length, greaterThanOrEqualTo(3));
      expect(forbiddenNameReads(), isEmpty);
    });

    test('源码对账：`lib/` 里每个 implements WireEnum 的枚举都登记在册', () {
      final declared = declaredWireEnums();
      expect(declared, isNotEmpty, reason: '抽取失效 ⇒ 下一条会假绿');
      expect(
        declared.toSet(),
        persistedEnums().map((e) => e.$1).toSet(),
        reason: '两边对不上 = 有人新加了落盘枚举却没进登记簿'
            '（或登记簿里有已删的枚举）：$declared',
      );
    });
  });

  group('契约层：每个落盘枚举都能按 wire 名往返', () {
    for (final (name, values) in persistedEnums()) {
      test('$name：每个取值往返成立且 wire 名唯一', () {
        expect(values, isNotEmpty);
        final seen = <String>{};
        for (final value in values) {
          expect(value.wireName, isNotEmpty, reason: '$name 有取值的 wire 名是空的');
          expect(
            seen.add(value.wireName),
            isTrue,
            reason: '$name 的 wire 名重复：${value.wireName}'
                '（重复 = 解码时必有一个取值永远读不回来）',
          );
          expect(wireEnumOf(values, value.wireName), value);
          expect(wireEnumOfOrThrow(values, value.wireName), value);
        }
      });

      test('$name：wire 名与改造前的 .name 逐字相同（零迁移）', () {
        for (final value in values) {
          expect(
            value.wireName,
            _sourceName(value),
            reason: '$name.${_sourceName(value)} 的 wire 名与 .name 不一致'
                ' ⇒ 磁盘格式变了、老文件读不回来（CTL-03 ② 的整个前提就是不迁移）',
          );
        }
      });

      test('$name：未知 wire 名回落 null，不抛', () {
        expect(wireEnumOf(values, null), isNull);
        expect(wireEnumOf(values, ''), isNull);
        expect(wireEnumOf(values, '__definitely_not_a_wire_name__'), isNull);
      });
    }
  });

  group('ThemeMode（SDK 枚举，不能 implements，单独适配）', () {
    test('往返成立', () {
      for (final mode in ThemeMode.values) {
        expect(themeModeFromWire(themeModeWire(mode)), mode);
      }
    });

    test('wire 名与改造前的 .name 逐字相同（零迁移）', () {
      for (final mode in ThemeMode.values) {
        expect(themeModeWire(mode), mode.name);
      }
    });

    test('未知/缺失一律回落跟随系统（改造前口径逐字不变）', () {
      expect(themeModeFromWire(null), ThemeMode.system);
      expect(themeModeFromWire(''), ThemeMode.system);
      expect(themeModeFromWire('bogus'), ThemeMode.system);
    });
  });

  group('源码层：lib/ 的落盘路径不再读枚举的 .name', () {
    test('判据：五种落盘形状零命中', () {
      final bad = forbiddenNameReads();
      expect(
        bad,
        isEmpty,
        reason: '这 $bad 处在 `--obfuscate` 下会让磁盘格式变成每次构建都不同的'
            '随机串，而 CI 跑非混淆编译 ⇒ 只有装到用户机器上才发现（CTL-03）',
      );
    });

    test('名单里每条都有理由（不写理由的条目等于「看不清就放行」）', () {
      for (final entry in _nonEnumReceivers.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '接收者 ${entry.key} 进名单却不说为什么不是枚举',
        );
      }
    });

    test('登记簿里的枚举都真的写了 wireName getter', () {
      expect(missingWireNameGetter(), isEmpty);
    });
  });

  group('判据自证（抽取器与判据本身要能被突变抓到）', () {
    test('五种形状分别被抓到', () {
      expect(
        forbiddenNameReads(const {
          'a.dart': '  final x = ShapeType.values.byName(raw);\n',
        }),
        hasLength(1),
        reason: '形状一（byName）不红就等于门禁没装',
      );
      expect(
        forbiddenNameReads(const {
          'a.dart': '  await prefs.setString(key, mode.name);\n',
        }),
        hasLength(1),
        reason: '形状二（prefs 写 .name）不红就等于门禁没装',
      );
      expect(
        forbiddenNameReads(const {
          'a.dart': "  'type': type.name,\n",
        }),
        hasLength(1),
        reason: '形状三（map 值位置 .name）不红就等于门禁没装',
      );
      expect(
        forbiddenNameReads(const {
          'a.dart': '  final m = ThemeMode.values.firstWhere(\n'
              '    (m) => m.name == saved,\n'
              '    orElse: () => ThemeMode.system,\n'
              '  );\n',
        }),
        hasLength(1),
        reason: '形状四（.name 与原始串比较）不红就等于门禁没装',
      );
      expect(
        forbiddenNameReads(const {
          'a.dart': '  for (final tool in BrushType.values)\n'
              '    tool.name: forTool(tool).toJson();\n',
        }),
        hasLength(1),
        reason: '形状五（枚举 map 键用 .name）不红就等于门禁没装',
      );
    });

    test('非枚举接收者不误伤（名单存在的意义）', () {
      expect(
        forbiddenNameReads(const {
          'a.dart': '  final t = tags.firstWhere((t) => t.name == trimmed);\n'
              "  final rel = {'entry': f.name, 'size': f.size};\n",
        }),
        isEmpty,
        reason: '把 Tag.name / File.name 判红 = 名单没生效，真违规会被一起淹没',
      );
    });

    test('注释里的同形文本不误伤', () {
      expect(
        forbiddenNameReads(const {
          'a.dart': '/// 以前这里是 `mode.name`，现在走 themeModeWire(mode)。\n'
              '// `values.byName()` 在混淆后会炸，所以禁掉了。\n',
        }),
        isEmpty,
      );
    });

    test('wireName / wireEnumOf 这类正确写法不误伤', () {
      expect(
        forbiddenNameReads(const {
          'a.dart': "  'paperType': doc.paperType.wireName,\n"
              '  final t = wireEnumOf(BrushType.values, json[\'type\'] as String?)\n'
              '      ?? BrushType.pen;\n'
              '  await prefs.setString(key, themeModeWire(mode));\n',
        }),
        isEmpty,
      );
    });

    test('源码抽取器抓得到 implements WireEnum（对账判据的前提）', () {
      expect(declaredWireEnums(), containsAll(<String>['ShapeType', 'AllDocKind']));
      expect(declaredWireEnums(), isNot(contains('NoteField')));
    });
  });
}

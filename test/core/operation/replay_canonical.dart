// Spike C 的状态规范化（桌面端一侧），与网页版 `tools/replay/canonical.mjs` 同规格。
//
// 规格全文抄在下面，两端各自照它实现、不互相 import；`replay-manifest.json` 的
// `digestSpec` 是这一份的代号，任一侧改了规格就必须同时改代号，另一侧立刻变红。
//
//   行分隔符 `\n`，末尾也有一行 `\n`；字段之间用制表符 `\t`。
//   第 1 行：`spikec-1`
//   每个图层（按文档层序）：`L<TAB>layerId<TAB>visible(0|1)<TAB>opacity(f6)`
//   该层每条笔画（按层内序）：
//     `S<TAB>id<TAB>color(u32 十进制)<TAB>width(f6)<TAB>type<TAB>opacity(f6)<TAB>seed<TAB>version<TAB>versionNonce`
//   紧接该笔画的点列：每点一行 `p<TAB>x(f6)<TAB>y(f6)<TAB>pressure(f6)`
//   `P<TAB>采样点数`
//   末尾 `E`
//   摘要 = UTF-8 字节的 SHA-256 小写十六进制。
//
// 为什么要这一层：两端的落盘 JSON 本来就不可能逐字节相同（Dart 把整数宽度写成
// `2.0`，TS 写成 `2`；键序、遗留布尔、可选键的取舍也各有习惯）。Spike C 要回答的是
// 「同一条操作序列在两端重放之后，文档状态是否同一」，所以先把状态压成与编码习惯
// 无关的定长文本再取摘要——`toStringAsFixed(6)` / `toFixed(6)` 两端同规格，把
// 「数字怎么写」这个已知分歧从比较里剥掉，只留「数字是什么」。
//
// 只规范化操作集能改动的部分（图层序/可见/不透明 + 笔画）。shapes/texts/images 仍由
// 命令体系管理，本阶段不进摘要——与 `document_operation.dart` 头注释同一依据。
import 'dart:convert' show utf8;
import 'dart:ui' show Color;

import 'package:crypto/crypto.dart' as crypto;
import 'package:drawing_notes_app/core/canvas_model/document.dart';

const String digestSpec = 'spikec-1';

String canonicalState(DrawingDocument doc) {
  final lines = <String>[digestSpec];
  for (final layer in doc.layers) {
    lines.add(
      ['L', layer.id, layer.visible ? '1' : '0', _f6(layer.opacity)].join('\t'),
    );
    for (final stroke in layer.strokes) {
      lines.add(
        [
          'S',
          stroke.id,
          _argb(stroke.color).toString(),
          _f6(stroke.width),
          stroke.type.name,
          _f6(stroke.opacity),
          stroke.seed.toString(),
          stroke.version.toString(),
          stroke.versionNonce.toString(),
        ].join('\t'),
      );
      for (final point in stroke.points) {
        lines.add(
          ['p', _f6(point.x), _f6(point.y), _f6(point.pressure)].join('\t'),
        );
      }
      lines.add(['P', stroke.points.length.toString()].join('\t'));
    }
  }
  lines.add('E');
  return '${lines.join('\n')}\n';
}

String stateDigest(DrawingDocument doc) =>
    crypto.sha256.convert(utf8.encode(canonicalState(doc))).toString();

String _f6(double value) => value.toStringAsFixed(6);

/// 与网页侧 `stroke.color >>> 0` 同一口径的无符号 32 位 ARGB。
int _argb(Color color) => color.toARGB32();

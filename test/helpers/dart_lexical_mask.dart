// 门禁共用的 Dart 词法「等长遮蔽器」（P1 修复，审计 2026-10-04）。
//
// 缘起：C-06（security_static_access_gate_test）与 V-12（focus_ring_coverage
// _test）各自复制过一份注释/字符串遮蔽状态机，`_maskCommentsAndStrings` 的
// 注释声称「含转义与三引号」，实测既不认 `${...}` 插值里的嵌套引号、也不
// 真正处理三引号与 raw string：`lib/features/notes/presentation/
// conflict_resolution_dialog.dart:92` 的一处嵌套引号让字符串态错位，把
// `:95-99` 的**纯代码**整段抹成空格——凡落在错位区间里的裸 `InkWell(` 或
// `VaultService.instance`，两条门禁都看不见（失明放行）。故抽成本文件一份
// 实现，供两条门禁共用，并按 Dart 词法补全：
//   - `//` 行注释（含 `///` `//!`）；
//   - `/* */` 块注释（Dart 允许嵌套，深度归零才结束）；
//   - `'...'` / `"..."` / `'''...'''` / `"""..."""`，含 `\` 转义；
//   - `r'...'` / `r'''...'''` 原始字符串（无转义、无插值）；
//   - `$ident` 简单插值只保留标识符本身（`'$Foo.instance'` 里的 `.instance`
//     是字面文本，不是代码）；
//   - `${ expr }` 花括号深度与内层引号递归——插值内是**代码**，不遮蔽。
//
// 等长契约：输出与输入逐字符对齐（注释与字符串文本换成空格、换行原样保留、
// 其余代码原样保留），所以偏移量与行号与原文一一对应，门禁可继续在遮蔽后
// 的文本上求括号配对与命中位置。
//
// 自测见 `test/helpers/dart_lexical_mask_test.dart`（遮蔽器一旦退化，两条
// 门禁即失去裁决力，必须有独立的词法回归）。
library;

/// 遮蔽 [src] 中的注释与字符串字面量文本，返回等长的「纯代码」文本。
String maskDartLexically(String src) => _Masker(src).run();

class _Masker {
  _Masker(this._src);

  final String _src;
  final StringBuffer _out = StringBuffer();
  int _i = 0;

  String run() {
    _code(inInterp: false);
    return _out.toString();
  }

  bool get _eof => _i >= _src.length;

  String get _c => _src[_i];

  String _at(int k) => _i + k < _src.length ? _src[_i + k] : '';

  /// 从 [_i] 起是否以 [s] 开头。
  bool _startsWith(String s) {
    if (_i + s.length > _src.length) return false;
    return _src.substring(_i, _i + s.length) == s;
  }

  /// 原样输出一个字符（代码）。
  void _keep() {
    _out.write(_src[_i]);
    _i++;
  }

  /// 原样输出 [n] 个字符（越界即止）。
  void _keepN(int n) {
    for (var k = 0; k < n && !_eof; k++) {
      _keep();
    }
  }

  /// 换成空格输出一个字符（换行保留，行号不漂）。
  void _blank() {
    _out.write(_src[_i] == '\n' ? '\n' : ' ');
    _i++;
  }

  void _blankN(int n) {
    for (var k = 0; k < n && !_eof; k++) {
      _blank();
    }
  }

  static bool _isIdentStart(String ch) =>
      ch == '_' || ch == r'$' || (ch.isNotEmpty && _isLetter(ch));

  static bool _isIdentPart(String ch) =>
      _isIdentStart(ch) || (ch.isNotEmpty && _isDigit(ch));

  static bool _isLetter(String ch) {
    final u = ch.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a) || u > 0x7f;
  }

  static bool _isDigit(String ch) {
    if (ch.isEmpty) return false;
    final u = ch.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }

  /// 代码上下文。[inInterp] 为真时，深度归零的 `}` 交还给外层（不消费）。
  void _code({required bool inInterp}) {
    var depth = 0;
    while (!_eof) {
      final ch = _c;
      if (inInterp && ch == '}' && depth == 0) return;
      if (ch == '{') {
        depth++;
        _keep();
        continue;
      }
      if (ch == '}') {
        if (depth > 0) depth--;
        _keep();
        continue;
      }
      if (ch == '/' && _at(1) == '/') {
        _lineComment();
        continue;
      }
      if (ch == '/' && _at(1) == '*') {
        _blockComment();
        continue;
      }
      if (ch == 'r' &&
          (_at(1) == "'" || _at(1) == '"') &&
          !(_i > 0 && _isIdentPart(_src[_i - 1]))) {
        _rawString();
        continue;
      }
      if (ch == "'" || ch == '"') {
        _string(ch);
        continue;
      }
      _keep();
    }
  }

  void _lineComment() {
    while (!_eof && _c != '\n') {
      _blank();
    }
  }

  void _blockComment() {
    var depth = 0;
    while (!_eof) {
      if (_startsWith('/*')) {
        depth++;
        _blankN(2);
        continue;
      }
      if (_startsWith('*/')) {
        depth--;
        _blankN(2);
        if (depth <= 0) return;
        continue;
      }
      _blank();
    }
  }

  /// 原始字符串：`r'...'` / `r'''...'''`——无转义、无插值。
  void _rawString() {
    final quote = _at(1);
    _blank(); // `r`
    _string(quote, raw: true);
  }

  /// 普通（非 raw）字符串字面量：判定三引号、处理转义与插值。
  void _string(String quote, {bool raw = false}) {
    final triple = quote * 3;
    final isTriple = _startsWith(triple);
    final term = isTriple ? triple : quote;
    _blankN(term.length);
    while (!_eof) {
      if (!raw && _c == r'\') {
        _blankN(2);
        continue;
      }
      if (_startsWith(term)) {
        _blankN(term.length);
        return;
      }
      // 非三引号字符串不跨行：遇到换行按未闭合就地收束，避免整文件错位。
      if (!isTriple && _c == '\n') return;
      if (!raw && _c == r'$') {
        if (_at(1) == '{') {
          _interpolation();
          continue;
        }
        if (_isIdentStart(_at(1))) {
          // `$ident`：仅标识符是代码，其后的点是字面文本。
          _keep();
          while (!_eof && _isIdentPart(_c)) {
            _keep();
          }
          continue;
        }
      }
      _blank();
    }
  }

  /// `${ ... }`：插值表达式是真代码，原样保留（内含字符串仍递归遮蔽）。
  void _interpolation() {
    _keepN(2); // `${`
    _code(inInterp: true);
    if (!_eof && _c == '}') _keep();
  }
}

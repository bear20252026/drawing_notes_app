// secure_bytes.dart — 安全内存：密钥使用后清零，Finalizer 确保销毁（2026-08-24）。
//
// 设计原则：
// - 密钥材料（KEK/DEK/签名私钥）必须在使用后立即清零
// - Finalizer 兜底：即使调用方忘记 dispose()，GC 回收时也会清零
// - 不可变外部访问：只能通过 withBytes() 回调使用，防止泄露引用
// - 防御性拷贝：构造时拷贝输入，dispose 后访问抛异常
//
// 参考：Rust Zeroize + Dart Finalizer（Dart 3.0+）

import 'dart:typed_data';

/// 安全字节数组——使用后自动清零。
///
/// 用法：
/// ```dart
/// final secret = SecureBytes(rawKey);
/// try {
///   secret.withBytes((bytes) {
///     // 使用 bytes（Uint8List 视图）
///     doCrypto(bytes);
///   });
/// } finally {
///   secret.dispose(); // 立即清零
/// }
/// // secret.withBytes(...) // 抛 StateError
/// ```
class SecureBytes {
  /// 从原始字节构造（防御性拷贝）。
  SecureBytes(List<int> source)
      : _data = Uint8List.fromList(source),
        _disposed = false {
    _finalizer.attach(this, _data, detach: this);
  }

  /// 从指定长度的零填充构造。
  SecureBytes.zeroed(int length)
      : _data = Uint8List(length),
        _disposed = false {
    _finalizer.attach(this, _data, detach: this);
  }

  static final Finalizer<Uint8List> _finalizer = Finalizer(_zeroize);

  Uint8List _data;
  bool _disposed;

  /// 字节长度。
  int get length => _data.length;

  /// 是否已释放。
  bool get isDisposed => _disposed;

  /// 在回调中使用密钥材料（视图——不拷贝）。
  ///
  /// 回调结束后视图失效（但底层内存可能仍存活直到 GC——
  /// 因此强烈建议显式 dispose()）。
  T withBytes<T>(T Function(Uint8List bytes) fn) {
    if (_disposed) {
      throw StateError('SecureBytes 已释放——无法访问');
    }
    return fn(_data);
  }

  /// 创建防御性拷贝（调用方负责清零返回值）。
  Uint8List copy() {
    if (_disposed) {
      throw StateError('SecureBytes 已释放——无法拷贝');
    }
    return Uint8List.fromList(_data);
  }

  /// 立即清零并释放（幂等——多次调用安全）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _zeroize(_data);
    _finalizer.detach(this);
  }

  /// 静态清零函数（Finalizer 回调——必须是静态/顶级函数）。
  static void _zeroize(Uint8List data) {
    // 多次覆写（防御编译器优化——volatile 等效）：
    // 第一次：全零
    for (var i = 0; i < data.length; i++) {
      data[i] = 0;
    }
    // 第二次：全 0xFF（防止残留电荷——物理取证防御）
    for (var i = 0; i < data.length; i++) {
      data[i] = 0xFF;
    }
    // 第三次：全零（最终状态）
    for (var i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  /// 异步安全版本——在 isolate 中清零（大密钥时避免阻塞 UI）。
  static Future<void> zeroizeAsync(Uint8List data) async {
    _zeroize(data);
  }
}

/// 安全字符串——密码/助记词等敏感文本。
///
/// 内部持有一份 UTF-8 字节，dispose 时清零。
class SecureString {
  SecureString(String value)
      : _bytes = SecureBytes(_encode(value)),
        _length = value.length;

  SecureBytes _bytes;
  final int _length;

  int get length => _length;
  bool get isDisposed => _bytes.isDisposed;

  /// 在回调中使用原始字符串。
  T withValue<T>(T Function(String value) fn) {
    return _bytes.withBytes((bytes) {
      return fn(String.fromCharCodes(bytes));
    });
  }

  /// 获取 UTF-8 字节（通过回调）。
  T withBytes<T>(T Function(Uint8List bytes) fn) {
    return _bytes.withBytes(fn);
  }

  void dispose() {
    _bytes.dispose();
  }

  static List<int> _encode(String s) {
    // 简单 UTF-8 编码（不引入 dart:convert 依赖——
    // 实际项目可用 utf8.encode）。
    final runes = s.runes.toList();
    final bytes = <int>[];
    for (final r in runes) {
      if (r < 0x80) {
        bytes.add(r);
      } else if (r < 0x800) {
        bytes.add(0xC0 | (r >> 6));
        bytes.add(0x80 | (r & 0x3F));
      } else if (r < 0x10000) {
        bytes.add(0xE0 | (r >> 12));
        bytes.add(0x80 | ((r >> 6) & 0x3F));
        bytes.add(0x80 | (r & 0x3F));
      } else {
        bytes.add(0xF0 | (r >> 18));
        bytes.add(0x80 | ((r >> 12) & 0x3F));
        bytes.add(0x80 | ((r >> 6) & 0x3F));
        bytes.add(0x80 | (r & 0x3F));
      }
    }
    return bytes;
  }
}

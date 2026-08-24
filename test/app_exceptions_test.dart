import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/error/app_exceptions.dart';

void main() {
  group('AppException', () {
    test('基础属性', () {
      const ex = _TestException('test message');
      expect(ex.message, 'test message');
      expect(ex.cause, isNull);
      expect(ex.stackTrace, isNull);
      expect(ex.type, '_TestException');
      expect(ex.toString(), '_TestException: test message');
    });

    test('携带 cause 和 stackTrace', () {
      final cause = StateError('original');
      final stack = StackTrace.current;
      final ex = _TestException('wrapped', cause: cause, stackTrace: stack);
      expect(ex.cause, cause);
      expect(ex.stackTrace, stack);
    });
  });

  group('NetworkException', () {
    test('默认可恢复', () {
      const ex = NetworkException('timeout');
      expect(ex.isRecoverable, isTrue);
      expect(ex.statusCode, isNull);
    });

    test('携带状态码', () {
      const ex = NetworkException('not found', statusCode: 404);
      expect(ex.statusCode, 404);
    });
  });

  group('StorageException', () {
    test('默认可恢复', () {
      const ex = StorageException('disk full');
      expect(ex.isRecoverable, isTrue);
    });

    test('携带路径', () {
      const ex = StorageException('not found', path: '/tmp/test.sbn');
      expect(ex.path, '/tmp/test.sbn');
    });
  });

  group('CorruptedDataException', () {
    test('继承自 StorageException', () {
      const ex = CorruptedDataException('bad header');
      expect(ex, isA<StorageException>());
      expect(ex.isRecoverable, isTrue);
    });
  });

  group('CryptoException', () {
    test('默认不可恢复', () {
      const ex = CryptoException('decrypt failed');
      expect(ex.isRecoverable, isFalse);
    });
  });

  group('AuthenticationException', () {
    test('继承自 CryptoException', () {
      const ex = AuthenticationException('wrong password');
      expect(ex, isA<CryptoException>());
      expect(ex.isRecoverable, isFalse);
    });
  });

  group('UIException', () {
    test('基础 UI 异常', () {
      const ex = UIException('render failed');
      expect(ex.isRecoverable, isFalse);
    });
  });

  group('NavigationException', () {
    test('继承自 UIException', () {
      const ex = NavigationException('route not found');
      expect(ex, isA<UIException>());
    });
  });

  group('ValidationException', () {
    test('可恢复且携带字段名', () {
      const ex = ValidationException('too short', field: 'password');
      expect(ex.isRecoverable, isTrue);
      expect(ex.field, 'password');
    });
  });

  group('PlatformException', () {
    test('不可恢复且携带平台标识', () {
      const ex = PlatformException('camera unavailable', platform: 'android');
      expect(ex.isRecoverable, isFalse);
      expect(ex.platform, 'android');
    });
  });

  group('异常类型检查', () {
    test('NetworkException is AppException', () {
      expect(const NetworkException('x'), isA<AppException>());
    });

    test('StorageException is AppException', () {
      expect(const StorageException('x'), isA<AppException>());
    });

    test('CryptoException is AppException', () {
      expect(const CryptoException('x'), isA<AppException>());
    });

    test('UIException is AppException', () {
      expect(const UIException('x'), isA<AppException>());
    });

    test('ValidationException is AppException', () {
      expect(const ValidationException('x'), isA<AppException>());
    });

    test('PlatformException is AppException', () {
      expect(const PlatformException('x'), isA<AppException>());
    });
  });
}

/// 测试用异常实现。
class _TestException extends AppException {
  const _TestException(super.message, {super.cause, super.stackTrace});
}

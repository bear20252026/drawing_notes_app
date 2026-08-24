import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/error/crash_reporter.dart';

void main() {
  group('NoopCrashReporter', () {
    test('reportException 不抛异常', () async {
      const reporter = NoopCrashReporter();
      await reporter.initialize();
      await reporter.reportException(
        StateError('test'),
        StackTrace.current,
        context: 'test',
        extra: {'key': 'value'},
      );
    });

    test('breadcrumb 不抛异常', () async {
      const reporter = NoopCrashReporter();
      await reporter.addBreadcrumb('test', category: 'ui');
    });

    test('setUser / clearUser 不抛异常', () async {
      const reporter = NoopCrashReporter();
      await reporter.setUserId('user123');
      await reporter.clearUser();
    });
  });

  group('DebugCrashReporter', () {
    test('reportException 不抛异常', () async {
      const reporter = DebugCrashReporter();
      await reporter.initialize();
      await reporter.reportException(
        StateError('test'),
        StackTrace.current,
        context: 'test',
        extra: {'key': 'value'},
      );
    });

    test('breadcrumb 不抛异常', () async {
      const reporter = DebugCrashReporter();
      await reporter.addBreadcrumb('test', category: 'ui');
    });
  });

  group('CrashReporterService', () {
    tearDown(() {
      // 重置为默认状态
      CrashReporterService.configure(kDebugMode
          ? const DebugCrashReporter()
          : const NoopCrashReporter());
    });

    test('默认实例在 Debug 模式为 DebugCrashReporter', () {
      // 注意：在测试环境中 kDebugMode 通常为 true
      final instance = CrashReporterService.instance;
      if (kDebugMode) {
        expect(instance, isA<DebugCrashReporter>());
      } else {
        expect(instance, isA<NoopCrashReporter>());
      }
    });

    test('configure 可替换实例', () async {
      const customReporter = NoopCrashReporter();
      CrashReporterService.configure(customReporter);
      expect(CrashReporterService.instance, same(customReporter));
    });

    test('report 便捷方法调用 reportException', () async {
      final reporter = _TestCrashReporter();
      CrashReporterService.configure(reporter);

      await CrashReporterService.report(
        StateError('test'),
        StackTrace.current,
        context: 'unit_test',
      );

      expect(reporter.reportedErrors, hasLength(1));
      expect(reporter.reportedErrors.first.error, isA<StateError>());
    });

    test('breadcrumb 便捷方法调用 addBreadcrumb', () async {
      final reporter = _TestCrashReporter();
      CrashReporterService.configure(reporter);

      await CrashReporterService.breadcrumb('user action', category: 'ui');

      expect(reporter.breadcrumbs, hasLength(1));
      expect(reporter.breadcrumbs.first.message, 'user action');
    });
  });
}

/// 测试用崩溃上报器——记录所有调用。
class _TestCrashReporter implements CrashReporter {
  final List<_Report> reportedErrors = [];
  final List<_Breadcrumb> breadcrumbs = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> reportException(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? extra,
  }) async {
    reportedErrors.add(_Report(error, stackTrace, context, extra));
  }

  @override
  Future<void> setUserId(String userId) async {}

  @override
  Future<void> clearUser() async {}

  @override
  Future<void> addBreadcrumb(String message, {String? category}) async {
    breadcrumbs.add(_Breadcrumb(message, category));
  }
}

class _Report {
  const _Report(this.error, this.stackTrace, this.context, this.extra);
  final Object error;
  final StackTrace? stackTrace;
  final String? context;
  final Map<String, dynamic>? extra;
}

class _Breadcrumb {
  const _Breadcrumb(this.message, this.category);
  final String message;
  final String? category;
}

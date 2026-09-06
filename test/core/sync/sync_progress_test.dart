// P4-B2 SyncProgress 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';

void main() {
  group('SyncProgress fraction', () {
    test('0/0 → 0.0', () {
      const p = SyncProgress(phase: SyncProgressPhase.started);
      expect(p.fraction, 0.0);
    });

    test('done < total → 比例', () {
      const p = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 3,
        totalCount: 7,
      );
      expect(p.fraction, closeTo(3.0 / 7.0, 0.001));
    });

    test('done == total → 1.0', () {
      const p = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 7,
        totalCount: 7,
      );
      expect(p.fraction, 1.0);
    });

    test('complete → 1.0', () {
      final p = SyncProgress.complete();
      expect(p.fraction, 1.0);
    });

    test('fraction 不超过 [0,1]', () {
      const p = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 10,
        totalCount: 5,
      );
      expect(p.fraction, 1.0);
    });
  });

  group('SyncProgress description', () {
    test('uploading 含计数', () {
      const p = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 3,
        totalCount: 7,
      );
      expect(p.description, contains('3/7'));
      expect(p.description, contains('上传'));
    });

    test('uploading 无总数', () {
      const p = SyncProgress(phase: SyncProgressPhase.uploading);
      expect(p.description, '正在上传…');
    });

    test('downloading 含计数', () {
      const p = SyncProgress(
        phase: SyncProgressPhase.downloading,
        doneCount: 2,
        totalCount: 5,
      );
      expect(p.description, contains('2/5'));
      expect(p.description, contains('下载'));
    });

    test('done 文案', () {
      final p = SyncProgress.complete();
      expect(p.description, '同步完成');
    });

    test('failed 使用 message', () {
      final p = SyncProgress.failure('网络错误');
      expect(p.description, '网络错误');
    });

    test('failed 无 message 使用默认', () {
      final p = SyncProgress.failure('');
      expect(p.description, '同步失败');
    });

    test('各阶段文案', () {
      expect(SyncProgress.starting().description, contains('启动'));
      expect(
        const SyncProgress(phase: SyncProgressPhase.connecting).description,
        contains('连接'),
      );
      expect(
        const SyncProgress(phase: SyncProgressPhase.planning).description,
        contains('比对'),
      );
      expect(
        const SyncProgress(phase: SyncProgressPhase.deleting).description,
        contains('删除'),
      );
      expect(
        const SyncProgress(
          phase: SyncProgressPhase.writingManifest,
        ).description,
        contains('清单'),
      );
    });
  });

  group('SyncProgress copyWith', () {
    test('只改部分字段', () {
      const a = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 1,
        totalCount: 5,
      );
      final b = a.copyWith(doneCount: 3);
      expect(b.doneCount, 3);
      expect(b.totalCount, 5);
      expect(b.phase, SyncProgressPhase.uploading);
    });

    test('copyWith 不改变原实例', () {
      const a = SyncProgress(phase: SyncProgressPhase.started);
      final b = a.copyWith(phase: SyncProgressPhase.done);
      expect(a.phase, SyncProgressPhase.started);
      expect(b.phase, SyncProgressPhase.done);
    });
  });

  group('SyncProgress 相等性', () {
    test('相同字段 → ==', () {
      const a = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 2,
        totalCount: 5,
      );
      const b = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 2,
        totalCount: 5,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('不同字段 → !=', () {
      const a = SyncProgress(phase: SyncProgressPhase.uploading);
      const b = SyncProgress(phase: SyncProgressPhase.downloading);
      expect(a, isNot(b));
    });
  });

  group('SyncProgress 工厂', () {
    test('starting()', () {
      final p = SyncProgress.starting();
      expect(p.phase, SyncProgressPhase.started);
      expect(p.doneCount, 0);
      expect(p.totalCount, 0);
    });

    test('phase()', () {
      final p = SyncProgress.phase(
        SyncProgressPhase.uploading,
        doneCount: 3,
        totalCount: 7,
        currentDocId: 'doc-1',
      );
      expect(p.phase, SyncProgressPhase.uploading);
      expect(p.doneCount, 3);
      expect(p.totalCount, 7);
      expect(p.currentDocId, 'doc-1');
    });

    test('complete()', () {
      final p = SyncProgress.complete();
      expect(p.phase, SyncProgressPhase.done);
      expect(p.fraction, 1.0);
    });

    test('failure()', () {
      final p = SyncProgress.failure('错误');
      expect(p.phase, SyncProgressPhase.failed);
      expect(p.message, '错误');
    });
  });

  group('SyncProgressPhase 枚举齐全', () {
    test('包含全部 9 个阶段', () {
      final phases = SyncProgressPhase.values;
      expect(phases.length, 9);
      expect(phases, contains(SyncProgressPhase.started));
      expect(phases, contains(SyncProgressPhase.connecting));
      expect(phases, contains(SyncProgressPhase.planning));
      expect(phases, contains(SyncProgressPhase.uploading));
      expect(phases, contains(SyncProgressPhase.downloading));
      expect(phases, contains(SyncProgressPhase.deleting));
      expect(phases, contains(SyncProgressPhase.writingManifest));
      expect(phases, contains(SyncProgressPhase.done));
      expect(phases, contains(SyncProgressPhase.failed));
    });
  });

  group('不可变性', () {
    test('同实例字段固定', () {
      const p = SyncProgress(
        phase: SyncProgressPhase.uploading,
        doneCount: 2,
        totalCount: 4,
        currentDocId: 'doc-x',
        message: 'msg',
      );
      // 多次访问字段值不变
      expect(p.phase, SyncProgressPhase.uploading);
      expect(p.phase, SyncProgressPhase.uploading);
      expect(p.doneCount, 2);
      expect(p.doneCount, 2);
      expect(p.fraction, closeTo(0.5, 0.001));
      expect(p.fraction, closeTo(0.5, 0.001));
    });
  });
}

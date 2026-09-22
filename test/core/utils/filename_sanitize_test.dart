import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/utils/filename_sanitize.dart';

void main() {
  test('sanitizeExportFileName 去除非法字符与尾点', () {
    expect(sanitizeExportFileName('笔记/画布:v1'), '笔记_画布_v1');
    expect(sanitizeExportFileName('title...'), 'title');
    expect(sanitizeExportFileName('  spaced  name  '), 'spaced name');
  });

  test('sanitizeExportFileName 空名回退与保留设备名', () {
    expect(sanitizeExportFileName('   '), isNotEmpty);
    expect(sanitizeExportFileName('CON'), startsWith('_'));
  });

  test('isSafeRemotePathSegment 拒绝穿越与非法字符', () {
    expect(isSafeRemotePathSegment('doc-1_ab~1'), isTrue);
    expect(isSafeRemotePathSegment('..'), isFalse);
    expect(isSafeRemotePathSegment('.'), isFalse);
    expect(isSafeRemotePathSegment('a/b'), isFalse);
    expect(isSafeRemotePathSegment(''), isFalse);
    expect(isSafeRemotePathSegment('中文'), isFalse);
  });

  test('isSafeRemoteRelativePath 允许多段合法路径', () {
    expect(isSafeRemoteRelativePath('docs/abc-123.json'), isTrue);
    expect(isSafeRemoteRelativePath('../../etc'), isFalse);
    expect(isSafeRemoteRelativePath('a/./b'), isFalse);
  });
}

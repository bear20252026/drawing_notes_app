import 'package:drawing_notes_app/core/utils/memory_trim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trimProcessWorkingSet 不抛异常（Windows 实调 / 其他平台 no-op）', () {
    // ④ 纯观感优化：任何平台调用都必须安全返回；Windows 上实调
    // SetProcessWorkingSetSize(-1,-1)，失败静默。
    expect(trimProcessWorkingSet, returnsNormally);
  });
}

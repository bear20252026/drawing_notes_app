import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('首次加载默认使用整笔删除模式', () async {
    final store = EraserModeStore();
    expect(await store.load(), EraserMode.stroke);
  });

  test('透明像素模式保存后可在新服务实例恢复', () async {
    final store = EraserModeStore();
    await store.save(EraserMode.pixel);

    expect(await EraserModeStore().load(), EraserMode.pixel);
  });

  test('损坏的偏好值安全回退到整笔删除', () async {
    SharedPreferences.setMockInitialValues({
      EraserModeStore.storageKey: 'invalid-mode',
    });

    expect(await EraserModeStore().load(), EraserMode.stroke);
  });
}

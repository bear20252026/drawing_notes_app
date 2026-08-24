import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 用户需求——EncryptionScopeService 加密对象选择测试（纯逻辑——不搞崩）。
void main() {
  test('初始状态：无加密', () {
    const service = EncryptionScopeService();
    expect(service.appEncrypted, false);
    expect(service.count, 0);
    expect(service.isEncrypted('note1'), false);
  });

  test('setAppEncrypted：应用级加密（加密整个应用）', () {
    const service = EncryptionScopeService();
    final encrypted = service.setAppEncrypted(true);
    expect(encrypted.appEncrypted, true);
    // 应用级加密——所有笔记都加密。
    expect(encrypted.isEncrypted('note1'), true);
    expect(encrypted.isEncrypted('canvas1'), true);
    // 首页预览——全部排除。
    expect(encrypted.filterForHomePreview(['note1', 'note2']), isEmpty);
  });

  test('setAppEncrypted：取消应用级加密（不可变）', () {
    const service = EncryptionScopeService();
    final encrypted = service.setAppEncrypted(true);
    final decrypted = encrypted.setAppEncrypted(false);
    expect(decrypted.appEncrypted, false);
    expect(decrypted.isEncrypted('note1'), false);
    expect(encrypted.appEncrypted, true); // 原实例不变。
  });

  test('setNoteEncrypted：单个笔记/画板加密', () {
    const service = EncryptionScopeService();
    final encrypted = service.setNoteEncrypted('note1', true);
    expect(encrypted.isEncrypted('note1'), true);
    expect(encrypted.isEncrypted('note2'), false); // 其他笔记不加密。
    expect(encrypted.encryptedNoteIds, ['note1']);
  });

  test('setNoteEncrypted：取消单个笔记加密', () {
    const service = EncryptionScopeService();
    final encrypted = service.setNoteEncrypted('note1', true);
    final decrypted = encrypted.setNoteEncrypted('note1', false);
    expect(decrypted.isEncrypted('note1'), false);
    expect(decrypted.encryptedNoteIds, isEmpty);
  });

  test('filterForHomePreview：加密笔记不预览（用户需求）', () {
    var service = const EncryptionScopeService();
    service = service.setNoteEncrypted('note2', true);
    final previewable = service.filterForHomePreview(['note1', 'note2', 'note3']);
    // note2 加密——排除。
    expect(previewable, ['note1', 'note3']);
  });

  test('filterForHomePreview：未加密全部可预览', () {
    const service = EncryptionScopeService();
    expect(service.filterForHomePreview(['n1', 'n2', 'n3']), ['n1', 'n2', 'n3']);
  });

  test('EncryptionScope：copyWith + 相等性', () {
    const scope = EncryptionScope(type: EncryptionScopeType.note, objectId: 'n1', encrypted: false);
    final updated = scope.copyWith(encrypted: true);
    expect(scope.encrypted, false); // 原实例不变。
    expect(updated.encrypted, true);
    const other = EncryptionScope(type: EncryptionScopeType.note, objectId: 'n1', encrypted: true);
    expect(scope, other); // 按 type+objectId 相等。
  });

  test('EncryptionScopeType 枚举', () {
    expect(EncryptionScopeType.values.length, 2);
    expect(EncryptionScopeType.app.name, 'app');
    expect(EncryptionScopeType.note.name, 'note');
  });
}

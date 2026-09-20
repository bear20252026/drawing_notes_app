import 'package:drawing_notes_app/core/utils/domain_display_labels.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// E6：存储默认值与展示文案分离；异常在 UI 层映射为人话。
String humanizeVaultException(Object e, AppLocalizations? l10n) {
  if (e is VaultFileLockException) {
    return l10n?.syncFailedUnknown ?? '保险库已锁定，加密文件不可读';
  }
  if (e is VaultUnlockException) return e.reason;
  return e.toString();
}

void main() {
  group('DomainDisplayLabels', () {
    test('空/历史默认标题 → 本地化展示；真实标题原样', () {
      expect(DomainDisplayLabels.isUntitledDocTitle(''), isTrue);
      expect(DomainDisplayLabels.isUntitledDocTitle('未命名'), isTrue);
      expect(DomainDisplayLabels.isUntitledDocTitle('未命名画布'), isTrue);
      expect(DomainDisplayLabels.isUntitledDocTitle('我的画布'), isFalse);
      expect(DomainDisplayLabels.docTitle(null, ''), '未命名');
      expect(DomainDisplayLabels.docTitle(null, '产品图'), '产品图');
    });

    test('图层名：历史 图层 1 / 空 → 映射；自定义名保留', () {
      expect(DomainDisplayLabels.isLegacyOrEmptyLayerName(''), isTrue);
      expect(DomainDisplayLabels.isLegacyOrEmptyLayerName('图层'), isTrue);
      expect(DomainDisplayLabels.isLegacyOrEmptyLayerName('图层 2'), isTrue);
      expect(DomainDisplayLabels.isLegacyOrEmptyLayerName('墨迹层'), isFalse);
      expect(DomainDisplayLabels.layerName(null, ''), '图层 1');
      expect(DomainDisplayLabels.layerName(null, '图层 3'), '图层 3');
      expect(DomainDisplayLabels.layerName(null, '墨迹层'), '墨迹层');
    });

    test('导出文件名用 untitled，不用中文默认值', () {
      expect(DomainDisplayLabels.exportBaseName(''), 'untitled');
      expect(DomainDisplayLabels.exportBaseName('未命名'), 'untitled');
      expect(DomainDisplayLabels.exportBaseName('季度报告'), '季度报告');
      expect(
        DomainDisplayLabels.isUntitledNotebookTitle('未命名分页画布'),
        isTrue,
      );
      expect(DomainDisplayLabels.isUntitledPageTitle('未命名页面'), isTrue);
    });

    test('异常映射：锁定异常保留技术 reason 或人话回退', () {
      final e = VaultFileLockException();
      final msg = humanizeVaultException(e, null);
      expect(msg, isNotEmpty);
    });
  });
}

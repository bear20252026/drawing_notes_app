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

    test('L-04：锁定占位单一键——locked 优先于未命名，真实标题原样', () {
      // zh 兜底（l10n 缺失时测试装配惯例）。
      expect(DomainDisplayLabels.lockedDocTitle(null), '加密内容');
      // locked 优先：空标题（新契约）与真实标题（防御）都显示锁定名。
      expect(
        DomainDisplayLabels.docTitleWithLock(null, '', locked: true),
        '加密内容',
      );
      expect(
        DomainDisplayLabels.docTitleWithLock(null, '机密画布', locked: true),
        '加密内容',
      );
      // 未锁定走原 docTitle 语义。
      expect(
        DomainDisplayLabels.docTitleWithLock(null, '', locked: false),
        '未命名',
      );
      expect(
        DomainDisplayLabels.docTitleWithLock(null, '产品图', locked: false),
        '产品图',
      );
    });
  });
}

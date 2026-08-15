// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Drawing Notes';

  @override
  String get search => 'Search';

  @override
  String get trash => 'Trash (recoverable within 30 days)';

  @override
  String get close => 'Close';

  @override
  String get newNotebook => 'New notebook';

  @override
  String get delete => 'Delete';

  @override
  String get homeTrashEmpty => 'Trash is empty';

  @override
  String homeDeletedAt(String time) {
    return 'Deleted at $time';
  }

  @override
  String get homeRecover => 'Recover';

  @override
  String get homeDeleteForever => 'Delete forever';

  @override
  String get homeEmptyTrash => 'Empty trash';

  @override
  String get homeCancel => 'Cancel';

  @override
  String get homeSwitchTheme => 'Switch appearance (system / light / dark)';

  @override
  String get homeMore => 'More options';

  @override
  String get editorUndo => 'Undo';

  @override
  String get editorRedo => 'Redo';

  @override
  String get editorShortcutsHelp => 'Keyboard shortcuts';

  @override
  String get editorMenu => 'Main menu';

  @override
  String get editorClearCanvas => 'Clear canvas';

  @override
  String get editorCopyPng => 'Copy PNG to clipboard';

  @override
  String get editorExportPng => 'Export PNG';

  @override
  String get editorExportSvg => 'Export SVG';

  @override
  String get editorShapeTool => 'Shape tool';

  @override
  String get noteActions => 'Notebook actions';

  @override
  String get noteImportPage => 'Import page from another notebook';

  @override
  String get noteImportMarkdown => 'Import Markdown or text';

  @override
  String get noteImportPdf => 'Import PDF and annotate per page';

  @override
  String get noteTidyPages => 'Tidy up pages';

  @override
  String get noteFilterHint => 'Filter by tag or keyword';

  @override
  String get noteEncryptionChoice => 'Choose encryption method';

  @override
  String get noteMemoryPassword => 'Memory password';

  @override
  String get noteMemoryPasswordSub =>
      'Set a password; enter it to decrypt when opening';

  @override
  String get noteUsbKey => 'USB key (password disk)';

  @override
  String get noteUsbKeySub =>
      'USB is the key: unlock by plugging in, lock on removal (zero knowledge)';

  @override
  String get noteRecoveryKeyTitle => 'Save your recovery key (very important!)';
}

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

  @override
  String get diskCopied => 'I have copied it';

  @override
  String get diskPinProtection => 'Enable PIN protection?';

  @override
  String get diskNoPin => 'No';

  @override
  String get diskYesPin => 'Enable';

  @override
  String get diskEnterPin => 'Enter password disk PIN';

  @override
  String get diskConfirm => 'OK';

  @override
  String get searchTitle => 'Full-text search';

  @override
  String get searchHint => 'Search text block content / title…';

  @override
  String get searchEmptyHint => 'Enter keywords to start searching';

  @override
  String get searchNoResults => 'No matching content found';

  @override
  String get editorStrokeColor => 'Stroke color';

  @override
  String get editorEraseStroke => 'Hit a stroke to delete the whole line';

  @override
  String get editorEraseTransparent =>
      'Carve out the current layer with transparent pixels';

  @override
  String get editorHighlightNormal =>
      'Write as a normal highlighter; undoable, savable and exportable';

  @override
  String get editorLaserTemporary =>
      'Shown briefly, fades out smoothly after ~4 seconds, not written to the page';

  @override
  String get editorTextColor => 'Text color';

  @override
  String get editorBold => 'Bold (Ctrl+B)';

  @override
  String get editorItalic => 'Italic (Ctrl+I)';

  @override
  String get diskPinInfo =>
      'After enabling, the master key is stored encrypted with a PIN (OWASP KEK mode); a lost USB drive cannot expose it directly. Unlocking requires entering the PIN.';

  @override
  String get editorExportPdf => 'Export PDF';

  @override
  String get editorExportJson => 'Export JSON';

  @override
  String get editorExportPptx => 'Export PPTX';

  @override
  String get editorExportWord => 'Export Word-compatible document';

  @override
  String get editorUnderline => 'Underline (Ctrl+U)';

  @override
  String get editorPdfPreview => 'Page preview (A4 pagination)';

  @override
  String get editorPasteValues =>
      'Paste values separated by commas / spaces / newlines, e.g.: 10, 25, 18, 42, 30';

  @override
  String editorImageInsertFail(String error) {
    return 'Failed to insert image: $error';
  }
}

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
  String get noteActions => 'Paged canvas actions';

  @override
  String get noteImportPage => 'Import page from another paged canvas';

  @override
  String get noteImportMarkdown => 'Import Markdown or text';

  @override
  String get noteImportPdf => 'Import PDF and annotate per page';

  @override
  String get noteTidyPages => 'Tidy up pages';

  @override
  String get noteFilterHint => 'Filter by tag or keyword';

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
  String get editorPasteValues =>
      'Paste values separated by commas / spaces / newlines, e.g.: 10, 25, 18, 42, 30';

  @override
  String editorImageInsertFail(String error) {
    return 'Failed to insert image: $error';
  }

  @override
  String get alignLeft => 'Left';

  @override
  String get alignCenter => 'Center';

  @override
  String get alignRight => 'Right';

  @override
  String editorAlignTooltip(String name) {
    return 'Align: $name (Ctrl+E)';
  }

  @override
  String editorPagePreviewTitle(String title) {
    return 'Page preview $title';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get nextStep => 'Next';

  @override
  String get gotIt => 'Got it';

  @override
  String get create => 'Create';

  @override
  String get lockTitle => 'App Lock';

  @override
  String get lockDescription =>
      'Once enabled, a password is required every time you open the app or return from the background.';

  @override
  String get lockOn => 'On';

  @override
  String get lockOff => 'Off';

  @override
  String get lockChangePassword => 'Change Password';

  @override
  String get lockResetDisk => 'Reset Disk';

  @override
  String get lockDiskStatusUnknown => 'Status unknown (failed to read vault)';

  @override
  String get lockDiskBound => 'Bound (can reset a forgotten password)';

  @override
  String get lockDiskUnbound =>
      'Unbound (a forgotten password cannot be recovered)';

  @override
  String get lockDiskUnbind => 'Unbind';

  @override
  String get lockDiskBind => 'Bind';

  @override
  String get lockVerifyCurrentPassword => 'Verify current password';

  @override
  String get lockVaultUnlockFailed =>
      'Failed to unlock the vault, please retry';

  @override
  String get lockBindFailed => 'Binding failed, please retry';

  @override
  String get lockBindSuccess =>
      'Bound. Keep the USB drive safe: without it the password cannot be reset, and do not delete password_reset_disk.key on it';

  @override
  String get lockUnbindTitle => 'Unbind reset disk';

  @override
  String get lockUnbindContent =>
      'After unbinding, a forgotten password cannot be reset.\n\nThe password_reset_disk.key file on the USB drive will not be deleted — remove it yourself.';

  @override
  String get lockUnbindFailed => 'Unbinding failed, please retry';

  @override
  String get lockUnbound => 'Unbound';

  @override
  String get lockSetPassword => 'Set password';

  @override
  String get lockConfirmPassword => 'Confirm password';

  @override
  String get lockMismatch => 'Entries don\'t match, please set again';

  @override
  String get lockVaultSyncFailed =>
      'File encryption sync failed, please retry or contact the developer';

  @override
  String get lockEnabled => 'App lock enabled';

  @override
  String get lockDisabled => 'App lock disabled';

  @override
  String get lockCannotDisableTitle => 'Can\'t disable App Lock';

  @override
  String get lockCannotDisableContent =>
      'Your files are encrypted with the app-lock password. Disabling App Lock would make encrypted files unreadable.\n\nTo change the password, use \"Change Password\".';

  @override
  String get lockPinLengthTitle => 'Password length';

  @override
  String lockPinLengthDigits(int count) {
    return '$count digits';
  }

  @override
  String get lockPinLengthHint =>
      '6+ digits recommended; numeric-only passwords have limited strength.';

  @override
  String get lockQuickUnlock => 'System-verified quick unlock';

  @override
  String get lockQuickUnlockOn =>
      'On (unlock from the lock screen with Windows Hello)';

  @override
  String get lockQuickUnlockOff =>
      'Off (enable to unlock with face, fingerprint, or PIN)';

  @override
  String get lockQuickEnableFailed => 'Failed to enable, please retry';

  @override
  String get lockQuickEnableDone =>
      'Enabled: unlock from the lock screen with system verification (face, fingerprint, or PIN)';

  @override
  String get lockQuickDisableDone =>
      'Disabled; the key copy in the system secure enclave has been deleted';

  @override
  String get lockBindHintBound =>
      'After binding a reset disk, a forgotten password can be reset with it; otherwise it cannot be recovered.';

  @override
  String get lockBindHintUnbound =>
      'After enabling App Lock, you can bind a reset disk in case you forget the password.';

  @override
  String get docShareComingSoon => 'Sharing coming soon';

  @override
  String get docSaveFailed => 'Save failed, please retry or save manually';

  @override
  String docExportedTo(String label, String path) {
    return 'Exported $label: $path';
  }

  @override
  String get docExportFailed => 'Export failed, please retry';

  @override
  String docPolicyDenied(String operation) {
    return 'Operation denied by policy ($operation)';
  }

  @override
  String get docInsertPageLink => 'Insert page link';

  @override
  String docStandalonePasswordTitle(String name) {
    return 'Standalone password for \"$name\"';
  }

  @override
  String get docSetStandalonePassword => 'Set standalone password';

  @override
  String get docSetStandalonePasswordHint =>
      '4–12 digits, must differ from the app-lock password';

  @override
  String get docChangeStandalonePassword => 'Change standalone password';

  @override
  String get docBindResetDisk => 'Bind reset disk';

  @override
  String get docBindResetDiskHint =>
      'After binding, a forgotten password can be reset with the USB drive without the old password';

  @override
  String get docRemoveStandalonePassword => 'Remove standalone password';

  @override
  String get docTags => 'Tags';

  @override
  String get docNewTag => 'New tag';

  @override
  String get shellAllDocs => 'All Documents';

  @override
  String get shellCanvasNotes => 'Canvas & Notes';

  @override
  String get shellSchedule => 'Calendar';

  @override
  String get shellSettings => 'Settings';

  @override
  String get shellEditorNotAssembled =>
      'Editor not yet assembled by the app layer';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppLock => 'App Lock';

  @override
  String get settingsAppLockHint => 'App-lock password · Reset disk';

  @override
  String get settingsStandalonePassword => 'Per-file Password';

  @override
  String get settingsStandalonePasswordHint =>
      'A second lock for individual canvases (set on the canvas card)';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsHighContrast => 'High contrast';

  @override
  String get settingsWebdav => 'WebDAV Sync';

  @override
  String get settingsWebdavHint => 'Local-first, sync across devices';

  @override
  String get settingsPasswordSystem => 'Password System';

  @override
  String get docsSort => 'Sort';

  @override
  String get docsSortGroupTime => 'Group by time';

  @override
  String get docsSortUpdated => 'By updated time';

  @override
  String get docsSortCreated => 'By created time';

  @override
  String get docsSortTitle => 'By title';

  @override
  String get docsNewDoc => 'New document';

  @override
  String get docsNewNote => 'New note';

  @override
  String get docsNewPagedCanvas => 'New paged canvas';

  @override
  String get docsNewCanvas => 'New canvas';

  @override
  String get settingsSectionSecurity => 'Passwords & Security';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsFilePasswordHelpContent =>
      'On the home page or in All Documents, tap the lock button on a canvas card to set a standalone password for that canvas. Opening it will then require this password, and the thumbnail is hidden behind a lock placeholder.\n\nThe per-file password is independent of the app-lock password — even if someone unlocks your app, they cannot open the canvas without it.';

  @override
  String get settingsThemeSystem => 'Follow system (tap to switch to light)';

  @override
  String get settingsThemeLight => 'Light (tap to switch to dark)';

  @override
  String get settingsThemeDark => 'Dark (tap to follow system)';

  @override
  String get settingsLayer1Title => 'Layer 1 · App-lock password';

  @override
  String get settingsLayer1Desc =>
      'Unlocks the app and the master-key vault — protects all canvases and notes. Reset with the reset disk if forgotten.';

  @override
  String get settingsLayer2Title => 'Layer 2 · Per-file password';

  @override
  String get settingsLayer2Desc =>
      'A standalone password for a single canvas, paged canvas, or note, independent of the app-lock password. Reset with the reset disk if forgotten.';

  @override
  String get settingsLayer3Title => 'Reset disk (USB drive)';

  @override
  String get settingsLayer3Desc =>
      'Plug in the USB drive → tap \"Forgot password\" → set a new one. The same disk resets both the app-lock and per-file passwords.';

  @override
  String get docUnsaved => 'Unsaved';

  @override
  String get docSaving => 'Saving…';

  @override
  String get docSaved => 'Saved';

  @override
  String docSavedAt(String time) {
    return 'Saved $time';
  }

  @override
  String get docUntitled => 'Untitled';

  @override
  String get docStandalonePasswordProtected =>
      'This note is protected by a standalone password';

  @override
  String get docStandalonePasswordUnset =>
      'This note has no standalone password yet';

  @override
  String get docCreatedAt => 'Created';

  @override
  String get docUpdatedAt => 'Updated';

  @override
  String get docBlockCount => 'Blocks';

  @override
  String get docTagNameHint => 'Tag name';

  @override
  String get docPinSameAsLock =>
      'The standalone password must differ from the app password';

  @override
  String get docConfirmStandalonePassword => 'Confirm standalone password';

  @override
  String get docPinMismatch => 'The two entries do not match. Please retry.';

  @override
  String get docSetNewPassword => 'Set new password';

  @override
  String docPasswordSetFor(String name) {
    return 'Set the standalone password for \"$name\"';
  }

  @override
  String get docPasswordSetDiskBound =>
      'Standalone password set and reset disk bound';

  @override
  String get docSetFailed => 'Failed to set the password. Please retry.';

  @override
  String get docVerifyCurrent => 'Verify current standalone password';

  @override
  String docPasswordChangedFor(String name) {
    return 'Changed the standalone password for \"$name\"';
  }

  @override
  String get docWrongPassword => 'Incorrect password or corrupted ciphertext';

  @override
  String get docChangeFailed => 'Failed to change the password. Please retry.';

  @override
  String get docBindDiskConfirmTitle => 'Bind reset disk?';

  @override
  String get docBindDiskConfirmContent =>
      'If you forget this note\'s standalone password later, insert the reset disk (USB drive) to reset it without the old password.\n\nThe disk only contains a random key file (password_reset_disk.key); note data never leaves the device.';

  @override
  String get docBindDiskConfirm => 'Bind with disk';

  @override
  String get docNotNow => 'Not now';

  @override
  String get docDiskNotFoundNoBind =>
      'No valid reset disk file (password_reset_disk.key) found; skipping binding.';

  @override
  String get docDiskNotFound =>
      'No valid reset disk file (password_reset_disk.key) found.';

  @override
  String get docVerifyToBind =>
      'Verify the standalone password to bind the reset disk';

  @override
  String get docDiskBound => 'Reset disk bound';

  @override
  String get docWrongOrAlreadyBound =>
      'Incorrect password or reset disk already bound';

  @override
  String get docBindFailed => 'Failed to bind. Please retry.';

  @override
  String docRemoveConfirmContent(String name) {
    return 'After removal, \"$name\" can be opened without the standalone password. Remove it?';
  }

  @override
  String get docRemove => 'Remove';

  @override
  String get docVerifyToRemove => 'Verify the standalone password to remove it';

  @override
  String docPasswordRemovedFor(String name) {
    return 'Removed the standalone password for \"$name\"';
  }

  @override
  String get docPasswordWrongOrCorrupt =>
      'Incorrect password or corrupted ciphertext';

  @override
  String get docRemoveFailed => 'Failed to remove the password. Please retry.';

  @override
  String get docUnlockTitle => 'This note is locked. Enter its password.';

  @override
  String get docForgotPassword => 'Forgot password?';

  @override
  String get docsTabDocs => 'Docs';

  @override
  String get docsTabFavorites => 'Favorites';

  @override
  String get docsEmptyNoMatch => 'No matching docs';

  @override
  String get docsEmptyNoMatchTip => 'Try other keywords or sorting options';

  @override
  String get docsEmptyNoFavorites => 'No favorite docs yet';

  @override
  String get docsEmptyNoFavoritesTip =>
      'Tap a doc\'s star to add it to favorites';

  @override
  String get docsEmptyFirstNote => 'Write your first note';

  @override
  String get docsEmptyFirstNoteTip =>
      'Notes are for typing; canvases are for sketching';
}

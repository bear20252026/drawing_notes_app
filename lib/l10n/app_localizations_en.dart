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
      'Once enabled, a password is required to open the app, and to return from the background after the grace period.';

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
  String get lockGraceTitle => 'Grace Period on Return';

  @override
  String get lockGraceHint =>
      'Come back within the grace period after leaving the app and you won\'t need to re-enter your password. The grace period only skips the lock screen; passwords for encrypted files and notes will still be requested.';

  @override
  String get lockGraceOff => 'Off (lock immediately on backgrounding)';

  @override
  String get lockGrace30s => '30 seconds';

  @override
  String get lockGrace1min => '1 minute';

  @override
  String get lockGrace5min => '5 minutes';

  @override
  String lockGraceCurrent(String option) {
    return 'Current: $option';
  }

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

  @override
  String get docsLoadFailedRetry => 'Failed to load. Pull down to retry';

  @override
  String get docsQuickSearch => 'Quick search';

  @override
  String get docsClearSearch => 'Clear search';

  @override
  String get docsRecent => 'Recent';

  @override
  String get docsNoDocs => 'No documents yet';

  @override
  String get docsMore => 'More';

  @override
  String get docsTrashTab => 'Trash';

  @override
  String get docsTree => 'Document tree';

  @override
  String get docsFavorite => 'Add to favorites';

  @override
  String get docsUnfavorite => 'Remove from favorites';

  @override
  String get docsMoreActions => 'More actions';

  @override
  String get docsGroupToday => 'Today';

  @override
  String get docsGroupThisWeek => 'This week';

  @override
  String get docsGroupEarlier => 'Earlier';

  @override
  String get docsGroupNeverUpdated => 'Never edited';

  @override
  String get open => 'Open';

  @override
  String get timeYesterday => 'Yesterday';

  @override
  String timeMonthDay(int month, int day) {
    return '$month/$day';
  }

  @override
  String get tagsEmpty => 'No tags yet';

  @override
  String get tagsEmptyTip => 'Open a note → Document info → Add tags';

  @override
  String get tagsAll => 'All tags';

  @override
  String get tagsNoDocs => 'No notes with this tag';

  @override
  String get commonConfirm => 'OK';

  @override
  String get commonPassword => 'Password';

  @override
  String get unlockEnterPassword => 'Enter password';

  @override
  String get unlockEmergency => 'Emergency';

  @override
  String get unlockBarrier => 'Password lock';

  @override
  String get unlockPasswordWrong => 'Incorrect password';

  @override
  String get unlock => 'Unlock';

  @override
  String get shellUnlockNoteTitle =>
      'This note is encrypted. Enter its password';

  @override
  String get shellUnlockCanvasTitle =>
      'This canvas is encrypted. Enter its standalone password';

  @override
  String get shellUnlockNotebookTitle =>
      'This paged canvas is encrypted. Enter its password';

  @override
  String get resetThisNote => 'this note';

  @override
  String get resetThisCanvas => 'this canvas';

  @override
  String get resetThisNotebook => 'this paged canvas';

  @override
  String resetDocNameQuote(String name) {
    return '“$name”';
  }

  @override
  String get resetForgotFilePassword => 'Forgot file password';

  @override
  String get resetForgotPassword => 'Forgot password';

  @override
  String get resetImpossible => 'Cannot reset';

  @override
  String get resetStandalonePassword => 'Standalone password';

  @override
  String get resetFailed => 'Reset failed';

  @override
  String get resetDiskMismatchOrCorrupt =>
      'The reset disk doesn\'t match or is damaged.';

  @override
  String resetDoneStandalone(String name) {
    return 'Standalone password of $name has been reset with the reset disk';
  }

  @override
  String resetDonePassword(String name) {
    return 'Password of $name has been reset with the reset disk';
  }

  @override
  String get resetUseDisk => 'Use reset disk';

  @override
  String get resetNoValidKey => 'No valid key found';

  @override
  String get resetSetNewFilePassword => 'Set a new file password';

  @override
  String resetSameAsLockScreen(String label) {
    return '$label must differ from the screen-lock password';
  }

  @override
  String get resetConfirmNewFilePassword => 'Confirm the new file password';

  @override
  String get resetMismatchRetry =>
      'The two entries don\'t match. Please try again';

  @override
  String get colorPickerTitle => 'Choose a color';

  @override
  String pinDigitsCount(int entered, int min, int max) {
    return '$entered / $max digits ($min–$max optional)';
  }

  @override
  String get lockButtonLock => 'Lock';

  @override
  String get lockButtonUnlock => 'Unlock';

  @override
  String get shellWorkspaceName => 'NoteStudio';

  @override
  String resetIntroNote(String name) {
    return 'Reset the standalone password of $name with the reset disk (USB drive).\n\nPrerequisite: this note has a reset disk bound (set a password, or bind one in password management).';
  }

  @override
  String resetIntroCanvas(String name) {
    return 'Reset the standalone password of $name with the reset disk (USB drive).\n\nPrerequisite: this canvas has a reset disk bound (set a password, or bind one in password management).';
  }

  @override
  String resetIntroNotebook(String name) {
    return 'Reset the password of $name with the reset disk (USB drive).\n\nPrerequisite: this paged canvas has a reset disk bound (set a password, or bind one in password management).';
  }

  @override
  String resetNotBoundNote(String name) {
    return '$name has no reset disk (USB drive) bound, so its password cannot be reset via the disk.\n\nYou can choose “Bind reset disk” in password management.';
  }

  @override
  String resetNotBoundCanvas(String name) {
    return '$name has no reset disk (USB drive) bound, so its password cannot be reset via the disk.\n\nYou can choose “Bind reset disk” in password management; passwords set in old versions (v1.5.x) must be changed once first to upgrade the format.';
  }

  @override
  String resetNotBoundNotebook(String name) {
    return '$name has no reset disk (USB drive) bound, so its password cannot be reset via the disk.\n\nAfter enabling password protection in Settings, choose “Bind reset disk” from the menu; passwords set in old versions must be changed once first to upgrade the format.';
  }

  @override
  String get resetNoValidKeyBody =>
      'No valid reset disk file (password_reset_disk.key) found at the chosen location.';

  @override
  String get homeReadListFailed => 'Failed to load the list. Please retry';

  @override
  String get homeNewInfiniteCanvas => 'New infinite canvas';

  @override
  String get homeNewInfiniteCanvasSub =>
      'Free-form drawing, shapes and diagrams';

  @override
  String get homeNewPagedCanvasSub =>
      'Multi-page binding, paper templates and mixed content';

  @override
  String get homeCreateFailedFull =>
      'Create failed: the notebook was not saved. Check disk space and retry';

  @override
  String get homeCanvasMissing => 'The canvas file is missing or corrupted';

  @override
  String get homeOpenCanvasFailed => 'Failed to open the canvas. Please retry';

  @override
  String get canvasStandalonePasswordProtected =>
      'This canvas is protected by a standalone password';

  @override
  String get canvasStandalonePasswordUnset =>
      'This canvas has no standalone password set';

  @override
  String get canvasVaultLockedSet =>
      'The vault is locked: re-verify the screen-lock password before setting';

  @override
  String get canvasVaultLockedRemove =>
      'The vault is locked and cannot re-seal: re-verify the screen-lock password and retry';

  @override
  String canvasPasswordSetDiskBoundFor(String name) {
    return 'Standalone password set for “$name” with the reset disk bound';
  }

  @override
  String get homeDeleteCanvasTitle => 'Delete canvas';

  @override
  String homeDeleteCanvasConfirm(String name) {
    return 'Delete the canvas “$name”? This cannot be undone.';
  }

  @override
  String get homeDeleteFailed => 'Delete failed. Please retry';

  @override
  String get homeSelectTemplate => 'Choose a note template';

  @override
  String get homeCreateFailed => 'Create failed. Please retry';

  @override
  String get homeTrashLoadFailed => 'Failed to load the trash. Please retry';

  @override
  String homeRecovered(String id) {
    return 'Restored “$id”';
  }

  @override
  String get homeRetry => 'Retry';

  @override
  String get homeNoCanvas => 'No canvases yet';

  @override
  String get homeNoNotes => 'No notes yet';

  @override
  String get homeEmptyTip =>
      'Tap the button in the lower-right corner to create one';

  @override
  String get homeInfiniteCanvas => 'Infinite canvases';

  @override
  String get homePagedCanvas => 'Paged canvases';

  @override
  String get homeDeleteNote => 'Delete note';

  @override
  String get homeStandalonePassword => 'Standalone password';

  @override
  String get homeDeleteInfiniteCanvas => 'Delete infinite canvas';

  @override
  String get homeNameHint => 'Enter a name';

  @override
  String get nbSessionLocked => 'The session is locked. Please unlock again';

  @override
  String get nbSessionExpired =>
      'The session expired. Please reopen this paged canvas';

  @override
  String get nbSessionRestored => 'Session restored';

  @override
  String get nbSaveFailed => 'Save failed. Please retry';

  @override
  String get nbReaderMode => 'Page reader';

  @override
  String get nbNewPage => 'New page';

  @override
  String get nbRenameNotebook => 'Rename paged canvas';

  @override
  String get nbOpenAsBlockDoc => 'Open as block document';

  @override
  String get nbNoPages => 'This paged canvas has no pages yet';

  @override
  String get nbNoPagesNew =>
      'This paged canvas has no pages yet — create one first';

  @override
  String get nbUntitledPage => 'Untitled page';

  @override
  String get nbNoteEncryptedLocked =>
      'The note is encrypted and the session is locked. Unlock again before opening';

  @override
  String get nbPickPageAsBlock => 'Choose a page to open as a block document';

  @override
  String get nbNoOtherNotebook => 'No other paged canvas to import from';

  @override
  String get nbPickSourceNotebook => 'Choose a source paged canvas';

  @override
  String get nbPickImportPages => 'Choose pages to import';

  @override
  String get nbExportPdfFailed =>
      'Failed to export the whole PDF. Please retry';

  @override
  String get nbDeletePage => 'Delete page';

  @override
  String get nbUndo => 'Undo';

  @override
  String get nbUndoSaveFailed => 'Undo failed to save. Please retry';

  @override
  String get nbPageRef => '🔗 Ref';

  @override
  String get nbUnfavoritePage => 'Remove from favorites';

  @override
  String get nbFavoritePage => 'Favorite this page';

  @override
  String get nbVersionHistory => 'Version history';

  @override
  String nbVersionHistoryOf(String name) {
    return 'Version history of “$name”';
  }

  @override
  String get nbPageNameLabel => 'Page name';

  @override
  String get nbChooseTemplate => 'Choose a template';

  @override
  String get nbCreateAndRecord => 'Create and start writing';

  @override
  String get nbPageNameHint => 'Enter a page name';

  @override
  String get nbPasswordHint => 'Enter the password';

  @override
  String get nbShowPassword => 'Show password';

  @override
  String get nbHidePassword => 'Hide password';

  @override
  String get impMarkdownText => 'Markdown / Text';

  @override
  String get impTextTooLarge =>
      'Text file too large (over the 20MB limit); import refused';

  @override
  String get impEmptyFile => 'The file is empty';

  @override
  String get impNoText => 'No text content parsed';

  @override
  String impImportedParagraphs(int count) {
    return 'Imported $count paragraphs';
  }

  @override
  String get impFailed => 'Import failed. Please retry';

  @override
  String get impPdfTypeGroup => 'PDF documents';

  @override
  String get impPdfNoPages => 'The PDF has no importable pages';

  @override
  String impPdfPageTitle(String name, int page) {
    return '$name · Page $page';
  }

  @override
  String impPdfDone(int count) {
    return 'Imported $count PDF pages; open any page to annotate';
  }

  @override
  String get impPdfFailed => 'Failed to import the PDF. Please retry';

  @override
  String get impChangePasswordProtect => 'Change password protection';

  @override
  String get impSetPasswordProtect => 'Set password protection';

  @override
  String get impChangeHint =>
      'After changing, opening requires the new password';

  @override
  String get impSetHint =>
      'Once set, page content is stored encrypted and requires the password to open';

  @override
  String get impPasswordSameAsLock =>
      'The password must differ from the screen-lock password';

  @override
  String get impRelockNeeded =>
      'Unlock with the password again before changing';

  @override
  String get impPasswordChanged => 'Password changed';

  @override
  String get impPasswordEnabled =>
      'Password protection enabled (page content stored encrypted)';

  @override
  String get impChangeFailed => 'Failed to change the password. Please retry';

  @override
  String get impSetFailed => 'Failed to set the password. Please retry';

  @override
  String get impBound => 'Reset disk bound';

  @override
  String get impBindFailed2 => 'Bind failed. Please retry';

  @override
  String get impUnlockFirst => 'Unlock with the password before binding';

  @override
  String get impNoVersions => 'No version history for this page yet';

  @override
  String get impRestore => 'Restore';

  @override
  String get syncFailedUnknown => 'Sync failed: unknown error';

  @override
  String get syncFailedRemoteFile =>
      'Sync failed: failed to sync a remote file. Check the server';

  @override
  String syncFailedHttpUnavailable(int code) {
    return 'Sync failed: server temporarily unavailable (HTTP $code). Try again later';
  }

  @override
  String get syncFailedDirMissing =>
      'Sync failed: remote directory missing or occupied. Check the remote directory settings';

  @override
  String get syncFailedHttps =>
      'Sync failed: HTTPS handshake failed. Check the server certificate';

  @override
  String get syncFailedConnect =>
      'Sync failed: cannot reach the server. Check the network or server address';

  @override
  String get syncFailedGeneric =>
      'Sync failed: check the network and account settings, then retry';

  @override
  String get syncMissingSalt =>
      'The sync config lacks its salt: tap “Save config” again before syncing';

  @override
  String get syncMaxRetries => 'Max retries reached';

  @override
  String get syncUpToDate => 'Already up to date';

  @override
  String syncWithConflicts(String base, int count) {
    return '$base; $count more documents changed both locally and remotely and were handled per your choice';
  }

  @override
  String get webdavTitle => 'WebDAV Sync';

  @override
  String get webdavUsername => 'Username';

  @override
  String get webdavSyncNow => 'Sync now';

  @override
  String get webdavSave => 'Save config';

  @override
  String get cmdNewSticky => 'New sticky note';

  @override
  String get cmdGroupEdit => 'Edit';

  @override
  String get cmdCancelConnect => 'Cancel connect';

  @override
  String get cmdConnectMode => 'Connect mode';

  @override
  String get cmdGroupSelected => 'Group selected';

  @override
  String get cmdNeedTwoFrames => 'Needs ≥2 frames';

  @override
  String get cmdFitContent => 'Fit content';

  @override
  String get cmdGroupView => 'View';

  @override
  String get cmdFitSelected => 'Fit selection';

  @override
  String get cmdZoomIn => 'Zoom in';

  @override
  String get cmdZoomOut => 'Zoom out';

  @override
  String get cmdExitMulti => 'Exit multi-select';

  @override
  String get cmdEnterMulti => 'Enter multi-select';

  @override
  String get cmdGroupSelect => 'Select';

  @override
  String get cmdClearSelection => 'Clear selection';

  @override
  String get cmdFocusSelected => 'Focus selection';

  @override
  String get cmdGroupJump => 'Go to';

  @override
  String get cmdNoMatch => 'No matching commands';

  @override
  String get edPickSourceFrame => 'Select a frame first as the connector start';

  @override
  String get edNewFrame => 'Add frame';

  @override
  String get edFit => 'Fit';

  @override
  String get edMultiSelect => 'Multi-select (group)';

  @override
  String get edGroup => 'Group';

  @override
  String get edStickyTitle => 'Sticky note';

  @override
  String get edFrameColor => 'Frame background color';

  @override
  String get edConnect => 'Connect';

  @override
  String get edEditContent => 'Edit content';

  @override
  String get edDeleteFrame => 'Delete frame';

  @override
  String get edSelect => 'Select';

  @override
  String get edSticky => 'Sticky';

  @override
  String get edBrush => 'Brush';

  @override
  String get edEraser => 'Eraser';

  @override
  String get edShape => 'Shape';

  @override
  String get edRect => 'Rectangle';

  @override
  String get edOval => 'Oval';

  @override
  String get pfCode => 'Code block';

  @override
  String get pfImage => 'Image';

  @override
  String get pfLink => 'Link';

  @override
  String get pfCanvas => 'Canvas';

  @override
  String get pfChart => 'Chart';

  @override
  String get pfTable => 'Table';

  @override
  String get pfDatabase => 'Database';

  @override
  String get pfAttachment => 'Attachment';

  @override
  String readerTitle(String name) {
    return '$name · Page reader';
  }

  @override
  String readerPageIndicator(int index, int total) {
    return 'Page $index of $total';
  }

  @override
  String get notesWritingTitle => 'Notes';

  @override
  String get notesRecent => 'Recent';

  @override
  String get obWelcome => 'Welcome to Drawing Notes';

  @override
  String get obBrushTip =>
      'Brush / eraser / eyedropper: switch on the top toolbar; draw with mouse or finger';

  @override
  String get obColorTip =>
      'Color and stroke: the color chip and thickness slider on the right of the toolbar';

  @override
  String get obLayerTip =>
      'Layers panel on the right: create, show/hide, opacity, reorder, merge';

  @override
  String get obSelectTip =>
      'Selection tool: marquee-select to move / scale / rotate / copy / delete';

  @override
  String get obNoteTip =>
      'Note pages support text and images: tap with the text tool; insert via the image button';

  @override
  String get obFullscreenTip =>
      'Fullscreen button top-right: hides toolbars for a clean canvas';

  @override
  String get obStart => 'Get started';

  @override
  String get presNoContent => 'Nothing to present';

  @override
  String presIndicator(int index, int total) {
    return '$index / $total · Click or → for next, Esc to exit';
  }

  @override
  String get presExit => 'Exit presentation';

  @override
  String get pdfPreviewUnavailable => 'Inline PDF preview unavailable';

  @override
  String get conflictApplyAll => 'Apply all';

  @override
  String get conflictKeepLocal => 'Keep local';

  @override
  String get conflictKeepCloud => 'Keep remote';

  @override
  String get conflictKeepBoth => 'Keep both';

  @override
  String get searchKindNotebook => 'Paged canvas';

  @override
  String get searchKindPageTitle => 'Page title';

  @override
  String get searchKindCanvas => 'Canvas';

  @override
  String get searchKindBlockDoc => 'Block document';

  @override
  String get searchKindDocTitle => 'Document title';

  @override
  String get templateBlank => 'Blank note';

  @override
  String get templateLined => 'Lined note';

  @override
  String get templateGrid => 'Grid paper';

  @override
  String get templateDot => 'Dot-grid note';

  @override
  String get templateMeeting => 'Meeting notes';

  @override
  String get templateCornell => 'Cornell notes';

  @override
  String get templatePlanner => 'Planner page';

  @override
  String get templateWhiteboard => 'Wide whiteboard';

  @override
  String get rootRefusedTitle => 'Cannot start on this device';

  @override
  String get rootRefusedBody =>
      'This device has ROOT access. To protect your encrypted notes, the app refuses to run on a compromised device.';

  @override
  String get canvasBindConfirmContent =>
      'When you forget this canvas’s standalone password, plug in the reset disk (USB drive) to reset without the old password.\n\nThe drive holds only a random key file (password_reset_disk.key); canvas data never leaves the device.';

  @override
  String canvasRemoveConfirmContent(String name) {
    return 'After removal, “$name” falls back to vault protection (master-key envelope) and no longer needs a standalone password. Remove it?';
  }

  @override
  String canvasBoundDiskFor(String name) {
    return 'Reset disk bound for “$name”';
  }

  @override
  String homeDeleteForeverConfirm(String name) {
    return 'Permanently delete “$name”? This cannot be undone.';
  }

  @override
  String get homeRestoreFailed => 'Restore failed. Please retry';

  @override
  String get homeTabCanvas => 'Canvases';

  @override
  String get homeTabNotes => 'Notes';

  @override
  String get canvasDeletePasswordTitle =>
      'This canvas is encrypted. Enter its standalone password';

  @override
  String get homeKindNote => 'Note';

  @override
  String get homeKindNotebookPage => 'Paged-canvas page';

  @override
  String homeUpdatedAt(String time) {
    return 'Updated $time';
  }

  @override
  String homeDeleteNoteConfirm(Object name) {
    return 'Delete the note “$name”? This cannot be undone.';
  }

  @override
  String get homeUntitledNotebookPage => 'Untitled';

  @override
  String get homeStandalonePasswordMenu => 'Standalone password…';

  @override
  String get nbEmptyTip => 'Tap New in the top-right corner';

  @override
  String get nbNoTagMatch => 'No pages match this tag';

  @override
  String get nbNoTagMatchTip => 'Try another tag';

  @override
  String get impBindAskContent =>
      'When you forget the password, plug in the USB drive to reset a new one.\n\nYou can also bind later via “Bind reset disk” in the menu.';

  @override
  String get impRestoreConfirmTitle => 'Restore this version?';

  @override
  String get impRestoreConfirmContent =>
      'The current page content will be overwritten by the chosen version (current content is saved to history first).';

  @override
  String get nbPageNameExampleHint => 'e.g. Product review 08-14';

  @override
  String nbDeletePageConfirm(String name) {
    return 'Delete the page “$name”? Its handwriting and text will be deleted too.';
  }

  @override
  String nbPageDeleted(String name) {
    return 'Deleted “$name”';
  }

  @override
  String nbExportedPdf(int count, String path) {
    return 'Exported a $count-page PDF: $path';
  }

  @override
  String cmdGotoFrame(String name) {
    return 'Go to “$name”';
  }

  @override
  String get obPinchTip =>
      'Pinch with two fingers to zoom, rotate with two fingers (touch devices)';

  @override
  String get obAutosaveTip =>
      'Content autosaves — no manual save needed; export to PNG anytime';

  @override
  String get syncFailedAuth =>
      'Sync failed: wrong username or password (server rejected the login)';

  @override
  String syncFailedRejected(String code) {
    return 'Sync failed: the server rejected this request (HTTP $code)';
  }

  @override
  String get syncHttpUnknown => 'unknown';

  @override
  String syncDoneSummary(int up, int down, int del) {
    return 'Sync done: ↑$up ↓$down ✕$del';
  }

  @override
  String get webdavFormDirty =>
      'The form has unsaved changes: tap “Save config” before syncing (avoids mismatched keys and cloud data)';

  @override
  String get webdavSyncSecretLabel =>
      'Sync password (required, for end-to-end encryption)';

  @override
  String get webdavSyncSecretHelper =>
      'Syncing is blocked without a sync password (prevents plaintext notes in the cloud)';

  @override
  String get webdavSyncing => 'Syncing…';

  @override
  String get tplDescMeeting =>
      'Starting structure with topics, decisions and action items.';

  @override
  String get tplDescCornell =>
      'Starting structure with cue, notes and summary areas.';

  @override
  String get tplDescPlanner =>
      'Starting structure with priorities, schedule and review.';

  @override
  String get tplDescWhiteboard =>
      'Wide blank canvas mode; this version still uses a fixed coordinate paper.';

  @override
  String get tplDescDefault =>
      'The paper background follows the template and is saved to the page.';

  @override
  String get homeDeleteForeverFailed => 'Permanent delete failed. Please retry';

  @override
  String get impDiskNotFound =>
      'No valid reset disk file (password_reset_disk.key) found';

  @override
  String get lockDiskKeepNote =>
      'Do not delete the password_reset_disk.key file on the USB drive';
}

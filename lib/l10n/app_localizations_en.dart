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

  @override
  String get cmdUndo => 'Undo';

  @override
  String get cmdRedo => 'Redo';

  @override
  String get cmdCopySelection => 'Copy selection';

  @override
  String get cmdPasteClipboard => 'Paste from clipboard';

  @override
  String get cmdDuplicateSelection => 'Duplicate selection';

  @override
  String get cmdDeleteSelection => 'Delete selection';

  @override
  String get cmdBold => 'Bold selected text';

  @override
  String get cmdItalic => 'Italicize selected text';

  @override
  String get cmdUnderline => 'Underline selected text';

  @override
  String get cmdStrikethrough => 'Strikethrough selected text';

  @override
  String get cmdCycleAlign => 'Cycle text alignment';

  @override
  String get cmdFitCanvas => 'Fit canvas';

  @override
  String get cmdToggleGrid => 'Show or hide grid';

  @override
  String get cmdToggleSnap => 'Toggle grid snap';

  @override
  String get cmdExportWord => 'Export Word-compatible document';

  @override
  String get catEdit => 'Edit';

  @override
  String get catFormat => 'Format';

  @override
  String get catInsert => 'Insert';

  @override
  String get catArrange => 'Arrange';

  @override
  String get catView => 'View';

  @override
  String get catExport => 'Export';

  @override
  String get expCopyRenderFail => 'Copy failed: cannot render the canvas';

  @override
  String get expCopyDecodeFail => 'Copy failed: pixel decoding failed';

  @override
  String get expCopiedPng => 'PNG copied to clipboard';

  @override
  String get expRenderFail => 'Export failed: cannot render the canvas';

  @override
  String get expNoPages => 'No pages to export';

  @override
  String get expEmptyCanvas => 'Export failed: the canvas is empty';

  @override
  String get expWordPagedOnly =>
      'Only paged notes support exporting Word-compatible documents';

  @override
  String get expWordNoText => 'This page has no text content to export';

  @override
  String get expTextPagedOnly =>
      'Only paged-canvas pages support exporting text';

  @override
  String get expTextNoText => 'This page has no text content';

  @override
  String get expPptxPackFail => 'Export failed: PPTX packaging failed';

  @override
  String get fileTypePng => 'PNG image';

  @override
  String get fileTypePdf => 'PDF document';

  @override
  String get fileTypeSvg => 'SVG vector image';

  @override
  String get fileTypeWord => 'Word-compatible document';

  @override
  String get fileTypeMarkdown => 'Markdown / Text';

  @override
  String get fileTypePptx => 'PPTX presentation';

  @override
  String get fileTypeJson => 'JSON project file';

  @override
  String get expWholeBookSuffix => 'whole-book';

  @override
  String get pdfPaperFollow => 'Follow canvas';

  @override
  String get pdfRangeCurrent => 'Current page';

  @override
  String get pdfRangeAll => 'All pages';

  @override
  String get pdfQualityLossless => 'Lossless';

  @override
  String get pdfQualityLosslessDesc => 'PNG lossless, largest size';

  @override
  String get pdfQualityStandardDesc => 'JPEG 80, recommended';

  @override
  String get pdfQualitySaverDesc => 'JPEG 60, smallest size';

  @override
  String get pdfGroupPaper => 'Paper';

  @override
  String get pdfGroupQuality => 'Quality';

  @override
  String pdfExportNPages(int count) {
    return 'Export $count pages';
  }

  @override
  String get inkStylusPressure => 'Stylus pressure';

  @override
  String get inkTouchPressure => 'Touch pressure';

  @override
  String get inkMouseVelocity => 'Mouse velocity simulation';

  @override
  String get inkConstant => 'Constant width';

  @override
  String get pomodoroPause => 'Pause';

  @override
  String get pomodoroStart => 'Start';

  @override
  String get pomodoroReset => 'Reset';

  @override
  String get pomodoroFinish => 'Pomodoro finished: take a break';

  @override
  String pageIndicator(int index, int total) {
    return 'Page $index of $total';
  }

  @override
  String get eraserWholeStroke => 'Whole stroke';

  @override
  String get eraserTransparent => 'Pixels';

  @override
  String get markerSave => 'Save';

  @override
  String get markerAutoFade => 'Auto-fade';

  @override
  String get tooltipSwapFill => 'Swap fill color';

  @override
  String get tooltipDashStyle => 'Solid / dashed';

  @override
  String get hintEyedropper => 'Tap the canvas to pick a color';

  @override
  String get hintTextTool => 'Tap the canvas to place text';

  @override
  String get hintConnect => 'Pick two elements in turn to connect';

  @override
  String get hintPixelEraser => 'Erase transparent pixels';

  @override
  String get hintStrokeEraser => 'Delete whole strokes';

  @override
  String get hintTempHighlight => 'Temporary highlight: auto-fades in ~4s';

  @override
  String get hintSavedHighlight => 'Highlighter: saved to the page';

  @override
  String get hintLaser =>
      'Laser pointer: fades segment by segment after release; not saved';

  @override
  String get hintBrush => 'Brush';

  @override
  String get toolEyedropper => 'Eyedropper';

  @override
  String get toolMarquee => 'Marquee-select elements';

  @override
  String get toolNodeLink => 'Node link';

  @override
  String get shapeRect => 'Rectangle';

  @override
  String get shapeEllipse => 'Ellipse';

  @override
  String get shapeDiamond => 'Diamond';

  @override
  String get shapeArrow => 'Arrow';

  @override
  String get shapeLine => 'Line';

  @override
  String get saveStateUnsaved => 'Unsaved';

  @override
  String get saveStateSaved => 'Saved';

  @override
  String get cropInvalid => 'Invalid crop area';

  @override
  String get cropSourceMissing => 'Source image file is missing';

  @override
  String get cropEncodeFail => 'Crop encoding failed';

  @override
  String get cropVaultLocked => 'Vault is locked; cannot save the crop';

  @override
  String get cropDone => 'Image cropped';

  @override
  String get cropDragHint =>
      'Drag the corners to adjust the crop area, then tap the crop button';

  @override
  String get cropHandleTopLeft => 'Adjust crop top-left corner';

  @override
  String get cropHandleTopRight => 'Adjust crop top-right corner';

  @override
  String get cropHandleBottomLeft => 'Adjust crop bottom-left corner';

  @override
  String get cropHandleBottomRight => 'Adjust crop bottom-right corner';

  @override
  String get canvasSemanticsLabel => 'Drawing canvas';

  @override
  String get canvasSemanticsHint =>
      'Double-tap blank space to insert text; draw with the toolbar tools';

  @override
  String get actSwitchInfinite => 'Switched to infinite canvas (unbounded)';

  @override
  String get actSwitchFixed => 'Switched back to fixed paper';

  @override
  String get actChartPagedOnly => 'Only paged-canvas pages support charts';

  @override
  String get actChartTitle => 'Generate chart';

  @override
  String get actChartBar => 'Bar chart';

  @override
  String get actChartLine => 'Line chart';

  @override
  String get actChartGenerate => 'Generate';

  @override
  String get actChartNoData => 'No valid numbers parsed';

  @override
  String get actSlidesPagedOnly =>
      'Only paged-canvas pages support slide presentation';

  @override
  String get actSlidesNoContent => 'This page has nothing to present';

  @override
  String get actSlidesUnavailable => 'Presentation unavailable';

  @override
  String get actStatsTitle => 'Canvas statistics';

  @override
  String get actStatStrokes => 'Handwritten strokes';

  @override
  String get actStatTextBlocks => 'Text blocks';

  @override
  String get actStatImages => 'Images';

  @override
  String get actStatShapes => 'Shapes';

  @override
  String get actStatCharts => 'Charts';

  @override
  String get actStatTotal => 'Total elements';

  @override
  String get actShapeLibPagedOnly =>
      'Only paged-canvas pages support the shape library';

  @override
  String actCopiedN(int count) {
    return 'Copied $count elements';
  }

  @override
  String get actPickFirst => 'Select elements to copy first';

  @override
  String actPastedN(int count) {
    return 'Pasted $count elements';
  }

  @override
  String get actCopiedTextStyle => 'Text style copied';

  @override
  String get actCopiedShapeStyle => 'Shape style copied';

  @override
  String get actPickStyleSource => 'Select a text block or shape first';

  @override
  String get actCopyStyleFirst =>
      'Copy a style first (Ctrl+Shift+C) before pasting';

  @override
  String get actPastedStyle => 'Style pasted';

  @override
  String get actPastePagedOnly => 'Only paged-canvas pages support pasting';

  @override
  String get actClipboardNoText => 'No pastable text in the clipboard';

  @override
  String get actShortcutsTitle => 'Shortcuts';

  @override
  String get barPagedNote => 'Paged note';

  @override
  String get barInfiniteCanvas => 'Infinite canvas';

  @override
  String get barHideLayers => 'Hide layers';

  @override
  String get barShowLayers => 'Show layers';

  @override
  String get barHideInspector => 'Hide inspector';

  @override
  String get barShowInspector => 'Show inspector';

  @override
  String get barExitFullscreen => 'Exit fullscreen';

  @override
  String get barEnterFullscreen => 'Fullscreen';

  @override
  String get barReadingOff => 'Turn off dark reading';

  @override
  String get barReadingOn => 'Dark reading (display only)';

  @override
  String get menuExportText => 'Export text';

  @override
  String get menuCommandPalette => 'Command palette';

  @override
  String get menuSlides => 'Slide presentation';

  @override
  String get menuStats => 'Statistics';

  @override
  String get menuShortcuts => 'Shortcut help';

  @override
  String get menuSwitchToFixed => 'Switch to fixed paper';

  @override
  String get menuSwitchToInfinite => 'Switch to infinite canvas';

  @override
  String get paletteRecent => 'Recently used';

  @override
  String get paletteNoMatch => 'No matching commands';

  @override
  String get textInputTitle => 'Enter text';

  @override
  String get textInputHint => 'Enter text content';

  @override
  String get distributeNeed3 => 'At least 3 elements are needed to distribute';

  @override
  String get distributedH => 'Distributed horizontally';

  @override
  String get distributedV => 'Distributed vertically';

  @override
  String get edPreviewPagedOnly =>
      'Only paged-canvas pages support paged preview';

  @override
  String get edNoTextHere => 'This page has no text content yet';

  @override
  String get edNoTextBlocks => 'No text blocks on this page';

  @override
  String edRecoloredN(int count) {
    return 'Recolored $count text blocks';
  }

  @override
  String get edImageLabel => 'Image';

  @override
  String get edNoteImageStoreUnavailable => 'Note image storage unavailable';

  @override
  String get edDrawingImageStoreUnavailable =>
      'Drawing image storage unavailable';

  @override
  String get edLinkStartPicked =>
      'Start picked; tap another element to finish the connector';

  @override
  String get edLinkCreated => 'Connector created';

  @override
  String get ctxCopyStyle => 'Copy style';

  @override
  String get ctxGroup => 'Group';

  @override
  String get ctxUngroup => 'Ungroup';

  @override
  String get ctxBringToFront => 'Bring to front';

  @override
  String get ctxSendToBack => 'Send to back';

  @override
  String get edLinkInvalid => 'Link invalid or unsupported';

  @override
  String get edLinkOpened => 'Link opened';

  @override
  String get edLinkTitle => 'Set link';

  @override
  String get edLinkCleared => 'Link cleared';

  @override
  String get edLinkSet => 'Link set';

  @override
  String get edGroupNeed2 =>
      'Marquee/multi-select at least 2 elements before grouping';

  @override
  String edGroupedN(int count) {
    return 'Grouped $count elements';
  }

  @override
  String get edUngrouped => 'Ungrouped';

  @override
  String get renameCanvasTitle => 'Rename canvas';

  @override
  String get textBold => 'Bold';

  @override
  String get textItalic => 'Italic';

  @override
  String get textTodo => 'To-do';

  @override
  String get textCenter => 'Center';

  @override
  String get textDone => 'Done';

  @override
  String get textWidthHandle => 'Adjust text width';

  @override
  String get toolEraserName => 'Eraser';

  @override
  String get pressureReal => 'Using the device\'s reported pressure range';

  @override
  String get pressureFallback =>
      'This device reports no usable pressure; a stable fallback is in use';

  @override
  String get coordsHide => 'Hide coordinates';

  @override
  String get coordsShow => 'Show canvas coordinates';

  @override
  String get zoomTooltip => 'Zoom canvas';

  @override
  String get layersTitle => 'Layers';

  @override
  String get layerNew => 'New layer';

  @override
  String get layerUp => 'Move up';

  @override
  String get layerDown => 'Move down';

  @override
  String get layerMergeDown => 'Merge down';

  @override
  String get layerDelete => 'Delete layer';

  @override
  String get propBrush => 'Brush';

  @override
  String get propBrushColor => 'Brush color';

  @override
  String get propImage => 'Image';

  @override
  String get propCropImage => 'Crop image';

  @override
  String get propShape => 'Shape';

  @override
  String get propFillColor => 'Fill color';

  @override
  String get propDash => 'Solid/dashed';

  @override
  String get propText => 'Text';

  @override
  String get propTextColor => 'Text color';

  @override
  String get fontSerif => 'Serif';

  @override
  String get fontMono => 'Monospace';

  @override
  String get fontHandwriting => 'Handwriting';

  @override
  String get fontDefault => 'Default';

  @override
  String get selCopy => 'Copy selection';

  @override
  String get selPaste => 'Paste';

  @override
  String get selUnlock => 'Unlock selection';

  @override
  String get selLock => 'Lock selection against accidental edits';

  @override
  String get selUnlockImage => 'Unlock image';

  @override
  String get selLockImage => 'Lock image against accidental edits';

  @override
  String get selUnlockShape => 'Unlock shape';

  @override
  String get selLockShape => 'Lock shape against accidental edits';

  @override
  String get selDeleteLockedKeep =>
      'Delete unlocked objects; locked ones are kept';

  @override
  String get selDelete => 'Delete selection';

  @override
  String get selShapeLocked => 'Shape is locked; cannot delete';

  @override
  String get selImageLocked => 'Image is locked; cannot delete';

  @override
  String get selDeleteContent => 'Delete selected content';

  @override
  String selNObjects(int count) {
    return '$count objects selected';
  }

  @override
  String get selShapeLockedEdit => 'Shape locked: unlock to edit';

  @override
  String get selShapeSelected => 'Shape selected: drag, scale, lock or delete';

  @override
  String get selImageLockedEdit => 'Image locked: unlock to edit';

  @override
  String get selImageSelected => 'Image selected: drag, scale, lock or delete';

  @override
  String selNStrokes(int count) {
    return '$count strokes selected';
  }

  @override
  String get selClear => 'Clear selection';

  @override
  String get shapeLibNoMatch => 'No matching shapes';

  @override
  String get noteImageSemantic => 'Note image';

  @override
  String get segmentEndpointSemantic => 'Adjust segment endpoint';

  @override
  String get saveStateSaving => 'Saving…';

  @override
  String saveStateSavedAt(String time) {
    return 'Saved $time';
  }

  @override
  String actInsertedShape(String name) {
    return 'Inserted “$name”';
  }

  @override
  String get tParagraph => 'Paragraph';

  @override
  String get tHeading => 'Heading';

  @override
  String get tBulletList => 'Bullet list';

  @override
  String get tOrderedList => 'Numbered list';

  @override
  String get tTodo => 'To-do';

  @override
  String get tQuote => 'Quote';

  @override
  String get tCode => 'Code';

  @override
  String get tDivider => 'Divider';

  @override
  String get tImage => 'Image';

  @override
  String get tLink => 'Link';

  @override
  String get tTable => 'Table';

  @override
  String get tDatabase => 'Database';

  @override
  String get tEmbedCanvas => 'Embed canvas';

  @override
  String get tEmbedChart => 'Embed chart';

  @override
  String get docSaveFailedRetry => 'Save failed. Please retry';

  @override
  String get docSavedToast => 'Document saved';

  @override
  String get docToolbarSave => 'Save';

  @override
  String get docToolbarOutline => 'Outline';

  @override
  String get docToolbarRefresh => 'Refresh';

  @override
  String get docOutlineEmpty =>
      'No heading blocks yet — insert a heading via the / menu to see it here';

  @override
  String get docUnsavedChangesTitle => 'Unsaved changes';

  @override
  String get docDiscard => 'Discard';

  @override
  String get blkSlashHint => 'Type / to add a block';

  @override
  String get blkEnterHint => 'Enter splits blocks; Backspace merges empty ones';

  @override
  String get blkDragToSort => 'Drag to sort';

  @override
  String semHeading(String level) {
    return 'Heading $level';
  }

  @override
  String get semTodo => 'To-do';

  @override
  String get semCode => 'Code block';

  @override
  String get semQuote => 'Quote';

  @override
  String get semBullet => 'Bullet list';

  @override
  String get semOrdered => 'Numbered list';

  @override
  String get semDivider => 'Divider';

  @override
  String get semCallout => 'Callout';

  @override
  String get semToggle => 'Toggle list';

  @override
  String get semImage => 'Image';

  @override
  String get semParagraph => 'Paragraph';

  @override
  String get semEmpty => 'empty';

  @override
  String get hintHeading => 'Heading';

  @override
  String get hintListItem => 'List item';

  @override
  String get hintTodo => 'To-do';

  @override
  String get hintToggle => 'Toggle list';

  @override
  String get hintQuote => 'Quote';

  @override
  String get hintCode => 'Code';

  @override
  String get hintTypeContent => 'Type something...';

  @override
  String get mtBold => 'Bold';

  @override
  String get mtItalic => 'Italic';

  @override
  String get mtUnderline => 'Underline';

  @override
  String get mtLink => 'Link';

  @override
  String get mtCopyBlock => 'Copy block';

  @override
  String get mtDeleteBlock => 'Delete block';

  @override
  String get outlineTitle => 'Outline';

  @override
  String get wBack => 'Back';

  @override
  String get wInsertPageLink => 'Insert page link';

  @override
  String get wSave => 'Save';

  @override
  String get wUnfavorite => 'Remove from favorites';

  @override
  String get wFavorite => 'Favorite';

  @override
  String get wDocInfo => 'Document info';

  @override
  String get wMore => 'More';

  @override
  String get wOpenInCanvas => 'Open in canvas';

  @override
  String get wFilePassword => 'File password';

  @override
  String get wShare => 'Share';

  @override
  String get docSnackSaveKept => 'Save failed; previous state kept';

  @override
  String get docSnackTagFailed => 'Failed to create the tag. Please retry';

  @override
  String get attUntitled => 'Untitled attachment';

  @override
  String get attEditDesc => 'Edit description';

  @override
  String get attOpenLink => 'Open link';

  @override
  String get attEditNote => 'Edit note';

  @override
  String get attDescHint => 'Attachment description / note';

  @override
  String get sgBasic => 'Basic';

  @override
  String get sgQuoteCode => 'Quote & code';

  @override
  String get sgMedia => 'Media';

  @override
  String get sgEmbed => 'Embed';

  @override
  String get sgOther => 'Other';

  @override
  String get slashNoMatch => 'No matches';

  @override
  String get dbUntitled => 'Database';

  @override
  String get dbAddField => 'Add field';

  @override
  String get dbAddRecord => 'Add record';

  @override
  String get dbSearchRecords => 'Search records';

  @override
  String get dbClearFilter => 'Clear filter';

  @override
  String get dbViewTable => 'Table';

  @override
  String get dbViewKanban => 'Kanban';

  @override
  String get dbViewList => 'List';

  @override
  String get dbCellHint => 'Enter a value';

  @override
  String get dbCellNone => 'Not selected';

  @override
  String dbRecordCount(int count) {
    return '$count records';
  }

  @override
  String get dbKanbanNeedsSelect =>
      'Kanban needs at least one option field; add a select field first';

  @override
  String get dbUngrouped => 'Ungrouped';

  @override
  String get dbNoTitleRecord => 'Untitled record';

  @override
  String get dbNoFieldsYet =>
      'No fields yet — tap “Add field” to start the table';

  @override
  String get dbFieldActions => 'Field actions';

  @override
  String get dbDeleteField => 'Delete field';

  @override
  String get dbToggleCheck => 'Toggle check';

  @override
  String get dbDeleteRecord => 'Delete record';

  @override
  String get embUnsafeImage => 'Unsafe image source blocked';

  @override
  String get embImageFailed => 'Failed to load image';

  @override
  String get embClickPreview => 'Tap to preview';

  @override
  String get embCanvasLabel => 'Embedded canvas';

  @override
  String get embChartLabel => 'Embedded chart';

  @override
  String get embHostBuilderHint =>
      'Host provides the builder to render full content';

  @override
  String get tblAddColumn => 'Add column';

  @override
  String get tblDeleteColumn => 'Delete column';

  @override
  String get tblAddRow => 'Add row';

  @override
  String get tblDeleteRow => 'Delete row';

  @override
  String get trashDeleteForeverTitle => 'Delete permanently';

  @override
  String get trashTitleBar => 'Trash';

  @override
  String get trashEmptyTitle => 'Trash is empty';

  @override
  String get trashEmptyTip =>
      'Deleted notes are kept here for 30 days and can be restored anytime';

  @override
  String get trashRestore => 'Restore';

  @override
  String get tplBlankName => 'Blank note';

  @override
  String get tplBlankDesc => 'Start from scratch';

  @override
  String get tplMeetingName => 'Meeting notes';

  @override
  String get tplMeetingDesc => 'Topics · decisions · action items';

  @override
  String get tplDailyName => 'Daily journal';

  @override
  String get tplDailyDesc => 'Done today · planned tomorrow';

  @override
  String get tplTodoName => 'To-do list';

  @override
  String get tplTodoDesc => 'Prebuilt to-do blocks';
}

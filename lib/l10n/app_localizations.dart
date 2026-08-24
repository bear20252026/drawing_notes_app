import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Drawing Notes'**
  String get appTitle;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash (recoverable within 30 days)'**
  String get trash;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @newNotebook.
  ///
  /// In en, this message translates to:
  /// **'New Notebook'**
  String get newNotebook;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @homeTrashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get homeTrashEmpty;

  /// No description provided for @homeDeletedAt.
  ///
  /// In en, this message translates to:
  /// **'Deleted at {time}'**
  String homeDeletedAt(Object time);

  /// No description provided for @homeRecover.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get homeRecover;

  /// No description provided for @homeDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete Forever'**
  String get homeDeleteForever;

  /// No description provided for @homeEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get homeEmptyTrash;

  /// No description provided for @homeCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get homeCancel;

  /// No description provided for @homeSwitchTheme.
  ///
  /// In en, this message translates to:
  /// **'Switch Theme (System / Light / Dark)'**
  String get homeSwitchTheme;

  /// No description provided for @homeMore.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get homeMore;

  /// No description provided for @homeRecovered.
  ///
  /// In en, this message translates to:
  /// **'Recovered \"{id}\"'**
  String homeRecovered(Object id);

  /// No description provided for @homePasswordDiskAndRecovery.
  ///
  /// In en, this message translates to:
  /// **'Password Disk & Recovery'**
  String get homePasswordDiskAndRecovery;

  /// No description provided for @homeInfiniteCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get homeInfiniteCanvas;

  /// No description provided for @homeNotebook.
  ///
  /// In en, this message translates to:
  /// **'Notebooks'**
  String get homeNotebook;

  /// No description provided for @homeRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get homeRecent;

  /// No description provided for @homeNewInfiniteCanvas.
  ///
  /// In en, this message translates to:
  /// **'New Canvas'**
  String get homeNewInfiniteCanvas;

  /// No description provided for @homeQuickRecord.
  ///
  /// In en, this message translates to:
  /// **'Quick Record'**
  String get homeQuickRecord;

  /// No description provided for @homeRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get homeRetry;

  /// No description provided for @homeErrorDrawingNotFound.
  ///
  /// In en, this message translates to:
  /// **'Drawing file not found or corrupted'**
  String get homeErrorDrawingNotFound;

  /// No description provided for @homeErrorOpenDrawing.
  ///
  /// In en, this message translates to:
  /// **'Failed to open drawing: {error}'**
  String homeErrorOpenDrawing(Object error);

  /// No description provided for @homeDeleteDrawing.
  ///
  /// In en, this message translates to:
  /// **'Delete Drawing'**
  String get homeDeleteDrawing;

  /// No description provided for @homeConfirmDeleteDrawing.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"? This action cannot be undone.'**
  String homeConfirmDeleteDrawing(Object title);

  /// No description provided for @homeDeleteNotebook.
  ///
  /// In en, this message translates to:
  /// **'Delete Notebook'**
  String get homeDeleteNotebook;

  /// No description provided for @homeConfirmDeleteNotebook.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete notebook \"{title}\"? All pages and content will be permanently deleted.'**
  String homeConfirmDeleteNotebook(Object title);

  /// No description provided for @homeConfirmPermanentDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete \"{name}\"? This action cannot be undone.'**
  String homeConfirmPermanentDelete(Object name);

  /// No description provided for @homeErrorDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String homeErrorDeleteFailed(Object error);

  /// No description provided for @homeErrorPolicyDenied.
  ///
  /// In en, this message translates to:
  /// **'Operation denied by policy ({policy})'**
  String homeErrorPolicyDenied(Object policy);

  /// No description provided for @homeLegacyEncryptionWarning.
  ///
  /// In en, this message translates to:
  /// **'Legacy encryption format detected (100K iterations). Please re-save to upgrade to the latest standard (600K iterations).'**
  String get homeLegacyEncryptionWarning;

  /// No description provided for @homeEncryptionUpgraded.
  ///
  /// In en, this message translates to:
  /// **'Encryption automatically upgraded to latest standard (600K iterations)'**
  String get homeEncryptionUpgraded;

  /// No description provided for @homeLegacyEncryptionManual.
  ///
  /// In en, this message translates to:
  /// **'Legacy encryption: manual re-save recommended'**
  String get homeLegacyEncryptionManual;

  /// No description provided for @homeErrorLoadList.
  ///
  /// In en, this message translates to:
  /// **'Failed to load list: {error}'**
  String homeErrorLoadList(Object error);

  /// No description provided for @homeNewDrawingTitle.
  ///
  /// In en, this message translates to:
  /// **'New Canvas'**
  String get homeNewDrawingTitle;

  /// No description provided for @homeErrorCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Creation failed: {error}'**
  String homeErrorCreateFailed(Object error);

  /// No description provided for @homeOpenCanvasTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Canvas {title}'**
  String homeOpenCanvasTitle(Object title);

  /// No description provided for @homeQuickRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Record {time}'**
  String homeQuickRecordTitle(Object time);

  /// No description provided for @editorUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get editorUndo;

  /// No description provided for @editorRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get editorRedo;

  /// No description provided for @editorShortcutsHelp.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts Help'**
  String get editorShortcutsHelp;

  /// No description provided for @editorMenu.
  ///
  /// In en, this message translates to:
  /// **'Main Menu'**
  String get editorMenu;

  /// No description provided for @editorClearCanvas.
  ///
  /// In en, this message translates to:
  /// **'Clear Canvas'**
  String get editorClearCanvas;

  /// No description provided for @editorCopyPng.
  ///
  /// In en, this message translates to:
  /// **'Copy PNG to Clipboard'**
  String get editorCopyPng;

  /// No description provided for @editorExportPng.
  ///
  /// In en, this message translates to:
  /// **'Export PNG'**
  String get editorExportPng;

  /// No description provided for @editorExportSvg.
  ///
  /// In en, this message translates to:
  /// **'Export SVG'**
  String get editorExportSvg;

  /// No description provided for @editorShapeTool.
  ///
  /// In en, this message translates to:
  /// **'Shape Tool'**
  String get editorShapeTool;

  /// No description provided for @editorCopySelection.
  ///
  /// In en, this message translates to:
  /// **'Copy Selection'**
  String get editorCopySelection;

  /// No description provided for @editorPasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get editorPasteFromClipboard;

  /// No description provided for @editorCopyPasteSelection.
  ///
  /// In en, this message translates to:
  /// **'Copy and Paste Selection'**
  String get editorCopyPasteSelection;

  /// No description provided for @editorDeleteSelection.
  ///
  /// In en, this message translates to:
  /// **'Delete Selection'**
  String get editorDeleteSelection;

  /// No description provided for @editorBoldText.
  ///
  /// In en, this message translates to:
  /// **'Bold Selected Text'**
  String get editorBoldText;

  /// No description provided for @editorItalicText.
  ///
  /// In en, this message translates to:
  /// **'Italic Selected Text'**
  String get editorItalicText;

  /// No description provided for @editorUnderlineText.
  ///
  /// In en, this message translates to:
  /// **'Underline Selected Text'**
  String get editorUnderlineText;

  /// No description provided for @editorStrikethroughText.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough Selected Text'**
  String get editorStrikethroughText;

  /// No description provided for @editorCycleAlignment.
  ///
  /// In en, this message translates to:
  /// **'Cycle Text Alignment'**
  String get editorCycleAlignment;

  /// No description provided for @editorFitCanvas.
  ///
  /// In en, this message translates to:
  /// **'Fit to Canvas'**
  String get editorFitCanvas;

  /// No description provided for @editorToggleGrid.
  ///
  /// In en, this message translates to:
  /// **'Toggle Grid'**
  String get editorToggleGrid;

  /// No description provided for @editorToggleGridSnap.
  ///
  /// In en, this message translates to:
  /// **'Toggle Grid Snap'**
  String get editorToggleGridSnap;

  /// No description provided for @editorDrawingCanvas.
  ///
  /// In en, this message translates to:
  /// **'Drawing Canvas'**
  String get editorDrawingCanvas;

  /// No description provided for @editorBoldLabel.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get editorBoldLabel;

  /// No description provided for @editorItalicLabel.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get editorItalicLabel;

  /// No description provided for @editorTodoLabel.
  ///
  /// In en, this message translates to:
  /// **'Todo'**
  String get editorTodoLabel;

  /// No description provided for @editorCenterAlign.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get editorCenterAlign;

  /// No description provided for @editorImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get editorImage;

  /// No description provided for @editorCancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel Selection'**
  String get editorCancelSelection;

  /// No description provided for @toolPen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get toolPen;

  /// No description provided for @toolPencil.
  ///
  /// In en, this message translates to:
  /// **'Pencil'**
  String get toolPencil;

  /// No description provided for @toolBrush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get toolBrush;

  /// No description provided for @toolHighlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get toolHighlighter;

  /// No description provided for @toolEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get toolEraser;

  /// No description provided for @toolLasso.
  ///
  /// In en, this message translates to:
  /// **'Lasso'**
  String get toolLasso;

  /// No description provided for @toolText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get toolText;

  /// No description provided for @toolImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get toolImage;

  /// No description provided for @toolRuler.
  ///
  /// In en, this message translates to:
  /// **'Ruler'**
  String get toolRuler;

  /// No description provided for @toolLaser.
  ///
  /// In en, this message translates to:
  /// **'Laser Pointer'**
  String get toolLaser;

  /// No description provided for @toolEyedropper.
  ///
  /// In en, this message translates to:
  /// **'Eyedropper'**
  String get toolEyedropper;

  /// No description provided for @editorSelectionColor.
  ///
  /// In en, this message translates to:
  /// **'Selection Color'**
  String get editorSelectionColor;

  /// No description provided for @editorStrokeWidth.
  ///
  /// In en, this message translates to:
  /// **'Stroke Width'**
  String get editorStrokeWidth;

  /// No description provided for @editorFontSize.
  ///
  /// In en, this message translates to:
  /// **'Text Size'**
  String get editorFontSize;

  /// No description provided for @editorShapeStrokeWidth.
  ///
  /// In en, this message translates to:
  /// **'Shape Border Width'**
  String get editorShapeStrokeWidth;

  /// No description provided for @editorPressureSettings.
  ///
  /// In en, this message translates to:
  /// **'Pressure Settings'**
  String get editorPressureSettings;

  /// No description provided for @editorMinWidth.
  ///
  /// In en, this message translates to:
  /// **'Min Width'**
  String get editorMinWidth;

  /// No description provided for @editorMaxWidth.
  ///
  /// In en, this message translates to:
  /// **'Max Width'**
  String get editorMaxWidth;

  /// No description provided for @editorPressureCurve.
  ///
  /// In en, this message translates to:
  /// **'Pressure Curve'**
  String get editorPressureCurve;

  /// No description provided for @editorFullStroke.
  ///
  /// In en, this message translates to:
  /// **'Full Stroke'**
  String get editorFullStroke;

  /// No description provided for @editorTransparent.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get editorTransparent;

  /// No description provided for @editorSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editorSave;

  /// No description provided for @editorAutoFade.
  ///
  /// In en, this message translates to:
  /// **'Auto Fade'**
  String get editorAutoFade;

  /// No description provided for @chartBar.
  ///
  /// In en, this message translates to:
  /// **'Bar Chart'**
  String get chartBar;

  /// No description provided for @chartLine.
  ///
  /// In en, this message translates to:
  /// **'Line Chart'**
  String get chartLine;

  /// No description provided for @cropImage.
  ///
  /// In en, this message translates to:
  /// **'Crop Image'**
  String get cropImage;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedToClipboard;

  /// No description provided for @exportTypePng.
  ///
  /// In en, this message translates to:
  /// **'PNG Image'**
  String get exportTypePng;

  /// No description provided for @exportTypePdf.
  ///
  /// In en, this message translates to:
  /// **'PDF Document'**
  String get exportTypePdf;

  /// No description provided for @exportTypeSvg.
  ///
  /// In en, this message translates to:
  /// **'SVG Vector'**
  String get exportTypeSvg;

  /// No description provided for @exportTypeWord.
  ///
  /// In en, this message translates to:
  /// **'Word Document'**
  String get exportTypeWord;

  /// No description provided for @exportTypeMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown / Text'**
  String get exportTypeMarkdown;

  /// No description provided for @exportTypePptx.
  ///
  /// In en, this message translates to:
  /// **'PPTX Presentation'**
  String get exportTypePptx;

  /// No description provided for @exportTypeJson.
  ///
  /// In en, this message translates to:
  /// **'JSON Project File'**
  String get exportTypeJson;

  /// No description provided for @exportTypeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown Format'**
  String get exportTypeUnknown;

  /// No description provided for @noteActions.
  ///
  /// In en, this message translates to:
  /// **'Notebook Actions'**
  String get noteActions;

  /// No description provided for @noteImportPage.
  ///
  /// In en, this message translates to:
  /// **'Import Pages from Other Notebooks'**
  String get noteImportPage;

  /// No description provided for @noteImportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Import Markdown or Text'**
  String get noteImportMarkdown;

  /// No description provided for @noteImportPdf.
  ///
  /// In en, this message translates to:
  /// **'Import PDF for Page-by-Page Annotation'**
  String get noteImportPdf;

  /// No description provided for @noteTidyPages.
  ///
  /// In en, this message translates to:
  /// **'Batch Tidy Pages'**
  String get noteTidyPages;

  /// No description provided for @noteFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by tag or keyword'**
  String get noteFilterHint;

  /// No description provided for @noteEncryptionChoice.
  ///
  /// In en, this message translates to:
  /// **'Choose Encryption Method'**
  String get noteEncryptionChoice;

  /// No description provided for @noteMemoryPassword.
  ///
  /// In en, this message translates to:
  /// **'Remember Password'**
  String get noteMemoryPassword;

  /// No description provided for @noteMemoryPasswordSub.
  ///
  /// In en, this message translates to:
  /// **'Set a password, enter it to decrypt when opening'**
  String get noteMemoryPasswordSub;

  /// No description provided for @noteUsbKey.
  ///
  /// In en, this message translates to:
  /// **'USB Key (Password Disk)'**
  String get noteUsbKey;

  /// No description provided for @noteUsbKeySub.
  ///
  /// In en, this message translates to:
  /// **'USB as Key: insert to unlock, remove to lock (zero-knowledge)'**
  String get noteUsbKeySub;

  /// No description provided for @noteRecoveryKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Your Recovery Key (Very Important!)'**
  String get noteRecoveryKeyTitle;

  /// No description provided for @noteNewPage.
  ///
  /// In en, this message translates to:
  /// **'New Page'**
  String get noteNewPage;

  /// No description provided for @noteSessionLocked.
  ///
  /// In en, this message translates to:
  /// **'Session locked, please unlock again'**
  String get noteSessionLocked;

  /// No description provided for @noteSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired, please unlock again'**
  String get noteSessionExpired;

  /// No description provided for @noteErrorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String noteErrorSaveFailed(Object error);

  /// No description provided for @noteEncryptionPasswordEnabled.
  ///
  /// In en, this message translates to:
  /// **'Password protection enabled (content encrypted)'**
  String get noteEncryptionPasswordEnabled;

  /// No description provided for @noteEncryptionUsbKeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'USB key encryption enabled (lock on removal)'**
  String get noteEncryptionUsbKeyEnabled;

  /// No description provided for @passwordUnlock.
  ///
  /// In en, this message translates to:
  /// **'Password Unlock'**
  String get passwordUnlock;

  /// No description provided for @passwordDisk.
  ///
  /// In en, this message translates to:
  /// **'Password Disk'**
  String get passwordDisk;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get enterPassword;

  /// No description provided for @diskCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Password Disk (Generate Key + Recovery Key)'**
  String get diskCreate;

  /// No description provided for @diskUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock (Select USB Password Disk Directory)'**
  String get diskUnlock;

  /// No description provided for @diskRecover.
  ///
  /// In en, this message translates to:
  /// **'Recover Master Key with Recovery Key (USB Lost)'**
  String get diskRecover;

  /// No description provided for @diskEncryptDecrypt.
  ///
  /// In en, this message translates to:
  /// **'Encrypt and Decrypt with Password Disk Key'**
  String get diskEncryptDecrypt;

  /// No description provided for @diskFingerprintCopied.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint copied'**
  String get diskFingerprintCopied;

  /// No description provided for @diskCopied.
  ///
  /// In en, this message translates to:
  /// **'I\'ve saved it'**
  String get diskCopied;

  /// No description provided for @diskPinProtection.
  ///
  /// In en, this message translates to:
  /// **'Enable PIN protection?'**
  String get diskPinProtection;

  /// No description provided for @diskNoPin.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get diskNoPin;

  /// No description provided for @diskYesPin.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get diskYesPin;

  /// No description provided for @diskEnterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter Password Disk PIN'**
  String get diskEnterPin;

  /// No description provided for @diskConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get diskConfirm;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Full-text Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search text content / titles…'**
  String get searchHint;

  /// No description provided for @searchEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter keywords to start searching'**
  String get searchEmptyHint;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching content found'**
  String get searchNoResults;

  /// No description provided for @editorStrokeColor.
  ///
  /// In en, this message translates to:
  /// **'Stroke Color'**
  String get editorStrokeColor;

  /// No description provided for @editorEraseStroke.
  ///
  /// In en, this message translates to:
  /// **'Erase entire stroke on hit'**
  String get editorEraseStroke;

  /// No description provided for @editorEraseTransparent.
  ///
  /// In en, this message translates to:
  /// **'Erase with transparent pixels on current layer'**
  String get editorEraseTransparent;

  /// No description provided for @editorHighlightNormal.
  ///
  /// In en, this message translates to:
  /// **'Writes as normal highlighter, undoable, saveable and exportable'**
  String get editorHighlightNormal;

  /// No description provided for @editorLaserTemporary.
  ///
  /// In en, this message translates to:
  /// **'Shows temporarily only, fades out in ~4 seconds, not saved'**
  String get editorLaserTemporary;

  /// No description provided for @editorTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text Color'**
  String get editorTextColor;

  /// No description provided for @editorBold.
  ///
  /// In en, this message translates to:
  /// **'Bold (Ctrl+B)'**
  String get editorBold;

  /// No description provided for @editorItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic (Ctrl+I)'**
  String get editorItalic;

  /// No description provided for @diskPinInfo.
  ///
  /// In en, this message translates to:
  /// **'When enabled, the master key is encrypted with PIN (OWASP KEK mode). Even if the USB is lost, the key cannot be read directly. Unlocking requires the PIN.'**
  String get diskPinInfo;

  /// No description provided for @editorExportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get editorExportPdf;

  /// No description provided for @editorExportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get editorExportJson;

  /// No description provided for @editorExportPptx.
  ///
  /// In en, this message translates to:
  /// **'Export PPTX'**
  String get editorExportPptx;

  /// No description provided for @editorExportWord.
  ///
  /// In en, this message translates to:
  /// **'Export Word Document'**
  String get editorExportWord;

  /// No description provided for @editorUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline (Ctrl+U)'**
  String get editorUnderline;

  /// No description provided for @editorPdfPreview.
  ///
  /// In en, this message translates to:
  /// **'Page Preview (A4 pagination)'**
  String get editorPdfPreview;

  /// No description provided for @editorPasteValues.
  ///
  /// In en, this message translates to:
  /// **'Paste values separated by comma/space/newline, e.g.: 10, 25, 18, 42, 30'**
  String get editorPasteValues;

  /// No description provided for @editorImageInsertFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to insert image: {error}'**
  String editorImageInsertFail(Object error);

  /// No description provided for @alignLeft.
  ///
  /// In en, this message translates to:
  /// **'Align Left'**
  String get alignLeft;

  /// No description provided for @alignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get alignCenter;

  /// No description provided for @alignRight.
  ///
  /// In en, this message translates to:
  /// **'Align Right'**
  String get alignRight;

  /// No description provided for @editorAlignTooltip.
  ///
  /// In en, this message translates to:
  /// **'Alignment: {name} (Ctrl+E)'**
  String editorAlignTooltip(Object name);

  /// No description provided for @editorPagePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Page Preview {title}'**
  String editorPagePreviewTitle(Object title);

  /// No description provided for @paperBlank.
  ///
  /// In en, this message translates to:
  /// **'Blank'**
  String get paperBlank;

  /// No description provided for @paperGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get paperGrid;

  /// No description provided for @paperLined.
  ///
  /// In en, this message translates to:
  /// **'Lined'**
  String get paperLined;

  /// No description provided for @paperDot.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get paperDot;

  /// No description provided for @editorPaperTemplate.
  ///
  /// In en, this message translates to:
  /// **'Paper Template: {type} (tap to switch)'**
  String editorPaperTemplate(Object type);

  /// No description provided for @editorShapeFillOn.
  ///
  /// In en, this message translates to:
  /// **'Shape Fill: On (new shapes filled by default)'**
  String get editorShapeFillOn;

  /// No description provided for @editorShapeFillOff.
  ///
  /// In en, this message translates to:
  /// **'Shape Fill: Off (new shapes filled by default)'**
  String get editorShapeFillOff;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @errorLoadDocument.
  ///
  /// In en, this message translates to:
  /// **'Failed to load document'**
  String get errorLoadDocument;

  /// No description provided for @errorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get errorSaveFailed;

  /// No description provided for @errorAutoSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto-save failed'**
  String get errorAutoSaveFailed;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light Theme'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark Theme'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get themeSystem;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Drawing Notes'**
  String get onboardingTitle;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture ideas with your pen. Supports infinite canvas, notebooks, and encryption.'**
  String get onboardingSubtitle;

  /// No description provided for @onboardingBrush.
  ///
  /// In en, this message translates to:
  /// **'Pen / Eraser / Eyedropper: switch via top toolbar, drag mouse or finger to draw'**
  String get onboardingBrush;

  /// No description provided for @onboardingColor.
  ///
  /// In en, this message translates to:
  /// **'Color & Width: color circle and width slider on the right side of toolbar'**
  String get onboardingColor;

  /// No description provided for @onboardingLayers.
  ///
  /// In en, this message translates to:
  /// **'Layer panel on the right: new, show/hide, opacity, order, merge'**
  String get onboardingLayers;

  /// No description provided for @onboardingSelect.
  ///
  /// In en, this message translates to:
  /// **'Selection tool: select area to move / scale / rotate / copy / delete'**
  String get onboardingSelect;

  /// No description provided for @onboardingText.
  ///
  /// In en, this message translates to:
  /// **'Notebook supports text and images: tap canvas with text tool to input, image button to insert'**
  String get onboardingText;

  /// No description provided for @onboardingPinch.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom canvas, two-finger rotate canvas (touchscreen devices)'**
  String get onboardingPinch;

  /// No description provided for @onboardingFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen button top-right: hide toolbar, view canvas only'**
  String get onboardingFullscreen;

  /// No description provided for @onboardingSave.
  ///
  /// In en, this message translates to:
  /// **'Content auto-saves, no manual save needed; export to PNG anytime'**
  String get onboardingSave;

  /// No description provided for @onboardingStart.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingStart;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @appErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get appErrorTitle;

  /// No description provided for @appErrorBody.
  ///
  /// In en, this message translates to:
  /// **'The app encountered an error, but your data is safe.'**
  String get appErrorBody;

  /// No description provided for @appErrorBackHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get appErrorBackHome;

  /// No description provided for @appErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'Error Details (Debug Mode)'**
  String get appErrorDetails;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @aiChat.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiChat;

  /// No description provided for @aiChatHint.
  ///
  /// In en, this message translates to:
  /// **'Type a question to start chatting…'**
  String get aiChatHint;

  /// No description provided for @aiChatEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chat history yet'**
  String get aiChatEmpty;

  /// No description provided for @securityLevel.
  ///
  /// In en, this message translates to:
  /// **'Security Level'**
  String get securityLevel;

  /// No description provided for @encryptionStatus.
  ///
  /// In en, this message translates to:
  /// **'Encryption Status'**
  String get encryptionStatus;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportTitle;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importTitle;

  /// No description provided for @layerPanel.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get layerPanel;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @recentDocuments.
  ///
  /// In en, this message translates to:
  /// **'Recent Documents'**
  String get recentDocuments;

  /// No description provided for @noRecentDocuments.
  ///
  /// In en, this message translates to:
  /// **'No recent documents'**
  String get noRecentDocuments;

  /// No description provided for @enableSync.
  ///
  /// In en, this message translates to:
  /// **'Enable Sync'**
  String get enableSync;

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync Status'**
  String get syncStatus;

  /// No description provided for @storagePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Storage permission required'**
  String get storagePermissionRequired;

  /// No description provided for @pen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get pen;

  /// No description provided for @eraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get eraser;

  /// No description provided for @selection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get selection;

  /// No description provided for @textTool.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textTool;

  /// No description provided for @shape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get shape;

  /// No description provided for @pageManagement.
  ///
  /// In en, this message translates to:
  /// **'Page Management'**
  String get pageManagement;

  /// No description provided for @deletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deletePage;

  /// No description provided for @renamePage.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renamePage;

  /// No description provided for @reorderPages.
  ///
  /// In en, this message translates to:
  /// **'Drag to Reorder'**
  String get reorderPages;

  /// No description provided for @drawingLayers.
  ///
  /// In en, this message translates to:
  /// **'Drawing Layers'**
  String get drawingLayers;

  /// No description provided for @textLayers.
  ///
  /// In en, this message translates to:
  /// **'Text Layers'**
  String get textLayers;

  /// No description provided for @noteContent.
  ///
  /// In en, this message translates to:
  /// **'Note Content'**
  String get noteContent;

  /// No description provided for @recentlyUsed.
  ///
  /// In en, this message translates to:
  /// **'Recently Used'**
  String get recentlyUsed;

  /// No description provided for @allShapes.
  ///
  /// In en, this message translates to:
  /// **'All Shapes'**
  String get allShapes;

  /// No description provided for @basicShapes.
  ///
  /// In en, this message translates to:
  /// **'Basic Shapes'**
  String get basicShapes;

  /// No description provided for @lines.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get lines;

  /// No description provided for @arrows.
  ///
  /// In en, this message translates to:
  /// **'Arrows'**
  String get arrows;

  /// No description provided for @highlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get highlighter;

  /// No description provided for @laserPointer.
  ///
  /// In en, this message translates to:
  /// **'Laser Pointer'**
  String get laserPointer;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @autoSaveLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto Save'**
  String get autoSaveLabel;

  /// No description provided for @storageLabel.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageLabel;

  /// No description provided for @securityLabel.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securityLabel;

  /// No description provided for @aiLabel.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get aiLabel;

  /// No description provided for @experimentalLabel.
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get experimentalLabel;

  /// No description provided for @hotkeysLabel.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys'**
  String get hotkeysLabel;

  /// No description provided for @syncLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncLabel;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @testRunnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Test Runner'**
  String get testRunnerTitle;

  /// No description provided for @testRunnerStart.
  ///
  /// In en, this message translates to:
  /// **'Start Tests'**
  String get testRunnerStart;

  /// No description provided for @p2pSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Peer-to-Peer Sync'**
  String get p2pSyncTitle;

  /// No description provided for @p2pSyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync directly between LAN devices'**
  String get p2pSyncSubtitle;

  /// No description provided for @viewAllPages.
  ///
  /// In en, this message translates to:
  /// **'View All Pages'**
  String get viewAllPages;

  /// No description provided for @blockEditorTitle1.
  ///
  /// In en, this message translates to:
  /// **'Heading 1'**
  String get blockEditorTitle1;

  /// No description provided for @blockEditorTitle2.
  ///
  /// In en, this message translates to:
  /// **'Heading 2'**
  String get blockEditorTitle2;

  /// No description provided for @blockEditorTitle3.
  ///
  /// In en, this message translates to:
  /// **'Heading 3'**
  String get blockEditorTitle3;

  /// No description provided for @blockEditorListItem.
  ///
  /// In en, this message translates to:
  /// **'List item'**
  String get blockEditorListItem;

  /// No description provided for @blockEditorCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter code…'**
  String get blockEditorCodeHint;

  /// No description provided for @blockEditorQuoteHint.
  ///
  /// In en, this message translates to:
  /// **'Quote…'**
  String get blockEditorQuoteHint;

  /// No description provided for @blockEditorParagraphHint.
  ///
  /// In en, this message translates to:
  /// **'Type text, or type / to open command menu…'**
  String get blockEditorParagraphHint;

  /// No description provided for @blockEditorImageLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Image load failed'**
  String get blockEditorImageLoadFail;

  /// No description provided for @blockEditorTableBlock.
  ///
  /// In en, this message translates to:
  /// **'Table block (see TableViewWidget)'**
  String get blockEditorTableBlock;

  /// No description provided for @blockEditorAddRow.
  ///
  /// In en, this message translates to:
  /// **'Add Row'**
  String get blockEditorAddRow;

  /// No description provided for @slidePresenterSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get slidePresenterSlide;

  /// No description provided for @slidePresenterExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get slidePresenterExit;

  /// No description provided for @unifiedToolbarBrush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get unifiedToolbarBrush;

  /// No description provided for @unifiedToolbarEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get unifiedToolbarEraser;

  /// No description provided for @unifiedToolbarSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get unifiedToolbarSelect;

  /// No description provided for @unifiedToolbarRectSelect.
  ///
  /// In en, this message translates to:
  /// **'Rectangle Selection'**
  String get unifiedToolbarRectSelect;

  /// No description provided for @unifiedToolbarLassoSelect.
  ///
  /// In en, this message translates to:
  /// **'Lasso Selection'**
  String get unifiedToolbarLassoSelect;

  /// No description provided for @unifiedToolbarRect.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get unifiedToolbarRect;

  /// No description provided for @unifiedToolbarEllipse.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get unifiedToolbarEllipse;

  /// No description provided for @unifiedToolbarLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get unifiedToolbarLine;

  /// No description provided for @unifiedToolbarArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get unifiedToolbarArrow;

  /// No description provided for @unifiedToolbarText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get unifiedToolbarText;

  /// No description provided for @unifiedToolbarEyedropper.
  ///
  /// In en, this message translates to:
  /// **'Eyedropper'**
  String get unifiedToolbarEyedropper;

  /// No description provided for @unifiedToolbarEraserOptions.
  ///
  /// In en, this message translates to:
  /// **'Eraser Options'**
  String get unifiedToolbarEraserOptions;

  /// No description provided for @unifiedToolbarEraseShapes.
  ///
  /// In en, this message translates to:
  /// **'Can erase shapes'**
  String get unifiedToolbarEraseShapes;

  /// No description provided for @unifiedToolbarGrid.
  ///
  /// In en, this message translates to:
  /// **'Show Grid'**
  String get unifiedToolbarGrid;

  /// No description provided for @unifiedToolbarSnap.
  ///
  /// In en, this message translates to:
  /// **'Snap to Grid'**
  String get unifiedToolbarSnap;

  /// No description provided for @unifiedToolbarZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get unifiedToolbarZoomOut;

  /// No description provided for @unifiedToolbarZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get unifiedToolbarZoomIn;

  /// No description provided for @unifiedToolbarFitCanvas.
  ///
  /// In en, this message translates to:
  /// **'Fit to Canvas'**
  String get unifiedToolbarFitCanvas;

  /// No description provided for @unifiedToolbarClickToPlaceText.
  ///
  /// In en, this message translates to:
  /// **'Click canvas to place text'**
  String get unifiedToolbarClickToPlaceText;

  /// No description provided for @unifiedToolbarClickToPickColor.
  ///
  /// In en, this message translates to:
  /// **'Click canvas to pick color'**
  String get unifiedToolbarClickToPickColor;

  /// No description provided for @unifiedPropertyBrush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get unifiedPropertyBrush;

  /// No description provided for @unifiedPropertyShape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get unifiedPropertyShape;

  /// No description provided for @unifiedPropertyText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get unifiedPropertyText;

  /// No description provided for @unifiedPropertyFillColor.
  ///
  /// In en, this message translates to:
  /// **'Fill Color'**
  String get unifiedPropertyFillColor;

  /// No description provided for @unifiedPropertyDashLine.
  ///
  /// In en, this message translates to:
  /// **'Solid/Dashed'**
  String get unifiedPropertyDashLine;

  /// No description provided for @unifiedPropertyTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text Color'**
  String get unifiedPropertyTextColor;

  /// No description provided for @unifiedLayerPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get unifiedLayerPanelTitle;

  /// No description provided for @unifiedLayerPanelRename.
  ///
  /// In en, this message translates to:
  /// **'Rename Layer'**
  String get unifiedLayerPanelRename;

  /// No description provided for @unifiedLayerPanelRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter layer name'**
  String get unifiedLayerPanelRenameHint;

  /// No description provided for @unifiedLayerPanelCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get unifiedLayerPanelCancel;

  /// No description provided for @unifiedLayerPanelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get unifiedLayerPanelConfirm;

  /// No description provided for @unnamedNote.
  ///
  /// In en, this message translates to:
  /// **'Untitled Note'**
  String get unnamedNote;

  /// No description provided for @inputText.
  ///
  /// In en, this message translates to:
  /// **'Input Text'**
  String get inputText;

  /// No description provided for @inputTextContent.
  ///
  /// In en, this message translates to:
  /// **'Enter text content'**
  String get inputTextContent;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed'**
  String get loadFailed;

  /// No description provided for @noteTitle.
  ///
  /// In en, this message translates to:
  /// **'Note Title'**
  String get noteTitle;

  /// Editor V2 title
  ///
  /// In en, this message translates to:
  /// **'Editor V2 - {docId}'**
  String editorV2Title(String docId);

  /// No description provided for @historyPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyPanelTitle;

  /// No description provided for @historySteps.
  ///
  /// In en, this message translates to:
  /// **'{count} steps'**
  String historySteps(int count);

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No history'**
  String get noHistory;

  /// No description provided for @exportPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportPanelTitle;

  /// No description provided for @exporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get exporting;

  /// No description provided for @exportFormat.
  ///
  /// In en, this message translates to:
  /// **'Export {format}'**
  String exportFormat(String format);

  /// No description provided for @exportPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get exportPreview;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @copyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyTooltip;

  /// No description provided for @pngExportHint.
  ///
  /// In en, this message translates to:
  /// **'PNG export requires Canvas rendering — use canvas context menu to export.'**
  String get pngExportHint;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @exportFormatPNG.
  ///
  /// In en, this message translates to:
  /// **'Image format'**
  String get exportFormatPNG;

  /// No description provided for @exportFormatSVG.
  ///
  /// In en, this message translates to:
  /// **'Vector format'**
  String get exportFormatSVG;

  /// No description provided for @exportFormatJSON.
  ///
  /// In en, this message translates to:
  /// **'Document format'**
  String get exportFormatJSON;

  /// No description provided for @propertiesPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get propertiesPanelTitle;

  /// No description provided for @colorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get colorLabel;

  /// No description provided for @strokeWidthLabel.
  ///
  /// In en, this message translates to:
  /// **'Stroke Width'**
  String get strokeWidthLabel;

  /// No description provided for @opacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacityLabel;

  /// No description provided for @lineStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Line Style'**
  String get lineStyleLabel;

  /// No description provided for @solidLine.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get solidLine;

  /// No description provided for @dashedLine.
  ///
  /// In en, this message translates to:
  /// **'Dashed'**
  String get dashedLine;

  /// No description provided for @dottedLine.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get dottedLine;

  /// No description provided for @titleHint.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleHint;

  /// No description provided for @startTypingHint.
  ///
  /// In en, this message translates to:
  /// **'Start typing…'**
  String get startTypingHint;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get zoomOut;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get zoomIn;

  /// No description provided for @zoomReset.
  ///
  /// In en, this message translates to:
  /// **'Reset (1x)'**
  String get zoomReset;

  /// No description provided for @fitWindow.
  ///
  /// In en, this message translates to:
  /// **'Fit to Window'**
  String get fitWindow;

  /// No description provided for @pageN.
  ///
  /// In en, this message translates to:
  /// **'Page {index}'**
  String pageN(int index);

  /// No description provided for @newPage.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newPage;

  /// No description provided for @slideN.
  ///
  /// In en, this message translates to:
  /// **'Slide {index}'**
  String slideN(int index);

  /// No description provided for @newColumn.
  ///
  /// In en, this message translates to:
  /// **'New Column'**
  String get newColumn;

  /// No description provided for @noLayers.
  ///
  /// In en, this message translates to:
  /// **'No layers'**
  String get noLayers;

  /// No description provided for @selectColor.
  ///
  /// In en, this message translates to:
  /// **'Select Color'**
  String get selectColor;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

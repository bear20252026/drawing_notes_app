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

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Drawing Notes'**
  String get appTitle;

  /// Search action
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Recycle bin entry
  ///
  /// In en, this message translates to:
  /// **'Trash (recoverable within 30 days)'**
  String get trash;

  /// Close dialog
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Create notebook action
  ///
  /// In en, this message translates to:
  /// **'New notebook'**
  String get newNotebook;

  /// Delete action
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Trash dialog empty state
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get homeTrashEmpty;

  /// Trash item deletion time
  ///
  /// In en, this message translates to:
  /// **'Deleted at {time}'**
  String homeDeletedAt(String time);

  /// Restore from trash action
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get homeRecover;

  /// Permanent delete action
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get homeDeleteForever;

  /// Empty trash action
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get homeEmptyTrash;

  /// Cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get homeCancel;

  /// Theme toggle tooltip
  ///
  /// In en, this message translates to:
  /// **'Switch appearance (system / light / dark)'**
  String get homeSwitchTheme;

  /// More actions tooltip
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get homeMore;

  /// Undo action
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get editorUndo;

  /// Redo action
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get editorRedo;

  /// Shortcuts help tooltip
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get editorShortcutsHelp;

  /// Main menu tooltip
  ///
  /// In en, this message translates to:
  /// **'Main menu'**
  String get editorMenu;

  /// Clear canvas dialog title
  ///
  /// In en, this message translates to:
  /// **'Clear canvas'**
  String get editorClearCanvas;

  /// Copy PNG dialog title
  ///
  /// In en, this message translates to:
  /// **'Copy PNG to clipboard'**
  String get editorCopyPng;

  /// Export PNG dialog title
  ///
  /// In en, this message translates to:
  /// **'Export PNG'**
  String get editorExportPng;

  /// Export SVG dialog title
  ///
  /// In en, this message translates to:
  /// **'Export SVG'**
  String get editorExportSvg;

  /// Shape tool tooltip
  ///
  /// In en, this message translates to:
  /// **'Shape tool'**
  String get editorShapeTool;

  /// Notebook menu tooltip
  ///
  /// In en, this message translates to:
  /// **'Notebook actions'**
  String get noteActions;

  /// Import page menu item
  ///
  /// In en, this message translates to:
  /// **'Import page from another notebook'**
  String get noteImportPage;

  /// Import text menu item
  ///
  /// In en, this message translates to:
  /// **'Import Markdown or text'**
  String get noteImportMarkdown;

  /// Import PDF menu item
  ///
  /// In en, this message translates to:
  /// **'Import PDF and annotate per page'**
  String get noteImportPdf;

  /// Tidy pages menu item
  ///
  /// In en, this message translates to:
  /// **'Tidy up pages'**
  String get noteTidyPages;

  /// Page filter hint
  ///
  /// In en, this message translates to:
  /// **'Filter by tag or keyword'**
  String get noteFilterHint;

  /// Encryption choice dialog title
  ///
  /// In en, this message translates to:
  /// **'Choose encryption method'**
  String get noteEncryptionChoice;

  /// Password option title
  ///
  /// In en, this message translates to:
  /// **'Memory password'**
  String get noteMemoryPassword;

  /// Password option subtitle
  ///
  /// In en, this message translates to:
  /// **'Set a password; enter it to decrypt when opening'**
  String get noteMemoryPasswordSub;

  /// Keyfile option title
  ///
  /// In en, this message translates to:
  /// **'USB key (password disk)'**
  String get noteUsbKey;

  /// Keyfile option subtitle
  ///
  /// In en, this message translates to:
  /// **'USB is the key: unlock by plugging in, lock on removal (zero knowledge)'**
  String get noteUsbKeySub;

  /// Recovery key dialog title
  ///
  /// In en, this message translates to:
  /// **'Save your recovery key (very important!)'**
  String get noteRecoveryKeyTitle;

  /// Recovery key acknowledge button
  ///
  /// In en, this message translates to:
  /// **'I have copied it'**
  String get diskCopied;

  /// PIN protection choice title
  ///
  /// In en, this message translates to:
  /// **'Enable PIN protection?'**
  String get diskPinProtection;

  /// Do not enable PIN
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get diskNoPin;

  /// Enable PIN
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get diskYesPin;

  /// PIN input dialog title
  ///
  /// In en, this message translates to:
  /// **'Enter password disk PIN'**
  String get diskEnterPin;

  /// Confirm button
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get diskConfirm;

  /// Search page title
  ///
  /// In en, this message translates to:
  /// **'Full-text search'**
  String get searchTitle;

  /// Search input hint
  ///
  /// In en, this message translates to:
  /// **'Search text block content / title…'**
  String get searchHint;

  /// Search empty state hint
  ///
  /// In en, this message translates to:
  /// **'Enter keywords to start searching'**
  String get searchEmptyHint;

  /// Search no results state
  ///
  /// In en, this message translates to:
  /// **'No matching content found'**
  String get searchNoResults;

  /// Stroke color tooltip
  ///
  /// In en, this message translates to:
  /// **'Stroke color'**
  String get editorStrokeColor;

  /// Eraser tooltip
  ///
  /// In en, this message translates to:
  /// **'Hit a stroke to delete the whole line'**
  String get editorEraseStroke;

  /// Transparent eraser tooltip
  ///
  /// In en, this message translates to:
  /// **'Carve out the current layer with transparent pixels'**
  String get editorEraseTransparent;

  /// Highlighter tooltip
  ///
  /// In en, this message translates to:
  /// **'Write as a normal highlighter; undoable, savable and exportable'**
  String get editorHighlightNormal;

  /// Laser pointer tooltip
  ///
  /// In en, this message translates to:
  /// **'Shown briefly, fades out smoothly after ~4 seconds, not written to the page'**
  String get editorLaserTemporary;

  /// Text color tooltip
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get editorTextColor;

  /// Bold tooltip
  ///
  /// In en, this message translates to:
  /// **'Bold (Ctrl+B)'**
  String get editorBold;

  /// Italic tooltip
  ///
  /// In en, this message translates to:
  /// **'Italic (Ctrl+I)'**
  String get editorItalic;

  /// PIN protection explanation
  ///
  /// In en, this message translates to:
  /// **'After enabling, the master key is stored encrypted with a PIN (OWASP KEK mode); a lost USB drive cannot expose it directly. Unlocking requires entering the PIN.'**
  String get diskPinInfo;

  /// Export PDF menu item
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get editorExportPdf;

  /// Export JSON menu item
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get editorExportJson;

  /// Export PPTX menu item
  ///
  /// In en, this message translates to:
  /// **'Export PPTX'**
  String get editorExportPptx;

  /// Export Word menu item
  ///
  /// In en, this message translates to:
  /// **'Export Word-compatible document'**
  String get editorExportWord;

  /// Underline tooltip
  ///
  /// In en, this message translates to:
  /// **'Underline (Ctrl+U)'**
  String get editorUnderline;

  /// PDF preview tooltip
  ///
  /// In en, this message translates to:
  /// **'Page preview (A4 pagination)'**
  String get editorPdfPreview;

  /// Paste values hint
  ///
  /// In en, this message translates to:
  /// **'Paste values separated by commas / spaces / newlines, e.g.: 10, 25, 18, 42, 30'**
  String get editorPasteValues;

  /// Image insert failure message
  ///
  /// In en, this message translates to:
  /// **'Failed to insert image: {error}'**
  String editorImageInsertFail(String error);
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

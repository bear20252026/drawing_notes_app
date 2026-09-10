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
  /// **'Paged canvas actions'**
  String get noteActions;

  /// Import page menu item
  ///
  /// In en, this message translates to:
  /// **'Import page from another paged canvas'**
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

  /// Left alignment name
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get alignLeft;

  /// Center alignment name
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get alignCenter;

  /// Right alignment name
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get alignRight;

  /// Alignment tooltip with alignment name
  ///
  /// In en, this message translates to:
  /// **'Align: {name} (Ctrl+E)'**
  String editorAlignTooltip(String name);

  /// Page preview dialog title
  ///
  /// In en, this message translates to:
  /// **'Page preview {title}'**
  String editorPagePreviewTitle(String title);

  /// 取消对话框或操作
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// 流程下一步
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextStep;

  /// 确认提示
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// 创建操作
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// 应用锁设置页标题与开关行
  ///
  /// In en, this message translates to:
  /// **'App Lock'**
  String get lockTitle;

  /// 应用锁说明文案
  ///
  /// In en, this message translates to:
  /// **'Once enabled, a password is required to open the app, and to return from the background after the grace period.'**
  String get lockDescription;

  /// 开关已开启状态
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get lockOn;

  /// 开关未开启状态
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get lockOff;

  /// 修改应用锁密码入口
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get lockChangePassword;

  /// 重置密码盘入口
  ///
  /// In en, this message translates to:
  /// **'Reset Disk'**
  String get lockResetDisk;

  /// 密码盘状态读取失败
  ///
  /// In en, this message translates to:
  /// **'Status unknown (failed to read vault)'**
  String get lockDiskStatusUnknown;

  /// 密码盘已绑定
  ///
  /// In en, this message translates to:
  /// **'Bound (can reset a forgotten password)'**
  String get lockDiskBound;

  /// 密码盘未绑定
  ///
  /// In en, this message translates to:
  /// **'Unbound (a forgotten password cannot be recovered)'**
  String get lockDiskUnbound;

  /// 解除绑定操作
  ///
  /// In en, this message translates to:
  /// **'Unbind'**
  String get lockDiskUnbind;

  /// 绑定操作
  ///
  /// In en, this message translates to:
  /// **'Bind'**
  String get lockDiskBind;

  /// 验证密码流程标题
  ///
  /// In en, this message translates to:
  /// **'Verify current password'**
  String get lockVerifyCurrentPassword;

  /// 保险库解锁失败
  ///
  /// In en, this message translates to:
  /// **'Failed to unlock the vault, please retry'**
  String get lockVaultUnlockFailed;

  /// 绑定失败
  ///
  /// In en, this message translates to:
  /// **'Binding failed, please retry'**
  String get lockBindFailed;

  /// 绑定成功提示
  ///
  /// In en, this message translates to:
  /// **'Bound. Keep the USB drive safe: without it the password cannot be reset, and do not delete password_reset_disk.key on it'**
  String get lockBindSuccess;

  /// 解除绑定确认框标题
  ///
  /// In en, this message translates to:
  /// **'Unbind reset disk'**
  String get lockUnbindTitle;

  /// 解除绑定确认框正文
  ///
  /// In en, this message translates to:
  /// **'After unbinding, a forgotten password cannot be reset.\n\nThe password_reset_disk.key file on the USB drive will not be deleted — remove it yourself.'**
  String get lockUnbindContent;

  /// 解除失败
  ///
  /// In en, this message translates to:
  /// **'Unbinding failed, please retry'**
  String get lockUnbindFailed;

  /// 解除成功提示
  ///
  /// In en, this message translates to:
  /// **'Unbound'**
  String get lockUnbound;

  /// 设置密码流程标题
  ///
  /// In en, this message translates to:
  /// **'Set password'**
  String get lockSetPassword;

  /// 确认密码流程标题
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get lockConfirmPassword;

  /// 两次密码不一致
  ///
  /// In en, this message translates to:
  /// **'Entries don\'t match, please set again'**
  String get lockMismatch;

  /// 保险库同步失败
  ///
  /// In en, this message translates to:
  /// **'File encryption sync failed, please retry or contact the developer'**
  String get lockVaultSyncFailed;

  /// 开启成功提示
  ///
  /// In en, this message translates to:
  /// **'App lock enabled'**
  String get lockEnabled;

  /// 关闭成功提示
  ///
  /// In en, this message translates to:
  /// **'App lock disabled'**
  String get lockDisabled;

  /// 阻止关闭弹窗标题
  ///
  /// In en, this message translates to:
  /// **'Can\'t disable App Lock'**
  String get lockCannotDisableTitle;

  /// 阻止关闭弹窗正文
  ///
  /// In en, this message translates to:
  /// **'Your files are encrypted with the app-lock password. Disabling App Lock would make encrypted files unreadable.\n\nTo change the password, use \"Change Password\".'**
  String get lockCannotDisableContent;

  /// 密码长度选择器标题
  ///
  /// In en, this message translates to:
  /// **'Password length'**
  String get lockPinLengthTitle;

  /// 当前密码长度
  ///
  /// In en, this message translates to:
  /// **'{count} digits'**
  String lockPinLengthDigits(int count);

  /// 密码长度建议
  ///
  /// In en, this message translates to:
  /// **'6+ digits recommended; numeric-only passwords have limited strength.'**
  String get lockPinLengthHint;

  /// 切后台宽限期设置行标题
  ///
  /// In en, this message translates to:
  /// **'Grace Period on Return'**
  String get lockGraceTitle;

  /// 宽限期档位对话框说明
  ///
  /// In en, this message translates to:
  /// **'Come back within the grace period after leaving the app and you won\'t need to re-enter your password. The grace period only skips the lock screen; passwords for encrypted files and notes will still be requested.'**
  String get lockGraceHint;

  /// 宽限期关闭档位
  ///
  /// In en, this message translates to:
  /// **'Off (lock immediately on backgrounding)'**
  String get lockGraceOff;

  /// 宽限期 30 秒档位
  ///
  /// In en, this message translates to:
  /// **'30 seconds'**
  String get lockGrace30s;

  /// 宽限期 1 分钟档位
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get lockGrace1min;

  /// 宽限期 5 分钟档位
  ///
  /// In en, this message translates to:
  /// **'5 minutes'**
  String get lockGrace5min;

  /// 宽限期当前值副标题
  ///
  /// In en, this message translates to:
  /// **'Current: {option}'**
  String lockGraceCurrent(String option);

  /// 快速解锁开关行
  ///
  /// In en, this message translates to:
  /// **'System-verified quick unlock'**
  String get lockQuickUnlock;

  /// 快速解锁开启状态
  ///
  /// In en, this message translates to:
  /// **'On (unlock from the lock screen with Windows Hello)'**
  String get lockQuickUnlockOn;

  /// 快速解锁关闭状态
  ///
  /// In en, this message translates to:
  /// **'Off (enable to unlock with face, fingerprint, or PIN)'**
  String get lockQuickUnlockOff;

  /// 快速解锁开启失败
  ///
  /// In en, this message translates to:
  /// **'Failed to enable, please retry'**
  String get lockQuickEnableFailed;

  /// 快速解锁开启成功
  ///
  /// In en, this message translates to:
  /// **'Enabled: unlock from the lock screen with system verification (face, fingerprint, or PIN)'**
  String get lockQuickEnableDone;

  /// 快速解锁关闭成功
  ///
  /// In en, this message translates to:
  /// **'Disabled; the key copy in the system secure enclave has been deleted'**
  String get lockQuickDisableDone;

  /// 绑定状态提示
  ///
  /// In en, this message translates to:
  /// **'After binding a reset disk, a forgotten password can be reset with it; otherwise it cannot be recovered.'**
  String get lockBindHintBound;

  /// 未绑定状态提示
  ///
  /// In en, this message translates to:
  /// **'After enabling App Lock, you can bind a reset disk in case you forget the password.'**
  String get lockBindHintUnbound;

  /// 分享占位提示
  ///
  /// In en, this message translates to:
  /// **'Sharing coming soon'**
  String get docShareComingSoon;

  /// 保存失败
  ///
  /// In en, this message translates to:
  /// **'Save failed, please retry or save manually'**
  String get docSaveFailed;

  /// 导出成功提示
  ///
  /// In en, this message translates to:
  /// **'Exported {label}: {path}'**
  String docExportedTo(String label, String path);

  /// 导出失败
  ///
  /// In en, this message translates to:
  /// **'Export failed, please retry'**
  String get docExportFailed;

  /// 策略拒绝
  ///
  /// In en, this message translates to:
  /// **'Operation denied by policy ({operation})'**
  String docPolicyDenied(String operation);

  /// 插入页面链接弹窗标题
  ///
  /// In en, this message translates to:
  /// **'Insert page link'**
  String get docInsertPageLink;

  /// 独立密码区块标题
  ///
  /// In en, this message translates to:
  /// **'Standalone password for \"{name}\"'**
  String docStandalonePasswordTitle(String name);

  /// 设置独立密码入口
  ///
  /// In en, this message translates to:
  /// **'Set standalone password'**
  String get docSetStandalonePassword;

  /// 设置独立密码说明
  ///
  /// In en, this message translates to:
  /// **'4–12 digits, must differ from the app-lock password'**
  String get docSetStandalonePasswordHint;

  /// 修改独立密码入口
  ///
  /// In en, this message translates to:
  /// **'Change standalone password'**
  String get docChangeStandalonePassword;

  /// 绑定重置密码盘入口
  ///
  /// In en, this message translates to:
  /// **'Bind reset disk'**
  String get docBindResetDisk;

  /// 绑定重置密码盘说明
  ///
  /// In en, this message translates to:
  /// **'After binding, a forgotten password can be reset with the USB drive without the old password'**
  String get docBindResetDiskHint;

  /// 移除独立密码入口
  ///
  /// In en, this message translates to:
  /// **'Remove standalone password'**
  String get docRemoveStandalonePassword;

  /// 标签区标题
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get docTags;

  /// 新建标签弹窗标题
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get docNewTag;

  /// 导航目的地
  ///
  /// In en, this message translates to:
  /// **'All Documents'**
  String get shellAllDocs;

  /// 导航目的地
  ///
  /// In en, this message translates to:
  /// **'Canvas & Notes'**
  String get shellCanvasNotes;

  /// 导航目的地
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get shellSchedule;

  /// 导航目的地
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get shellSettings;

  /// 编辑器缺位兜底文案
  ///
  /// In en, this message translates to:
  /// **'Editor not yet assembled by the app layer'**
  String get shellEditorNotAssembled;

  /// 设置页标题
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// 设置页应用锁入口
  ///
  /// In en, this message translates to:
  /// **'App Lock'**
  String get settingsAppLock;

  /// 应用锁入口说明
  ///
  /// In en, this message translates to:
  /// **'App-lock password · Reset disk'**
  String get settingsAppLockHint;

  /// 单文件密码入口
  ///
  /// In en, this message translates to:
  /// **'Per-file Password'**
  String get settingsStandalonePassword;

  /// 单文件密码说明
  ///
  /// In en, this message translates to:
  /// **'A second lock for individual canvases (set on the canvas card)'**
  String get settingsStandalonePasswordHint;

  /// 外观入口
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// 高对比度入口
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get settingsHighContrast;

  /// WebDAV 入口
  ///
  /// In en, this message translates to:
  /// **'WebDAV Sync'**
  String get settingsWebdav;

  /// WebDAV 说明
  ///
  /// In en, this message translates to:
  /// **'Local-first, sync across devices'**
  String get settingsWebdavHint;

  /// 密码体系分组标题
  ///
  /// In en, this message translates to:
  /// **'Password System'**
  String get settingsPasswordSystem;

  /// 排序菜单提示
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get docsSort;

  /// 排序选项
  ///
  /// In en, this message translates to:
  /// **'Group by time'**
  String get docsSortGroupTime;

  /// 排序选项
  ///
  /// In en, this message translates to:
  /// **'By updated time'**
  String get docsSortUpdated;

  /// 排序选项
  ///
  /// In en, this message translates to:
  /// **'By created time'**
  String get docsSortCreated;

  /// 排序选项
  ///
  /// In en, this message translates to:
  /// **'By title'**
  String get docsSortTitle;

  /// 新建入口
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get docsNewDoc;

  /// 新建入口
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get docsNewNote;

  /// 新建入口
  ///
  /// In en, this message translates to:
  /// **'New paged canvas'**
  String get docsNewPagedCanvas;

  /// 新建入口
  ///
  /// In en, this message translates to:
  /// **'New canvas'**
  String get docsNewCanvas;

  /// 设置页分组标题
  ///
  /// In en, this message translates to:
  /// **'Passwords & Security'**
  String get settingsSectionSecurity;

  /// 设置页分组标题
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsSectionGeneral;

  /// 单文件密码帮助弹窗正文
  ///
  /// In en, this message translates to:
  /// **'On the home page or in All Documents, tap the lock button on a canvas card to set a standalone password for that canvas. Opening it will then require this password, and the thumbnail is hidden behind a lock placeholder.\n\nThe per-file password is independent of the app-lock password — even if someone unlocks your app, they cannot open the canvas without it.'**
  String get settingsFilePasswordHelpContent;

  /// 外观状态标签
  ///
  /// In en, this message translates to:
  /// **'Follow system (tap to switch to light)'**
  String get settingsThemeSystem;

  /// 外观状态标签
  ///
  /// In en, this message translates to:
  /// **'Light (tap to switch to dark)'**
  String get settingsThemeLight;

  /// 外观状态标签
  ///
  /// In en, this message translates to:
  /// **'Dark (tap to follow system)'**
  String get settingsThemeDark;

  /// 密码体系卡第 1 层
  ///
  /// In en, this message translates to:
  /// **'Layer 1 · App-lock password'**
  String get settingsLayer1Title;

  /// 密码体系卡第 1 层说明
  ///
  /// In en, this message translates to:
  /// **'Unlocks the app and the master-key vault — protects all canvases and notes. Reset with the reset disk if forgotten.'**
  String get settingsLayer1Desc;

  /// 密码体系卡第 2 层
  ///
  /// In en, this message translates to:
  /// **'Layer 2 · Per-file password'**
  String get settingsLayer2Title;

  /// 密码体系卡第 2 层说明
  ///
  /// In en, this message translates to:
  /// **'A standalone password for a single canvas, paged canvas, or note, independent of the app-lock password. Reset with the reset disk if forgotten.'**
  String get settingsLayer2Desc;

  /// 密码体系卡第 3 层
  ///
  /// In en, this message translates to:
  /// **'Reset disk (USB drive)'**
  String get settingsLayer3Title;

  /// 密码体系卡第 3 层说明
  ///
  /// In en, this message translates to:
  /// **'Plug in the USB drive → tap \"Forgot password\" → set a new one. The same disk resets both the app-lock and per-file passwords.'**
  String get settingsLayer3Desc;

  /// No description provided for @docUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get docUnsaved;

  /// No description provided for @docSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get docSaving;

  /// No description provided for @docSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get docSaved;

  /// No description provided for @docSavedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved {time}'**
  String docSavedAt(String time);

  /// No description provided for @docUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get docUntitled;

  /// No description provided for @docStandalonePasswordProtected.
  ///
  /// In en, this message translates to:
  /// **'This note is protected by a standalone password'**
  String get docStandalonePasswordProtected;

  /// No description provided for @docStandalonePasswordUnset.
  ///
  /// In en, this message translates to:
  /// **'This note has no standalone password yet'**
  String get docStandalonePasswordUnset;

  /// No description provided for @docCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get docCreatedAt;

  /// No description provided for @docUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get docUpdatedAt;

  /// No description provided for @docBlockCount.
  ///
  /// In en, this message translates to:
  /// **'Blocks'**
  String get docBlockCount;

  /// No description provided for @docTagNameHint.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get docTagNameHint;

  /// No description provided for @docPinSameAsLock.
  ///
  /// In en, this message translates to:
  /// **'The standalone password must differ from the app password'**
  String get docPinSameAsLock;

  /// No description provided for @docConfirmStandalonePassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm standalone password'**
  String get docConfirmStandalonePassword;

  /// No description provided for @docPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two entries do not match. Please retry.'**
  String get docPinMismatch;

  /// No description provided for @docSetNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get docSetNewPassword;

  /// No description provided for @docPasswordSetFor.
  ///
  /// In en, this message translates to:
  /// **'Set the standalone password for \"{name}\"'**
  String docPasswordSetFor(String name);

  /// No description provided for @docPasswordSetDiskBound.
  ///
  /// In en, this message translates to:
  /// **'Standalone password set and reset disk bound'**
  String get docPasswordSetDiskBound;

  /// No description provided for @docSetFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to set the password. Please retry.'**
  String get docSetFailed;

  /// No description provided for @docVerifyCurrent.
  ///
  /// In en, this message translates to:
  /// **'Verify current standalone password'**
  String get docVerifyCurrent;

  /// No description provided for @docPasswordChangedFor.
  ///
  /// In en, this message translates to:
  /// **'Changed the standalone password for \"{name}\"'**
  String docPasswordChangedFor(String name);

  /// No description provided for @docWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password or corrupted ciphertext'**
  String get docWrongPassword;

  /// No description provided for @docChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change the password. Please retry.'**
  String get docChangeFailed;

  /// No description provided for @docBindDiskConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Bind reset disk?'**
  String get docBindDiskConfirmTitle;

  /// No description provided for @docBindDiskConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'If you forget this note\'s standalone password later, insert the reset disk (USB drive) to reset it without the old password.\n\nThe disk only contains a random key file (password_reset_disk.key); note data never leaves the device.'**
  String get docBindDiskConfirmContent;

  /// No description provided for @docBindDiskConfirm.
  ///
  /// In en, this message translates to:
  /// **'Bind with disk'**
  String get docBindDiskConfirm;

  /// No description provided for @docNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get docNotNow;

  /// No description provided for @docDiskNotFoundNoBind.
  ///
  /// In en, this message translates to:
  /// **'No valid reset disk file (password_reset_disk.key) found; skipping binding.'**
  String get docDiskNotFoundNoBind;

  /// No description provided for @docDiskNotFound.
  ///
  /// In en, this message translates to:
  /// **'No valid reset disk file (password_reset_disk.key) found.'**
  String get docDiskNotFound;

  /// No description provided for @docVerifyToBind.
  ///
  /// In en, this message translates to:
  /// **'Verify the standalone password to bind the reset disk'**
  String get docVerifyToBind;

  /// No description provided for @docDiskBound.
  ///
  /// In en, this message translates to:
  /// **'Reset disk bound'**
  String get docDiskBound;

  /// No description provided for @docWrongOrAlreadyBound.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password or reset disk already bound'**
  String get docWrongOrAlreadyBound;

  /// No description provided for @docBindFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to bind. Please retry.'**
  String get docBindFailed;

  /// No description provided for @docRemoveConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'After removal, \"{name}\" can be opened without the standalone password. Remove it?'**
  String docRemoveConfirmContent(String name);

  /// No description provided for @docRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get docRemove;

  /// No description provided for @docVerifyToRemove.
  ///
  /// In en, this message translates to:
  /// **'Verify the standalone password to remove it'**
  String get docVerifyToRemove;

  /// No description provided for @docPasswordRemovedFor.
  ///
  /// In en, this message translates to:
  /// **'Removed the standalone password for \"{name}\"'**
  String docPasswordRemovedFor(String name);

  /// No description provided for @docPasswordWrongOrCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password or corrupted ciphertext'**
  String get docPasswordWrongOrCorrupt;

  /// No description provided for @docRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove the password. Please retry.'**
  String get docRemoveFailed;

  /// No description provided for @docUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'This note is locked. Enter its password.'**
  String get docUnlockTitle;

  /// No description provided for @docForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get docForgotPassword;

  /// No description provided for @docsTabDocs.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get docsTabDocs;

  /// No description provided for @docsTabFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get docsTabFavorites;

  /// No description provided for @docsEmptyNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching docs'**
  String get docsEmptyNoMatch;

  /// No description provided for @docsEmptyNoMatchTip.
  ///
  /// In en, this message translates to:
  /// **'Try other keywords or sorting options'**
  String get docsEmptyNoMatchTip;

  /// No description provided for @docsEmptyNoFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorite docs yet'**
  String get docsEmptyNoFavorites;

  /// No description provided for @docsEmptyNoFavoritesTip.
  ///
  /// In en, this message translates to:
  /// **'Tap a doc\'s star to add it to favorites'**
  String get docsEmptyNoFavoritesTip;

  /// No description provided for @docsEmptyFirstNote.
  ///
  /// In en, this message translates to:
  /// **'Write your first note'**
  String get docsEmptyFirstNote;

  /// No description provided for @docsEmptyFirstNoteTip.
  ///
  /// In en, this message translates to:
  /// **'Notes are for typing; canvases are for sketching'**
  String get docsEmptyFirstNoteTip;

  /// No description provided for @docsLoadFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Failed to load. Pull down to retry'**
  String get docsLoadFailedRetry;

  /// No description provided for @docsQuickSearch.
  ///
  /// In en, this message translates to:
  /// **'Quick search'**
  String get docsQuickSearch;

  /// No description provided for @docsClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get docsClearSearch;

  /// No description provided for @docsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get docsRecent;

  /// No description provided for @docsNoDocs.
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get docsNoDocs;

  /// No description provided for @docsMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get docsMore;

  /// No description provided for @docsTrashTab.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get docsTrashTab;

  /// No description provided for @docsTree.
  ///
  /// In en, this message translates to:
  /// **'Document tree'**
  String get docsTree;

  /// No description provided for @docsFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get docsFavorite;

  /// No description provided for @docsUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get docsUnfavorite;

  /// No description provided for @docsMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get docsMoreActions;

  /// No description provided for @docsGroupToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get docsGroupToday;

  /// No description provided for @docsGroupThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get docsGroupThisWeek;

  /// No description provided for @docsGroupEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get docsGroupEarlier;

  /// No description provided for @docsGroupNeverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Never edited'**
  String get docsGroupNeverUpdated;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timeYesterday;

  /// No description provided for @timeMonthDay.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String timeMonthDay(int month, int day);

  /// No description provided for @tagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get tagsEmpty;

  /// No description provided for @tagsEmptyTip.
  ///
  /// In en, this message translates to:
  /// **'Open a note → Document info → Add tags'**
  String get tagsEmptyTip;

  /// No description provided for @tagsAll.
  ///
  /// In en, this message translates to:
  /// **'All tags'**
  String get tagsAll;

  /// No description provided for @tagsNoDocs.
  ///
  /// In en, this message translates to:
  /// **'No notes with this tag'**
  String get tagsNoDocs;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonConfirm;

  /// No description provided for @commonPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get commonPassword;

  /// No description provided for @unlockEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get unlockEnterPassword;

  /// No description provided for @unlockEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get unlockEmergency;

  /// No description provided for @unlockBarrier.
  ///
  /// In en, this message translates to:
  /// **'Password lock'**
  String get unlockBarrier;

  /// No description provided for @unlockPasswordWrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get unlockPasswordWrong;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @shellUnlockNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'This note is encrypted. Enter its password'**
  String get shellUnlockNoteTitle;

  /// No description provided for @shellUnlockCanvasTitle.
  ///
  /// In en, this message translates to:
  /// **'This canvas is encrypted. Enter its standalone password'**
  String get shellUnlockCanvasTitle;

  /// No description provided for @shellUnlockNotebookTitle.
  ///
  /// In en, this message translates to:
  /// **'This paged canvas is encrypted. Enter its password'**
  String get shellUnlockNotebookTitle;

  /// No description provided for @resetThisNote.
  ///
  /// In en, this message translates to:
  /// **'this note'**
  String get resetThisNote;

  /// No description provided for @resetThisCanvas.
  ///
  /// In en, this message translates to:
  /// **'this canvas'**
  String get resetThisCanvas;

  /// No description provided for @resetThisNotebook.
  ///
  /// In en, this message translates to:
  /// **'this paged canvas'**
  String get resetThisNotebook;

  /// No description provided for @resetDocNameQuote.
  ///
  /// In en, this message translates to:
  /// **'“{name}”'**
  String resetDocNameQuote(String name);

  /// No description provided for @resetForgotFilePassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot file password'**
  String get resetForgotFilePassword;

  /// No description provided for @resetForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get resetForgotPassword;

  /// No description provided for @resetImpossible.
  ///
  /// In en, this message translates to:
  /// **'Cannot reset'**
  String get resetImpossible;

  /// No description provided for @resetStandalonePassword.
  ///
  /// In en, this message translates to:
  /// **'Standalone password'**
  String get resetStandalonePassword;

  /// No description provided for @resetFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed'**
  String get resetFailed;

  /// No description provided for @resetDiskMismatchOrCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The reset disk doesn\'t match or is damaged.'**
  String get resetDiskMismatchOrCorrupt;

  /// No description provided for @resetDoneStandalone.
  ///
  /// In en, this message translates to:
  /// **'Standalone password of {name} has been reset with the reset disk'**
  String resetDoneStandalone(String name);

  /// No description provided for @resetDonePassword.
  ///
  /// In en, this message translates to:
  /// **'Password of {name} has been reset with the reset disk'**
  String resetDonePassword(String name);

  /// No description provided for @resetUseDisk.
  ///
  /// In en, this message translates to:
  /// **'Use reset disk'**
  String get resetUseDisk;

  /// No description provided for @resetNoValidKey.
  ///
  /// In en, this message translates to:
  /// **'No valid key found'**
  String get resetNoValidKey;

  /// No description provided for @resetSetNewFilePassword.
  ///
  /// In en, this message translates to:
  /// **'Set a new file password'**
  String get resetSetNewFilePassword;

  /// No description provided for @resetSameAsLockScreen.
  ///
  /// In en, this message translates to:
  /// **'{label} must differ from the screen-lock password'**
  String resetSameAsLockScreen(String label);

  /// No description provided for @resetConfirmNewFilePassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm the new file password'**
  String get resetConfirmNewFilePassword;

  /// No description provided for @resetMismatchRetry.
  ///
  /// In en, this message translates to:
  /// **'The two entries don\'t match. Please try again'**
  String get resetMismatchRetry;

  /// No description provided for @colorPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a color'**
  String get colorPickerTitle;

  /// No description provided for @pinDigitsCount.
  ///
  /// In en, this message translates to:
  /// **'{entered} / {max} digits ({min}–{max} optional)'**
  String pinDigitsCount(int entered, int min, int max);

  /// No description provided for @lockButtonLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lockButtonLock;

  /// No description provided for @lockButtonUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockButtonUnlock;

  /// No description provided for @shellWorkspaceName.
  ///
  /// In en, this message translates to:
  /// **'NoteStudio'**
  String get shellWorkspaceName;

  /// No description provided for @resetIntroNote.
  ///
  /// In en, this message translates to:
  /// **'Reset the standalone password of {name} with the reset disk (USB drive).\n\nPrerequisite: this note has a reset disk bound (set a password, or bind one in password management).'**
  String resetIntroNote(String name);

  /// No description provided for @resetIntroCanvas.
  ///
  /// In en, this message translates to:
  /// **'Reset the standalone password of {name} with the reset disk (USB drive).\n\nPrerequisite: this canvas has a reset disk bound (set a password, or bind one in password management).'**
  String resetIntroCanvas(String name);

  /// No description provided for @resetIntroNotebook.
  ///
  /// In en, this message translates to:
  /// **'Reset the password of {name} with the reset disk (USB drive).\n\nPrerequisite: this paged canvas has a reset disk bound (set a password, or bind one in password management).'**
  String resetIntroNotebook(String name);

  /// No description provided for @resetNotBoundNote.
  ///
  /// In en, this message translates to:
  /// **'{name} has no reset disk (USB drive) bound, so its password cannot be reset via the disk.\n\nYou can choose “Bind reset disk” in password management.'**
  String resetNotBoundNote(String name);

  /// No description provided for @resetNotBoundCanvas.
  ///
  /// In en, this message translates to:
  /// **'{name} has no reset disk (USB drive) bound, so its password cannot be reset via the disk.\n\nYou can choose “Bind reset disk” in password management; passwords set in old versions (v1.5.x) must be changed once first to upgrade the format.'**
  String resetNotBoundCanvas(String name);

  /// No description provided for @resetNotBoundNotebook.
  ///
  /// In en, this message translates to:
  /// **'{name} has no reset disk (USB drive) bound, so its password cannot be reset via the disk.\n\nAfter enabling password protection in Settings, choose “Bind reset disk” from the menu; passwords set in old versions must be changed once first to upgrade the format.'**
  String resetNotBoundNotebook(String name);

  /// No description provided for @resetNoValidKeyBody.
  ///
  /// In en, this message translates to:
  /// **'No valid reset disk file (password_reset_disk.key) found at the chosen location.'**
  String get resetNoValidKeyBody;

  /// No description provided for @homeReadListFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the list. Please retry'**
  String get homeReadListFailed;

  /// No description provided for @homeNewInfiniteCanvas.
  ///
  /// In en, this message translates to:
  /// **'New infinite canvas'**
  String get homeNewInfiniteCanvas;

  /// No description provided for @homeNewInfiniteCanvasSub.
  ///
  /// In en, this message translates to:
  /// **'Free-form drawing, shapes and diagrams'**
  String get homeNewInfiniteCanvasSub;

  /// No description provided for @homeNewPagedCanvasSub.
  ///
  /// In en, this message translates to:
  /// **'Multi-page binding, paper templates and mixed content'**
  String get homeNewPagedCanvasSub;

  /// No description provided for @homeCreateFailedFull.
  ///
  /// In en, this message translates to:
  /// **'Create failed: the notebook was not saved. Check disk space and retry'**
  String get homeCreateFailedFull;

  /// No description provided for @homeCanvasMissing.
  ///
  /// In en, this message translates to:
  /// **'The canvas file is missing or corrupted'**
  String get homeCanvasMissing;

  /// No description provided for @homeOpenCanvasFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the canvas. Please retry'**
  String get homeOpenCanvasFailed;

  /// No description provided for @canvasStandalonePasswordProtected.
  ///
  /// In en, this message translates to:
  /// **'This canvas is protected by a standalone password'**
  String get canvasStandalonePasswordProtected;

  /// No description provided for @canvasStandalonePasswordUnset.
  ///
  /// In en, this message translates to:
  /// **'This canvas has no standalone password set'**
  String get canvasStandalonePasswordUnset;

  /// No description provided for @canvasVaultLockedSet.
  ///
  /// In en, this message translates to:
  /// **'The vault is locked: re-verify the screen-lock password before setting'**
  String get canvasVaultLockedSet;

  /// No description provided for @canvasVaultLockedRemove.
  ///
  /// In en, this message translates to:
  /// **'The vault is locked and cannot re-seal: re-verify the screen-lock password and retry'**
  String get canvasVaultLockedRemove;

  /// No description provided for @canvasPasswordSetDiskBoundFor.
  ///
  /// In en, this message translates to:
  /// **'Standalone password set for “{name}” with the reset disk bound'**
  String canvasPasswordSetDiskBoundFor(String name);

  /// No description provided for @homeDeleteCanvasTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete canvas'**
  String get homeDeleteCanvasTitle;

  /// No description provided for @homeDeleteCanvasConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the canvas “{name}”? This cannot be undone.'**
  String homeDeleteCanvasConfirm(String name);

  /// No description provided for @homeDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed. Please retry'**
  String get homeDeleteFailed;

  /// No description provided for @homeSelectTemplate.
  ///
  /// In en, this message translates to:
  /// **'Choose a note template'**
  String get homeSelectTemplate;

  /// No description provided for @homeCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Create failed. Please retry'**
  String get homeCreateFailed;

  /// No description provided for @homeTrashLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the trash. Please retry'**
  String get homeTrashLoadFailed;

  /// No description provided for @homeRecovered.
  ///
  /// In en, this message translates to:
  /// **'Restored “{id}”'**
  String homeRecovered(String id);

  /// No description provided for @homeRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get homeRetry;

  /// No description provided for @homeNoCanvas.
  ///
  /// In en, this message translates to:
  /// **'No canvases yet'**
  String get homeNoCanvas;

  /// No description provided for @homeNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get homeNoNotes;

  /// No description provided for @homeEmptyTip.
  ///
  /// In en, this message translates to:
  /// **'Tap the button in the lower-right corner to create one'**
  String get homeEmptyTip;

  /// No description provided for @homeInfiniteCanvas.
  ///
  /// In en, this message translates to:
  /// **'Infinite canvases'**
  String get homeInfiniteCanvas;

  /// No description provided for @homePagedCanvas.
  ///
  /// In en, this message translates to:
  /// **'Paged canvases'**
  String get homePagedCanvas;

  /// No description provided for @homeDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get homeDeleteNote;

  /// No description provided for @homeStandalonePassword.
  ///
  /// In en, this message translates to:
  /// **'Standalone password'**
  String get homeStandalonePassword;

  /// No description provided for @homeDeleteInfiniteCanvas.
  ///
  /// In en, this message translates to:
  /// **'Delete infinite canvas'**
  String get homeDeleteInfiniteCanvas;

  /// No description provided for @homeNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get homeNameHint;

  /// No description provided for @nbSessionLocked.
  ///
  /// In en, this message translates to:
  /// **'The session is locked. Please unlock again'**
  String get nbSessionLocked;

  /// No description provided for @nbSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'The session expired. Please reopen this paged canvas'**
  String get nbSessionExpired;

  /// No description provided for @nbSessionRestored.
  ///
  /// In en, this message translates to:
  /// **'Session restored'**
  String get nbSessionRestored;

  /// No description provided for @nbSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed. Please retry'**
  String get nbSaveFailed;

  /// No description provided for @nbReaderMode.
  ///
  /// In en, this message translates to:
  /// **'Page reader'**
  String get nbReaderMode;

  /// No description provided for @nbNewPage.
  ///
  /// In en, this message translates to:
  /// **'New page'**
  String get nbNewPage;

  /// No description provided for @nbRenameNotebook.
  ///
  /// In en, this message translates to:
  /// **'Rename paged canvas'**
  String get nbRenameNotebook;

  /// No description provided for @nbOpenAsBlockDoc.
  ///
  /// In en, this message translates to:
  /// **'Open as block document'**
  String get nbOpenAsBlockDoc;

  /// No description provided for @nbNoPages.
  ///
  /// In en, this message translates to:
  /// **'This paged canvas has no pages yet'**
  String get nbNoPages;

  /// No description provided for @nbNoPagesNew.
  ///
  /// In en, this message translates to:
  /// **'This paged canvas has no pages yet — create one first'**
  String get nbNoPagesNew;

  /// No description provided for @nbUntitledPage.
  ///
  /// In en, this message translates to:
  /// **'Untitled page'**
  String get nbUntitledPage;

  /// No description provided for @nbNoteEncryptedLocked.
  ///
  /// In en, this message translates to:
  /// **'The note is encrypted and the session is locked. Unlock again before opening'**
  String get nbNoteEncryptedLocked;

  /// No description provided for @nbPickPageAsBlock.
  ///
  /// In en, this message translates to:
  /// **'Choose a page to open as a block document'**
  String get nbPickPageAsBlock;

  /// No description provided for @nbNoOtherNotebook.
  ///
  /// In en, this message translates to:
  /// **'No other paged canvas to import from'**
  String get nbNoOtherNotebook;

  /// No description provided for @nbPickSourceNotebook.
  ///
  /// In en, this message translates to:
  /// **'Choose a source paged canvas'**
  String get nbPickSourceNotebook;

  /// No description provided for @nbPickImportPages.
  ///
  /// In en, this message translates to:
  /// **'Choose pages to import'**
  String get nbPickImportPages;

  /// No description provided for @nbExportPdfFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export the whole PDF. Please retry'**
  String get nbExportPdfFailed;

  /// No description provided for @nbDeletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
  String get nbDeletePage;

  /// No description provided for @nbUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get nbUndo;

  /// No description provided for @nbUndoSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Undo failed to save. Please retry'**
  String get nbUndoSaveFailed;

  /// No description provided for @nbPageRef.
  ///
  /// In en, this message translates to:
  /// **'🔗 Ref'**
  String get nbPageRef;

  /// No description provided for @nbUnfavoritePage.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get nbUnfavoritePage;

  /// No description provided for @nbFavoritePage.
  ///
  /// In en, this message translates to:
  /// **'Favorite this page'**
  String get nbFavoritePage;

  /// No description provided for @nbVersionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version history'**
  String get nbVersionHistory;

  /// No description provided for @nbVersionHistoryOf.
  ///
  /// In en, this message translates to:
  /// **'Version history of “{name}”'**
  String nbVersionHistoryOf(String name);

  /// No description provided for @nbPageNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Page name'**
  String get nbPageNameLabel;

  /// No description provided for @nbChooseTemplate.
  ///
  /// In en, this message translates to:
  /// **'Choose a template'**
  String get nbChooseTemplate;

  /// No description provided for @nbCreateAndRecord.
  ///
  /// In en, this message translates to:
  /// **'Create and start writing'**
  String get nbCreateAndRecord;

  /// No description provided for @nbPageNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a page name'**
  String get nbPageNameHint;

  /// No description provided for @nbPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the password'**
  String get nbPasswordHint;

  /// No description provided for @nbShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get nbShowPassword;

  /// No description provided for @nbHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get nbHidePassword;

  /// No description provided for @impMarkdownText.
  ///
  /// In en, this message translates to:
  /// **'Markdown / Text'**
  String get impMarkdownText;

  /// No description provided for @impTextTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Text file too large (over the 20MB limit); import refused'**
  String get impTextTooLarge;

  /// No description provided for @impEmptyFile.
  ///
  /// In en, this message translates to:
  /// **'The file is empty'**
  String get impEmptyFile;

  /// No description provided for @impNoText.
  ///
  /// In en, this message translates to:
  /// **'No text content parsed'**
  String get impNoText;

  /// No description provided for @impImportedParagraphs.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} paragraphs'**
  String impImportedParagraphs(int count);

  /// No description provided for @impFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed. Please retry'**
  String get impFailed;

  /// No description provided for @impPdfTypeGroup.
  ///
  /// In en, this message translates to:
  /// **'PDF documents'**
  String get impPdfTypeGroup;

  /// No description provided for @impPdfNoPages.
  ///
  /// In en, this message translates to:
  /// **'The PDF has no importable pages'**
  String get impPdfNoPages;

  /// No description provided for @impPdfPageTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} · Page {page}'**
  String impPdfPageTitle(String name, int page);

  /// No description provided for @impPdfDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} PDF pages; open any page to annotate'**
  String impPdfDone(int count);

  /// No description provided for @impPdfFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import the PDF. Please retry'**
  String get impPdfFailed;

  /// No description provided for @impChangePasswordProtect.
  ///
  /// In en, this message translates to:
  /// **'Change password protection'**
  String get impChangePasswordProtect;

  /// No description provided for @impSetPasswordProtect.
  ///
  /// In en, this message translates to:
  /// **'Set password protection'**
  String get impSetPasswordProtect;

  /// No description provided for @impChangeHint.
  ///
  /// In en, this message translates to:
  /// **'After changing, opening requires the new password'**
  String get impChangeHint;

  /// No description provided for @impSetHint.
  ///
  /// In en, this message translates to:
  /// **'Once set, page content is stored encrypted and requires the password to open'**
  String get impSetHint;

  /// No description provided for @impPasswordSameAsLock.
  ///
  /// In en, this message translates to:
  /// **'The password must differ from the screen-lock password'**
  String get impPasswordSameAsLock;

  /// No description provided for @impRelockNeeded.
  ///
  /// In en, this message translates to:
  /// **'Unlock with the password again before changing'**
  String get impRelockNeeded;

  /// No description provided for @impPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get impPasswordChanged;

  /// No description provided for @impPasswordEnabled.
  ///
  /// In en, this message translates to:
  /// **'Password protection enabled (page content stored encrypted)'**
  String get impPasswordEnabled;

  /// No description provided for @impChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change the password. Please retry'**
  String get impChangeFailed;

  /// No description provided for @impSetFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to set the password. Please retry'**
  String get impSetFailed;

  /// No description provided for @impBound.
  ///
  /// In en, this message translates to:
  /// **'Reset disk bound'**
  String get impBound;

  /// No description provided for @impBindFailed2.
  ///
  /// In en, this message translates to:
  /// **'Bind failed. Please retry'**
  String get impBindFailed2;

  /// No description provided for @impUnlockFirst.
  ///
  /// In en, this message translates to:
  /// **'Unlock with the password before binding'**
  String get impUnlockFirst;

  /// No description provided for @impNoVersions.
  ///
  /// In en, this message translates to:
  /// **'No version history for this page yet'**
  String get impNoVersions;

  /// No description provided for @impRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get impRestore;

  /// No description provided for @syncFailedUnknown.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: unknown error'**
  String get syncFailedUnknown;

  /// No description provided for @syncFailedRemoteFile.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: failed to sync a remote file. Check the server'**
  String get syncFailedRemoteFile;

  /// No description provided for @syncFailedHttpUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: server temporarily unavailable (HTTP {code}). Try again later'**
  String syncFailedHttpUnavailable(int code);

  /// No description provided for @syncFailedDirMissing.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: remote directory missing or occupied. Check the remote directory settings'**
  String get syncFailedDirMissing;

  /// No description provided for @syncFailedHttps.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: HTTPS handshake failed. Check the server certificate'**
  String get syncFailedHttps;

  /// No description provided for @syncFailedConnect.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: cannot reach the server. Check the network or server address'**
  String get syncFailedConnect;

  /// No description provided for @syncFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: check the network and account settings, then retry'**
  String get syncFailedGeneric;

  /// No description provided for @syncMissingSalt.
  ///
  /// In en, this message translates to:
  /// **'The sync config lacks its salt: tap “Save config” again before syncing'**
  String get syncMissingSalt;

  /// No description provided for @syncMaxRetries.
  ///
  /// In en, this message translates to:
  /// **'Max retries reached'**
  String get syncMaxRetries;

  /// No description provided for @syncUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get syncUpToDate;

  /// No description provided for @syncWithConflicts.
  ///
  /// In en, this message translates to:
  /// **'{base}; {count} more documents changed both locally and remotely and were handled per your choice'**
  String syncWithConflicts(String base, int count);

  /// No description provided for @webdavTitle.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Sync'**
  String get webdavTitle;

  /// No description provided for @webdavUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get webdavUsername;

  /// No description provided for @webdavSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get webdavSyncNow;

  /// No description provided for @webdavSave.
  ///
  /// In en, this message translates to:
  /// **'Save config'**
  String get webdavSave;

  /// No description provided for @cmdNewSticky.
  ///
  /// In en, this message translates to:
  /// **'New sticky note'**
  String get cmdNewSticky;

  /// No description provided for @cmdGroupEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get cmdGroupEdit;

  /// No description provided for @cmdCancelConnect.
  ///
  /// In en, this message translates to:
  /// **'Cancel connect'**
  String get cmdCancelConnect;

  /// No description provided for @cmdConnectMode.
  ///
  /// In en, this message translates to:
  /// **'Connect mode'**
  String get cmdConnectMode;

  /// No description provided for @cmdGroupSelected.
  ///
  /// In en, this message translates to:
  /// **'Group selected'**
  String get cmdGroupSelected;

  /// No description provided for @cmdNeedTwoFrames.
  ///
  /// In en, this message translates to:
  /// **'Needs ≥2 frames'**
  String get cmdNeedTwoFrames;

  /// No description provided for @cmdFitContent.
  ///
  /// In en, this message translates to:
  /// **'Fit content'**
  String get cmdFitContent;

  /// No description provided for @cmdGroupView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get cmdGroupView;

  /// No description provided for @cmdFitSelected.
  ///
  /// In en, this message translates to:
  /// **'Fit selection'**
  String get cmdFitSelected;

  /// No description provided for @cmdZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get cmdZoomIn;

  /// No description provided for @cmdZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get cmdZoomOut;

  /// No description provided for @cmdExitMulti.
  ///
  /// In en, this message translates to:
  /// **'Exit multi-select'**
  String get cmdExitMulti;

  /// No description provided for @cmdEnterMulti.
  ///
  /// In en, this message translates to:
  /// **'Enter multi-select'**
  String get cmdEnterMulti;

  /// No description provided for @cmdGroupSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get cmdGroupSelect;

  /// No description provided for @cmdClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get cmdClearSelection;

  /// No description provided for @cmdFocusSelected.
  ///
  /// In en, this message translates to:
  /// **'Focus selection'**
  String get cmdFocusSelected;

  /// No description provided for @cmdGroupJump.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get cmdGroupJump;

  /// No description provided for @cmdNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get cmdNoMatch;

  /// No description provided for @edPickSourceFrame.
  ///
  /// In en, this message translates to:
  /// **'Select a frame first as the connector start'**
  String get edPickSourceFrame;

  /// No description provided for @edNewFrame.
  ///
  /// In en, this message translates to:
  /// **'Add frame'**
  String get edNewFrame;

  /// No description provided for @edFit.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get edFit;

  /// No description provided for @edMultiSelect.
  ///
  /// In en, this message translates to:
  /// **'Multi-select (group)'**
  String get edMultiSelect;

  /// No description provided for @edGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get edGroup;

  /// No description provided for @edStickyTitle.
  ///
  /// In en, this message translates to:
  /// **'Sticky note'**
  String get edStickyTitle;

  /// No description provided for @edFrameColor.
  ///
  /// In en, this message translates to:
  /// **'Frame background color'**
  String get edFrameColor;

  /// No description provided for @edConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get edConnect;

  /// No description provided for @edEditContent.
  ///
  /// In en, this message translates to:
  /// **'Edit content'**
  String get edEditContent;

  /// No description provided for @edDeleteFrame.
  ///
  /// In en, this message translates to:
  /// **'Delete frame'**
  String get edDeleteFrame;

  /// No description provided for @edSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get edSelect;

  /// No description provided for @edSticky.
  ///
  /// In en, this message translates to:
  /// **'Sticky'**
  String get edSticky;

  /// No description provided for @edBrush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get edBrush;

  /// No description provided for @edEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get edEraser;

  /// No description provided for @edShape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get edShape;

  /// No description provided for @edRect.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get edRect;

  /// No description provided for @edOval.
  ///
  /// In en, this message translates to:
  /// **'Oval'**
  String get edOval;

  /// No description provided for @pfCode.
  ///
  /// In en, this message translates to:
  /// **'Code block'**
  String get pfCode;

  /// No description provided for @pfImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get pfImage;

  /// No description provided for @pfLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get pfLink;

  /// No description provided for @pfCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get pfCanvas;

  /// No description provided for @pfChart.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get pfChart;

  /// No description provided for @pfTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get pfTable;

  /// No description provided for @pfDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get pfDatabase;

  /// No description provided for @pfAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get pfAttachment;

  /// No description provided for @readerTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} · Page reader'**
  String readerTitle(String name);

  /// No description provided for @readerPageIndicator.
  ///
  /// In en, this message translates to:
  /// **'Page {index} of {total}'**
  String readerPageIndicator(int index, int total);

  /// No description provided for @notesWritingTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesWritingTitle;

  /// No description provided for @notesRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get notesRecent;

  /// No description provided for @obWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Drawing Notes'**
  String get obWelcome;

  /// No description provided for @obBrushTip.
  ///
  /// In en, this message translates to:
  /// **'Brush / eraser / eyedropper: switch on the top toolbar; draw with mouse or finger'**
  String get obBrushTip;

  /// No description provided for @obColorTip.
  ///
  /// In en, this message translates to:
  /// **'Color and stroke: the color chip and thickness slider on the right of the toolbar'**
  String get obColorTip;

  /// No description provided for @obLayerTip.
  ///
  /// In en, this message translates to:
  /// **'Layers panel on the right: create, show/hide, opacity, reorder, merge'**
  String get obLayerTip;

  /// No description provided for @obSelectTip.
  ///
  /// In en, this message translates to:
  /// **'Selection tool: marquee-select to move / scale / rotate / copy / delete'**
  String get obSelectTip;

  /// No description provided for @obNoteTip.
  ///
  /// In en, this message translates to:
  /// **'Note pages support text and images: tap with the text tool; insert via the image button'**
  String get obNoteTip;

  /// No description provided for @obFullscreenTip.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen button top-right: hides toolbars for a clean canvas'**
  String get obFullscreenTip;

  /// No description provided for @obStart.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get obStart;

  /// No description provided for @presNoContent.
  ///
  /// In en, this message translates to:
  /// **'Nothing to present'**
  String get presNoContent;

  /// No description provided for @presIndicator.
  ///
  /// In en, this message translates to:
  /// **'{index} / {total} · Click or → for next, Esc to exit'**
  String presIndicator(int index, int total);

  /// No description provided for @presExit.
  ///
  /// In en, this message translates to:
  /// **'Exit presentation'**
  String get presExit;

  /// No description provided for @pdfPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Inline PDF preview unavailable'**
  String get pdfPreviewUnavailable;

  /// No description provided for @conflictApplyAll.
  ///
  /// In en, this message translates to:
  /// **'Apply all'**
  String get conflictApplyAll;

  /// No description provided for @conflictKeepLocal.
  ///
  /// In en, this message translates to:
  /// **'Keep local'**
  String get conflictKeepLocal;

  /// No description provided for @conflictKeepCloud.
  ///
  /// In en, this message translates to:
  /// **'Keep remote'**
  String get conflictKeepCloud;

  /// No description provided for @conflictKeepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get conflictKeepBoth;

  /// No description provided for @searchKindNotebook.
  ///
  /// In en, this message translates to:
  /// **'Paged canvas'**
  String get searchKindNotebook;

  /// No description provided for @searchKindPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Page title'**
  String get searchKindPageTitle;

  /// No description provided for @searchKindCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get searchKindCanvas;

  /// No description provided for @searchKindBlockDoc.
  ///
  /// In en, this message translates to:
  /// **'Block document'**
  String get searchKindBlockDoc;

  /// No description provided for @searchKindDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Document title'**
  String get searchKindDocTitle;

  /// No description provided for @templateBlank.
  ///
  /// In en, this message translates to:
  /// **'Blank note'**
  String get templateBlank;

  /// No description provided for @templateLined.
  ///
  /// In en, this message translates to:
  /// **'Lined note'**
  String get templateLined;

  /// No description provided for @templateGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid paper'**
  String get templateGrid;

  /// No description provided for @templateDot.
  ///
  /// In en, this message translates to:
  /// **'Dot-grid note'**
  String get templateDot;

  /// No description provided for @templateMeeting.
  ///
  /// In en, this message translates to:
  /// **'Meeting notes'**
  String get templateMeeting;

  /// No description provided for @templateCornell.
  ///
  /// In en, this message translates to:
  /// **'Cornell notes'**
  String get templateCornell;

  /// No description provided for @templatePlanner.
  ///
  /// In en, this message translates to:
  /// **'Planner page'**
  String get templatePlanner;

  /// No description provided for @templateWhiteboard.
  ///
  /// In en, this message translates to:
  /// **'Wide whiteboard'**
  String get templateWhiteboard;

  /// No description provided for @rootRefusedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot start on this device'**
  String get rootRefusedTitle;

  /// No description provided for @rootRefusedBody.
  ///
  /// In en, this message translates to:
  /// **'This device has ROOT access. To protect your encrypted notes, the app refuses to run on a compromised device.'**
  String get rootRefusedBody;

  /// No description provided for @canvasBindConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'When you forget this canvas’s standalone password, plug in the reset disk (USB drive) to reset without the old password.\n\nThe drive holds only a random key file (password_reset_disk.key); canvas data never leaves the device.'**
  String get canvasBindConfirmContent;

  /// No description provided for @canvasRemoveConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'After removal, “{name}” falls back to vault protection (master-key envelope) and no longer needs a standalone password. Remove it?'**
  String canvasRemoveConfirmContent(String name);

  /// No description provided for @canvasBoundDiskFor.
  ///
  /// In en, this message translates to:
  /// **'Reset disk bound for “{name}”'**
  String canvasBoundDiskFor(String name);

  /// No description provided for @homeDeleteForeverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete “{name}”? This cannot be undone.'**
  String homeDeleteForeverConfirm(String name);

  /// No description provided for @homeRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed. Please retry'**
  String get homeRestoreFailed;

  /// No description provided for @homeTabCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvases'**
  String get homeTabCanvas;

  /// No description provided for @homeTabNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get homeTabNotes;

  /// No description provided for @canvasDeletePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'This canvas is encrypted. Enter its standalone password'**
  String get canvasDeletePasswordTitle;

  /// No description provided for @homeKindNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get homeKindNote;

  /// No description provided for @homeKindNotebookPage.
  ///
  /// In en, this message translates to:
  /// **'Paged-canvas page'**
  String get homeKindNotebookPage;

  /// No description provided for @homeUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String homeUpdatedAt(String time);

  /// No description provided for @homeDeleteNoteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the note “{name}”? This cannot be undone.'**
  String homeDeleteNoteConfirm(Object name);

  /// No description provided for @homeUntitledNotebookPage.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get homeUntitledNotebookPage;

  /// No description provided for @homeStandalonePasswordMenu.
  ///
  /// In en, this message translates to:
  /// **'Standalone password…'**
  String get homeStandalonePasswordMenu;

  /// No description provided for @nbEmptyTip.
  ///
  /// In en, this message translates to:
  /// **'Tap New in the top-right corner'**
  String get nbEmptyTip;

  /// No description provided for @nbNoTagMatch.
  ///
  /// In en, this message translates to:
  /// **'No pages match this tag'**
  String get nbNoTagMatch;

  /// No description provided for @nbNoTagMatchTip.
  ///
  /// In en, this message translates to:
  /// **'Try another tag'**
  String get nbNoTagMatchTip;

  /// No description provided for @impBindAskContent.
  ///
  /// In en, this message translates to:
  /// **'When you forget the password, plug in the USB drive to reset a new one.\n\nYou can also bind later via “Bind reset disk” in the menu.'**
  String get impBindAskContent;

  /// No description provided for @impRestoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore this version?'**
  String get impRestoreConfirmTitle;

  /// No description provided for @impRestoreConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'The current page content will be overwritten by the chosen version (current content is saved to history first).'**
  String get impRestoreConfirmContent;

  /// No description provided for @nbPageNameExampleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Product review 08-14'**
  String get nbPageNameExampleHint;

  /// No description provided for @nbDeletePageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the page “{name}”? Its handwriting and text will be deleted too.'**
  String nbDeletePageConfirm(String name);

  /// No description provided for @nbPageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted “{name}”'**
  String nbPageDeleted(String name);

  /// No description provided for @nbExportedPdf.
  ///
  /// In en, this message translates to:
  /// **'Exported a {count}-page PDF: {path}'**
  String nbExportedPdf(int count, String path);

  /// No description provided for @cmdGotoFrame.
  ///
  /// In en, this message translates to:
  /// **'Go to “{name}”'**
  String cmdGotoFrame(String name);

  /// No description provided for @obPinchTip.
  ///
  /// In en, this message translates to:
  /// **'Pinch with two fingers to zoom, rotate with two fingers (touch devices)'**
  String get obPinchTip;

  /// No description provided for @obAutosaveTip.
  ///
  /// In en, this message translates to:
  /// **'Content autosaves — no manual save needed; export to PNG anytime'**
  String get obAutosaveTip;

  /// No description provided for @syncFailedAuth.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: wrong username or password (server rejected the login)'**
  String get syncFailedAuth;

  /// No description provided for @syncFailedRejected.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: the server rejected this request (HTTP {code})'**
  String syncFailedRejected(String code);

  /// No description provided for @syncHttpUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get syncHttpUnknown;

  /// No description provided for @syncDoneSummary.
  ///
  /// In en, this message translates to:
  /// **'Sync done: ↑{up} ↓{down} ✕{del}'**
  String syncDoneSummary(int up, int down, int del);

  /// No description provided for @webdavFormDirty.
  ///
  /// In en, this message translates to:
  /// **'The form has unsaved changes: tap “Save config” before syncing (avoids mismatched keys and cloud data)'**
  String get webdavFormDirty;

  /// No description provided for @webdavSyncSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync password (required, for end-to-end encryption)'**
  String get webdavSyncSecretLabel;

  /// No description provided for @webdavSyncSecretHelper.
  ///
  /// In en, this message translates to:
  /// **'Syncing is blocked without a sync password (prevents plaintext notes in the cloud)'**
  String get webdavSyncSecretHelper;

  /// No description provided for @webdavSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get webdavSyncing;

  /// No description provided for @tplDescMeeting.
  ///
  /// In en, this message translates to:
  /// **'Starting structure with topics, decisions and action items.'**
  String get tplDescMeeting;

  /// No description provided for @tplDescCornell.
  ///
  /// In en, this message translates to:
  /// **'Starting structure with cue, notes and summary areas.'**
  String get tplDescCornell;

  /// No description provided for @tplDescPlanner.
  ///
  /// In en, this message translates to:
  /// **'Starting structure with priorities, schedule and review.'**
  String get tplDescPlanner;

  /// No description provided for @tplDescWhiteboard.
  ///
  /// In en, this message translates to:
  /// **'Wide blank canvas mode; this version still uses a fixed coordinate paper.'**
  String get tplDescWhiteboard;

  /// No description provided for @tplDescDefault.
  ///
  /// In en, this message translates to:
  /// **'The paper background follows the template and is saved to the page.'**
  String get tplDescDefault;

  /// No description provided for @homeDeleteForeverFailed.
  ///
  /// In en, this message translates to:
  /// **'Permanent delete failed. Please retry'**
  String get homeDeleteForeverFailed;

  /// No description provided for @impDiskNotFound.
  ///
  /// In en, this message translates to:
  /// **'No valid reset disk file (password_reset_disk.key) found'**
  String get impDiskNotFound;

  /// No description provided for @lockDiskKeepNote.
  ///
  /// In en, this message translates to:
  /// **'Do not delete the password_reset_disk.key file on the USB drive'**
  String get lockDiskKeepNote;

  /// No description provided for @cmdUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get cmdUndo;

  /// No description provided for @cmdRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get cmdRedo;

  /// No description provided for @cmdCopySelection.
  ///
  /// In en, this message translates to:
  /// **'Copy selection'**
  String get cmdCopySelection;

  /// No description provided for @cmdPasteClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get cmdPasteClipboard;

  /// No description provided for @cmdDuplicateSelection.
  ///
  /// In en, this message translates to:
  /// **'Duplicate selection'**
  String get cmdDuplicateSelection;

  /// No description provided for @cmdDeleteSelection.
  ///
  /// In en, this message translates to:
  /// **'Delete selection'**
  String get cmdDeleteSelection;

  /// No description provided for @cmdBold.
  ///
  /// In en, this message translates to:
  /// **'Bold selected text'**
  String get cmdBold;

  /// No description provided for @cmdItalic.
  ///
  /// In en, this message translates to:
  /// **'Italicize selected text'**
  String get cmdItalic;

  /// No description provided for @cmdUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline selected text'**
  String get cmdUnderline;

  /// No description provided for @cmdStrikethrough.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough selected text'**
  String get cmdStrikethrough;

  /// No description provided for @cmdCycleAlign.
  ///
  /// In en, this message translates to:
  /// **'Cycle text alignment'**
  String get cmdCycleAlign;

  /// No description provided for @cmdFitCanvas.
  ///
  /// In en, this message translates to:
  /// **'Fit canvas'**
  String get cmdFitCanvas;

  /// No description provided for @cmdToggleGrid.
  ///
  /// In en, this message translates to:
  /// **'Show or hide grid'**
  String get cmdToggleGrid;

  /// No description provided for @cmdToggleSnap.
  ///
  /// In en, this message translates to:
  /// **'Toggle grid snap'**
  String get cmdToggleSnap;

  /// No description provided for @cmdExportWord.
  ///
  /// In en, this message translates to:
  /// **'Export Word-compatible document'**
  String get cmdExportWord;

  /// No description provided for @catEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get catEdit;

  /// No description provided for @catFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get catFormat;

  /// No description provided for @catInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get catInsert;

  /// No description provided for @catArrange.
  ///
  /// In en, this message translates to:
  /// **'Arrange'**
  String get catArrange;

  /// No description provided for @catView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get catView;

  /// No description provided for @catExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get catExport;

  /// No description provided for @expCopyRenderFail.
  ///
  /// In en, this message translates to:
  /// **'Copy failed: cannot render the canvas'**
  String get expCopyRenderFail;

  /// No description provided for @expCopyDecodeFail.
  ///
  /// In en, this message translates to:
  /// **'Copy failed: pixel decoding failed'**
  String get expCopyDecodeFail;

  /// No description provided for @expCopiedPng.
  ///
  /// In en, this message translates to:
  /// **'PNG copied to clipboard'**
  String get expCopiedPng;

  /// No description provided for @expRenderFail.
  ///
  /// In en, this message translates to:
  /// **'Export failed: cannot render the canvas'**
  String get expRenderFail;

  /// No description provided for @expNoPages.
  ///
  /// In en, this message translates to:
  /// **'No pages to export'**
  String get expNoPages;

  /// No description provided for @expEmptyCanvas.
  ///
  /// In en, this message translates to:
  /// **'Export failed: the canvas is empty'**
  String get expEmptyCanvas;

  /// No description provided for @expWordPagedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only paged notes support exporting Word-compatible documents'**
  String get expWordPagedOnly;

  /// No description provided for @expWordNoText.
  ///
  /// In en, this message translates to:
  /// **'This page has no text content to export'**
  String get expWordNoText;

  /// No description provided for @expTextPagedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only paged-canvas pages support exporting text'**
  String get expTextPagedOnly;

  /// No description provided for @expTextNoText.
  ///
  /// In en, this message translates to:
  /// **'This page has no text content'**
  String get expTextNoText;

  /// No description provided for @expPptxPackFail.
  ///
  /// In en, this message translates to:
  /// **'Export failed: PPTX packaging failed'**
  String get expPptxPackFail;

  /// No description provided for @fileTypePng.
  ///
  /// In en, this message translates to:
  /// **'PNG image'**
  String get fileTypePng;

  /// No description provided for @fileTypePdf.
  ///
  /// In en, this message translates to:
  /// **'PDF document'**
  String get fileTypePdf;

  /// No description provided for @fileTypeSvg.
  ///
  /// In en, this message translates to:
  /// **'SVG vector image'**
  String get fileTypeSvg;

  /// No description provided for @fileTypeWord.
  ///
  /// In en, this message translates to:
  /// **'Word-compatible document'**
  String get fileTypeWord;

  /// No description provided for @fileTypeMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown / Text'**
  String get fileTypeMarkdown;

  /// No description provided for @fileTypePptx.
  ///
  /// In en, this message translates to:
  /// **'PPTX presentation'**
  String get fileTypePptx;

  /// No description provided for @fileTypeJson.
  ///
  /// In en, this message translates to:
  /// **'JSON project file'**
  String get fileTypeJson;

  /// No description provided for @expWholeBookSuffix.
  ///
  /// In en, this message translates to:
  /// **'whole-book'**
  String get expWholeBookSuffix;

  /// No description provided for @pdfPaperFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow canvas'**
  String get pdfPaperFollow;

  /// No description provided for @pdfRangeCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current page'**
  String get pdfRangeCurrent;

  /// No description provided for @pdfRangeAll.
  ///
  /// In en, this message translates to:
  /// **'All pages'**
  String get pdfRangeAll;

  /// No description provided for @pdfQualityLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get pdfQualityLossless;

  /// No description provided for @pdfQualityLosslessDesc.
  ///
  /// In en, this message translates to:
  /// **'PNG lossless, largest size'**
  String get pdfQualityLosslessDesc;

  /// No description provided for @pdfQualityStandardDesc.
  ///
  /// In en, this message translates to:
  /// **'JPEG 80, recommended'**
  String get pdfQualityStandardDesc;

  /// No description provided for @pdfQualitySaverDesc.
  ///
  /// In en, this message translates to:
  /// **'JPEG 60, smallest size'**
  String get pdfQualitySaverDesc;

  /// No description provided for @pdfGroupPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get pdfGroupPaper;

  /// No description provided for @pdfGroupQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get pdfGroupQuality;

  /// No description provided for @pdfExportNPages.
  ///
  /// In en, this message translates to:
  /// **'Export {count} pages'**
  String pdfExportNPages(int count);

  /// No description provided for @inkStylusPressure.
  ///
  /// In en, this message translates to:
  /// **'Stylus pressure'**
  String get inkStylusPressure;

  /// No description provided for @inkTouchPressure.
  ///
  /// In en, this message translates to:
  /// **'Touch pressure'**
  String get inkTouchPressure;

  /// No description provided for @inkMouseVelocity.
  ///
  /// In en, this message translates to:
  /// **'Mouse velocity simulation'**
  String get inkMouseVelocity;

  /// No description provided for @inkConstant.
  ///
  /// In en, this message translates to:
  /// **'Constant width'**
  String get inkConstant;

  /// No description provided for @pomodoroPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pomodoroPause;

  /// No description provided for @pomodoroStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get pomodoroStart;

  /// No description provided for @pomodoroReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get pomodoroReset;

  /// No description provided for @pomodoroFinish.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro finished: take a break'**
  String get pomodoroFinish;

  /// No description provided for @pageIndicator.
  ///
  /// In en, this message translates to:
  /// **'Page {index} of {total}'**
  String pageIndicator(int index, int total);

  /// No description provided for @eraserWholeStroke.
  ///
  /// In en, this message translates to:
  /// **'Whole stroke'**
  String get eraserWholeStroke;

  /// No description provided for @eraserTransparent.
  ///
  /// In en, this message translates to:
  /// **'Pixels'**
  String get eraserTransparent;

  /// No description provided for @markerSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get markerSave;

  /// No description provided for @markerAutoFade.
  ///
  /// In en, this message translates to:
  /// **'Auto-fade'**
  String get markerAutoFade;

  /// No description provided for @tooltipSwapFill.
  ///
  /// In en, this message translates to:
  /// **'Swap fill color'**
  String get tooltipSwapFill;

  /// No description provided for @tooltipDashStyle.
  ///
  /// In en, this message translates to:
  /// **'Solid / dashed'**
  String get tooltipDashStyle;

  /// No description provided for @hintEyedropper.
  ///
  /// In en, this message translates to:
  /// **'Tap the canvas to pick a color'**
  String get hintEyedropper;

  /// No description provided for @hintTextTool.
  ///
  /// In en, this message translates to:
  /// **'Tap the canvas to place text'**
  String get hintTextTool;

  /// No description provided for @hintConnect.
  ///
  /// In en, this message translates to:
  /// **'Pick two elements in turn to connect'**
  String get hintConnect;

  /// No description provided for @hintPixelEraser.
  ///
  /// In en, this message translates to:
  /// **'Erase transparent pixels'**
  String get hintPixelEraser;

  /// No description provided for @hintStrokeEraser.
  ///
  /// In en, this message translates to:
  /// **'Delete whole strokes'**
  String get hintStrokeEraser;

  /// No description provided for @hintTempHighlight.
  ///
  /// In en, this message translates to:
  /// **'Temporary highlight: auto-fades in ~4s'**
  String get hintTempHighlight;

  /// No description provided for @hintSavedHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlighter: saved to the page'**
  String get hintSavedHighlight;

  /// No description provided for @hintLaser.
  ///
  /// In en, this message translates to:
  /// **'Laser pointer: fades segment by segment after release; not saved'**
  String get hintLaser;

  /// No description provided for @hintBrush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get hintBrush;

  /// No description provided for @toolEyedropper.
  ///
  /// In en, this message translates to:
  /// **'Eyedropper'**
  String get toolEyedropper;

  /// No description provided for @toolMarquee.
  ///
  /// In en, this message translates to:
  /// **'Marquee-select elements'**
  String get toolMarquee;

  /// No description provided for @toolNodeLink.
  ///
  /// In en, this message translates to:
  /// **'Node link'**
  String get toolNodeLink;

  /// No description provided for @shapeRect.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get shapeRect;

  /// No description provided for @shapeEllipse.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get shapeEllipse;

  /// No description provided for @shapeDiamond.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get shapeDiamond;

  /// No description provided for @shapeArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get shapeArrow;

  /// No description provided for @shapeLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get shapeLine;

  /// No description provided for @saveStateUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get saveStateUnsaved;

  /// No description provided for @saveStateSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saveStateSaved;

  /// No description provided for @cropInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid crop area'**
  String get cropInvalid;

  /// No description provided for @cropSourceMissing.
  ///
  /// In en, this message translates to:
  /// **'Source image file is missing'**
  String get cropSourceMissing;

  /// No description provided for @cropEncodeFail.
  ///
  /// In en, this message translates to:
  /// **'Crop encoding failed'**
  String get cropEncodeFail;

  /// No description provided for @cropVaultLocked.
  ///
  /// In en, this message translates to:
  /// **'Vault is locked; cannot save the crop'**
  String get cropVaultLocked;

  /// No description provided for @cropDone.
  ///
  /// In en, this message translates to:
  /// **'Image cropped'**
  String get cropDone;

  /// No description provided for @cropDragHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the corners to adjust the crop area, then tap the crop button'**
  String get cropDragHint;

  /// No description provided for @cropHandleTopLeft.
  ///
  /// In en, this message translates to:
  /// **'Adjust crop top-left corner'**
  String get cropHandleTopLeft;

  /// No description provided for @cropHandleTopRight.
  ///
  /// In en, this message translates to:
  /// **'Adjust crop top-right corner'**
  String get cropHandleTopRight;

  /// No description provided for @cropHandleBottomLeft.
  ///
  /// In en, this message translates to:
  /// **'Adjust crop bottom-left corner'**
  String get cropHandleBottomLeft;

  /// No description provided for @cropHandleBottomRight.
  ///
  /// In en, this message translates to:
  /// **'Adjust crop bottom-right corner'**
  String get cropHandleBottomRight;

  /// No description provided for @canvasSemanticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Drawing canvas'**
  String get canvasSemanticsLabel;

  /// No description provided for @canvasSemanticsHint.
  ///
  /// In en, this message translates to:
  /// **'Double-tap blank space to insert text; draw with the toolbar tools'**
  String get canvasSemanticsHint;

  /// No description provided for @actSwitchInfinite.
  ///
  /// In en, this message translates to:
  /// **'Switched to infinite canvas (unbounded)'**
  String get actSwitchInfinite;

  /// No description provided for @actSwitchFixed.
  ///
  /// In en, this message translates to:
  /// **'Switched back to fixed paper'**
  String get actSwitchFixed;

  /// No description provided for @actChartPagedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only paged-canvas pages support charts'**
  String get actChartPagedOnly;

  /// No description provided for @actChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate chart'**
  String get actChartTitle;

  /// No description provided for @actChartBar.
  ///
  /// In en, this message translates to:
  /// **'Bar chart'**
  String get actChartBar;

  /// No description provided for @actChartLine.
  ///
  /// In en, this message translates to:
  /// **'Line chart'**
  String get actChartLine;

  /// No description provided for @actChartGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get actChartGenerate;

  /// No description provided for @actChartNoData.
  ///
  /// In en, this message translates to:
  /// **'No valid numbers parsed'**
  String get actChartNoData;

  /// No description provided for @actSlidesPagedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only paged-canvas pages support slide presentation'**
  String get actSlidesPagedOnly;

  /// No description provided for @actSlidesNoContent.
  ///
  /// In en, this message translates to:
  /// **'This page has nothing to present'**
  String get actSlidesNoContent;

  /// No description provided for @actSlidesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Presentation unavailable'**
  String get actSlidesUnavailable;

  /// No description provided for @actStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Canvas statistics'**
  String get actStatsTitle;

  /// No description provided for @actStatStrokes.
  ///
  /// In en, this message translates to:
  /// **'Handwritten strokes'**
  String get actStatStrokes;

  /// No description provided for @actStatTextBlocks.
  ///
  /// In en, this message translates to:
  /// **'Text blocks'**
  String get actStatTextBlocks;

  /// No description provided for @actStatImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get actStatImages;

  /// No description provided for @actStatShapes.
  ///
  /// In en, this message translates to:
  /// **'Shapes'**
  String get actStatShapes;

  /// No description provided for @actStatCharts.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get actStatCharts;

  /// No description provided for @actStatTotal.
  ///
  /// In en, this message translates to:
  /// **'Total elements'**
  String get actStatTotal;

  /// No description provided for @actShapeLibPagedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only paged-canvas pages support the shape library'**
  String get actShapeLibPagedOnly;

  /// No description provided for @actCopiedN.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} elements'**
  String actCopiedN(int count);

  /// No description provided for @actPickFirst.
  ///
  /// In en, this message translates to:
  /// **'Select elements to copy first'**
  String get actPickFirst;

  /// No description provided for @actPastedN.
  ///
  /// In en, this message translates to:
  /// **'Pasted {count} elements'**
  String actPastedN(int count);

  /// No description provided for @actCopiedTextStyle.
  ///
  /// In en, this message translates to:
  /// **'Text style copied'**
  String get actCopiedTextStyle;

  /// No description provided for @actCopiedShapeStyle.
  ///
  /// In en, this message translates to:
  /// **'Shape style copied'**
  String get actCopiedShapeStyle;

  /// No description provided for @actPickStyleSource.
  ///
  /// In en, this message translates to:
  /// **'Select a text block or shape first'**
  String get actPickStyleSource;

  /// No description provided for @actCopyStyleFirst.
  ///
  /// In en, this message translates to:
  /// **'Copy a style first (Ctrl+Shift+C) before pasting'**
  String get actCopyStyleFirst;

  /// No description provided for @actPastedStyle.
  ///
  /// In en, this message translates to:
  /// **'Style pasted'**
  String get actPastedStyle;

  /// No description provided for @actPastePagedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only paged-canvas pages support pasting'**
  String get actPastePagedOnly;

  /// No description provided for @actClipboardNoText.
  ///
  /// In en, this message translates to:
  /// **'No pastable text in the clipboard'**
  String get actClipboardNoText;

  /// No description provided for @actShortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get actShortcutsTitle;

  /// No description provided for @barPagedNote.
  ///
  /// In en, this message translates to:
  /// **'Paged note'**
  String get barPagedNote;

  /// No description provided for @barInfiniteCanvas.
  ///
  /// In en, this message translates to:
  /// **'Infinite canvas'**
  String get barInfiniteCanvas;

  /// No description provided for @barHideLayers.
  ///
  /// In en, this message translates to:
  /// **'Hide layers'**
  String get barHideLayers;

  /// No description provided for @barShowLayers.
  ///
  /// In en, this message translates to:
  /// **'Show layers'**
  String get barShowLayers;

  /// No description provided for @barHideInspector.
  ///
  /// In en, this message translates to:
  /// **'Hide inspector'**
  String get barHideInspector;

  /// No description provided for @barShowInspector.
  ///
  /// In en, this message translates to:
  /// **'Show inspector'**
  String get barShowInspector;

  /// No description provided for @barExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get barExitFullscreen;

  /// No description provided for @barEnterFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get barEnterFullscreen;

  /// No description provided for @barReadingOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off dark reading'**
  String get barReadingOff;

  /// No description provided for @barReadingOn.
  ///
  /// In en, this message translates to:
  /// **'Dark reading (display only)'**
  String get barReadingOn;

  /// No description provided for @menuExportText.
  ///
  /// In en, this message translates to:
  /// **'Export text'**
  String get menuExportText;

  /// No description provided for @menuCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get menuCommandPalette;

  /// No description provided for @menuSlides.
  ///
  /// In en, this message translates to:
  /// **'Slide presentation'**
  String get menuSlides;

  /// No description provided for @menuStats.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get menuStats;

  /// No description provided for @menuShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcut help'**
  String get menuShortcuts;

  /// No description provided for @menuSwitchToFixed.
  ///
  /// In en, this message translates to:
  /// **'Switch to fixed paper'**
  String get menuSwitchToFixed;

  /// No description provided for @menuSwitchToInfinite.
  ///
  /// In en, this message translates to:
  /// **'Switch to infinite canvas'**
  String get menuSwitchToInfinite;

  /// No description provided for @paletteRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get paletteRecent;

  /// No description provided for @paletteNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get paletteNoMatch;

  /// No description provided for @textInputTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter text'**
  String get textInputTitle;

  /// No description provided for @textInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter text content'**
  String get textInputHint;

  /// No description provided for @distributeNeed3.
  ///
  /// In en, this message translates to:
  /// **'At least 3 elements are needed to distribute'**
  String get distributeNeed3;

  /// No description provided for @distributedH.
  ///
  /// In en, this message translates to:
  /// **'Distributed horizontally'**
  String get distributedH;

  /// No description provided for @distributedV.
  ///
  /// In en, this message translates to:
  /// **'Distributed vertically'**
  String get distributedV;

  /// No description provided for @edPreviewPagedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only paged-canvas pages support paged preview'**
  String get edPreviewPagedOnly;

  /// No description provided for @edNoTextHere.
  ///
  /// In en, this message translates to:
  /// **'This page has no text content yet'**
  String get edNoTextHere;

  /// No description provided for @edNoTextBlocks.
  ///
  /// In en, this message translates to:
  /// **'No text blocks on this page'**
  String get edNoTextBlocks;

  /// No description provided for @edRecoloredN.
  ///
  /// In en, this message translates to:
  /// **'Recolored {count} text blocks'**
  String edRecoloredN(int count);

  /// No description provided for @edImageLabel.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get edImageLabel;

  /// No description provided for @edNoteImageStoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Note image storage unavailable'**
  String get edNoteImageStoreUnavailable;

  /// No description provided for @edDrawingImageStoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Drawing image storage unavailable'**
  String get edDrawingImageStoreUnavailable;

  /// No description provided for @edLinkStartPicked.
  ///
  /// In en, this message translates to:
  /// **'Start picked; tap another element to finish the connector'**
  String get edLinkStartPicked;

  /// No description provided for @edLinkCreated.
  ///
  /// In en, this message translates to:
  /// **'Connector created'**
  String get edLinkCreated;

  /// No description provided for @ctxCopyStyle.
  ///
  /// In en, this message translates to:
  /// **'Copy style'**
  String get ctxCopyStyle;

  /// No description provided for @ctxGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get ctxGroup;

  /// No description provided for @ctxUngroup.
  ///
  /// In en, this message translates to:
  /// **'Ungroup'**
  String get ctxUngroup;

  /// No description provided for @ctxBringToFront.
  ///
  /// In en, this message translates to:
  /// **'Bring to front'**
  String get ctxBringToFront;

  /// No description provided for @ctxSendToBack.
  ///
  /// In en, this message translates to:
  /// **'Send to back'**
  String get ctxSendToBack;

  /// No description provided for @edLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'Link invalid or unsupported'**
  String get edLinkInvalid;

  /// No description provided for @edLinkOpened.
  ///
  /// In en, this message translates to:
  /// **'Link opened'**
  String get edLinkOpened;

  /// No description provided for @edLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Set link'**
  String get edLinkTitle;

  /// No description provided for @edLinkCleared.
  ///
  /// In en, this message translates to:
  /// **'Link cleared'**
  String get edLinkCleared;

  /// No description provided for @edLinkSet.
  ///
  /// In en, this message translates to:
  /// **'Link set'**
  String get edLinkSet;

  /// No description provided for @edGroupNeed2.
  ///
  /// In en, this message translates to:
  /// **'Marquee/multi-select at least 2 elements before grouping'**
  String get edGroupNeed2;

  /// No description provided for @edGroupedN.
  ///
  /// In en, this message translates to:
  /// **'Grouped {count} elements'**
  String edGroupedN(int count);

  /// No description provided for @edUngrouped.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get edUngrouped;

  /// No description provided for @renameCanvasTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename canvas'**
  String get renameCanvasTitle;

  /// No description provided for @textBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get textBold;

  /// No description provided for @textItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get textItalic;

  /// No description provided for @textTodo.
  ///
  /// In en, this message translates to:
  /// **'To-do'**
  String get textTodo;

  /// No description provided for @textCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get textCenter;

  /// No description provided for @textDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get textDone;

  /// No description provided for @textWidthHandle.
  ///
  /// In en, this message translates to:
  /// **'Adjust text width'**
  String get textWidthHandle;

  /// No description provided for @toolEraserName.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get toolEraserName;

  /// No description provided for @pressureReal.
  ///
  /// In en, this message translates to:
  /// **'Using the device\'s reported pressure range'**
  String get pressureReal;

  /// No description provided for @pressureFallback.
  ///
  /// In en, this message translates to:
  /// **'This device reports no usable pressure; a stable fallback is in use'**
  String get pressureFallback;

  /// No description provided for @coordsHide.
  ///
  /// In en, this message translates to:
  /// **'Hide coordinates'**
  String get coordsHide;

  /// No description provided for @coordsShow.
  ///
  /// In en, this message translates to:
  /// **'Show canvas coordinates'**
  String get coordsShow;

  /// No description provided for @zoomTooltip.
  ///
  /// In en, this message translates to:
  /// **'Zoom canvas'**
  String get zoomTooltip;

  /// No description provided for @layersTitle.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get layersTitle;

  /// No description provided for @layerNew.
  ///
  /// In en, this message translates to:
  /// **'New layer'**
  String get layerNew;

  /// No description provided for @layerUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get layerUp;

  /// No description provided for @layerDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get layerDown;

  /// No description provided for @layerMergeDown.
  ///
  /// In en, this message translates to:
  /// **'Merge down'**
  String get layerMergeDown;

  /// No description provided for @layerDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete layer'**
  String get layerDelete;

  /// No description provided for @propBrush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get propBrush;

  /// No description provided for @propBrushColor.
  ///
  /// In en, this message translates to:
  /// **'Brush color'**
  String get propBrushColor;

  /// No description provided for @propImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get propImage;

  /// No description provided for @propCropImage.
  ///
  /// In en, this message translates to:
  /// **'Crop image'**
  String get propCropImage;

  /// No description provided for @propShape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get propShape;

  /// No description provided for @propFillColor.
  ///
  /// In en, this message translates to:
  /// **'Fill color'**
  String get propFillColor;

  /// No description provided for @propDash.
  ///
  /// In en, this message translates to:
  /// **'Solid/dashed'**
  String get propDash;

  /// No description provided for @propText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get propText;

  /// No description provided for @propTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get propTextColor;

  /// No description provided for @fontSerif.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get fontSerif;

  /// No description provided for @fontMono.
  ///
  /// In en, this message translates to:
  /// **'Monospace'**
  String get fontMono;

  /// No description provided for @fontHandwriting.
  ///
  /// In en, this message translates to:
  /// **'Handwriting'**
  String get fontHandwriting;

  /// No description provided for @fontDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get fontDefault;

  /// No description provided for @selCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy selection'**
  String get selCopy;

  /// No description provided for @selPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get selPaste;

  /// No description provided for @selUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock selection'**
  String get selUnlock;

  /// No description provided for @selLock.
  ///
  /// In en, this message translates to:
  /// **'Lock selection against accidental edits'**
  String get selLock;

  /// No description provided for @selUnlockImage.
  ///
  /// In en, this message translates to:
  /// **'Unlock image'**
  String get selUnlockImage;

  /// No description provided for @selLockImage.
  ///
  /// In en, this message translates to:
  /// **'Lock image against accidental edits'**
  String get selLockImage;

  /// No description provided for @selUnlockShape.
  ///
  /// In en, this message translates to:
  /// **'Unlock shape'**
  String get selUnlockShape;

  /// No description provided for @selLockShape.
  ///
  /// In en, this message translates to:
  /// **'Lock shape against accidental edits'**
  String get selLockShape;

  /// No description provided for @selDeleteLockedKeep.
  ///
  /// In en, this message translates to:
  /// **'Delete unlocked objects; locked ones are kept'**
  String get selDeleteLockedKeep;

  /// No description provided for @selDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete selection'**
  String get selDelete;

  /// No description provided for @selShapeLocked.
  ///
  /// In en, this message translates to:
  /// **'Shape is locked; cannot delete'**
  String get selShapeLocked;

  /// No description provided for @selImageLocked.
  ///
  /// In en, this message translates to:
  /// **'Image is locked; cannot delete'**
  String get selImageLocked;

  /// No description provided for @selDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'Delete selected content'**
  String get selDeleteContent;

  /// No description provided for @selNObjects.
  ///
  /// In en, this message translates to:
  /// **'{count} objects selected'**
  String selNObjects(int count);

  /// No description provided for @selShapeLockedEdit.
  ///
  /// In en, this message translates to:
  /// **'Shape locked: unlock to edit'**
  String get selShapeLockedEdit;

  /// No description provided for @selShapeSelected.
  ///
  /// In en, this message translates to:
  /// **'Shape selected: drag, scale, lock or delete'**
  String get selShapeSelected;

  /// No description provided for @selImageLockedEdit.
  ///
  /// In en, this message translates to:
  /// **'Image locked: unlock to edit'**
  String get selImageLockedEdit;

  /// No description provided for @selImageSelected.
  ///
  /// In en, this message translates to:
  /// **'Image selected: drag, scale, lock or delete'**
  String get selImageSelected;

  /// No description provided for @selNStrokes.
  ///
  /// In en, this message translates to:
  /// **'{count} strokes selected'**
  String selNStrokes(int count);

  /// No description provided for @selClear.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get selClear;

  /// No description provided for @shapeLibNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching shapes'**
  String get shapeLibNoMatch;

  /// No description provided for @noteImageSemantic.
  ///
  /// In en, this message translates to:
  /// **'Note image'**
  String get noteImageSemantic;

  /// No description provided for @segmentEndpointSemantic.
  ///
  /// In en, this message translates to:
  /// **'Adjust segment endpoint'**
  String get segmentEndpointSemantic;

  /// No description provided for @saveStateSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saveStateSaving;

  /// No description provided for @saveStateSavedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved {time}'**
  String saveStateSavedAt(String time);

  /// No description provided for @actInsertedShape.
  ///
  /// In en, this message translates to:
  /// **'Inserted “{name}”'**
  String actInsertedShape(String name);
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

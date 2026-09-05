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

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '绘图笔记';

  @override
  String get search => '搜索';

  @override
  String get trash => '回收站（30 天内可恢复）';

  @override
  String get close => '关闭';

  @override
  String get delete => '删除';

  @override
  String get homeTrashEmpty => '回收站为空';

  @override
  String homeDeletedAt(String time) {
    return '删除于 $time';
  }

  @override
  String get homeRecover => '恢复';

  @override
  String get homeDeleteForever => '永久删除';

  @override
  String get homeEmptyTrash => '清空回收站';

  @override
  String get homeCancel => '取消';

  @override
  String get editorUndo => '撤销';

  @override
  String get editorRedo => '重做';

  @override
  String get editorShortcutsHelp => '快捷键帮助';

  @override
  String get editorMenu => '主菜单';

  @override
  String get editorClearCanvas => '清空画布';

  @override
  String get editorCopyPng => '复制 PNG 到剪贴板';

  @override
  String get editorExportPng => '导出 PNG';

  @override
  String get editorExportSvg => '导出 SVG';

  @override
  String get editorShapeTool => '形状工具';

  @override
  String get noteActions => '分页画布操作';

  @override
  String get noteImportPage => '从其他分页画布引入页面';

  @override
  String get noteImportMarkdown => '导入 Markdown 或文本';

  @override
  String get noteImportPdf => '导入 PDF 并逐页批注';

  @override
  String get noteTidyPages => '批量整理页面';

  @override
  String get noteFilterHint => '筛选标签或关键词';

  @override
  String get searchTitle => '全文搜索';

  @override
  String get searchHint => '搜索文字块内容 / 标题…';

  @override
  String get searchEmptyHint => '输入关键词开始搜索';

  @override
  String get searchNoResults => '未找到匹配内容';

  @override
  String get editorStrokeColor => '笔触颜色';

  @override
  String get editorEraseStroke => '命中笔画即删除整条线';

  @override
  String get editorEraseTransparent => '以透明像素挖空当前图层';

  @override
  String get editorHighlightNormal => '作为普通高亮笔写入页面，可撤销、保存和导出';

  @override
  String get editorLaserTemporary => '仅短暂显示，约 4 秒后平滑淡出，不写入页面';

  @override
  String get editorTextColor => '文字颜色';

  @override
  String get editorBold => '加粗 (Ctrl+B)';

  @override
  String get editorItalic => '斜体 (Ctrl+I)';

  @override
  String get editorExportPdf => '导出 PDF';

  @override
  String get editorExportJson => '导出 JSON';

  @override
  String get editorExportPptx => '导出 PPTX';

  @override
  String get editorExportWord => '导出 Word 兼容文档';

  @override
  String get editorUnderline => '下划线 (Ctrl+U)';

  @override
  String get editorPasteValues => '粘贴数值，用逗号/空格/换行分隔，例如：10, 25, 18, 42, 30';

  @override
  String editorImageInsertFail(String error) {
    return '插入图片失败：$error';
  }

  @override
  String get alignLeft => '左对齐';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '右对齐';

  @override
  String editorAlignTooltip(String name) {
    return '对齐：$name (Ctrl+E)';
  }

  @override
  String editorPagePreviewTitle(String title) {
    return '分页预览 $title';
  }

  @override
  String get cancel => '取消';

  @override
  String get nextStep => '下一步';

  @override
  String get gotIt => '知道了';

  @override
  String get create => '创建';

  @override
  String get lockTitle => '应用锁';

  @override
  String get lockDescription => '开启后，打开应用需要输入密码才能进入；切后台超过宽限期回来同样需要。';

  @override
  String get lockOn => '已开启';

  @override
  String get lockOff => '未开启';

  @override
  String get lockChangePassword => '修改密码';

  @override
  String get lockResetDisk => '重置密码盘';

  @override
  String get lockDiskStatusUnknown => '状态未知（保险库读取失败）';

  @override
  String get lockDiskBound => '已绑定（忘记密码时可用它重置）';

  @override
  String get lockDiskUnbound => '未绑定（忘记密码将无法找回）';

  @override
  String get lockDiskUnbind => '解除绑定';

  @override
  String get lockDiskBind => '绑定';

  @override
  String get lockVerifyCurrentPassword => '验证当前密码';

  @override
  String get lockVaultUnlockFailed => '保险库解锁失败，请重试';

  @override
  String get lockBindFailed => '绑定失败，请重试';

  @override
  String get lockBindSuccess =>
      '已绑定。请妥善保管 U 盘：U 盘丢失将无法重置密码，U 盘上的 password_reset_disk.key 文件请勿删除';

  @override
  String get lockUnbindTitle => '解除重置密码盘';

  @override
  String get lockUnbindContent =>
      '解除后，忘记密码将无法重置。\n\nU 盘上的 password_reset_disk.key 文件不会被删除，请自行删除。';

  @override
  String get lockUnbindFailed => '解除失败，请重试';

  @override
  String get lockUnbound => '已解除绑定';

  @override
  String get lockSetPassword => '设置密码';

  @override
  String get lockConfirmPassword => '确认密码';

  @override
  String get lockMismatch => '两次输入不一致，请重新设置';

  @override
  String get lockVaultSyncFailed => '文件加密同步失败，请重试或联系开发者';

  @override
  String get lockEnabled => '应用锁已开启';

  @override
  String get lockDisabled => '应用锁已关闭';

  @override
  String get lockCannotDisableTitle => '无法关闭应用锁';

  @override
  String get lockCannotDisableContent =>
      '你的文件已使用开屏密码加密保护，关闭应用锁会导致加密文件无法解锁读取。\n\n如需更换密码，请使用「修改密码」。';

  @override
  String get lockPinLengthTitle => '密码长度';

  @override
  String lockPinLengthDigits(int count) {
    return '$count 位';
  }

  @override
  String get lockPinLengthHint => '建议 6 位以上，纯数字密码强度有限。';

  @override
  String get lockGraceTitle => '切后台宽限期';

  @override
  String get lockGraceHint => '离开应用后在宽限期内回来，无需重新输入密码。宽限期只免锁屏，加密文件与笔记的密码仍会重新要求。';

  @override
  String get lockGraceOff => '关闭（切后台立即锁定）';

  @override
  String get lockGrace30s => '30 秒';

  @override
  String get lockGrace1min => '1 分钟';

  @override
  String get lockGrace5min => '5 分钟';

  @override
  String lockGraceCurrent(String option) {
    return '当前：$option';
  }

  @override
  String get lockQuickUnlock => '系统验证快速解锁';

  @override
  String get lockQuickUnlockOn => '已开启（锁屏可用 Windows Hello 解锁开屏）';

  @override
  String get lockQuickUnlockOff => '未开启（开启后锁屏可用人脸/指纹/PIN 解锁开屏）';

  @override
  String get lockQuickEnableFailed => '开启失败，请重试';

  @override
  String get lockQuickEnableDone => '已开启：锁屏可用系统验证（人脸/指纹/PIN）快速解锁';

  @override
  String get lockQuickDisableDone => '已关闭，系统安全区中的密钥副本已删除';

  @override
  String get lockBindHintBound => '绑定重置密码盘后，忘记密码可用它重置；未绑定时忘记密码将无法找回。';

  @override
  String get lockBindHintUnbound => '开启应用锁后，可绑定重置密码盘以防忘记密码。';

  @override
  String get docShareComingSoon => '分享功能即将支持';

  @override
  String get docSaveFailed => '保存失败，请重试或手动保存';

  @override
  String docExportedTo(String label, String path) {
    return '已导出 $label：$path';
  }

  @override
  String get docExportFailed => '导出失败，请重试';

  @override
  String docPolicyDenied(String operation) {
    return '操作被策略拒绝（$operation）';
  }

  @override
  String get docInsertPageLink => '插入页面链接';

  @override
  String docStandalonePasswordTitle(String name) {
    return '「$name」独立密码';
  }

  @override
  String get docSetStandalonePassword => '设置独立密码';

  @override
  String get docSetStandalonePasswordHint => '4–12 位数字，须与开屏密码不同';

  @override
  String get docChangeStandalonePassword => '修改独立密码';

  @override
  String get docBindResetDisk => '绑定重置密码盘';

  @override
  String get docBindResetDiskHint => '绑定后忘记密码可插 U 盘免旧密码重置';

  @override
  String get docRemoveStandalonePassword => '移除独立密码';

  @override
  String get docTags => '标签';

  @override
  String get docNewTag => '新建标签';

  @override
  String get shellAllDocs => '全部文档';

  @override
  String get shellCanvasNotes => '画布·笔记';

  @override
  String get shellSchedule => '日历';

  @override
  String get shellSettings => '设置';

  @override
  String get shellEditorNotAssembled => '编辑器尚未由应用层装配';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppLock => '应用锁';

  @override
  String get settingsAppLockHint => '开屏密码 · 重置密码盘';

  @override
  String get settingsStandalonePassword => '单文件密码';

  @override
  String get settingsStandalonePasswordHint => '个别画布的第二道锁（在画布卡片设置）';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsHighContrast => '高对比度';

  @override
  String get settingsWebdav => 'WebDAV 同步';

  @override
  String get settingsWebdavHint => '本地优先，跨设备同步';

  @override
  String get settingsPasswordSystem => '密码体系';

  @override
  String get docsSort => '排序';

  @override
  String get docsSortGroupTime => '按时间分组';

  @override
  String get docsSortUpdated => '按更新时间';

  @override
  String get docsSortCreated => '按创建时间';

  @override
  String get docsSortTitle => '按标题';

  @override
  String get docsNewDoc => '新建文档';

  @override
  String get docsNewNote => '新建笔记';

  @override
  String get docsNewPagedCanvas => '新建分页画布';

  @override
  String get docsNewCanvas => '新建画布';

  @override
  String get settingsSectionSecurity => '密码与安全';

  @override
  String get settingsSectionGeneral => '通用';

  @override
  String get settingsFilePasswordHelpContent =>
      '在首页或全部文档页，点击画布卡片上的锁形按钮，可为单个画布设置独立密码。设置后打开该画布需要输入此密码，缩略图也会隐藏为锁形占位。\n\n单文件密码独立于开屏密码——即使有人解锁了你的应用，没有这个密码也打不开对应的画布。';

  @override
  String get settingsThemeSystem => '跟随系统（点击切换为浅色）';

  @override
  String get settingsThemeLight => '浅色（点击切换为深色）';

  @override
  String get settingsThemeDark => '深色（点击切换为跟随系统）';

  @override
  String get settingsLayer1Title => '第 1 层 · 开屏密码';

  @override
  String get settingsLayer1Desc => '解锁应用，同时解开主密钥保险库——保护全部画布与笔记。忘记时可用重置密码盘重设。';

  @override
  String get settingsLayer2Title => '第 2 层 · 文件密码';

  @override
  String get settingsLayer2Desc => '给单个画布/分页画布/笔记另设的独立密码，独立于开屏密码。忘记时可用重置密码盘重设。';

  @override
  String get settingsLayer3Title => '重置密码盘（U 盘）';

  @override
  String get settingsLayer3Desc => '插入 U 盘 → 点「忘记密码」→ 重置新密码。开屏密码与文件密码通用同一把盘。';

  @override
  String get docUnsaved => '未保存';

  @override
  String get docSaving => '保存中…';

  @override
  String get docSaved => '已保存';

  @override
  String docSavedAt(String time) {
    return '已保存 $time';
  }

  @override
  String get docUntitled => '未命名';

  @override
  String get docStandalonePasswordProtected => '此笔记受独立密码保护';

  @override
  String get docStandalonePasswordUnset => '此笔记当前未设置独立密码';

  @override
  String get docCreatedAt => '创建于';

  @override
  String get docUpdatedAt => '更新于';

  @override
  String get docBlockCount => '块数量';

  @override
  String get docTagNameHint => '标签名称';

  @override
  String get docPinSameAsLock => '独立密码不能与开屏密码相同';

  @override
  String get docConfirmStandalonePassword => '确认独立密码';

  @override
  String get docPinMismatch => '两次输入不一致，请重试';

  @override
  String get docSetNewPassword => '设置新密码';

  @override
  String docPasswordSetFor(String name) {
    return '已为「$name」设置独立密码';
  }

  @override
  String get docPasswordSetDiskBound => '已设置独立密码并绑定重置密码盘';

  @override
  String get docSetFailed => '设置失败，请重试';

  @override
  String get docVerifyCurrent => '验证当前独立密码';

  @override
  String docPasswordChangedFor(String name) {
    return '已修改「$name」的独立密码';
  }

  @override
  String get docWrongPassword => '原密码不正确或密文已损坏';

  @override
  String get docChangeFailed => '修改失败，请重试';

  @override
  String get docBindDiskConfirmTitle => '绑定重置密码盘？';

  @override
  String get docBindDiskConfirmContent =>
      '绑定后忘记此笔记的独立密码时，可插入重置密码盘（U 盘）免旧密码重置。\n\nU 盘上只有随机钥匙文件（password_reset_disk.key），笔记数据不会离开设备。';

  @override
  String get docBindDiskConfirm => '插盘绑定';

  @override
  String get docNotNow => '暂不';

  @override
  String get docDiskNotFoundNoBind =>
      '未找到有效的重置密码盘文件（password_reset_disk.key），本次不绑定';

  @override
  String get docDiskNotFound => '未找到有效的重置密码盘文件（password_reset_disk.key）';

  @override
  String get docVerifyToBind => '验证独立密码以绑定重置盘';

  @override
  String get docDiskBound => '已绑定重置密码盘';

  @override
  String get docWrongOrAlreadyBound => '密码不正确或已绑定重置密码盘';

  @override
  String get docBindFailed => '绑定失败，请重试';

  @override
  String docRemoveConfirmContent(String name) {
    return '移除后「$name」不再需要独立密码即可打开。确定移除吗？';
  }

  @override
  String get docRemove => '移除';

  @override
  String get docVerifyToRemove => '验证独立密码以移除';

  @override
  String docPasswordRemovedFor(String name) {
    return '已移除「$name」的独立密码';
  }

  @override
  String get docPasswordWrongOrCorrupt => '密码不正确或密文已损坏';

  @override
  String get docRemoveFailed => '移除失败，请重试';

  @override
  String get docUnlockTitle => '该笔记已加密，输入密码';

  @override
  String get docForgotPassword => '忘记密码？';

  @override
  String get docsTabDocs => '文档';

  @override
  String get docsTabFavorites => '收藏夹';

  @override
  String get docsEmptyNoMatch => '没有匹配的文档';

  @override
  String get docsEmptyNoMatchTip => '试试其他关键词或排序方式';

  @override
  String get docsEmptyNoFavorites => '暂无收藏文档';

  @override
  String get docsEmptyNoFavoritesTip => '点击文档行星标可添加到收藏夹';

  @override
  String get docsEmptyFirstNote => '记下第一笔';

  @override
  String get docsEmptyFirstNoteTip => '笔记用来打字，画布用来写写画画';

  @override
  String get docsLoadFailedRetry => '加载失败，请下拉刷新重试';

  @override
  String get docsQuickSearch => '快速搜索';

  @override
  String get docsClearSearch => '清除搜索';

  @override
  String get docsRecent => '最近文档';

  @override
  String get docsNoDocs => '暂无文档';

  @override
  String get docsMore => '更多';

  @override
  String get docsTrashTab => '回收站';

  @override
  String get docsTree => '文档树';

  @override
  String get docsFavorite => '添加收藏';

  @override
  String get docsUnfavorite => '取消收藏';

  @override
  String get docsMoreActions => '更多操作';

  @override
  String get docsGroupToday => '今天';

  @override
  String get docsGroupThisWeek => '本周';

  @override
  String get docsGroupEarlier => '更早';

  @override
  String get docsGroupNeverUpdated => '从未更新';

  @override
  String get open => '打开';

  @override
  String get timeYesterday => '昨天';

  @override
  String timeMonthDay(int month, int day) {
    return '$month 月 $day 日';
  }

  @override
  String get tagsEmpty => '暂无标签';

  @override
  String get tagsEmptyTip => '打开笔记 → 文档信息 → 添加标签';

  @override
  String get tagsAll => '全部标签';

  @override
  String get tagsNoDocs => '该标签下暂无笔记';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonPassword => '密码';

  @override
  String get unlockEnterPassword => '输入密码';

  @override
  String get unlockEmergency => '紧急情况';

  @override
  String get unlockBarrier => '密码锁';

  @override
  String get unlockPasswordWrong => '密码不正确';

  @override
  String get unlock => '解锁';

  @override
  String get shellUnlockNoteTitle => '该笔记已加密，输入密码';

  @override
  String get shellUnlockCanvasTitle => '该画布已加密，输入独立密码';

  @override
  String get shellUnlockNotebookTitle => '该分页画布已加密，输入密码';

  @override
  String get resetThisNote => '该笔记';

  @override
  String get resetThisCanvas => '该画布';

  @override
  String get resetThisNotebook => '该分页画布';

  @override
  String resetDocNameQuote(String name) {
    return '「$name」';
  }

  @override
  String get resetForgotFilePassword => '忘记文件密码';

  @override
  String get resetForgotPassword => '忘记密码';

  @override
  String get resetImpossible => '无法重置';

  @override
  String get resetStandalonePassword => '独立密码';

  @override
  String get resetFailed => '重置失败';

  @override
  String get resetDiskMismatchOrCorrupt => '重置密码盘不匹配或已损坏。';

  @override
  String resetDoneStandalone(String name) {
    return '已用重置密码盘重置$name的独立密码';
  }

  @override
  String resetDonePassword(String name) {
    return '已用重置密码盘重置$name的密码';
  }

  @override
  String get resetUseDisk => '使用重置密码盘';

  @override
  String get resetNoValidKey => '未找到有效钥匙';

  @override
  String get resetSetNewFilePassword => '设置新文件密码';

  @override
  String resetSameAsLockScreen(String label) {
    return '$label不能与开屏密码相同';
  }

  @override
  String get resetConfirmNewFilePassword => '确认新文件密码';

  @override
  String get resetMismatchRetry => '两次输入不一致，请重试';

  @override
  String get colorPickerTitle => '选择颜色';

  @override
  String pinDigitsCount(int entered, int min, int max) {
    return '$entered / $max 位（$min–$max 位可选）';
  }

  @override
  String get lockButtonLock => '锁定';

  @override
  String get lockButtonUnlock => '解锁';

  @override
  String get shellWorkspaceName => '画记';

  @override
  String resetIntroNote(String name) {
    return '使用重置密码盘（U 盘）重置$name的独立密码。\n\n前提：该笔记已绑定重置密码盘（设置密码或密码管理中绑定）。';
  }

  @override
  String resetIntroCanvas(String name) {
    return '使用重置密码盘（U 盘）重置$name的独立密码。\n\n前提：该画布已绑定重置密码盘（设置密码或密码管理中绑定）。';
  }

  @override
  String resetIntroNotebook(String name) {
    return '使用重置密码盘（U 盘）重置$name的密码。\n\n前提：该分页画布已绑定重置密码盘（设置密码或密码管理中绑定）。';
  }

  @override
  String resetNotBoundNote(String name) {
    return '$name未绑定重置密码盘（U 盘），无法通过重置盘重置密码。\n\n可在密码管理中选择「绑定重置密码盘」。';
  }

  @override
  String resetNotBoundCanvas(String name) {
    return '$name未绑定重置密码盘（U 盘），无法通过重置盘重置密码。\n\n可在密码管理中选择「绑定重置密码盘」；旧版本（v1.5.x）设置的密码文件需先修改一次密码升级格式。';
  }

  @override
  String resetNotBoundNotebook(String name) {
    return '$name未绑定重置密码盘（U 盘），无法通过重置盘重置密码。\n\n可在「设置/修改密码保护」后于菜单中选择「绑定重置密码盘」；旧版本设置的密码需先修改一次密码升级格式。';
  }

  @override
  String get resetNoValidKeyBody =>
      '所选位置未找到有效的重置密码盘文件（password_reset_disk.key）。';

  @override
  String get homeReadListFailed => '读取列表失败，请重试';

  @override
  String get homeNewInfiniteCanvas => '新建无限画布';

  @override
  String get homeNewInfiniteCanvasSub => '自由绘制、图形与关系图';

  @override
  String get homeNewPagedCanvasSub => '多页装订、纸张模板与图文混排';

  @override
  String get homeCreateFailedFull => '新建失败：笔记本未能保存，请检查磁盘空间后重试';

  @override
  String get homeCanvasMissing => '画布文件不存在或已损坏';

  @override
  String get homeOpenCanvasFailed => '打开画布失败，请重试';

  @override
  String get canvasStandalonePasswordProtected => '此画布受独立密码保护';

  @override
  String get canvasStandalonePasswordUnset => '此画布当前未设置独立密码';

  @override
  String get canvasVaultLockedSet => '加密底座已锁定：请重新验证开屏密码后再设置';

  @override
  String get canvasVaultLockedRemove => '加密底座已锁定，无法回封：请重新验证开屏密码后再试';

  @override
  String canvasPasswordSetDiskBoundFor(String name) {
    return '已为「$name」设置独立密码并绑定重置密码盘';
  }

  @override
  String get homeDeleteCanvasTitle => '删除画布';

  @override
  String homeDeleteCanvasConfirm(String name) {
    return '确定删除画布「$name」吗？此操作不可恢复。';
  }

  @override
  String get homeDeleteFailed => '删除失败，请重试';

  @override
  String get homeSelectTemplate => '选择笔记模板';

  @override
  String get homeCreateFailed => '创建失败，请重试';

  @override
  String get homeTrashLoadFailed => '回收站加载失败，请重试';

  @override
  String homeRecovered(String id) {
    return '已恢复「$id」';
  }

  @override
  String get homeRetry => '重试';

  @override
  String get homeNoCanvas => '还没有画布';

  @override
  String get homeNoNotes => '还没有笔记';

  @override
  String get homeEmptyTip => '点击右下角按钮新建一个吧';

  @override
  String get homeInfiniteCanvas => '无限画布';

  @override
  String get homePagedCanvas => '分页画布';

  @override
  String get homeDeleteNote => '删除笔记';

  @override
  String get homeStandalonePassword => '独立密码';

  @override
  String get homeDeleteInfiniteCanvas => '删除无限画布';

  @override
  String get homeNameHint => '请输入名称';

  @override
  String get nbSessionLocked => '会话已锁定，请重新解锁';

  @override
  String get nbSessionExpired => '会话已过期，请重新打开该分页画布';

  @override
  String get nbSessionRestored => '会话已恢复';

  @override
  String get nbSaveFailed => '保存失败，请重试';

  @override
  String get nbReaderMode => '翻页阅读';

  @override
  String get nbNewPage => '新建页面';

  @override
  String get nbRenameNotebook => '重命名分页画布';

  @override
  String get nbOpenAsBlockDoc => '以块文档打开';

  @override
  String get nbNoPages => '这个分页画布还没有页面';

  @override
  String get nbNoPagesNew => '这个分页画布还没有页面，先新建一页吧';

  @override
  String get nbUntitledPage => '未命名页面';

  @override
  String get nbNoteEncryptedLocked => '该笔记已加密且会话已锁定，请重新解锁后再打开';

  @override
  String get nbPickPageAsBlock => '选择要以块文档打开的页面';

  @override
  String get nbNoOtherNotebook => '暂没有其他分页画布可引入';

  @override
  String get nbPickSourceNotebook => '选择源分页画布';

  @override
  String get nbPickImportPages => '选择要引入的页面';

  @override
  String get nbExportPdfFailed => '导出整本 PDF 失败，请重试';

  @override
  String get nbDeletePage => '删除页面';

  @override
  String get nbUndo => '撤销';

  @override
  String get nbUndoSaveFailed => '撤销保存失败，请重试';

  @override
  String get nbPageRef => '🔗 引用';

  @override
  String get nbUnfavoritePage => '取消收藏';

  @override
  String get nbFavoritePage => '收藏页面';

  @override
  String get nbVersionHistory => '版本历史';

  @override
  String nbVersionHistoryOf(String name) {
    return '「$name」版本历史';
  }

  @override
  String get nbPageNameLabel => '页面名称';

  @override
  String get nbChooseTemplate => '选择模板';

  @override
  String get nbCreateAndRecord => '创建并开始记录';

  @override
  String get nbPageNameHint => '请输入页面名称';

  @override
  String get nbPasswordHint => '请输入密码';

  @override
  String get nbShowPassword => '显示密码';

  @override
  String get nbHidePassword => '隐藏密码';

  @override
  String get impMarkdownText => 'Markdown / 文本';

  @override
  String get impTextTooLarge => '文本文件过大（超过 20MB 限制），拒绝导入';

  @override
  String get impEmptyFile => '文件内容为空';

  @override
  String get impNoText => '未解析到文本内容';

  @override
  String impImportedParagraphs(int count) {
    return '已导入 $count 段文字';
  }

  @override
  String get impFailed => '导入失败，请重试';

  @override
  String get impPdfTypeGroup => 'PDF 文档';

  @override
  String get impPdfNoPages => 'PDF 没有可导入的页面';

  @override
  String impPdfPageTitle(String name, int page) {
    return '$name · 第 $page 页';
  }

  @override
  String impPdfDone(int count) {
    return '已导入 PDF 共 $count 页；打开任一页面即可手写批注';
  }

  @override
  String get impPdfFailed => '导入 PDF 失败，请重试';

  @override
  String get impChangePasswordProtect => '修改密码保护';

  @override
  String get impSetPasswordProtect => '设置密码保护';

  @override
  String get impChangeHint => '修改后打开需输入新密码';

  @override
  String get impSetHint => '设置后页面内容将加密存储，打开需输入密码';

  @override
  String get impPasswordSameAsLock => '密码不能与开屏密码相同';

  @override
  String get impRelockNeeded => '请重新输入密码解锁后再修改';

  @override
  String get impPasswordChanged => '密码已修改';

  @override
  String get impPasswordEnabled => '已启用密码保护（页面内容加密存储）';

  @override
  String get impChangeFailed => '修改密码失败，请重试';

  @override
  String get impSetFailed => '设置密码失败，请重试';

  @override
  String get impBound => '已绑定重置密码盘';

  @override
  String get impBindFailed2 => '绑定失败，请重试';

  @override
  String get impUnlockFirst => '请先输入密码解锁后再绑定';

  @override
  String get impNoVersions => '该页面暂无历史版本';

  @override
  String get impRestore => '恢复';

  @override
  String get syncFailedUnknown => '同步失败：未知错误';

  @override
  String get syncFailedRemoteFile => '同步失败：同步远端文件失败，请检查服务器';

  @override
  String syncFailedHttpUnavailable(int code) {
    return '同步失败：服务器暂时不可用（HTTP $code），请稍后再试';
  }

  @override
  String get syncFailedDirMissing => '同步失败：服务器目录不存在或路径被占用，请检查远端目录设置';

  @override
  String get syncFailedHttps => '同步失败：安全连接（HTTPS）握手失败，请检查服务器证书';

  @override
  String get syncFailedConnect => '同步失败：连不上服务器，请检查网络或服务器地址';

  @override
  String get syncFailedGeneric => '同步失败：请检查网络与账号设置后重试';

  @override
  String get syncMissingSalt => '同步配置缺少加密盐：请重新点击「保存配置」后再同步';

  @override
  String get syncMaxRetries => '达到最大重试次数';

  @override
  String get syncUpToDate => '已是最新，无需同步';

  @override
  String syncWithConflicts(String base, int count) {
    return '$base；另有 $count 个文档本地与云端均有改动，已按你的选择处理';
  }

  @override
  String get webdavTitle => 'WebDAV 同步';

  @override
  String get webdavUsername => '用户名';

  @override
  String get webdavSyncNow => '立即同步';

  @override
  String get webdavSave => '保存配置';

  @override
  String get cmdNewSticky => '新建便签';

  @override
  String get cmdGroupEdit => '编辑';

  @override
  String get cmdCancelConnect => '取消连线';

  @override
  String get cmdConnectMode => '连线模式';

  @override
  String get cmdGroupSelected => '编组所选';

  @override
  String get cmdNeedTwoFrames => '需 ≥2 帧';

  @override
  String get cmdFitContent => '适应内容';

  @override
  String get cmdGroupView => '视图';

  @override
  String get cmdFitSelected => '适应所选';

  @override
  String get cmdZoomIn => '放大';

  @override
  String get cmdZoomOut => '缩小';

  @override
  String get cmdExitMulti => '退出多选';

  @override
  String get cmdEnterMulti => '进入多选';

  @override
  String get cmdGroupSelect => '选择';

  @override
  String get cmdClearSelection => '清空所选';

  @override
  String get cmdFocusSelected => '聚焦所选';

  @override
  String get cmdGroupJump => '跳转';

  @override
  String get cmdNoMatch => '没有匹配的命令';

  @override
  String get edPickSourceFrame => '请先选中一个帧作为连线起点';

  @override
  String get edNewFrame => '新增帧';

  @override
  String get edFit => '适应';

  @override
  String get edMultiSelect => '多选(编组)';

  @override
  String get edGroup => '编组';

  @override
  String get edStickyTitle => '便签';

  @override
  String get edFrameColor => '帧背景色';

  @override
  String get edConnect => '连线';

  @override
  String get edEditContent => '编辑内容';

  @override
  String get edDeleteFrame => '删除帧';

  @override
  String get edSelect => '选择';

  @override
  String get edSticky => '便签';

  @override
  String get edBrush => '画笔';

  @override
  String get edEraser => '橡皮';

  @override
  String get edShape => '形状';

  @override
  String get edRect => '矩形';

  @override
  String get edOval => '椭圆';

  @override
  String get pfCode => '代码块';

  @override
  String get pfImage => '图片';

  @override
  String get pfLink => '链接';

  @override
  String get pfCanvas => '画布';

  @override
  String get pfChart => '图表';

  @override
  String get pfTable => '表格';

  @override
  String get pfDatabase => '数据库';

  @override
  String get pfAttachment => '附件';

  @override
  String readerTitle(String name) {
    return '$name · 翻页阅读';
  }

  @override
  String readerPageIndicator(int index, int total) {
    return '第 $index 页 / 共 $total 页';
  }

  @override
  String get notesWritingTitle => '笔记';

  @override
  String get notesRecent => '最近';

  @override
  String get obWelcome => '欢迎使用绘图笔记';

  @override
  String get obBrushTip => '画笔 / 橡皮擦 / 吸管：顶部工具条切换，拖动鼠标或手指绘画';

  @override
  String get obColorTip => '颜色与粗细：工具条右侧圆形色块与粗细滑块';

  @override
  String get obLayerTip => '图层面板在右侧：新建、显隐、透明度、顺序、合并';

  @override
  String get obSelectTip => '选区工具：框选后可移动 / 缩放 / 旋转 / 复制 / 删除';

  @override
  String get obNoteTip => '笔记页支持文字与图片：文字工具点击画布输入，图片按钮插入';

  @override
  String get obFullscreenTip => '右上角全屏按钮：隐藏工具栏只看画布';

  @override
  String get obStart => '开始使用';

  @override
  String get presNoContent => '没有可演示的内容';

  @override
  String presIndicator(int index, int total) {
    return '$index / $total · 点击或 → 下一页，Esc 退出';
  }

  @override
  String get presExit => '退出演示';

  @override
  String get pdfPreviewUnavailable => 'PDF 内嵌预览不可用';

  @override
  String get conflictApplyAll => '应用全部';

  @override
  String get conflictKeepLocal => '保留本地';

  @override
  String get conflictKeepCloud => '保留云端';

  @override
  String get conflictKeepBoth => '两者皆留';

  @override
  String get searchKindNotebook => '分页画布';

  @override
  String get searchKindPageTitle => '页面标题';

  @override
  String get searchKindCanvas => '画布';

  @override
  String get searchKindBlockDoc => '块文档';

  @override
  String get searchKindDocTitle => '文档标题';

  @override
  String get templateBlank => '空白笔记';

  @override
  String get templateLined => '横线笔记';

  @override
  String get templateGrid => '方格纸';

  @override
  String get templateDot => '点阵笔记';

  @override
  String get templateMeeting => '会议记录';

  @override
  String get templateCornell => '康奈尔笔记';

  @override
  String get templatePlanner => '计划页';

  @override
  String get templateWhiteboard => '宽阔白板';

  @override
  String get rootRefusedTitle => '无法在此设备上启动';

  @override
  String get rootRefusedBody => '检测到设备已获取 ROOT 权限。为保护你的加密笔记数据，本应用在已破解设备上拒绝运行。';

  @override
  String get canvasBindConfirmContent =>
      '绑定后忘记此画布的独立密码时，可插入重置密码盘（U 盘）免旧密码重置。\n\nU 盘上只有随机钥匙文件（password_reset_disk.key），画布数据不会离开设备。';

  @override
  String canvasRemoveConfirmContent(String name) {
    return '移除后「$name」将回到加密底座保护（主密钥信封），不再需要独立密码。确定移除吗？';
  }

  @override
  String canvasBoundDiskFor(String name) {
    return '已为「$name」绑定重置密码盘';
  }

  @override
  String homeDeleteForeverConfirm(String name) {
    return '确定永久删除「$name」吗？此操作不可恢复。';
  }

  @override
  String get homeRestoreFailed => '恢复失败，请重试';

  @override
  String get homeTabCanvas => '画布';

  @override
  String get homeTabNotes => '笔记';

  @override
  String get canvasDeletePasswordTitle => '该画布已加密，输入独立密码';

  @override
  String get homeKindNote => '笔记';

  @override
  String get homeKindNotebookPage => '分页画布页面';

  @override
  String homeUpdatedAt(String time) {
    return '更新于 $time';
  }

  @override
  String homeDeleteNoteConfirm(Object name) {
    return '确定删除笔记「$name」吗？此操作不可恢复。';
  }

  @override
  String get homeUntitledNotebookPage => '未命名';

  @override
  String get homeStandalonePasswordMenu => '独立密码…';

  @override
  String get nbEmptyTip => '点击右上角新建';

  @override
  String get nbNoTagMatch => '没有匹配该标签的页面';

  @override
  String get nbNoTagMatchTip => '试试选择其他标签';

  @override
  String get impBindAskContent =>
      '绑定后忘记密码时，插入 U 盘即可重置新密码。\n\n可以稍后在菜单「绑定重置密码盘」中补绑。';

  @override
  String get impRestoreConfirmTitle => '恢复该版本？';

  @override
  String get impRestoreConfirmContent => '将用所选版本覆盖当前页面内容（当前内容会先存入历史）。';

  @override
  String get nbPageNameExampleHint => '例如：产品评审 08-14';

  @override
  String nbDeletePageConfirm(String name) {
    return '确定删除页面「$name」吗？其中的手写与文字内容将一并删除。';
  }

  @override
  String nbPageDeleted(String name) {
    return '已删除「$name」';
  }

  @override
  String nbExportedPdf(int count, String path) {
    return '已导出整本 $count 页 PDF：$path';
  }

  @override
  String cmdGotoFrame(String name) {
    return '跳转到「$name」';
  }

  @override
  String get obPinchTip => '双指捏合缩放画布、双指旋转画布（触屏设备）';

  @override
  String get obAutosaveTip => '内容自动保存，无需手动保存；可随时导出为 PNG';

  @override
  String get syncFailedAuth => '同步失败：用户名或密码不对（服务器拒绝登录）';

  @override
  String syncFailedRejected(String code) {
    return '同步失败：服务器拒绝了这次请求（HTTP $code）';
  }

  @override
  String get syncHttpUnknown => '未知';

  @override
  String syncDoneSummary(int up, int down, int del) {
    return '同步完成：↑$up ↓$down ✕$del';
  }

  @override
  String get webdavFormDirty => '表单有未保存的修改：请先点击「保存配置」再同步（避免加密密钥与云端数据错配）';

  @override
  String get webdavSyncSecretLabel => '同步密码（必填，用于端到端加密）';

  @override
  String get webdavSyncSecretHelper => '未设置同步密码时同步会被阻止（防止笔记明文上云）';

  @override
  String get webdavSyncing => '同步中…';

  @override
  String get tplDescMeeting => '包含议题、决策和行动项的起始结构。';

  @override
  String get tplDescCornell => '包含线索、笔记和总结区域的起始结构。';

  @override
  String get tplDescPlanner => '包含重点、日程与复盘的起始结构。';

  @override
  String get tplDescWhiteboard => '使用宽阔空白画布模式；当前版本仍采用固定坐标纸面。';

  @override
  String get tplDescDefault => '纸张背景会随模板设置并保存到页面。';

  @override
  String get homeDeleteForeverFailed => '永久删除失败，请重试';

  @override
  String get impDiskNotFound => '未找到有效的重置密码盘文件（password_reset_disk.key）';

  @override
  String get lockDiskKeepNote => 'U 盘上的 password_reset_disk.key 文件请勿删除';

  @override
  String get cmdUndo => '撤销';

  @override
  String get cmdRedo => '重做';

  @override
  String get cmdCopySelection => '复制选中对象';

  @override
  String get cmdPasteClipboard => '从剪贴板粘贴';

  @override
  String get cmdDuplicateSelection => '复制并粘贴选中对象';

  @override
  String get cmdDeleteSelection => '删除选中对象';

  @override
  String get cmdBold => '加粗选中文字';

  @override
  String get cmdItalic => '斜体选中文字';

  @override
  String get cmdUnderline => '下划线选中文字';

  @override
  String get cmdStrikethrough => '删除线选中文字';

  @override
  String get cmdCycleAlign => '循环切换文本对齐';

  @override
  String get cmdFitCanvas => '适应画布';

  @override
  String get cmdToggleGrid => '显示或隐藏网格';

  @override
  String get cmdToggleSnap => '切换网格吸附';

  @override
  String get cmdExportWord => '导出 Word 兼容文档';

  @override
  String get catEdit => '编辑';

  @override
  String get catFormat => '格式';

  @override
  String get catInsert => '插入';

  @override
  String get catArrange => '排列';

  @override
  String get catView => '视图';

  @override
  String get catExport => '导出';

  @override
  String get expCopyRenderFail => '复制失败：无法渲染画布';

  @override
  String get expCopyDecodeFail => '复制失败：像素解码失败';

  @override
  String get expCopiedPng => '已复制 PNG 到剪贴板';

  @override
  String get expRenderFail => '导出失败：无法渲染画布';

  @override
  String get expNoPages => '没有可导出的页面';

  @override
  String get expEmptyCanvas => '导出失败：画布内容为空';

  @override
  String get expWordPagedOnly => '仅分页笔记支持导出 Word 兼容文档';

  @override
  String get expWordNoText => '本页还没有可导出的文字内容';

  @override
  String get expTextPagedOnly => '仅分页画布页面支持导出文本';

  @override
  String get expTextNoText => '本页还没有文字内容';

  @override
  String get expPptxPackFail => '导出失败：PPTX 打包失败';

  @override
  String get fileTypePng => 'PNG 图片';

  @override
  String get fileTypePdf => 'PDF 文档';

  @override
  String get fileTypeSvg => 'SVG 矢量图';

  @override
  String get fileTypeWord => 'Word 兼容文档';

  @override
  String get fileTypeMarkdown => 'Markdown / 文本';

  @override
  String get fileTypePptx => 'PPTX 演示文稿';

  @override
  String get fileTypeJson => 'JSON 工程文件';

  @override
  String get expWholeBookSuffix => '全本';

  @override
  String get pdfPaperFollow => '跟随画布';

  @override
  String get pdfRangeCurrent => '当前页';

  @override
  String get pdfRangeAll => '全部页';

  @override
  String get pdfQualityLossless => '无损';

  @override
  String get pdfQualityLosslessDesc => 'PNG 无损，体积最大';

  @override
  String get pdfQualityStandardDesc => 'JPEG 80，推荐';

  @override
  String get pdfQualitySaverDesc => 'JPEG 60，体积最小';

  @override
  String get pdfGroupPaper => '纸张';

  @override
  String get pdfGroupQuality => '质量';

  @override
  String pdfExportNPages(int count) {
    return '导出 $count 页';
  }

  @override
  String get inkStylusPressure => '触控笔压感';

  @override
  String get inkTouchPressure => '触摸压感';

  @override
  String get inkMouseVelocity => '鼠标速度模拟';

  @override
  String get inkConstant => '固定笔宽';

  @override
  String get pomodoroPause => '暂停';

  @override
  String get pomodoroStart => '开始';

  @override
  String get pomodoroReset => '重置';

  @override
  String get pomodoroFinish => '番茄钟结束：休息一下吧';

  @override
  String pageIndicator(int index, int total) {
    return '第 $index 页 / 共 $total 页';
  }

  @override
  String get eraserWholeStroke => '整笔';

  @override
  String get eraserTransparent => '透明';

  @override
  String get markerSave => '保存';

  @override
  String get markerAutoFade => '自动消失';

  @override
  String get tooltipSwapFill => '切换填充色';

  @override
  String get tooltipDashStyle => '实线 / 虚线';

  @override
  String get hintEyedropper => '点击画布取色';

  @override
  String get hintTextTool => '点击画布放置文字';

  @override
  String get hintConnect => '依次选择两个元素建立连接';

  @override
  String get hintPixelEraser => '透明像素擦除';

  @override
  String get hintStrokeEraser => '整笔删除';

  @override
  String get hintTempHighlight => '临时高亮：约 4 秒后自动消失';

  @override
  String get hintSavedHighlight => '高亮笔：将保存到页面';

  @override
  String get hintLaser => '激光指示器：释放后从起笔端逐段消退，不会保存';

  @override
  String get hintBrush => '画笔';

  @override
  String get toolEyedropper => '吸管工具';

  @override
  String get toolMarquee => '框选多个元素';

  @override
  String get toolNodeLink => '节点连线';

  @override
  String get shapeRect => '矩形';

  @override
  String get shapeEllipse => '椭圆';

  @override
  String get shapeDiamond => '菱形';

  @override
  String get shapeArrow => '箭头';

  @override
  String get shapeLine => '直线';

  @override
  String get saveStateUnsaved => '未保存';

  @override
  String get saveStateSaved => '已保存';

  @override
  String get cropInvalid => '裁剪区域无效';

  @override
  String get cropSourceMissing => '原图文件不存在';

  @override
  String get cropEncodeFail => '裁剪编码失败';

  @override
  String get cropVaultLocked => '保险库已锁定，无法保存裁剪';

  @override
  String get cropDone => '已裁剪图片';

  @override
  String get cropDragHint => '拖动图片四角调整裁剪区域，再点裁剪按钮确认';

  @override
  String get cropHandleTopLeft => '调整裁剪框左上角';

  @override
  String get cropHandleTopRight => '调整裁剪框右上角';

  @override
  String get cropHandleBottomLeft => '调整裁剪框左下角';

  @override
  String get cropHandleBottomRight => '调整裁剪框右下角';

  @override
  String get canvasSemanticsLabel => '绘图画布';

  @override
  String get canvasSemanticsHint => '双击空白处插入文字；使用工具栏工具绘制';

  @override
  String get actSwitchInfinite => '已切换为无限画布（可无限延展）';

  @override
  String get actSwitchFixed => '已切回固定纸张';

  @override
  String get actChartPagedOnly => '仅分页画布页面支持图表';

  @override
  String get actChartTitle => '生成图表';

  @override
  String get actChartBar => '柱状图';

  @override
  String get actChartLine => '折线图';

  @override
  String get actChartGenerate => '生成';

  @override
  String get actChartNoData => '未解析到有效数值';

  @override
  String get actSlidesPagedOnly => '仅分页画布页面支持幻灯片演示';

  @override
  String get actSlidesNoContent => '本页还没有可演示的内容';

  @override
  String get actSlidesUnavailable => '演示功能不可用';

  @override
  String get actStatsTitle => '画布统计';

  @override
  String get actStatStrokes => '手写笔画';

  @override
  String get actStatTextBlocks => '文字块';

  @override
  String get actStatImages => '图片';

  @override
  String get actStatShapes => '形状';

  @override
  String get actStatCharts => '图表';

  @override
  String get actStatTotal => '合计元素';

  @override
  String get actShapeLibPagedOnly => '仅分页画布页面支持形状库';

  @override
  String actCopiedN(int count) {
    return '已复制 $count 个元素';
  }

  @override
  String get actPickFirst => '请先选中要复制的元素';

  @override
  String actPastedN(int count) {
    return '已粘贴 $count 个元素';
  }

  @override
  String get actCopiedTextStyle => '已复制文字样式';

  @override
  String get actCopiedShapeStyle => '已复制形状样式';

  @override
  String get actPickStyleSource => '请先选中文字块或形状';

  @override
  String get actCopyStyleFirst => '请先复制样式（Ctrl+Shift+C）再粘贴';

  @override
  String get actPastedStyle => '已粘贴样式';

  @override
  String get actPastePagedOnly => '仅分页画布页面支持粘贴';

  @override
  String get actClipboardNoText => '剪贴板没有可粘贴的文本';

  @override
  String get actShortcutsTitle => '快捷键';

  @override
  String get barPagedNote => '分页笔记';

  @override
  String get barInfiniteCanvas => '无限画布';

  @override
  String get barHideLayers => '隐藏图层';

  @override
  String get barShowLayers => '显示图层';

  @override
  String get barHideInspector => '隐藏属性';

  @override
  String get barShowInspector => '显示属性';

  @override
  String get barExitFullscreen => '退出全屏';

  @override
  String get barEnterFullscreen => '全屏模式';

  @override
  String get barReadingOff => '关闭深色阅读';

  @override
  String get barReadingOn => '深色阅读（仅显示）';

  @override
  String get menuExportText => '导出文本';

  @override
  String get menuCommandPalette => '命令面板';

  @override
  String get menuSlides => '幻灯片演示';

  @override
  String get menuStats => '统计';

  @override
  String get menuShortcuts => '快捷键帮助';

  @override
  String get menuSwitchToFixed => '切换为固定纸张';

  @override
  String get menuSwitchToInfinite => '切换为无限画布';

  @override
  String get paletteRecent => '最近使用';

  @override
  String get paletteNoMatch => '没有可执行的匹配命令';

  @override
  String get textInputTitle => '输入文字';

  @override
  String get textInputHint => '请输入文字内容';

  @override
  String get distributeNeed3 => '至少需要 3 个元素才能分布';

  @override
  String get distributedH => '已水平等间距分布';

  @override
  String get distributedV => '已垂直等间距分布';

  @override
  String get edPreviewPagedOnly => '仅分页画布页面支持分页预览';

  @override
  String get edNoTextHere => '本页还没有文字内容';

  @override
  String get edNoTextBlocks => '本页没有文字块';

  @override
  String edRecoloredN(int count) {
    return '已批量改色 $count 个文字块';
  }

  @override
  String get edImageLabel => '图片';

  @override
  String get edNoteImageStoreUnavailable => '笔记页图片存储不可用';

  @override
  String get edDrawingImageStoreUnavailable => '绘图文档图片存储不可用';

  @override
  String get edLinkStartPicked => '已选择起点，再点击另一个元素完成连线';

  @override
  String get edLinkCreated => '已创建连接';

  @override
  String get ctxCopyStyle => '复制样式';

  @override
  String get ctxGroup => '分组';

  @override
  String get ctxUngroup => '取消分组';

  @override
  String get ctxBringToFront => '置顶';

  @override
  String get ctxSendToBack => '置底';

  @override
  String get edLinkInvalid => '链接无效或不受支持';

  @override
  String get edLinkOpened => '已打开链接';

  @override
  String get edLinkTitle => '设置链接';

  @override
  String get edLinkCleared => '已清除链接';

  @override
  String get edLinkSet => '已设置链接';

  @override
  String get edGroupNeed2 => '请先框选/多选至少 2 个元素再分组';

  @override
  String edGroupedN(int count) {
    return '已分组 $count 个元素';
  }

  @override
  String get edUngrouped => '已取消分组';

  @override
  String get renameCanvasTitle => '重命名画布';

  @override
  String get textBold => '加粗';

  @override
  String get textItalic => '斜体';

  @override
  String get textTodo => '待办';

  @override
  String get textCenter => '居中';

  @override
  String get textDone => '完成';

  @override
  String get textWidthHandle => '调整文字宽度';

  @override
  String get toolEraserName => '橡皮擦';

  @override
  String get pressureReal => '正在使用设备上报的真实压力范围';

  @override
  String get pressureFallback => '当前设备未报告可用压感，正在使用稳定的回退策略';

  @override
  String get coordsHide => '隐藏坐标';

  @override
  String get coordsShow => '显示画布坐标';

  @override
  String get zoomTooltip => '缩放画布';

  @override
  String get layersTitle => '图层';

  @override
  String get layerNew => '新建图层';

  @override
  String get layerUp => '上移';

  @override
  String get layerDown => '下移';

  @override
  String get layerMergeDown => '向下合并';

  @override
  String get layerDelete => '删除图层';

  @override
  String get propBrush => '画笔';

  @override
  String get propBrushColor => '画笔颜色';

  @override
  String get propImage => '图片';

  @override
  String get propCropImage => '裁剪图片';

  @override
  String get propShape => '形状';

  @override
  String get propFillColor => '填充色';

  @override
  String get propDash => '实线/虚线';

  @override
  String get propText => '文字';

  @override
  String get propTextColor => '文字颜色';

  @override
  String get fontSerif => '衬线字体';

  @override
  String get fontMono => '等宽字体';

  @override
  String get fontHandwriting => '手写字体';

  @override
  String get fontDefault => '默认字体';

  @override
  String get selCopy => '复制选中内容';

  @override
  String get selPaste => '粘贴';

  @override
  String get selUnlock => '解锁选中对象';

  @override
  String get selLock => '锁定选中对象，防止误触编辑';

  @override
  String get selUnlockImage => '解除图片锁定';

  @override
  String get selLockImage => '锁定图片，防止误触编辑';

  @override
  String get selUnlockShape => '解除形状锁定';

  @override
  String get selLockShape => '锁定形状，防止误触编辑';

  @override
  String get selDeleteLockedKeep => '删除未锁定对象；锁定对象会保留';

  @override
  String get selDelete => '删除选中对象';

  @override
  String get selShapeLocked => '形状已锁定，无法删除';

  @override
  String get selImageLocked => '图片已锁定，无法删除';

  @override
  String get selDeleteContent => '删除选中内容';

  @override
  String selNObjects(int count) {
    return '已选中 $count 个对象';
  }

  @override
  String get selShapeLockedEdit => '形状已锁定：解除锁定后可编辑';

  @override
  String get selShapeSelected => '已选中形状：可拖动、缩放、锁定或删除';

  @override
  String get selImageLockedEdit => '图片已锁定：解除锁定后可编辑';

  @override
  String get selImageSelected => '已选中图片：可拖动、缩放、锁定或删除';

  @override
  String selNStrokes(int count) {
    return '已选中 $count 笔';
  }

  @override
  String get selClear => '清除选区';

  @override
  String get shapeLibNoMatch => '没有匹配的形状';

  @override
  String get noteImageSemantic => '笔记图片';

  @override
  String get segmentEndpointSemantic => '调整线段端点';

  @override
  String get saveStateSaving => '保存中…';

  @override
  String saveStateSavedAt(String time) {
    return '已保存 $time';
  }

  @override
  String actInsertedShape(String name) {
    return '已插入「$name」';
  }

  @override
  String get tParagraph => '段落';

  @override
  String get tHeading => '标题';

  @override
  String get tBulletList => '无序列表';

  @override
  String get tOrderedList => '有序列表';

  @override
  String get tTodo => '待办';

  @override
  String get tQuote => '引用';

  @override
  String get tCode => '代码';

  @override
  String get tDivider => '分隔线';

  @override
  String get tImage => '图片';

  @override
  String get tLink => '链接';

  @override
  String get tTable => '表格';

  @override
  String get tDatabase => '数据库';

  @override
  String get tEmbedCanvas => '内嵌画布';

  @override
  String get tEmbedChart => '内嵌图表';

  @override
  String get docSaveFailedRetry => '保存失败，请重试';

  @override
  String get docSavedToast => '文档已保存';

  @override
  String get docToolbarSave => '保存';

  @override
  String get docToolbarOutline => '大纲';

  @override
  String get docToolbarRefresh => '刷新';

  @override
  String get docOutlineEmpty => '暂无标题块，用 / 菜单插入「标题」后出现在这里';

  @override
  String get docUnsavedChangesTitle => '未保存的改动';

  @override
  String get docDiscard => '放弃';

  @override
  String get blkSlashHint => '键入 / 添加块';

  @override
  String get blkEnterHint => '按 Enter 分块，按 Backspace 合并空块';

  @override
  String get blkDragToSort => '拖拽排序';

  @override
  String semHeading(String level) {
    return '标题$level';
  }

  @override
  String get semTodo => '待办事项';

  @override
  String get semCode => '代码块';

  @override
  String get semQuote => '引用';

  @override
  String get semBullet => '无序列表';

  @override
  String get semOrdered => '有序列表';

  @override
  String get semDivider => '分割线';

  @override
  String get semCallout => '提示';

  @override
  String get semToggle => '切换列表';

  @override
  String get semImage => '图片';

  @override
  String get semParagraph => '段落';

  @override
  String get semEmpty => '空';

  @override
  String get hintHeading => '标题';

  @override
  String get hintListItem => '列表项';

  @override
  String get hintTodo => '待办事项';

  @override
  String get hintToggle => '切换列表';

  @override
  String get hintQuote => '引用';

  @override
  String get hintCode => '代码';

  @override
  String get hintTypeContent => '输入内容...';

  @override
  String get mtBold => '粗体';

  @override
  String get mtItalic => '斜体';

  @override
  String get mtUnderline => '下划线';

  @override
  String get mtLink => '链接';

  @override
  String get mtCopyBlock => '复制块';

  @override
  String get mtDeleteBlock => '删除块';

  @override
  String get outlineTitle => '大纲';

  @override
  String get wBack => '返回';

  @override
  String get wInsertPageLink => '插入页面链接';

  @override
  String get wSave => '保存';

  @override
  String get wUnfavorite => '取消收藏';

  @override
  String get wFavorite => '收藏';

  @override
  String get wDocInfo => '文档信息';

  @override
  String get wMore => '更多';

  @override
  String get wOpenInCanvas => '在画布中打开';

  @override
  String get wFilePassword => '文件密码';

  @override
  String get wShare => '分享';

  @override
  String get docSnackSaveKept => '保存失败，已保持原状态';

  @override
  String get docSnackTagFailed => '创建标签失败，请重试';

  @override
  String get attUntitled => '未命名附件';

  @override
  String get attEditDesc => '编辑描述';

  @override
  String get attOpenLink => '打开链接';

  @override
  String get attEditNote => '编辑备注';

  @override
  String get attDescHint => '附件的描述/备注';

  @override
  String get sgBasic => '基础';

  @override
  String get sgQuoteCode => '引用与代码';

  @override
  String get sgMedia => '媒体';

  @override
  String get sgEmbed => '嵌入';

  @override
  String get sgOther => '其他';

  @override
  String get slashNoMatch => '无匹配项';

  @override
  String get dbUntitled => '数据库';

  @override
  String get dbAddField => '添加字段';

  @override
  String get dbAddRecord => '添加记录';

  @override
  String get dbSearchRecords => '搜索记录';

  @override
  String get dbClearFilter => '清除筛选';

  @override
  String get dbViewTable => '表';

  @override
  String get dbViewKanban => '看板';

  @override
  String get dbViewList => '列表';

  @override
  String get dbCellHint => '输入值';

  @override
  String get dbCellNone => '未选择';

  @override
  String dbRecordCount(int count) {
    return '$count 条记录';
  }

  @override
  String get dbKanbanNeedsSelect => '看板需要至少一个“选项”字段，请先添加 select 字段';

  @override
  String get dbUngrouped => '未分组';

  @override
  String get dbNoTitleRecord => '无标题记录';

  @override
  String get dbNoFieldsYet => '还没有字段，点击“添加字段”开始建表';

  @override
  String get dbFieldActions => '字段操作';

  @override
  String get dbDeleteField => '删除字段';

  @override
  String get dbToggleCheck => '切换勾选';

  @override
  String get dbDeleteRecord => '删除记录';

  @override
  String get embUnsafeImage => '图片来源不安全，已拦截';

  @override
  String get embImageFailed => '图片加载失败';

  @override
  String get embClickPreview => '点击预览';

  @override
  String get embCanvasLabel => '内嵌画布';

  @override
  String get embChartLabel => '内嵌图表';

  @override
  String get embHostBuilderHint => '由宿主提供 builder 以渲染完整内容';

  @override
  String get tblAddColumn => '添加列';

  @override
  String get tblDeleteColumn => '删除列';

  @override
  String get tblAddRow => '添加行';

  @override
  String get tblDeleteRow => '删除行';

  @override
  String get trashDeleteForeverTitle => '彻底删除';

  @override
  String get trashTitleBar => '回收站';

  @override
  String get trashEmptyTitle => '回收站是空的';

  @override
  String get trashEmptyTip => '删除的笔记在此保留 30 天，可随时恢复';

  @override
  String get trashRestore => '恢复';

  @override
  String get tplBlankName => '空白笔记';

  @override
  String get tplBlankDesc => '从零开始';

  @override
  String get tplMeetingName => '会议纪要';

  @override
  String get tplMeetingDesc => '议题 · 决议 · 行动项';

  @override
  String get tplDailyName => '每日日志';

  @override
  String get tplDailyDesc => '今日完成 · 明日计划';

  @override
  String get tplTodoName => '待办清单';

  @override
  String get tplTodoDesc => '预置待办块';
}

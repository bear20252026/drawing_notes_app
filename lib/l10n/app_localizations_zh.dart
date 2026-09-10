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
}

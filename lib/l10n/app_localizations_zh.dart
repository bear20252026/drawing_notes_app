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
  String get newNotebook => '新建笔记本';

  @override
  String get delete => '删除';

  @override
  String get homeTrashEmpty => '回收站为空';

  @override
  String homeDeletedAt(Object time) {
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
  String get homeSwitchTheme => '切换外观（系统 / 浅色 / 深色）';

  @override
  String get homeMore => '更多操作';

  @override
  String homeRecovered(Object id) {
    return '已恢复「$id」';
  }

  @override
  String get homePasswordDiskAndRecovery => '密码盘与恢复';

  @override
  String get homeInfiniteCanvas => '无限画布';

  @override
  String get homeNotebook => '笔记本';

  @override
  String get homeRecent => '最近';

  @override
  String get homeNewInfiniteCanvas => '新建无限画布';

  @override
  String get homeQuickRecord => '快速记录';

  @override
  String get homeRetry => '重试';

  @override
  String get homeErrorDrawingNotFound => '画作文件不存在或已损坏';

  @override
  String homeErrorOpenDrawing(Object error) {
    return '打开画作失败：$error';
  }

  @override
  String get homeDeleteDrawing => '删除画作';

  @override
  String homeConfirmDeleteDrawing(Object title) {
    return '确定删除画作「$title」吗？此操作不可恢复。';
  }

  @override
  String get homeDeleteNotebook => '删除笔记本';

  @override
  String homeConfirmDeleteNotebook(Object title) {
    return '确定删除笔记本「$title」吗？其中所有页面内容将一并删除，此操作不可恢复。';
  }

  @override
  String homeConfirmPermanentDelete(Object name) {
    return '确定永久删除「$name」吗？此操作不可恢复。';
  }

  @override
  String homeErrorDeleteFailed(Object error) {
    return '删除失败：$error';
  }

  @override
  String homeErrorPolicyDenied(Object policy) {
    return '操作被策略拒绝（$policy）';
  }

  @override
  String get homeLegacyEncryptionWarning =>
      '检测到旧版加密格式（10 万次迭代），建议重新保存以升级至最新加密标准（60 万次）';

  @override
  String get homeEncryptionUpgraded => '已自动升级加密至最新标准（60 万次迭代）';

  @override
  String get homeLegacyEncryptionManual => '旧版加密格式：建议手动重新保存升级';

  @override
  String homeErrorLoadList(Object error) {
    return '读取列表失败：$error';
  }

  @override
  String get homeNewDrawingTitle => '新建无限画布';

  @override
  String homeErrorCreateFailed(Object error) {
    return '新建失败：$error';
  }

  @override
  String homeOpenCanvasTitle(Object title) {
    return '打开无限画布 $title';
  }

  @override
  String homeQuickRecordTitle(Object time) {
    return '快速记录 $time';
  }

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
  String get editorCopySelection => '复制选中对象';

  @override
  String get editorPasteFromClipboard => '从剪贴板粘贴';

  @override
  String get editorCopyPasteSelection => '复制并粘贴选中对象';

  @override
  String get editorDeleteSelection => '删除选中对象';

  @override
  String get editorBoldText => '加粗选中文字';

  @override
  String get editorItalicText => '斜体选中文字';

  @override
  String get editorUnderlineText => '下划线选中文字';

  @override
  String get editorStrikethroughText => '删除线选中文字';

  @override
  String get editorCycleAlignment => '循环切换文本对齐';

  @override
  String get editorFitCanvas => '适应画布';

  @override
  String get editorToggleGrid => '显示或隐藏网格';

  @override
  String get editorToggleGridSnap => '切换网格吸附';

  @override
  String get editorDrawingCanvas => '绘图画布';

  @override
  String get editorBoldLabel => '加粗';

  @override
  String get editorItalicLabel => '斜体';

  @override
  String get editorTodoLabel => '待办';

  @override
  String get editorCenterAlign => '居中';

  @override
  String get editorImage => '图片';

  @override
  String get editorCancelSelection => '取消选择';

  @override
  String get toolPen => '画笔';

  @override
  String get toolPencil => '铅笔';

  @override
  String get toolBrush => '毛笔';

  @override
  String get toolHighlighter => '荧光笔';

  @override
  String get toolEraser => '橡皮擦';

  @override
  String get toolLasso => '套索';

  @override
  String get toolText => '文字';

  @override
  String get toolImage => '图片';

  @override
  String get toolRuler => '直尺';

  @override
  String get toolLaser => '激光笔';

  @override
  String get toolEyedropper => '吸色';

  @override
  String get editorSelectionColor => '选区颜色';

  @override
  String get editorStrokeWidth => '画笔粗细';

  @override
  String get editorFontSize => '文字大小';

  @override
  String get editorShapeStrokeWidth => '形状边框粗细';

  @override
  String get editorPressureSettings => '压感设置';

  @override
  String get editorMinWidth => '最小粗细';

  @override
  String get editorMaxWidth => '最大粗细';

  @override
  String get editorPressureCurve => '压感曲线';

  @override
  String get editorFullStroke => '整笔';

  @override
  String get editorTransparent => '透明';

  @override
  String get editorSave => '保存';

  @override
  String get editorAutoFade => '自动消失';

  @override
  String get chartBar => '柱状图';

  @override
  String get chartLine => '折线图';

  @override
  String get cropImage => '裁剪图片';

  @override
  String get copiedToClipboard => '已复制';

  @override
  String get exportTypePng => 'PNG 图片';

  @override
  String get exportTypePdf => 'PDF 文档';

  @override
  String get exportTypeSvg => 'SVG 矢量图';

  @override
  String get exportTypeWord => 'Word 兼容文档';

  @override
  String get exportTypeMarkdown => 'Markdown / 文本';

  @override
  String get exportTypePptx => 'PPTX 演示文稿';

  @override
  String get exportTypeJson => 'JSON 工程文件';

  @override
  String get exportTypeUnknown => '未知格式';

  @override
  String get noteActions => '笔记本操作';

  @override
  String get noteImportPage => '从其他笔记本引入页面';

  @override
  String get noteImportMarkdown => '导入 Markdown 或文本';

  @override
  String get noteImportPdf => '导入 PDF 并逐页批注';

  @override
  String get noteTidyPages => '批量整理页面';

  @override
  String get noteFilterHint => '筛选标签或关键词';

  @override
  String get noteEncryptionChoice => '选择加密方式';

  @override
  String get noteMemoryPassword => '记忆密码';

  @override
  String get noteMemoryPasswordSub => '设置密码，打开时输入密码解密';

  @override
  String get noteUsbKey => 'U盘钥匙（密码盘）';

  @override
  String get noteUsbKeySub => 'U盘即钥匙：插入 U 盘解锁，拔盘即锁（零知识）';

  @override
  String get noteRecoveryKeyTitle => '保存您的恢复密钥（非常重要！）';

  @override
  String get noteNewPage => '新建页面';

  @override
  String get noteSessionLocked => '会话已锁定，请重新解锁';

  @override
  String get noteSessionExpired => '会话已过期，请重新解锁';

  @override
  String noteErrorSaveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get noteEncryptionPasswordEnabled => '已启用密码保护（页面内容加密存储）';

  @override
  String get noteEncryptionUsbKeyEnabled => '已启用 U盘钥匙加密（拔盘即锁）';

  @override
  String get passwordUnlock => '密码解锁';

  @override
  String get passwordDisk => '密码盘';

  @override
  String get unlock => '解锁';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get diskCreate => '创建密码盘（生成密钥 + 恢复密钥）';

  @override
  String get diskUnlock => '解锁（选择 U 盘密码盘目录）';

  @override
  String get diskRecover => '用恢复密钥找回主密钥（U 盘丢失）';

  @override
  String get diskEncryptDecrypt => '用密码盘密钥加密并解密回显';

  @override
  String get diskFingerprintCopied => '指纹已复制';

  @override
  String get diskCopied => '我已抄写';

  @override
  String get diskPinProtection => '是否启用 PIN 保护？';

  @override
  String get diskNoPin => '不启用';

  @override
  String get diskYesPin => '启用';

  @override
  String get diskEnterPin => '输入密码盘 PIN';

  @override
  String get diskConfirm => '确定';

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
  String get diskPinInfo =>
      '启用后主密钥经 PIN 加密存储（OWASP KEK 模式），U 盘丢失也无法直接读出；解锁需输入 PIN。';

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
  String get editorPdfPreview => '分页预览（按 A4 分页）';

  @override
  String get editorPasteValues => '粘贴数值，用逗号/空格/换行分隔，例如：10, 25, 18, 42, 30';

  @override
  String editorImageInsertFail(Object error) {
    return '插入图片失败：$error';
  }

  @override
  String get alignLeft => '左对齐';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '右对齐';

  @override
  String editorAlignTooltip(Object name) {
    return '对齐：$name (Ctrl+E)';
  }

  @override
  String editorPagePreviewTitle(Object title) {
    return '分页预览 $title';
  }

  @override
  String get paperBlank => '空白';

  @override
  String get paperGrid => '网格';

  @override
  String get paperLined => '横线';

  @override
  String get paperDot => '点阵';

  @override
  String editorPaperTemplate(Object type) {
    return '纸张模板：$type（点击切换）';
  }

  @override
  String get editorShapeFillOn => '形状填充：开（新建形状默认填充）';

  @override
  String get editorShapeFillOff => '形状填充：关（新建形状默认填充）';

  @override
  String get create => '新建';

  @override
  String get retry => '重试';

  @override
  String get confirm => '确定';

  @override
  String get errorLoadDocument => '加载文档失败';

  @override
  String get errorSaveFailed => '保存失败';

  @override
  String get errorAutoSaveFailed => '自动保存失败';

  @override
  String get appearance => '外观';

  @override
  String get themeLight => '浅色主题';

  @override
  String get themeDark => '深色主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get onboardingTitle => '欢迎使用绘图笔记';

  @override
  String get onboardingSubtitle => '用画笔记录灵感，支持无限画布、笔记本和加密保护';

  @override
  String get onboardingBrush => '画笔 / 橡皮擦 / 吸管：顶部工具条切换，拖动鼠标或手指绘画';

  @override
  String get onboardingColor => '颜色与粗细：工具条右侧圆形色块与粗细滑块';

  @override
  String get onboardingLayers => '图层面板在右侧：新建、显隐、透明度、顺序、合并';

  @override
  String get onboardingSelect => '选区工具：框选后可移动 / 缩放 / 旋转 / 复制 / 删除';

  @override
  String get onboardingText => '笔记页支持文字与图片：文字工具点击画布输入，图片按钮插入';

  @override
  String get onboardingPinch => '双指捏合缩放画布、双指旋转画布（触屏设备）';

  @override
  String get onboardingFullscreen => '右上角全屏按钮：隐藏工具栏只看画布';

  @override
  String get onboardingSave => '内容自动保存，无需手动保存；可随时导出为 PNG';

  @override
  String get onboardingStart => '开始使用';

  @override
  String get onboardingGetStarted => '开始使用';

  @override
  String get onboardingSkip => '跳过';

  @override
  String get appErrorTitle => '出了点问题';

  @override
  String get appErrorBody => '应用遇到了一个错误，但数据不会丢失。';

  @override
  String get appErrorBackHome => '返回首页';

  @override
  String get appErrorDetails => '错误详情（调试模式）';

  @override
  String get settings => '设置';

  @override
  String get about => '关于';

  @override
  String get version => '版本';

  @override
  String get aiChat => 'AI 助手';

  @override
  String get aiChatHint => '输入问题开始对话…';

  @override
  String get aiChatEmpty => '还没有对话记录';

  @override
  String get securityLevel => '安全等级';

  @override
  String get encryptionStatus => '加密状态';

  @override
  String get exportTitle => '导出';

  @override
  String get importTitle => '导入';

  @override
  String get layerPanel => '图层';

  @override
  String get historyTitle => '历史记录';

  @override
  String get recentDocuments => '最近文档';

  @override
  String get noRecentDocuments => '暂无最近文档';

  @override
  String get enableSync => '启用同步';

  @override
  String get syncStatus => '同步状态';

  @override
  String get storagePermissionRequired => '需要存储权限';

  @override
  String get pen => '画笔';

  @override
  String get eraser => '橡皮擦';

  @override
  String get selection => '选择';

  @override
  String get textTool => '文字';

  @override
  String get shape => '形状';

  @override
  String get pageManagement => '页面管理';

  @override
  String get deletePage => '删除';

  @override
  String get renamePage => '重命名';

  @override
  String get reorderPages => '拖拽排序';

  @override
  String get drawingLayers => '绘图层';

  @override
  String get textLayers => '文字层';

  @override
  String get noteContent => '笔记内容';

  @override
  String get recentlyUsed => '最近使用';

  @override
  String get allShapes => '全部形状';

  @override
  String get basicShapes => '基础形状';

  @override
  String get lines => '线条';

  @override
  String get arrows => '箭头';

  @override
  String get highlighter => '荧光笔';

  @override
  String get laserPointer => '激光笔';

  @override
  String get settingsTitle => '设置';

  @override
  String get themeLabel => '主题';

  @override
  String get languageLabel => '语言';

  @override
  String get selectLanguage => '选择语言';

  @override
  String get autoSaveLabel => '自动保存';

  @override
  String get storageLabel => '存储';

  @override
  String get securityLabel => '安全';

  @override
  String get aiLabel => 'AI';

  @override
  String get experimentalLabel => '实验功能';

  @override
  String get hotkeysLabel => '快捷键';

  @override
  String get syncLabel => '同步';

  @override
  String get diagnostics => '诊断';

  @override
  String get testRunnerTitle => '测试运行器';

  @override
  String get testRunnerStart => '开始测试';

  @override
  String get p2pSyncTitle => '点对点同步';

  @override
  String get p2pSyncSubtitle => '局域网设备间直接同步';

  @override
  String get viewAllPages => '查看所有页面';

  @override
  String get blockEditorTitle1 => '标题 1';

  @override
  String get blockEditorTitle2 => '标题 2';

  @override
  String get blockEditorTitle3 => '标题 3';

  @override
  String get blockEditorListItem => '列表项';

  @override
  String get blockEditorCodeHint => '输入代码…';

  @override
  String get blockEditorQuoteHint => '引用…';

  @override
  String get blockEditorParagraphHint => '输入文字，或输入 / 打开命令菜单…';

  @override
  String get blockEditorImageLoadFail => '图片加载失败';

  @override
  String get blockEditorTableBlock => '表格块（详见 TableViewWidget）';

  @override
  String get blockEditorAddRow => '添加行';

  @override
  String get slidePresenterSlide => '幻灯片';

  @override
  String get slidePresenterExit => '退出';

  @override
  String get unifiedToolbarBrush => '画笔';

  @override
  String get unifiedToolbarEraser => '橡皮擦';

  @override
  String get unifiedToolbarSelect => '选择';

  @override
  String get unifiedToolbarRectSelect => '矩形选区';

  @override
  String get unifiedToolbarLassoSelect => '套索选区';

  @override
  String get unifiedToolbarRect => '矩形';

  @override
  String get unifiedToolbarEllipse => '椭圆';

  @override
  String get unifiedToolbarLine => '直线';

  @override
  String get unifiedToolbarArrow => '箭头';

  @override
  String get unifiedToolbarText => '文字';

  @override
  String get unifiedToolbarEyedropper => '吸管取色';

  @override
  String get unifiedToolbarEraserOptions => '橡皮擦选项';

  @override
  String get unifiedToolbarEraseShapes => '可擦除形状';

  @override
  String get unifiedToolbarGrid => '网格显示';

  @override
  String get unifiedToolbarSnap => '网格吸附';

  @override
  String get unifiedToolbarZoomOut => '缩小';

  @override
  String get unifiedToolbarZoomIn => '放大';

  @override
  String get unifiedToolbarFitCanvas => '适应画布';

  @override
  String get unifiedToolbarClickToPlaceText => '点击画布放置文字';

  @override
  String get unifiedToolbarClickToPickColor => '点击画布取色';

  @override
  String get unifiedPropertyBrush => '画笔';

  @override
  String get unifiedPropertyShape => '形状';

  @override
  String get unifiedPropertyText => '文字';

  @override
  String get unifiedPropertyFillColor => '填充色';

  @override
  String get unifiedPropertyDashLine => '实线/虚线';

  @override
  String get unifiedPropertyTextColor => '文字颜色';

  @override
  String get unifiedLayerPanelTitle => '图层';

  @override
  String get unifiedLayerPanelRename => '重命名图层';

  @override
  String get unifiedLayerPanelRenameHint => '输入图层名称';

  @override
  String get unifiedLayerPanelCancel => '取消';

  @override
  String get unifiedLayerPanelConfirm => '确定';

  @override
  String get unnamedNote => '未命名笔记';

  @override
  String get inputText => '输入文字';

  @override
  String get inputTextContent => '输入文字内容';

  @override
  String get cancel => '取消';

  @override
  String get note => '笔记';

  @override
  String get save => '保存';

  @override
  String get loadFailed => '加载失败';

  @override
  String get noteTitle => '笔记标题';

  @override
  String editorV2Title(String docId) {
    return 'Editor V2 - $docId';
  }

  @override
  String get historyPanelTitle => '历史记录';

  @override
  String historySteps(int count) {
    return '$count 步';
  }

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String get noHistory => '无历史记录';

  @override
  String get exportPanelTitle => '导出';

  @override
  String get exporting => '导出中...';

  @override
  String exportFormat(String format) {
    return '导出 $format';
  }

  @override
  String get exportPreview => '预览';

  @override
  String get copied => '已复制';

  @override
  String get copyTooltip => '复制';

  @override
  String get pngExportHint => 'PNG 导出需要 Canvas 渲染——请使用画布右键菜单导出。';

  @override
  String exportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String get exportFormatPNG => '图片格式';

  @override
  String get exportFormatSVG => '矢量格式';

  @override
  String get exportFormatJSON => '文档格式';

  @override
  String get propertiesPanelTitle => '属性';

  @override
  String get colorLabel => '颜色';

  @override
  String get strokeWidthLabel => '线宽';

  @override
  String get opacityLabel => '透明度';

  @override
  String get lineStyleLabel => '线条样式';

  @override
  String get solidLine => '实线';

  @override
  String get dashedLine => '虚线';

  @override
  String get dottedLine => '点线';

  @override
  String get titleHint => '标题';

  @override
  String get startTypingHint => '开始输入…';

  @override
  String get zoomOut => '缩小';

  @override
  String get zoomIn => '放大';

  @override
  String get zoomReset => '重置 (1x)';

  @override
  String get fitWindow => '适应窗口';

  @override
  String pageN(int index) {
    return '页面 $index';
  }

  @override
  String get newPage => '新建';

  @override
  String slideN(int index) {
    return '幻灯片 $index';
  }

  @override
  String get newColumn => '新列';

  @override
  String get noLayers => '无图层';

  @override
  String get selectColor => '选择颜色';
}

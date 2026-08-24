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
  String get newNotebook => 'New Notebook';

  @override
  String get delete => 'Delete';

  @override
  String get homeTrashEmpty => 'Trash is empty';

  @override
  String homeDeletedAt(Object time) {
    return 'Deleted at $time';
  }

  @override
  String get homeRecover => 'Recover';

  @override
  String get homeDeleteForever => 'Delete Forever';

  @override
  String get homeEmptyTrash => 'Empty Trash';

  @override
  String get homeCancel => 'Cancel';

  @override
  String get homeSwitchTheme => 'Switch Theme (System / Light / Dark)';

  @override
  String get homeMore => 'More Actions';

  @override
  String homeRecovered(Object id) {
    return 'Recovered \"$id\"';
  }

  @override
  String get homePasswordDiskAndRecovery => 'Password Disk & Recovery';

  @override
  String get homeInfiniteCanvas => 'Canvas';

  @override
  String get homeNotebook => 'Notebooks';

  @override
  String get homeRecent => 'Recent';

  @override
  String get homeNewInfiniteCanvas => 'New Canvas';

  @override
  String get homeQuickRecord => 'Quick Record';

  @override
  String get homeRetry => 'Retry';

  @override
  String get homeErrorDrawingNotFound => 'Drawing file not found or corrupted';

  @override
  String homeErrorOpenDrawing(Object error) {
    return 'Failed to open drawing: $error';
  }

  @override
  String get homeDeleteDrawing => 'Delete Drawing';

  @override
  String homeConfirmDeleteDrawing(Object title) {
    return 'Are you sure you want to delete \"$title\"? This action cannot be undone.';
  }

  @override
  String get homeDeleteNotebook => 'Delete Notebook';

  @override
  String homeConfirmDeleteNotebook(Object title) {
    return 'Are you sure you want to delete notebook \"$title\"? All pages and content will be permanently deleted.';
  }

  @override
  String homeConfirmPermanentDelete(Object name) {
    return 'Are you sure you want to permanently delete \"$name\"? This action cannot be undone.';
  }

  @override
  String homeErrorDeleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String homeErrorPolicyDenied(Object policy) {
    return 'Operation denied by policy ($policy)';
  }

  @override
  String get homeLegacyEncryptionWarning =>
      'Legacy encryption format detected (100K iterations). Please re-save to upgrade to the latest standard (600K iterations).';

  @override
  String get homeEncryptionUpgraded =>
      'Encryption automatically upgraded to latest standard (600K iterations)';

  @override
  String get homeLegacyEncryptionManual =>
      'Legacy encryption: manual re-save recommended';

  @override
  String homeErrorLoadList(Object error) {
    return 'Failed to load list: $error';
  }

  @override
  String get homeNewDrawingTitle => 'New Canvas';

  @override
  String homeErrorCreateFailed(Object error) {
    return 'Creation failed: $error';
  }

  @override
  String homeOpenCanvasTitle(Object title) {
    return 'Open Canvas $title';
  }

  @override
  String homeQuickRecordTitle(Object time) {
    return 'Quick Record $time';
  }

  @override
  String get editorUndo => 'Undo';

  @override
  String get editorRedo => 'Redo';

  @override
  String get editorShortcutsHelp => 'Keyboard Shortcuts Help';

  @override
  String get editorMenu => 'Main Menu';

  @override
  String get editorClearCanvas => 'Clear Canvas';

  @override
  String get editorCopyPng => 'Copy PNG to Clipboard';

  @override
  String get editorExportPng => 'Export PNG';

  @override
  String get editorExportSvg => 'Export SVG';

  @override
  String get editorShapeTool => 'Shape Tool';

  @override
  String get editorCopySelection => 'Copy Selection';

  @override
  String get editorPasteFromClipboard => 'Paste from Clipboard';

  @override
  String get editorCopyPasteSelection => 'Copy and Paste Selection';

  @override
  String get editorDeleteSelection => 'Delete Selection';

  @override
  String get editorBoldText => 'Bold Selected Text';

  @override
  String get editorItalicText => 'Italic Selected Text';

  @override
  String get editorUnderlineText => 'Underline Selected Text';

  @override
  String get editorStrikethroughText => 'Strikethrough Selected Text';

  @override
  String get editorCycleAlignment => 'Cycle Text Alignment';

  @override
  String get editorFitCanvas => 'Fit to Canvas';

  @override
  String get editorToggleGrid => 'Toggle Grid';

  @override
  String get editorToggleGridSnap => 'Toggle Grid Snap';

  @override
  String get editorDrawingCanvas => 'Drawing Canvas';

  @override
  String get editorBoldLabel => 'Bold';

  @override
  String get editorItalicLabel => 'Italic';

  @override
  String get editorTodoLabel => 'Todo';

  @override
  String get editorCenterAlign => 'Center';

  @override
  String get editorImage => 'Image';

  @override
  String get editorCancelSelection => 'Cancel Selection';

  @override
  String get toolPen => 'Pen';

  @override
  String get toolPencil => 'Pencil';

  @override
  String get toolBrush => 'Brush';

  @override
  String get toolHighlighter => 'Highlighter';

  @override
  String get toolEraser => 'Eraser';

  @override
  String get toolLasso => 'Lasso';

  @override
  String get toolText => 'Text';

  @override
  String get toolImage => 'Image';

  @override
  String get toolRuler => 'Ruler';

  @override
  String get toolLaser => 'Laser Pointer';

  @override
  String get toolEyedropper => 'Eyedropper';

  @override
  String get editorSelectionColor => 'Selection Color';

  @override
  String get editorStrokeWidth => 'Stroke Width';

  @override
  String get editorFontSize => 'Text Size';

  @override
  String get editorShapeStrokeWidth => 'Shape Border Width';

  @override
  String get editorPressureSettings => 'Pressure Settings';

  @override
  String get editorMinWidth => 'Min Width';

  @override
  String get editorMaxWidth => 'Max Width';

  @override
  String get editorPressureCurve => 'Pressure Curve';

  @override
  String get editorFullStroke => 'Full Stroke';

  @override
  String get editorTransparent => 'Transparent';

  @override
  String get editorSave => 'Save';

  @override
  String get editorAutoFade => 'Auto Fade';

  @override
  String get chartBar => 'Bar Chart';

  @override
  String get chartLine => 'Line Chart';

  @override
  String get cropImage => 'Crop Image';

  @override
  String get copiedToClipboard => 'Copied';

  @override
  String get exportTypePng => 'PNG Image';

  @override
  String get exportTypePdf => 'PDF Document';

  @override
  String get exportTypeSvg => 'SVG Vector';

  @override
  String get exportTypeWord => 'Word Document';

  @override
  String get exportTypeMarkdown => 'Markdown / Text';

  @override
  String get exportTypePptx => 'PPTX Presentation';

  @override
  String get exportTypeJson => 'JSON Project File';

  @override
  String get exportTypeUnknown => 'Unknown Format';

  @override
  String get noteActions => 'Notebook Actions';

  @override
  String get noteImportPage => 'Import Pages from Other Notebooks';

  @override
  String get noteImportMarkdown => 'Import Markdown or Text';

  @override
  String get noteImportPdf => 'Import PDF for Page-by-Page Annotation';

  @override
  String get noteTidyPages => 'Batch Tidy Pages';

  @override
  String get noteFilterHint => 'Filter by tag or keyword';

  @override
  String get noteEncryptionChoice => 'Choose Encryption Method';

  @override
  String get noteMemoryPassword => 'Remember Password';

  @override
  String get noteMemoryPasswordSub =>
      'Set a password, enter it to decrypt when opening';

  @override
  String get noteUsbKey => 'USB Key (Password Disk)';

  @override
  String get noteUsbKeySub =>
      'USB as Key: insert to unlock, remove to lock (zero-knowledge)';

  @override
  String get noteRecoveryKeyTitle => 'Save Your Recovery Key (Very Important!)';

  @override
  String get noteNewPage => 'New Page';

  @override
  String get noteSessionLocked => 'Session locked, please unlock again';

  @override
  String get noteSessionExpired => 'Session expired, please unlock again';

  @override
  String noteErrorSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get noteEncryptionPasswordEnabled =>
      'Password protection enabled (content encrypted)';

  @override
  String get noteEncryptionUsbKeyEnabled =>
      'USB key encryption enabled (lock on removal)';

  @override
  String get passwordUnlock => 'Password Unlock';

  @override
  String get passwordDisk => 'Password Disk';

  @override
  String get unlock => 'Unlock';

  @override
  String get enterPassword => 'Enter password';

  @override
  String get diskCreate => 'Create Password Disk (Generate Key + Recovery Key)';

  @override
  String get diskUnlock => 'Unlock (Select USB Password Disk Directory)';

  @override
  String get diskRecover => 'Recover Master Key with Recovery Key (USB Lost)';

  @override
  String get diskEncryptDecrypt => 'Encrypt and Decrypt with Password Disk Key';

  @override
  String get diskFingerprintCopied => 'Fingerprint copied';

  @override
  String get diskCopied => 'I\'ve saved it';

  @override
  String get diskPinProtection => 'Enable PIN protection?';

  @override
  String get diskNoPin => 'No';

  @override
  String get diskYesPin => 'Yes';

  @override
  String get diskEnterPin => 'Enter Password Disk PIN';

  @override
  String get diskConfirm => 'Confirm';

  @override
  String get searchTitle => 'Full-text Search';

  @override
  String get searchHint => 'Search text content / titles…';

  @override
  String get searchEmptyHint => 'Enter keywords to start searching';

  @override
  String get searchNoResults => 'No matching content found';

  @override
  String get editorStrokeColor => 'Stroke Color';

  @override
  String get editorEraseStroke => 'Erase entire stroke on hit';

  @override
  String get editorEraseTransparent =>
      'Erase with transparent pixels on current layer';

  @override
  String get editorHighlightNormal =>
      'Writes as normal highlighter, undoable, saveable and exportable';

  @override
  String get editorLaserTemporary =>
      'Shows temporarily only, fades out in ~4 seconds, not saved';

  @override
  String get editorTextColor => 'Text Color';

  @override
  String get editorBold => 'Bold (Ctrl+B)';

  @override
  String get editorItalic => 'Italic (Ctrl+I)';

  @override
  String get diskPinInfo =>
      'When enabled, the master key is encrypted with PIN (OWASP KEK mode). Even if the USB is lost, the key cannot be read directly. Unlocking requires the PIN.';

  @override
  String get editorExportPdf => 'Export PDF';

  @override
  String get editorExportJson => 'Export JSON';

  @override
  String get editorExportPptx => 'Export PPTX';

  @override
  String get editorExportWord => 'Export Word Document';

  @override
  String get editorUnderline => 'Underline (Ctrl+U)';

  @override
  String get editorPdfPreview => 'Page Preview (A4 pagination)';

  @override
  String get editorPasteValues =>
      'Paste values separated by comma/space/newline, e.g.: 10, 25, 18, 42, 30';

  @override
  String editorImageInsertFail(Object error) {
    return 'Failed to insert image: $error';
  }

  @override
  String get alignLeft => 'Align Left';

  @override
  String get alignCenter => 'Center';

  @override
  String get alignRight => 'Align Right';

  @override
  String editorAlignTooltip(Object name) {
    return 'Alignment: $name (Ctrl+E)';
  }

  @override
  String editorPagePreviewTitle(Object title) {
    return 'Page Preview $title';
  }

  @override
  String get paperBlank => 'Blank';

  @override
  String get paperGrid => 'Grid';

  @override
  String get paperLined => 'Lined';

  @override
  String get paperDot => 'Dotted';

  @override
  String editorPaperTemplate(Object type) {
    return 'Paper Template: $type (tap to switch)';
  }

  @override
  String get editorShapeFillOn =>
      'Shape Fill: On (new shapes filled by default)';

  @override
  String get editorShapeFillOff =>
      'Shape Fill: Off (new shapes filled by default)';

  @override
  String get create => 'Create';

  @override
  String get retry => 'Retry';

  @override
  String get confirm => 'Confirm';

  @override
  String get errorLoadDocument => 'Failed to load document';

  @override
  String get errorSaveFailed => 'Save failed';

  @override
  String get errorAutoSaveFailed => 'Auto-save failed';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeLight => 'Light Theme';

  @override
  String get themeDark => 'Dark Theme';

  @override
  String get themeSystem => 'Follow System';

  @override
  String get onboardingTitle => 'Welcome to Drawing Notes';

  @override
  String get onboardingSubtitle =>
      'Capture ideas with your pen. Supports infinite canvas, notebooks, and encryption.';

  @override
  String get onboardingBrush =>
      'Pen / Eraser / Eyedropper: switch via top toolbar, drag mouse or finger to draw';

  @override
  String get onboardingColor =>
      'Color & Width: color circle and width slider on the right side of toolbar';

  @override
  String get onboardingLayers =>
      'Layer panel on the right: new, show/hide, opacity, order, merge';

  @override
  String get onboardingSelect =>
      'Selection tool: select area to move / scale / rotate / copy / delete';

  @override
  String get onboardingText =>
      'Notebook supports text and images: tap canvas with text tool to input, image button to insert';

  @override
  String get onboardingPinch =>
      'Pinch to zoom canvas, two-finger rotate canvas (touchscreen devices)';

  @override
  String get onboardingFullscreen =>
      'Fullscreen button top-right: hide toolbar, view canvas only';

  @override
  String get onboardingSave =>
      'Content auto-saves, no manual save needed; export to PNG anytime';

  @override
  String get onboardingStart => 'Get Started';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get appErrorTitle => 'Something went wrong';

  @override
  String get appErrorBody =>
      'The app encountered an error, but your data is safe.';

  @override
  String get appErrorBackHome => 'Back to Home';

  @override
  String get appErrorDetails => 'Error Details (Debug Mode)';

  @override
  String get settings => 'Settings';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get aiChat => 'AI Assistant';

  @override
  String get aiChatHint => 'Type a question to start chatting…';

  @override
  String get aiChatEmpty => 'No chat history yet';

  @override
  String get securityLevel => 'Security Level';

  @override
  String get encryptionStatus => 'Encryption Status';

  @override
  String get exportTitle => 'Export';

  @override
  String get importTitle => 'Import';

  @override
  String get layerPanel => 'Layers';

  @override
  String get historyTitle => 'History';

  @override
  String get recentDocuments => 'Recent Documents';

  @override
  String get noRecentDocuments => 'No recent documents';

  @override
  String get enableSync => 'Enable Sync';

  @override
  String get syncStatus => 'Sync Status';

  @override
  String get storagePermissionRequired => 'Storage permission required';

  @override
  String get pen => 'Pen';

  @override
  String get eraser => 'Eraser';

  @override
  String get selection => 'Selection';

  @override
  String get textTool => 'Text';

  @override
  String get shape => 'Shape';

  @override
  String get pageManagement => 'Page Management';

  @override
  String get deletePage => 'Delete';

  @override
  String get renamePage => 'Rename';

  @override
  String get reorderPages => 'Drag to Reorder';

  @override
  String get drawingLayers => 'Drawing Layers';

  @override
  String get textLayers => 'Text Layers';

  @override
  String get noteContent => 'Note Content';

  @override
  String get recentlyUsed => 'Recently Used';

  @override
  String get allShapes => 'All Shapes';

  @override
  String get basicShapes => 'Basic Shapes';

  @override
  String get lines => 'Lines';

  @override
  String get arrows => 'Arrows';

  @override
  String get highlighter => 'Highlighter';

  @override
  String get laserPointer => 'Laser Pointer';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get themeLabel => 'Theme';

  @override
  String get languageLabel => 'Language';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get autoSaveLabel => 'Auto Save';

  @override
  String get storageLabel => 'Storage';

  @override
  String get securityLabel => 'Security';

  @override
  String get aiLabel => 'AI';

  @override
  String get experimentalLabel => 'Experimental';

  @override
  String get hotkeysLabel => 'Hotkeys';

  @override
  String get syncLabel => 'Sync';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get testRunnerTitle => 'Test Runner';

  @override
  String get testRunnerStart => 'Start Tests';

  @override
  String get p2pSyncTitle => 'Peer-to-Peer Sync';

  @override
  String get p2pSyncSubtitle => 'Sync directly between LAN devices';

  @override
  String get viewAllPages => 'View All Pages';

  @override
  String get blockEditorTitle1 => 'Heading 1';

  @override
  String get blockEditorTitle2 => 'Heading 2';

  @override
  String get blockEditorTitle3 => 'Heading 3';

  @override
  String get blockEditorListItem => 'List item';

  @override
  String get blockEditorCodeHint => 'Enter code…';

  @override
  String get blockEditorQuoteHint => 'Quote…';

  @override
  String get blockEditorParagraphHint =>
      'Type text, or type / to open command menu…';

  @override
  String get blockEditorImageLoadFail => 'Image load failed';

  @override
  String get blockEditorTableBlock => 'Table block (see TableViewWidget)';

  @override
  String get blockEditorAddRow => 'Add Row';

  @override
  String get slidePresenterSlide => 'Slide';

  @override
  String get slidePresenterExit => 'Exit';

  @override
  String get unifiedToolbarBrush => 'Brush';

  @override
  String get unifiedToolbarEraser => 'Eraser';

  @override
  String get unifiedToolbarSelect => 'Select';

  @override
  String get unifiedToolbarRectSelect => 'Rectangle Selection';

  @override
  String get unifiedToolbarLassoSelect => 'Lasso Selection';

  @override
  String get unifiedToolbarRect => 'Rectangle';

  @override
  String get unifiedToolbarEllipse => 'Ellipse';

  @override
  String get unifiedToolbarLine => 'Line';

  @override
  String get unifiedToolbarArrow => 'Arrow';

  @override
  String get unifiedToolbarText => 'Text';

  @override
  String get unifiedToolbarEyedropper => 'Eyedropper';

  @override
  String get unifiedToolbarEraserOptions => 'Eraser Options';

  @override
  String get unifiedToolbarEraseShapes => 'Can erase shapes';

  @override
  String get unifiedToolbarGrid => 'Show Grid';

  @override
  String get unifiedToolbarSnap => 'Snap to Grid';

  @override
  String get unifiedToolbarZoomOut => 'Zoom Out';

  @override
  String get unifiedToolbarZoomIn => 'Zoom In';

  @override
  String get unifiedToolbarFitCanvas => 'Fit to Canvas';

  @override
  String get unifiedToolbarClickToPlaceText => 'Click canvas to place text';

  @override
  String get unifiedToolbarClickToPickColor => 'Click canvas to pick color';

  @override
  String get unifiedPropertyBrush => 'Brush';

  @override
  String get unifiedPropertyShape => 'Shape';

  @override
  String get unifiedPropertyText => 'Text';

  @override
  String get unifiedPropertyFillColor => 'Fill Color';

  @override
  String get unifiedPropertyDashLine => 'Solid/Dashed';

  @override
  String get unifiedPropertyTextColor => 'Text Color';

  @override
  String get unifiedLayerPanelTitle => 'Layers';

  @override
  String get unifiedLayerPanelRename => 'Rename Layer';

  @override
  String get unifiedLayerPanelRenameHint => 'Enter layer name';

  @override
  String get unifiedLayerPanelCancel => 'Cancel';

  @override
  String get unifiedLayerPanelConfirm => 'Confirm';

  @override
  String get unnamedNote => 'Untitled Note';

  @override
  String get inputText => 'Input Text';

  @override
  String get inputTextContent => 'Enter text content';

  @override
  String get cancel => 'Cancel';

  @override
  String get note => 'Note';

  @override
  String get save => 'Save';

  @override
  String get loadFailed => 'Load failed';

  @override
  String get noteTitle => 'Note Title';

  @override
  String editorV2Title(String docId) {
    return 'Editor V2 - $docId';
  }

  @override
  String get historyPanelTitle => 'History';

  @override
  String historySteps(int count) {
    return '$count steps';
  }

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get noHistory => 'No history';

  @override
  String get exportPanelTitle => 'Export';

  @override
  String get exporting => 'Exporting...';

  @override
  String exportFormat(String format) {
    return 'Export $format';
  }

  @override
  String get exportPreview => 'Preview';

  @override
  String get copied => 'Copied';

  @override
  String get copyTooltip => 'Copy';

  @override
  String get pngExportHint =>
      'PNG export requires Canvas rendering — use canvas context menu to export.';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get exportFormatPNG => 'Image format';

  @override
  String get exportFormatSVG => 'Vector format';

  @override
  String get exportFormatJSON => 'Document format';

  @override
  String get propertiesPanelTitle => 'Properties';

  @override
  String get colorLabel => 'Color';

  @override
  String get strokeWidthLabel => 'Stroke Width';

  @override
  String get opacityLabel => 'Opacity';

  @override
  String get lineStyleLabel => 'Line Style';

  @override
  String get solidLine => 'Solid';

  @override
  String get dashedLine => 'Dashed';

  @override
  String get dottedLine => 'Dotted';

  @override
  String get titleHint => 'Title';

  @override
  String get startTypingHint => 'Start typing…';

  @override
  String get zoomOut => 'Zoom Out';

  @override
  String get zoomIn => 'Zoom In';

  @override
  String get zoomReset => 'Reset (1x)';

  @override
  String get fitWindow => 'Fit to Window';

  @override
  String pageN(int index) {
    return 'Page $index';
  }

  @override
  String get newPage => 'New';

  @override
  String slideN(int index) {
    return 'Slide $index';
  }

  @override
  String get newColumn => 'New Column';

  @override
  String get noLayers => 'No layers';

  @override
  String get selectColor => 'Select Color';
}

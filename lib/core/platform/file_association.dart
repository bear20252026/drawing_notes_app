import 'dart:io';

/// 文件关联处理器（.dnproj 文件）。
///
/// .dnproj 是绘图笔记项目的文件扩展名，双击可直接打开项目。
/// 桌面平台（Windows/macOS/Linux）通过命令行参数传入文件路径。
class FileAssociation {
  FileAssociation._();

  /// 从命令行参数中提取 .dnproj 文件路径。
  ///
  /// Windows: `drawing_notes_app.exe path/to/file.dnproj`
  /// macOS:   `open -a DrawingNotes path/to/file.dnproj`
  /// Linux:   `drawing_notes_app path/to/file.dnproj`
  ///
  /// 返回找到的第一个 .dnproj 路径，若无则返回 null。
  static String? extractProjectPath(List<String> args) {
    for (final arg in args) {
      if (arg.endsWith('.dnproj') && File(arg).existsSync()) {
        return arg;
      }
    }
    return null;
  }

  /// 从命令行参数中提取所有 .dnproj 文件路径。
  static List<String> extractAllProjectPaths(List<String> args) {
    return args
        .where((arg) => arg.endsWith('.dnproj'))
        .where((arg) => File(arg).existsSync())
        .toList();
  }

  /// 注册文件关联（安装时调用）。
  ///
  /// Windows: 写入注册表 HKEY_CLASSES_ROOT\.dnproj
  /// macOS:   写入 Info.plist CFBundleDocumentTypes
  /// Linux:   创建 .desktop 文件和 MIME 类型
  ///
  /// 注意：此方法需要管理员/root 权限，通常由安装器调用。
  static Future<void> registerFileAssociation() async {
    if (Platform.isWindows) {
      await _registerWindows();
    } else if (Platform.isMacOS) {
      await _registerMacOS();
    } else if (Platform.isLinux) {
      await _registerLinux();
    }
  }

  /// 注销文件关联。
  static Future<void> unregisterFileAssociation() async {
    if (Platform.isWindows) {
      await _unregisterWindows();
    } else if (Platform.isMacOS) {
      await _unregisterMacOS();
    } else if (Platform.isLinux) {
      await _unregisterLinux();
    }
  }

  // --- Windows 注册表操作 ---

  static Future<void> _registerWindows() async {
    try {
      // 写入 .dnproj 扩展名关联
      await Process.run('reg', [
        'add',
        r'HKEY_CLASSES_ROOT\.dnproj',
        '/ve',
        '/d',
        'DrawingNotesProject',
        '/f',
      ]);

      // 写入文件类型描述和图标
      await Process.run('reg', [
        'add',
        r'HKEY_CLASSES_ROOT\DrawingNotesProject',
        '/ve',
        '/d',
        '绘图笔记项目文件',
        '/f',
      ]);

      // 写入打开命令
      final exePath = Platform.resolvedExecutable;
      await Process.run('reg', [
        'add',
        r'HKEY_CLASSES_ROOT\DrawingNotesProject\shell\open\command',
        '/ve',
        '/d',
        '"$exePath" "%1"',
        '/f',
      ]);
    } catch (_) {
      // 注册表写入失败静默忽略（非管理员权限时可能发生）。
    }
  }

  static Future<void> _unregisterWindows() async {
    try {
      await Process.run('reg', [
        'delete',
        r'HKEY_CLASSES_ROOT\.dnproj',
        '/f',
      ]);
      await Process.run('reg', [
        'delete',
        r'HKEY_CLASSES_ROOT\DrawingNotesProject',
        '/f',
      ]);
    } catch (_) {}
  }

  // --- macOS Info.plist 操作 ---

  static Future<void> _registerMacOS() async {
    // macOS 文件关联在 Info.plist 的 CFBundleDocumentTypes 中声明。
    // 安装时通过 macOS installer 或手动编辑 Info.plist 配置。
    // 应用运行时无需额外操作，macOS 自动处理。
  }

  static Future<void> _unregisterMacOS() async {
    // macOS 文件关联在 Info.plist 中声明，卸载时自动移除。
  }

  // --- Linux .desktop 和 MIME 操作 ---

  static Future<void> _registerLinux() async {
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;

      final desktopDir = '$home/.local/share/applications';
      final dir = Directory(desktopDir);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      final desktopFile = File('$desktopDir/drawing_notes_app.desktop');
      final exePath = Platform.resolvedExecutable;

      await desktopFile.writeAsString('''
[Desktop Entry]
Name=绘图笔记
Comment=Drawing and note-taking workspace
Exec=$exePath %f
Icon=drawing_notes_app
Terminal=false
Type=Application
Categories=Utility;Graphics;
MimeType=application/x-drawing-notes-project;
''');

      // 更新 MIME 数据库
      final mimeDir = Directory('$home/.local/share/mime/packages');
      if (!mimeDir.existsSync()) {
        await mimeDir.create(recursive: true);
      }

      final mimeFile =
          File('$home/.local/share/mime/packages/drawing-notes-project.xml');
      await mimeFile.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-drawing-notes-project">
    <comment>绘图笔记项目文件</comment>
    <glob pattern="*.dnproj"/>
  </mime-type>
</mime-info>
''');

      await Process.run('update-mime-database', ['$home/.local/share/mime']);
      await Process.run('update-desktop-database', [desktopDir]);
    } catch (_) {}
  }

  static Future<void> _unregisterLinux() async {
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;

      final desktopFile =
          File('$home/.local/share/applications/drawing_notes_app.desktop');
      if (desktopFile.existsSync()) {
        await desktopFile.delete();
      }

      final mimeFile = File(
          '$home/.local/share/mime/packages/drawing-notes-project.xml');
      if (mimeFile.existsSync()) {
        await mimeFile.delete();
      }

      await Process.run('update-mime-database', ['$home/.local/share/mime']);
      await Process.run(
          'update-desktop-database', ['$home/.local/share/applications']);
    } catch (_) {}
  }
}

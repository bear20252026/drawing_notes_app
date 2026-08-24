# 旧版本卸载指引

## 问题说明

搜索"绘图笔记"出现两个版本，原因是系统中存在旧的安装残留。

## 旧版本位置

1. **Windows 旧版本**：`D:\DrawingNotesApp`
   - 这是一个旧的 Windows 安装包
   - 包含 `drawing_notes_app.exe` 和卸载程序 `unins000.exe`

2. **测试版本**：`D:\install_test`（如存在）
   - 可能是测试期间创建的临时版本

## 卸载步骤

### Windows 旧版本卸载

1. **方法一：使用卸载程序**
   - 打开 `D:\DrawingNotesApp` 目录
   - 运行 `unins000.exe`
   - 按照提示完成卸载

2. **方法二：手动删除**
   - 如果卸载程序无法运行，可手动删除整个 `D:\DrawingNotesApp` 目录
   - 删除注册表项（可选，高级用户）：
     ```
     HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\drawing_notes_app
     ```

### 测试版本清理

1. 删除 `D:\install_test` 目录（如存在）

### Android 旧版本卸载

如果在 Android 设备上看到两个版本：

1. 打开 **设置** → **应用管理**
2. 查找所有名为"绘图笔记"的应用
3. 卸载旧的版本（通常日期较早的那个）
4. 保留最新版本

## 验证清理结果

1. **Windows**：
   - 检查 `D:\DrawingNotesApp` 目录是否已删除
   - 运行新版本，确认只有一个实例

2. **Android**：
   - 在应用管理中确认只有一个"绘图笔记"
   - 搜索应用时只显示一个结果

## 应用信息确认

- **应用名称**：绘图笔记
- **Android 包名**：`gov.drawingnotes.drawing_notes_app`
- **Windows 可执行文件**：`drawing_notes_app.exe`

所有版本应使用相同的包名和应用名称，确保不会出现重复。

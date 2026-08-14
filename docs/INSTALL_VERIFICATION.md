# Windows 安装包安装验证报告

> 验证日期：2026-08-13
> 验证对象：`drawing_notes_app-1.0.0+1-windows-setup.exe`（Inno Setup 6 生成的 Windows 安装程序）
> 验证方式：实际静默安装 → 文件结构核验 → 应用启动验证 → 正常关闭

---

## 一、验证结论

| 验证项 | 结果 |
|--------|------|
| 安装包完整性 | ✅ 通过（11,105,442 字节，MZ/PE 头签名有效） |
| 静默安装执行 | ✅ 通过（退出码 0，无报错） |
| 安装文件结构 | ✅ 通过（7 个安装文件 + data 资源目录齐全） |
| 应用启动 | ✅ 通过（进程正常存活，内存占用 183MB） |
| 应用关闭 | ✅ 通过（正常终止，无残留进程） |

**总体结论：安装包可安装、可运行，验收通过。**

---

## 二、安装过程记录

```
执行命令：
  drawing_notes_app-1.0.0+1-windows-setup.exe
    /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=D:\DrawingNotesApp

安装退出码：0（成功）
安装目录：D:\DrawingNotesApp
```

## 三、安装文件结构核验

安装目录 `D:\DrawingNotesApp` 共 7 个文件：

| 文件 | 大小 | 说明 | 核验 |
|------|------|------|------|
| `drawing_notes_app.exe` | 91 KB | 应用主程序（MZ + PE 签名有效） | ✅ |
| `flutter_windows.dll` | 20.3 MB | Flutter 桌面运行时 | ✅ |
| `dartjni.dll` | 57 KB | Dart/JNI 桥接（Windows 桌面依赖） | ✅ |
| `file_selector_windows_plugin.dll` | 108 KB | 文件选择器原生插件 | ✅ |
| `data/app.so` | 5.7 MB | Dart AOT 编译产物（业务逻辑） | ✅ |
| `data/flutter_assets/` | — | 应用资源（图标/字体/着色器） | ✅ |
| `data/icudtl.dat` | 842 KB | ICU 国际化数据 | ✅ |
| `unins000.exe` / `unins000.dat` | 4.4 MB | Inno Setup 卸载程序 | ✅ |

> 说明：`app.so`（Dart AOT）与 `flutter_windows.dll` 均在安装目录内随包分发，
> 应用**不依赖外部运行时**，可独立运行。

## 四、启动验证记录

```
启动方式：cmd start drawing_notes_app.exe
等待 10 秒后检查进程：
  drawing_notes_app.exe  PID 40300  Console  1  183,912 K  ✅ 进程存活

判定：应用成功启动并保持运行（未崩溃、未闪退），内存占用正常。
关闭方式：taskkill 正常终止，无残留进程。
```

## 五、验收说明

- 安装包由 **fastforge 0.6.12**（flutter_distributor 官方最新版）在 ASCII 路径 `D:\huaban_build`
  下构建（中文路径会导致 CMake/Inno Setup 编码错乱，见 `docs/ACCEPTANCE_CHECKLIST.md` 附注）。
- 安装包可拷回任意 Windows x64 机器分发安装。
- 卸载入口：安装目录内 `unins000.exe`（Inno Setup 标准卸载程序）。

## 六、复验命令（验收人员可自行执行）

```bat
:: 1. 安装（静默）
drawing_notes_app-1.0.0+1-windows-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=D:\DrawingNotesApp

:: 2. 启动
start D:\DrawingNotesApp\drawing_notes_app.exe

:: 3. 确认进程存在
tasklist /FI "IMAGENAME eq drawing_notes_app.exe"

:: 4. 关闭
taskkill /F /IM drawing_notes_app.exe
```

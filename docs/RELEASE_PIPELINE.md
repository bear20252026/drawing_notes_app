# 发布规范（Release Pipeline）

> 生效日期：2026-08-31。本规范对本地脚本与云端 workflow 同时约束，**新增发布产物形态时必须同步更新本文件**。

## 铁律

0. **修改即同步**：每次代码修改提交后必须立即运行 `bash tools/sync_github.sh ["说明"]`
   ——脚本自动提交（有修改时）→ 推送（3 次重试）→ 校验远端 HEAD == 本地 HEAD。
   **禁止留本地未推送提交**（"推了"不等于"推到了"，必须以脚本 VERIFIED 输出为准）。

1. **所有安装包生成后，必须压缩为 zip 格式随发布一起产出**——原始安装包与 zip 双轨提供（zip 便于下载/分享/完整性校验，原始包便于直接安装）。
2. 版本号**三处同步**（漏一处会导致云端产物名带旧版本）：
   - `pubspec.yaml` → `version: X.Y.Z+N`
   - `tools/drawing_notes_setup.iss` → `#define MyAppVersion "X.Y.Z"`
   - `CHANGELOG.md` → `## [X.Y.Z] - 日期`

## 发布流程

### 本地打包（tools/release_windows.ps1）

1. 质量门：`flutter pub get` → `flutter analyze` → `flutter test`（全量）。
2. Fastforge 打包 Windows EXE 安装程序（Inno Setup）。
3. 生成 `dist/SHA256SUMS.txt`（所有 EXE 的 SHA256）。
4. **压缩步骤**：每个 EXE 同目录生成同名 `.zip`（`Compress-Archive`）。

### 云端（.github/workflows/release-build.yml，tag `v[0-9]*` 触发）

| Job | 产物 | zip |
|---|---|---|
| Android | app-release.apk（+ AAB） | `drawing_notes_android_release.zip` |
| Windows | setup_drawing_notes_X.Y.Z.exe | `drawing_notes_windows_setup.zip` |

zip 在各 job 内随原始包一起上传 Artifact 并挂载到 GitHub Release（APK/ZIP 由
`attach-android` job 幂等补挂，发版即 4/4 齐）。

**2026-10-17 起两条口径变了**（CTL-04 落地 / CTL-03 受阻，业主点名采纳）：

1. **推 tag 不再等于对外发布**。出包前多了一道 `preflight` job：它先把 tag **剥成提交**
   （本仓 annotated / lightweight 两种 tag 混用），再要求那个提交的 check 结论
   **既没有红的、且全量 CI 那条 job 的成功记录在册**——「结论表是空的」不算通过。
   然后 Release 以 `draft: true` 创建，四件资产挂完之后，人在 GitHub 上点 **Publish**
   才公开；tag 过滤也从 `v*` 收紧到 `v[0-9]*`（`v-test` 这类误 tag 不再触发）。
   此前是 `draft: false`（手滑推 tag 就直接公开），而「先确认编排全绿再推 tag」只是
   **业主口径的口头纪律**——AGENTS.md 里并没有写这条，机器上也没有闸门。
   草稿的连带效果（是有意的，不是 bug）：`Latest` 指针只认已发布的 Release ⇒
   推 tag 之后公开面上仍是上一个版本可下载，直到人工点 Publish。
2. **出货产物仍未混淆**（CTL-03 今天只做了一半，另一半被实测证据挡住）：两条腿还是
   `flutter build apk/appbundle/windows --release`，没有 `--obfuscate`。
   原因是 Flutter 3.47 的混淆文档明写「依赖类名/函数名/库名做匹配的代码会失效」，而本仓
   有 28 处在运行时读类型名（22 个 `e.runtimeType.toString()` + 6 个 `${e.runtimeType}`），
   其中三条 snackbar（粘贴失败 / 插图失败 / 打开链接失败）、`saveFailure` 芯片的
   `errorKind`、`AuditLogger` 的 `detail`，以及 `main.dart` 拼进**审计 action id** 的
   类型名，都会变成每次构建都不同的随机串——而 `flutter test` 与 `-d windows` 的 smoke
   跑的都是**非混淆编译** ⇒ CI 永远抓不到，只有装到用户机器上才现形。
   落盘枚举用 `.name` 那半边（`paperType`/`shapeType`/`strokeStyle`/`type`/`align`/
   `chartType`/`kind`/`encryptionMode`/`template`/`viewType` 等 14 处 encode）今天是安全的
   ——官方文档写的是「Enum names are not obfuscated **currently**」，但 "currently"
   不是承诺，要显式 wire 名才敢长期依赖。**解锁顺序**：① 诊断面改成 `is` 判定出的字面量
   代码（类型判断不受混淆影响）②落盘枚举加显式 wire 名 ③再加 `--obfuscate` 并配符号表
   artifact（那时才需要谈「符号挂不挂公开 Release」）。

另有 `.github/workflows/weekly-evidence.yml`（每周日 + 手动）补直推流程从来拿不到的
三类证据：依赖清单/秘密扫描/SBOM、**Windows 发布形态构建**、Android 构建。
它不是门禁——红了不阻断 master，只开一条去重后的待办 issue。它的构建命令必须与
`release-build.yml` 的出货命令**逐字同形**（改一处要改两处），否则采的是不出货的形状。

### 本地跑法速查

```bash
# Windows 本地（bash 下 fastforge.bat 需全路径；fastforge 内部要能找到 flutter）
"/c/Users/17296/AppData/Local/Pub/Cache/bin/fastforge.bat" package --platform windows --targets exe
# 或 PowerShell（需把 D:\flutter\bin 与 LOCALAPPDATA\Pub\Cache\bin 加入 PATH）
.\tools\release_windows.ps1
```

### 云端监控与产物下载

```bash
gh run watch $(gh run list --workflow=release-build.yml --limit 1 --json databaseId -q '.[0].databaseId') --exit-status
gh release download "vX.Y.Z" -D Downloads --pattern "*.exe" --pattern "*.apk" --pattern "*.zip" --clobber
```

## 检查清单（发版前逐项勾选）

- [ ] `pubspec.yaml` 版本已提升
- [ ] `tools/drawing_notes_setup.iss` 的 `MyAppVersion` 已同步
- [ ] `CHANGELOG.md` 已添加版本段落
- [ ] `flutter test` 全量绿 + `dart analyze` 0 问题
- [ ] Release 资产同时包含：原始安装包 + **zip 包**（Windows 与 Android 各一）
- [ ] 草稿 Release 逐项核对过四件资产与版本号，**再人工点 Publish**（推 tag 不再自动公开）
- [ ] `preflight` job 绿——它校验的是 **tag 剥出来的那个提交**的 CI 结论（不是本次
      release run 自己）；红了先去看是不是那个提交根本没跑过 CI 或被连推掐成了 cancelled
- [ ] 出货产物是否已混淆：目前**没有**（CTL-03 受阻，原因见上文「两条口径」第 2 条）
- [ ] 下载产物实测安装/启动

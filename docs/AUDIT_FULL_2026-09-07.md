# 全量审计台账（2026-09-07）

> 范围：全仓 297 个 lib 文件（约 6.9 万行）+ 272 个测试文件 + 10 个 CI 工作流 + 文档/构建资产。
> 方法：8 个审计域并行深扫（设计规范/三输入无障碍/异步可靠性/性能/国际化/架构质量/安全数据/测试文档构建），
> 逐条 file:line 取证后分 4 波修复（Wave A 可靠性+安全 → Wave B 设计+无障碍+绘画性能 → Wave C 笔记性能+补测试+质量收敛 → 散项收口）。
> 结果：**110 个审计大类、367 条带证据发现、280 项问题修复、102 项提升落地**；门禁全程全绿（analyze 0 issue、测试 1870→1952 全过）。
> 发版：v1.17.0。

---

## 一、审计大类清单（110 项）

图例：✅=通过（无发现）；🔧=发现并已修复；📋=发现，留档未决（见第四节）。

### A. 设计规范域（DESIGN_SYSTEM / DESIGN.md / AppleMotion）（18 类）

| # | 大类 | 结论 |
|---|---|---|
| A1 | 主强调色唯一性（Action Blue 全 App 唯一） | 🔧 17 处 42A5F5 杂散蓝收敛为 actionBlue |
| A2 | 颜色字面量禁令（页面层禁 Color(0x…)） | 🔧 16 组 UI 字面量收编（含深色面板→surface） |
| A3 | 功能语义色（收藏橙/成功绿/危险红） | 🔧 F5A623/FF9800→favourite、30D158→noteGreen |
| A4 | 焦点环规范（focusBlue 2px） | 🔧 3 处 focusedBorder 违规 |
| A5 | 深浅模式一致性 | 🔧 阅读页/小地图/浮层硬编码底色改 colorScheme |
| A6 | 圆角档位（0/5/8/11/18/pill） | 🔧 28→18、6→5、12→11，含手写合法值令牌化共 8 处 |
| A7 | 排版层级（17/13/11.5 三层 + 1.47 行高） | 🔧 77 处手写 TextStyle 令牌化 |
| A8 | AppleType 工具引用 | 🔧 全部改为 controlStyle/captionStyle/titleStyle/bodyStyle.copyWith |
| A9 | 动效曲线白名单（禁 easeOutCubic/easeIn*） | 🔧 全部命中点清除（11 处动效项内含） |
| A10 | 动效时长令牌（AppleMotion.*） | 🔧 手写 180/250/260/400ms 全部令牌化 |
| A11 | <300ms 硬规则 | 🔧 PIN 抖动 400ms→250ms |
| A12 | 频率闸门（键盘触发不动画） | 🔧 阅读页键盘翻页改 jumpToPage |
| A13 | 只动 transform/opacity | ✅ 抽查未发现违规 |
| A14 | 禁 scale(0) 入场 | ✅ 无发现 |
| A15 | 按压态 0.95（ApplePressable） | ✅ 抽查合规 |
| A16 | 玻璃边界（浮层可用/内容层禁用） | ✅ 未发现内容层违规；配方字面量属令牌域豁免 |
| A17 | 环境渐变收编 | 🔧 新增 ambientDark/LightGradient 令牌 |
| A18 | 触觉/材质常量归属 | 📋 liquid_glass_rim 4s 属材质域，豁免留档 |

### B. 三输入兼容与无障碍域（14 类）

| # | 大类 | 结论 |
|---|---|---|
| B1 | 右键入口（onSecondaryTap*）配对长按 | ✅ 4 处全部已配对 |
| B2 | 长按专属入口配对菜单/按钮 | 🔧 页卡「以块文档打开」补 ⋮ 菜单项 |
| B3 | 核心操作键盘可达 | 🔧 Ctrl/Cmd+S 手动保存；📋 色板键盘调色/小地图键盘平移/裁剪键盘微调 |
| B4 | 触控目标 ≥44×44 | 🔧 16 组控件扩热区（视觉不变） |
| B5 | 纯图标控件 Semantics | 🔧 11 组补 label/button/checked/expanded |
| B6 | IconButton tooltip | 🔧 6 处补齐 + GlassFab 支持透传 |
| B7 | 对话框确认/取消键盘可达 | 🔧 AppleDialog/GlassDialog 系统性 autofocus（危险操作落安全侧） |
| B8 | SimpleDialog 首项 autofocus | 🔧 13 个对话框补齐 |
| B9 | 文本溢出防护（长文案/可变长） | 🔧 状态栏/选区栏/侧栏导航/冲突对话框 4 处 |
| B10 | 块内元素键盘操作 | 📋 块上移/下移快捷键（需焦点模型设计） |
| B11 | 读屏可用性（Semantics 完整性） | 🔧 见 B5；📋 全库 Semantics 普查留专项 |
| B12 | 减弱动效三信号 | ✅ AppleMotion.reduceMotionOf 已接入 |
| B13 | 拖拽手柄等价入口 | 📋 块排序 Alt+↑/↓（同 B10） |
| B14 | 悬停反馈（桌面） | ✅ AnimatedScale hover 已有 |

### C. 异步可靠性域（10 类）

| # | 大类 | 结论 |
|---|---|---|
| C1 | await 后 setState 的 mounted 保护 | 🔧 16 处补齐 |
| C2 | TextEditingController 生命周期 | 🔧 4 处对话框泄漏（路由退出后 dispose） |
| C3 | 复杂 controller 映射生命周期 | 🔧 表格编辑器行列增删重建 |
| C4 | fire-and-forget Future | 🔧 11 处收敛（含假「已保存」根因 onSave 类型修复） |
| C5 | Timer.periodic/Stream 取消路径 | ✅ 3 处均正确 |
| C6 | 对话框 builder 内 ctx.mounted | 🔧 日程时间选择器 1 处 |
| C7 | Completer 死等 | ✅ 4 处均有收敛路径 |
| C8 | async 方法异常逃逸 | 🔧 并入 C4 |
| C9 | setState after dispose 静态可检性 | 📋 unawaited_futures lint 启用留档（198 项计量） |
| C10 | 保存回调类型契约 | 🔧 DocEditor.onSave 改 FutureOr |

### D. 性能与内存域（12 类）

| # | 大类 | 结论 |
|---|---|---|
| D1 | build/paint 高频分配 | 🔧 ConnectorPainter 零拷贝、ChartPainter 预建 |
| D2 | shouldRepaint 精度 | 🔧 6 个 painter 字段比较 + 视口快照 |
| D3 | TextPainter 缓存 | 🔧 笔记本文字块/edgeless 标签 Expando 缓存 |
| D4 | 笔迹 Path 缓存 | 🔧 edgeless 笔迹 Expando 缓存 |
| D5 | 长列表虚拟化 | 🔧 分组文档列表打平 builder 化 |
| D6 | 搜索/输入防抖 | 🔧 数据库块+search_page 接入 SearchDebouncer |
| D7 | 缓存预算与淘汰 | 🔧 StrokePictureCache 32MB 字节预算 |
| D8 | 主线程重计算 | 🔧 笔记本 JSON 编码入 isolate + 去 pretty-print |
| D9 | ticker 数量 | 🔧 骨架屏 24→1 共享 controller |
| D10 | 排序短路 | 🔧 图片项/元数据有序检测 |
| D11 | 高频整页重建范围 | 📋 edgeless 通知分域（需架构改造） |
| D12 | 增量光栅化 | 📋 封顶画布增量脏矩形（大项留专项） |

### E. 国际化域（6 类）

| # | 大类 | 结论 |
|---|---|---|
| E1 | UI 硬编码中文 | 📋 1040 处/120 文件（超大项，见未决清单） |
| E2 | arb key 对称性 | ✅ zh/en 各 198 key 完全一致 |
| E3 | 未翻译条目 | ✅ untranslated_messages.json 为空 |
| E4 | 文本溢出（国际化预留） | 🔧 4 处（同 B9） |
| E5 | 日期/时间格式统一 | 🔧 time_format 工具收敛 10 处；📋 intl locale 化随 E1 |
| E6 | 持久化数据与展示文案分离 | 📋 '未命名'/'图层 1' 写盘默认值（存量数据兼容） |

### F. 架构与代码质量域（12 类）

| # | 大类 | 结论 |
|---|---|---|
| F1 | 超长文件（>700 行 15 个） | 📋 拆分属重构，需用户同意后专项 |
| F2 | 重复代码 | 🔧 时间格式化/十六进制/HTML 转义/SnackBar 四类去重 |
| F3 | 死代码/未使用公开 API | 📋 HomeLockButton 等 4 处删除需同意 |
| F4 | 空 catch 无意图标注 | 🔧 18 处逐处注释 + 1 处补审计日志 |
| F5 | 错误处理一致性 | 🔧 清理后 rethrow 策略对齐 |
| F6 | 魔法数字/时长 | 🔧 5 处具名常量 + safe_url 4096 |
| F7 | 跨 feature 循环依赖 | 📋 notes↔doc 等 6 组（需契约层设计） |
| F8 | Deprecated API | ✅ withOpacity 0 处、WillPopScope 0 处 |
| F9 | part 文件蔓延 | 📋 editor_page_* 六分文件合并留专项 |
| F10 | 存储层清洗规则统一 | 📋 导出名/同步名两套清洗并存 |
| F11 | DCM 复杂度阈值 | 📋 60→40 逐步回调计划 |
| F12 | analysis lint 强度 | 📋 启用评估完成（198 项计量），整改后启用 |

### G. 安全与数据完整性域（16 类）

| # | 大类 | 结论 |
|---|---|---|
| G1 | 凭据驻留内存面 | 📋 WebDAV 密码 controller 常驻（权衡留档） |
| G2 | 不可信字符串透传 UI | 🔧 WebDAV 远端异常消息静态化 |
| G3 | 输入长度/字符校验 | 🔧 标签名清洗 + 上限；📋 其余命名入口随 E1 |
| G4 | 路径遍历防护 | ✅ 白名单齐备（+新增契约测试锁定） |
| G5 | 临时文件失败清理 | 🔧 7 个 store 补齐 |
| G6 | 固定名 tmp 劫持面 | 🔧 标签库随机后缀化 |
| G7 | JSON 无防护强转 | 🔧 5 组高危点类型检查化 |
| G8 | .bak 备份失败处理 | 🔧 fail-closed |
| G9 | 回收站时间源正确性 | 🔧 sidecar 读写格式对齐 |
| G10 | 版本历史无界（内存） | 🔧 fromJson 截断 8 版 |
| G11 | 版本历史无界（磁盘 vault） | 📋 旧版保留是设计决策，GC 需用户同意 |
| G12 | 非原子直写 | 🔧 同步基线/图片存储原子化 |
| G13 | 并发写竞态（写尾队列） | 🔧 delete/restoreTrash/storeImage/TagStore 4 处入队 |
| G14 | 密码操作与保存并发 | 📋 密码流串行化留专项（改动面大） |
| G15 | 时区/UTC 一致性 | 📋 LWW 裁决时差扭曲（需数据迁移方案） |
| G16 | 脏数据入口过滤 | 🔧 listAll isValidId 门禁 |

### H. 测试域（8 类）

| # | 大类 | 结论 |
|---|---|---|
| H1 | 零覆盖安全核心 | 🔧 vault_manifest 12 用例 |
| H2 | 零覆盖扩展点 | 🔧 plugin_registry 8 用例 |
| H3 | 零覆盖存储类 | 🔧 baseline store 7 + repository 契约 8 + config store 5 |
| H4 | 零覆盖安全语义 | 🔧 session_secrets 6（DEK 清零）+ local_id_generator 6 |
| H5 | 零覆盖流程/UI | 🔧 sync_fix 7 + 冲突对话框 autofocus |
| H6 | 导出消毒 | 🔧 HTML 导出 11 用例（XSS 注入） |
| H7 | 脆弱测试（墙钟/真文件时间） | 📋 FakeClock 收敛留专项 |
| H8 | 基准测试混入默认套件 | 📋 Argon2 基准移 tags 留专项 |

### I. 文档域（8 类）

| # | 大类 | 结论 |
|---|---|---|
| I1 | README 测试计数 | 🔧 1255+→1950+ |
| I2 | README_EN 计数一致性 | 🔧 391+→1950+ |
| I3 | 目录名说明时效 | 🔧 改写为条件性说明 |
| I4 | ARCHITECTURE 计数/废模块行 | 🔧 修正 |
| I5 | docs/ 112 文件无索引 | 🔧 docs/README.md 现行 vs 快照分界 |
| I6 | CHANGELOG 体例一致性 | 🔧 1.16.1 补测试小节 |
| I7 | 功能概览时效（1.16.x 缺席） | 📋 随下轮文档专项 |
| I8 | 审计报告归属约定 | ✅ html 保持 untracked；本台账为 md 入库 |

### J. 构建发布域（14 类）

| # | 大类 | 结论 |
|---|---|---|
| J1 | 版本三处一致性 | ✅ 校验通过（CI 有门禁）+ 🔧 本次 bump 1.17.0 |
| J2 | CI 工作流 concurrency | 🔧 9 个补取消组 |
| J3 | Flutter 版本 pin | ✅ 全部 3.47.0 |
| J4 | Python/pip pin+cache | ✅ 已有 |
| J5 | 第三方 action SHA pin | 📋 升级+SHA 化留专项 |
| J6 | upload-artifact 版本漂移 | 📋 统一大版本留专项 |
| J7 | 未引用大资产 | 📋 3.4MB 原始图标删除需同意 |
| J8 | 必要大字体 | ✅ DroidSansFallback 被 PDF 导出引用，保留 |
| J9 | linter 规则集 | 📋 评估完成留档 |
| J10 | DCM 配置死键 | ✅ W3 已合并（历史项复核） |
| J11 | 发版流程三处同步 | 🔧 本次执行 |
| J12 | 门禁命令一致性 | ✅ CI 与本地一致 |
| J13 | secret-scan/sbom/code-guard | ✅ 配置正常 |
| J14 | release-build 触发 | ✅ dispatch+tag 正常 |

---

## 二、问题修复清单（280 项）

> 每项均已验证：flutter analyze 0 issue + 相关测试全绿；全量 1952 测试通过。

### P1 可靠性（34 项）
- **mounted 保护 ×16**：editor_page_actions（_createChart/_openShapeLibrary/_showCommandPalette/_pasteFromClipboard）、editor_page_editing（_addStickyNote/_changeSelectedTextColor/_insertImage×3/_showItemContextMenu/_setLink）、editor_page_input（_pickColor/_showColorPicker）、notebook_view_page_manage（_createPage×2/_renameNotebook）、attachment_block_view（_editDescription）。
- **controller 泄漏 ×4**：_setLink、_renameCanvas、showTextCellEditor、_editDescription（ModalRoute.completed 后 dispose，避免打挂退出动画期重建）。
- **表格编辑器生命周期 ×1**：_rebuildControllers() 行列增删全量重建（消除索引错位+泄漏）。
- **fire-and-forget ×11**：home_page（创建笔记/回收站加载/恢复/永久删除）、doc_page（_toggleDocTag 先落盘后更新 UI+失败回滚、_createTagInline 补 catch）、doc_editor（_manualSave 真等待）、_openHref（await Process.start）、_showShortcutHelp/_showPaginationPreview（await 化）、notebook_view_page（_saveIfChanged catchError）。
- **对话框 ctx.mounted ×1**：schedule 时间选择器。
- **回调类型契约 ×1**：DocEditor.onSave → FutureOr<void> Function。

### P2 存储安全与数据完整性（22 项）
原子写补齐 ×7（saveThumbnail/_writeSealedBytes/note_block_doc/notebook/edgeless/同步基线/标签随机 tmp+rename 回退）；.bak fail-closed ×1；JSON 防护 ×5（sync manifest/sync_cipher/sync_planner/note_block_doc+note_block whereType/notebook+edgeless FormatException 包装）；回收站时间源 ×1；标签清洗+重名幂等+写尾队列 ×1（三合一计 1 项按审计条目）；listAll isValidId ×1；delete/restoreTrash 入队 ×1；notebook delete 入队 ×1；storeImage 原子化 ×1；WebDAV 消息静态化 ×1；_syncNow https 预检+未保存拦截 ×1；版本历史截断 ×1。（对应审计 G 组 22 条编号）

### P3 设计规范（115 项）
- 颜色 16：text_overlays 输入框三态+便签边框×2、overlays 选中框×4、drag_ops 手柄、canvas_surface 小地图、editor_components 番茄钟、doc_editor_selection、doc_page_widgets×2、doc_page×3、edgeless 激活底色、reader 背景×2、文字宽度手柄（+ambient 渐变收编）。
- 圆角 8：glass_dialog 28→18、skeleton ×5、tags_view、glass_surface。
- 动效 11：text_overlays×2、overlays、image_preview、home_page_widgets、reader 键盘去动画、unlock_sheets×2、pin_pad 抖动、doc_editor×2、doc_page、presentation_page。
- 焦点环 3：text_overlays、home_page_widgets、webdav。
- 排版 77：all_docs 域 21、doc 域 22（B2a 52 项中 doc 侧）、notes/security/shared 域 25、apple_empty_state 2、note_frame_preview 1 等（13/13.5/14→control、11–12.5→caption、15/16w600→title、17→body/title、10/19/28 保留字号走 copyWith）。

### P4 三输入无障碍（49 项）
触控目标 16（裁剪手柄/便签 todo/颜色按钮/图层眼睛/图层小图标/坐标开关/选区工具条/块 todo/折叠箭头/拖拽手柄/表格 checkbox/工具按钮/形状按钮/色阶圆点/最近色/预设色板）；Semantics 11（同上控件补 label/button/checked/expanded）；tooltip 6（清除搜索/返回/清除筛选/保存/密码可见切换/GlassFab 透传）；对话框 autofocus 10（AppleDialog.confirm 系统性 + 首选项 Focus×6 + 关闭钮×3 + 冲突「应用全部」）；溢出 4（状态栏/选区栏/侧栏导航/冲突对话框）；菜单等价 1（以块文档打开）；快捷键 1（Ctrl/Cmd+S）。

### P5 性能（10 项）
1 ConnectorPainter 零拷贝；2 shouldRepaint×5 painter 字段比较+视口快照；3 MiniMap 指纹；4 ChartPainter 标签预建；5 PaginationPreview memo；6 笔记本 TextPainter Expando；7 edgeless 标签 TextPainter ×2 painter；8 edgeless 笔迹 Path Expando；9 framesSortedByZ 记忆化；10 ink 层渲染计划单槽缓存 + isolate 编码 + 骨架共享 ticker + 数据库防抖 + 列表打平 + 编码复用 + 排序短路 + 32MB 预算（后八者归入对应审计条目计数）。

### P6 代码质量（50 项）
time_format 迁移 10；hexEncode 迁移 6；escapeHtml 收敛 2；AppSnack 收敛 7；空 catch 标注 18；search_page 防抖化 1；maxUrlLength 1；时长具名常量 5（defaultBackoffThreshold/defaultMaxDelay/bindSuccessSnackDuration/_cosmeticRefreshDelay/_historyDebounceDelay）。

---

## 三、提升清单（102 项）

| 组 | 项 | 数量 |
|---|---|---|
| 新增测试用例 | vault_manifest 12 / plugin_registry 8 / file_sync_baseline_store 7 / local_id_generator 6 / session_secrets 6 / sync_fix 7 / DocumentRepository 契约 8 / WebDAV TLS 门禁 5 / HTML 导出消毒 11 | 70 |
| 新工具 | time_format.dart / hex_encode.dart / html_escape.dart / app_snack.dart | 4 |
| 新令牌 | AppleColor.ambientDarkGradient / ambientLightGradient | 2 |
| 组件能力 | GlassFab.tooltip 参数；sync_store 编码 LRU 复用缓存；app.dart 快照单 now() | 3 |
| CI | 9 个工作流 concurrency 取消组 | 9 |
| 文档 | README 计数 / README_EN 计数 / README 目录说明 / ARCHITECTURE / docs 索引 / CHANGELOG 1.16.1 补注 / CHANGELOG 1.17.0 条目 / 本台账 | 8 |
| 发版 | pubspec 1.17.0+68 / iss MyAppVersion / 三处一致性复核 | 3 |
| 额外收敛 | tag_store hex / baseline hex / lint 启用评估数据 | 3 |
| **合计** | | **102** |

---

## 四、未决清单（留档，按优先级）

1. **i18n 全面国际化**（E1）：1040 处硬编码中文/120 文件 + arb 扩充 + intl locale 化。建议按共享组件→主页面→功能页三批推进；存量持久化默认值（'未命名'）需存储/展示分离方案。
2. **时区一致性**（G15）：updatedAt 无偏移 ISO 串跨时区扭曲 LWW 裁决。方案：写侧 toUtc、读侧双格式兼容 + 存量迁移，随同步大版本落地。
3. **vault 版本 GC**（G11）：objects/ 无界增长是「可回溯」设计使然；需用户决策保留策略（如保留最近 N 版）。
4. **密码操作写队列串行化**（G14）：storage_service_file_password 六入口绕过 _writeTails；需重构为经队列的独占段。
5. **edgeless 通知分域**（D11）与**封顶画布增量光栅化**（D12）：两项大型渲染架构改造。
6. **死代码删除**（F3）：HomeLockButton、ApplePillSearchField、MemorySystemUnlockKeyStore（仅测试引用）、ScheduleEntry、3.4MB 原始图标资产——删除需用户同意。
7. **超长文件拆分**（F1）与 **part 文件合并**（F9）：属重构，需同意后专项。
8. **lint 启用**（F12/C9）：unawaited_futures + avoid_slow_async_io 共 198 处 info（已计量）；逐处整改后启用防回退。
9. **跨 feature 循环依赖**（F7）：notes↔doc 最重（29+3 处）；建议契约层上移 core。
10. **无障碍深化**（B3/B10/B11）：色板键盘调色（RGB 输入框）、小地图键盘平移、裁剪键盘微调、块 Alt+↑/↓ 排序、全库 Semantics 普查。
11. **测试基建**（H7/H8）：FakeClock 收敛 6 个直接依赖 DateTime.now 的测试；Argon2 基准移独立 tag。
12. **CI 供应链**（J5/J6）：第三方 action commit SHA pin + upload-artifact 版本统一。
13. **WebDAV 密码驻留**（G1）：按需读取方案权衡。
14. **功能概览文档**（I7）：README 补 1.16.x 亮点节。

---

## 五、验证记录

- 基线（修复前）：flutter analyze No issues；flutter test 1870 全过。
- 终态（发版前）：flutter analyze No issues；flutter test **1952 全过**（+82：70 新用例 + Wave A 安全回归 11 + 适配 1）。
- 门禁纪律：每波修复后独立跑 analyze+相关测试子集；并发编辑冲突由波次隔离（A→B→C）消除。
- 版本：1.16.4+67 → 1.17.0+68（pubspec / iss / CHANGELOG 三处同步，CI check_version_consistency 通过）。

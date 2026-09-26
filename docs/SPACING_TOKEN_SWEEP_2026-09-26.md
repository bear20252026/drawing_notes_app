# 离档间距清单（审计 2026-09-26 #34）

> 性质：**清单，未改代码**。离档值（6/10/14/18/20/22 等）归一到哪个合法档位
> （4/8/12/16/24/32/48）需要逐处视觉确认——10 与 8/12 等距，取舍取决于设计意图，
> 机械批量替换的视觉回归风险大于令牌纯度收益。建议后续带视觉验收的专项一次性处理。

## 处理结果（v1.17.29，审计批次 G）

2026-09-27 逐处确认并归一（96 处改动），规则与豁免如下。**未改任何布局结构**，
仅数值就近归档；触控目标约束处（44px 热区）归一后仍达标。

### 归一规则（逐处确认后提炼）

| 语义 | 决策 |
|---|---|
| 弹出菜单图标→文字 | 10 → **8**（全库弹窗统一） |
| 侧栏导航/树行图标→文字 | 10 → **12**（对齐同文件导航行既有 12） |
| 卡片/行内小图标→文字 | 6 → **4**（非交互微间隙：锁标、info、链接标头） |
| 紧邻操作按钮的前间隙 | 6 → **8**（文字/说明 → 按钮） |
| 列表分隔高度（卡片间） | 10 → **12**（home_page_tabs、skeleton） |
| 列表分隔高度（树行间隔条） | 10 → **12** |
| 容器水平内距（顶栏/Tab 栏） | 20 → **16** |
| 卡片内边距 | 14 → **12**（紧凑卡：附件回退卡）或 **16**（大卡：笔记本卡、PDF 预览、设置卡） |
| 面板/看板列卡片内边距 | 6/10 → **8/12** |
| 触控钮内边距 | 14 → **12**（doc 工具栏：20px 图标 + 24 = 44px 仍达标） |
| 标题/正文水平基准 | 20 → **16**（doc 大标题，正文块起点≈12 保持轻微层次） |
| 大节间距（表单/对话框分区） | 20 → **24**；中节 14 → **16** |
| 空态图标→标题 | 20/18 → **24/16** |
| 徽标下划线间隙 | 6 → **4**（Tab 下 2px 指示条贴文字） |

### 豁免保留（7 处）

| 位置 | 值 | 理由 |
|---|---|---|
| `doc_pdf_adapter.dart` 3 处 `pw.EdgeInsets` | 10 | PDF 文档版式域（v1.17.27 既定裁决，非 Flutter UI 令牌管辖） |
| `editor_exporter.dart:545` `pw.SizedBox` | 18 | 同上 |
| `editor_page_text_overlays.dart:215` 便利贴 padding | 10/6 | 画布内容（便利贴样式），随导出产物呈现，非 UI 界面层 |
| `editor_page_text_overlays.dart:262` 复选框热区内边距 | 6 | 44×44 热区内视觉图标定位，画布内容 |
| `apple_design.dart:486` 部件内边距 | 14/8 | 令牌层自身（DESIGN.md 组件段），不在本轮清单 101 处内 |

### 决策明细（逐处）

- all_docs：sidebar 树间隔 10→12、树行图标距 10→12、头像距 10→12、工作区头顶 20→16；
  page_widgets 顶栏/Tab 水平 20→16、Tab 间距 18→16、指示条间隙 6→4、分组头 14/6→16/4、
  菜单图标距 10→8×3；mobile Tab 外距 6→4（注释「紧凑化」）、菜单图标距 10→8×2；
  doc_row 锁标/星标前隙 6→4、菜单图标距 10→8×2。
- doc：标题字段水平 20→16；嵌套子块缩进 20→16（对齐大纲每级 16）；slash 组头顶 10→12；
  toolbar 触控钮 14→12（注释同步）；attachment 图标距 10→8×2、嵌入预览前隙 10→8、
  回退卡 14→12 + 6→4/8、书签卡 6→8；doc_page_widgets 菜单图标距 10→8×6、分享钮 14→16、
  反链标头 6→4；embedded 图注前隙 6→4、链接块外隙 6→8、链接卡 10→12、图标距 10→8；
  database 三视图空态 20→24；kanban 列距 10→12、列卡 10→12、卡间隙 6→8、记录卡 10→12。
- drawing：命令面板搜索下隙 10→8、分组头 10→12；文字斜杠菜单行 6→8（对齐 block_slash_menu）；
  状态栏缩放钮 10→8；属性面板容器 10→12、节隙 6→4/8、色点距 10→8；番茄钟浮条 10→8；
  演示页卡 20→16；图层卡 6→8；形状库搜索下隙 10→8、形状格 6→8；PDF 面板组标 6→4。
- notes：冲突行 6→8；home 卡片菜单图标距 10→8×3、卡内容 10/6→8/4、笔记本卡 14→16、
  锁标隙 6→4；notebook_view 页行 6→4、新页表单节隙 20→24；onboarding 行 6/10→8/8；
  pdf_preview 14→16；settings 卡 14→14→16 全周、层隙 10→12、层图标距 10→8、
  节头底 6→4；home_tabs 分隔 10→12。
- shared/core/main：锁门图标隙 18→16、10/6→8/4；app_lock 设置 info 隙 6→4；
  webdav 摘要隙 6→4；色板节隙 10/10/14→8/8/16、RGB 场距 6→8×2；pin_pad 标题隙 20→24、
  计数隙 10→8、水平 28→24；skeleton 分隔 14→12；main 根拒屏图标隙 20→24。


## EdgeInsets 类（42 处）

| 文件:行 | 现值 | 就近档位候选 |
|lib\features\all_docs\presentation\all_docs_sidebar.dart:326 | EdgeInsets.fromLTRB(16, 20, 12, 8) | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:137 | EdgeInsets.symmetric(horizontal: 20) | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:292 | EdgeInsets.symmetric(horizontal: 20) | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:297 | EdgeInsets.only(right: 18) | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:498 | EdgeInsets.fromLTRB(16, 14, 8, 6) | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_mobile.dart:282 | EdgeInsets.symmetric(horizontal: 6) | 4/8/12/16/24 就近 |
|lib\features\doc\application\doc_pdf_adapter.dart:143 | EdgeInsets.only(left: 10) | 4/8/12/16/24 就近 |
|lib\features\doc\application\doc_pdf_adapter.dart:162 | EdgeInsets.all(10) | 4/8/12/16/24 就近 |
|lib\features\doc\application\doc_pdf_adapter.dart:175 | EdgeInsets.all(10) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\block_slash_menu.dart:372 | EdgeInsets.fromLTRB(12, 10, 12, 4) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_editor_blocks.dart:130 | EdgeInsets.only(left: 20) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\attachment_block_view.dart:211 | EdgeInsets.all(14) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_editor_toolbar.dart:118 | EdgeInsets.all(14) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_editor_ui.dart:11 | EdgeInsets.fromLTRB(20, 12, 20, 0) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:266 | EdgeInsets.symmetric(horizontal: 14) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\embedded_block_view.dart:238 | EdgeInsets.symmetric(vertical: 6, horizontal: 4) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\embedded_block_view.dart:254 | EdgeInsets.symmetric(vertical: 10, horizontal: 12) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\database\database_table_view.dart:105 | EdgeInsets.symmetric(vertical: 20) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\database\database_list_view.dart:42 | EdgeInsets.symmetric(vertical: 20) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\database\database_kanban_view.dart:70 | EdgeInsets.symmetric(vertical: 20) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\database\database_kanban_view.dart:94 | EdgeInsets.all(10) | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\database\database_kanban_view.dart:142 | EdgeInsets.all(10) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\editor_page_dialogs.dart:122 | EdgeInsets.fromLTRB(8, 10, 8, 2) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\editor_page_text_overlays.dart:127 | EdgeInsets.symmetric(horizontal: 12, vertical: 6) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\editor_page_text_overlays.dart:215 | EdgeInsets.symmetric(horizontal: 10, vertical: 6) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\editor_page_text_overlays.dart:262 | EdgeInsets.only(right: 6) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\editor_statusbar.dart:308 | EdgeInsets.symmetric(horizontal: 10, vertical: 4) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\properties_panel.dart:66 | EdgeInsets.all(10) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\components\editor_widgets.dart:119 | EdgeInsets.symmetric(horizontal: 10, vertical: 4) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\components\editor_widgets.dart:220 | EdgeInsets.all(20) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\layer_panel.dart:146 | EdgeInsets.all(6) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\shape_library.dart:206 | EdgeInsets.all(6) | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\pdf_export_panel.dart:312 | EdgeInsets.only(bottom: 6) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\conflict_resolution_dialog.dart:79 | EdgeInsets.symmetric(vertical: 6) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\home_page_widgets.dart:214 | EdgeInsets.fromLTRB(12, 10, 6, 8) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\home_page_widgets.dart:338 | EdgeInsets.all(14) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\notebook_view_page_widgets.dart:70 | EdgeInsets.fromLTRB(8, 6, 4, 6) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\onboarding.dart:141 | EdgeInsets.symmetric(vertical: 6) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\pdf_preview.dart:81 | EdgeInsets.all(14) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\settings_page.dart:220 | EdgeInsets.fromLTRB(16, 14, 16, 14) | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\settings_page.dart:316 | EdgeInsets.fromLTRB(4, 0, 0, 6) | 4/8/12/16/24 就近 |
|lib\shared\widgets\pin_pad.dart:292 | EdgeInsets.fromLTRB(28, 0, 28, 16) | 4/8/12/16/24 就近 |

## SizedBox 类（59 处）

|lib\main.dart:180 |                     const SizedBox(height: 20), | 4/8/12/16/24 就近 |
|lib\core\security\app_lock_gate.dart:465 |                 const SizedBox(height: 18), | 4/8/12/16/24 就近 |
|lib\core\security\app_lock_gate.dart:473 |                 const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\core\security\app_lock_gate.dart:475 |                 const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_sidebar.dart:150 |                   if (i == navCount) return const SizedBox(height: 10); | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_sidebar.dart:273 |               const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_sidebar.dart:343 |           const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_doc_row.dart:148 |                 const SizedBox(width: 6), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_doc_row.dart:170 |               const SizedBox(width: 6), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_doc_row.dart:295 |             SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_doc_row.dart:309 |               const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_mobile.dart:379 |                     SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_mobile.dart:389 |                     SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:220 |               SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:236 |               SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:252 |               SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\all_docs\presentation\all_docs_page_widgets.dart:314 |                     const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\attachment_block_view.dart:119 |               const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\attachment_block_view.dart:162 |             const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\attachment_block_view.dart:182 |           const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\attachment_block_view.dart:220 |           const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\attachment_block_view.dart:226 |           const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\attachment_block_view.dart:262 |               const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\database\database_kanban_view.dart:61 |             const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\database\database_kanban_view.dart:117 |                 const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\embedded_block_view.dart:205 |             const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\embedded_block_view.dart:273 |               const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:166 |                     const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:181 |                     const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:197 |                   const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:213 |                   const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:230 |                   const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:249 |                     const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\doc\presentation\doc_page_widgets.dart:357 |               const SizedBox(width: 6), | 4/8/12/16/24 就近 |
|lib\features\drawing\application\editor_exporter.dart:545 |             pw.SizedBox(height: 18), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\app_lock_settings_page.dart:144 |                   const SizedBox(width: 6), | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\editor_page_dialogs.dart:97 |             const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\properties_panel.dart:79 |               const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\properties_panel.dart:114 |                   const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\properties_panel.dart:303 |                 const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\features\drawing\presentation\shape_library.dart:170 |             const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\home_page_tabs.dart:183 |         separatorBuilder: (_, _) => const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\settings_page.dart:234 |             const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\settings_page.dart:281 |         const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\notebook_view_page_widgets.dart:313 |               const SizedBox(height: 20), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\home_page_widgets.dart:85 |               SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\home_page_widgets.dart:95 |               SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\home_page_widgets.dart:108 |               SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\home_page_widgets.dart:350 |                       const SizedBox(width: 6), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\onboarding.dart:146 |           const SizedBox(width: 10), | 4/8/12/16/24 就近 |
|lib\features\notes\presentation\webdav_sync_settings_page.dart:497 |             const SizedBox(height: 6), | 4/8/12/16/24 就近 |
|lib\shared\widgets\color_picker_dialog.dart:335 |               const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\shared\widgets\color_picker_dialog.dart:343 |                 const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\shared\widgets\color_picker_dialog.dart:382 |               const SizedBox(height: 14), | 4/8/12/16/24 就近 |
|lib\shared\widgets\color_picker_dialog.dart:403 |                       const SizedBox(width: 6), | 4/8/12/16/24 就近 |
|lib\shared\widgets\color_picker_dialog.dart:405 |                       const SizedBox(width: 6), | 4/8/12/16/24 就近 |
|lib\shared\widgets\pin_pad.dart:202 |                   const SizedBox(height: 20), | 4/8/12/16/24 就近 |
|lib\shared\widgets\pin_pad.dart:252 |                               const SizedBox(height: 10), | 4/8/12/16/24 就近 |
|lib\shared\widgets\skeleton.dart:86 |       separatorBuilder: (_, _) => const SizedBox(height: 14), | 4/8/12/16/24 就近 |

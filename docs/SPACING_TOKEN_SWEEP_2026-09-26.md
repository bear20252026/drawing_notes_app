# 离档间距清单（审计 2026-09-26 #34）

> 性质：**清单，未改代码**。离档值（6/10/14/18/20/22 等）归一到哪个合法档位
> （4/8/12/16/24/32/48）需要逐处视觉确认——10 与 8/12 等距，取舍取决于设计意图，
> 机械批量替换的视觉回归风险大于令牌纯度收益。建议后续带视觉验收的专项一次性处理。

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

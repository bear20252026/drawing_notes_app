#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""架构重组迁移脚本（S1：Feature-First 物理隔离）。

目标结构（2026 官方推荐，见 docs/ARCHITECTURE_ASSESSMENT_2026-08-15.md）：
  lib/core/                         共享内核（不依赖功能模块）
  lib/features/drawing/{domain,application,infrastructure,presentation}
  lib/features/notes/{domain,application,infrastructure,presentation}
  lib/shared/                       跨功能共享 UI

策略：
1. 90 个 Dart 文件按归属 git mv 到新位置（内容零改动）。
2. 所有项目内 import 统一转为 package: 路径（避免 ../.. 迷宫，
   2026 社区推荐），迁移后引用稳定。
3. 不改变任何逻辑；验证=analyze 零问题 + 全量测试全绿。

用法：python tools/migrate_arch.py [--dry-run|--apply]
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PKG = 'drawing_notes_app'
LIB = ROOT / 'lib'

# ---------------------------------------------------------------
# 精确映射表：原相对路径（lib/ 下）→ 新相对路径（lib/ 下）
# 归属原则：绘图→drawing、笔记→notes、共享存储/主题→core、共享 UI→shared
# ---------------------------------------------------------------
MAP = {
    # ---- features/drawing/domain（绘图实体，纯 Dart 理想）----
    'models/document.dart': 'features/drawing/domain/document.dart',
    'models/layer.dart': 'features/drawing/domain/layer.dart',
    'models/stroke.dart': 'features/drawing/domain/stroke.dart',
    'models/shape_item.dart': 'features/drawing/domain/shape_item.dart',
    'models/shape_endpoint_binding.dart': 'features/drawing/domain/shape_endpoint_binding.dart',
    'models/selection.dart': 'features/drawing/domain/selection.dart',
    'models/document_image_item.dart': 'features/drawing/domain/document_image_item.dart',
    # text_item 画布文字块（笔记富文本轻量段，主用于画布）
    'models/text_item.dart': 'features/drawing/domain/text_item.dart',
    'engine/fractional_index.dart': 'features/drawing/domain/fractional_index.dart',

    # ---- features/drawing/application（控制器/命令/用例）----
    'engine/drawing_controller.dart': 'features/drawing/application/drawing_controller.dart',
    'engine/drawing_controller_history.dart': 'features/drawing/application/drawing_controller_history.dart',
    'engine/drawing_controller_objects.dart': 'features/drawing/application/drawing_controller_objects.dart',
    'engine/drawing_controller_render.dart': 'features/drawing/application/drawing_controller_render.dart',
    'engine/drawing_controller_selection.dart': 'features/drawing/application/drawing_controller_selection.dart',
    'engine/drawing_controller_temporary.dart': 'features/drawing/application/drawing_controller_temporary.dart',
    'engine/document_commands.dart': 'features/drawing/application/document_commands.dart',
    'engine/document_transaction.dart': 'features/drawing/application/document_transaction.dart',
    'engine/command_registry.dart': 'features/drawing/application/command_registry.dart',
    'engine/plugin_registry.dart': 'features/drawing/application/plugin_registry.dart',
    'engine/eraser_mode.dart': 'features/drawing/application/eraser_mode.dart',
    'engine/eraser_mode_store.dart': 'features/drawing/application/eraser_mode_store.dart',
    'engine/editor_input_arbiter.dart': 'features/drawing/application/editor_input_arbiter.dart',
    'engine/gesture_math.dart': 'features/drawing/application/gesture_math.dart',
    'engine/brush_preset_store.dart': 'features/drawing/application/brush_preset_store.dart',
    'engine/search_service.dart': 'features/drawing/application/search_service.dart',
    'engine/stylus_input.dart': 'features/drawing/application/stylus_input.dart',
    'engine/text_run_delta.dart': 'features/drawing/application/text_run_delta.dart',
    'engine/editor_exporter.dart': 'features/drawing/application/editor_exporter.dart',

    # ---- features/drawing/infrastructure（渲染/缓存/编解码/同步实现）----
    'engine/stroke_renderer.dart': 'features/drawing/infrastructure/stroke_renderer.dart',
    'engine/stroke_geometry_cache.dart': 'features/drawing/infrastructure/stroke_geometry_cache.dart',
    'engine/stroke_picture_cache.dart': 'features/drawing/infrastructure/stroke_picture_cache.dart',
    'engine/ink_layer_painter.dart': 'features/drawing/infrastructure/ink_layer_painter.dart',
    'engine/layer_compositor.dart': 'features/drawing/infrastructure/layer_compositor.dart',
    'engine/pencil_shader.dart': 'features/drawing/infrastructure/pencil_shader.dart',
    'engine/view_transform_cache.dart': 'features/drawing/infrastructure/view_transform_cache.dart',
    'engine/shape_renderer.dart': 'features/drawing/infrastructure/shape_renderer.dart',
    'engine/shape_recognizer.dart': 'features/drawing/infrastructure/shape_recognizer.dart',
    'engine/shape_creation_geometry.dart': 'features/drawing/infrastructure/shape_creation_geometry.dart',
    'engine/shape_binding_geometry.dart': 'features/drawing/infrastructure/shape_binding_geometry.dart',
    'engine/sync_path_cipher.dart': 'features/drawing/infrastructure/sync_path_cipher.dart',
    'engine/sync_service.dart': 'features/drawing/infrastructure/sync_service.dart',
    'engine/svg_exporter.dart': 'features/drawing/infrastructure/svg_exporter.dart',
    'engine/pdf_hybrid_exporter.dart': 'features/drawing/infrastructure/pdf_hybrid_exporter.dart',
    'engine/encryption_service.dart': 'features/drawing/infrastructure/encryption_service.dart',

    # ---- features/drawing/presentation（画布 UI）----
    'ui/canvas_painter.dart': 'features/drawing/presentation/canvas_painter.dart',
    'ui/pages/editor_page.dart': 'features/drawing/presentation/editor_page.dart',
    'ui/pages/editor_page_actions.dart': 'features/drawing/presentation/editor_page_actions.dart',
    'ui/pages/editor_page_commands.dart': 'features/drawing/presentation/editor_page_commands.dart',
    'ui/pages/editor_page_dialogs.dart': 'features/drawing/presentation/editor_page_dialogs.dart',
    'ui/pages/editor_page_drag_ops.dart': 'features/drawing/presentation/editor_page_drag_ops.dart',
    'ui/pages/editor_page_editing.dart': 'features/drawing/presentation/editor_page_editing.dart',
    'ui/pages/editor_page_input.dart': 'features/drawing/presentation/editor_page_input.dart',
    'ui/pages/editor_page_overlays.dart': 'features/drawing/presentation/editor_page_overlays.dart',
    'ui/pages/editor_page_persistence.dart': 'features/drawing/presentation/editor_page_persistence.dart',
    'ui/pages/editor_page_shortcuts.dart': 'features/drawing/presentation/editor_page_shortcuts.dart',
    'ui/pages/editor_page_tools.dart': 'features/drawing/presentation/editor_page_tools.dart',
    'ui/widgets/editor_components.dart': 'features/drawing/presentation/editor_components.dart',
    'ui/widgets/editor_context_bar.dart': 'features/drawing/presentation/editor_context_bar.dart',
    'ui/widgets/editor_left_toolbar.dart': 'features/drawing/presentation/editor_left_toolbar.dart',
    'ui/widgets/editor_statusbar.dart': 'features/drawing/presentation/editor_statusbar.dart',
    'ui/widgets/editor_toolbar.dart': 'features/drawing/presentation/editor_toolbar.dart',
    'ui/widgets/editor_viewmodel.dart': 'features/drawing/presentation/editor_viewmodel.dart',
    'ui/widgets/layer_panel.dart': 'features/drawing/presentation/layer_panel.dart',
    'ui/widgets/properties_panel.dart': 'features/drawing/presentation/properties_panel.dart',
    'ui/widgets/shape_library.dart': 'features/drawing/presentation/shape_library.dart',

    # ---- features/notes/domain（笔记实体）----
    'models/notebook.dart': 'features/notes/domain/notebook.dart',

    # ---- features/notes/infrastructure（笔记存储/导出实现）----
    'storage/notebook_storage.dart': 'features/notes/infrastructure/notebook_storage.dart',
    'engine/paged_note_rtf_exporter.dart': 'features/notes/infrastructure/paged_note_rtf_exporter.dart',

    # ---- features/notes/presentation（笔记 UI）----
    'ui/pages/home_page.dart': 'features/notes/presentation/home_page.dart',
    'ui/pages/notebook_view_page.dart': 'features/notes/presentation/notebook_view_page.dart',
    'ui/pages/notebook_view_page_imports.dart': 'features/notes/presentation/notebook_view_page_imports.dart',
    'ui/pages/notebook_view_page_manage.dart': 'features/notes/presentation/notebook_view_page_manage.dart',
    'ui/pages/notebook_view_page_widgets.dart': 'features/notes/presentation/notebook_view_page_widgets.dart',
    'ui/pages/presentation_page.dart': 'features/notes/presentation/presentation_page.dart',
    'ui/pages/search_page.dart': 'features/notes/presentation/search_page.dart',
    'ui/pages/password_disk_page.dart': 'features/notes/presentation/password_disk_page.dart',
    'ui/onboarding.dart': 'features/notes/presentation/onboarding.dart',

    # ---- core/storage（共享存储抽象，不依赖功能模块）----
    'storage/document_codec.dart': 'core/storage/document_codec.dart',
    'storage/repository.dart': 'core/storage/repository.dart',
    'storage/storage_service.dart': 'core/storage/storage_service.dart',
    'storage/password_disk.dart': 'core/storage/password_disk.dart',
    'storage/local_id_generator.dart': 'core/storage/local_id_generator.dart',
    'storage/pdf_import_service.dart': 'core/storage/pdf_import_service.dart',

    # ---- core/theme（全局主题）----
    'app_design.dart': 'core/theme/app_design.dart',
    'app_theme_controller.dart': 'core/theme/app_theme_controller.dart',

    # ---- shared/widgets（跨功能共享 UI）----
    'ui/widgets/ambient_background.dart': 'shared/widgets/ambient_background.dart',
    'ui/widgets/glass_surface.dart': 'shared/widgets/glass_surface.dart',
    'ui/widgets/color_picker_dialog.dart': 'shared/widgets/color_picker_dialog.dart',

    # ---- 保留在 lib/ 根（应用入口/装配）----
    # 'main.dart' / 'app.dart' 留在 lib/ 根
}


def normalize_rel(path: Path) -> str:
    return path.relative_to(LIB).as_posix()


def rewrite_imports() -> None:
    """把所有项目内相对 import 统一转为 package: 路径。"""
    import_re = re.compile(
        r"(import\s+')(\.\.?/)([^']+)(';)",
    )
    # 旧相对路径 → 新 package 路径的反查表
    to_pkg: dict[str, str] = {}
    for old, new in MAP.items():
        to_pkg[old] = f'package:{PKG}/{new}'
    # 反向：新文件被引用时旧路径已不存在，无法直接查；
    # 因此分两遍：先收集全部文件新路径，再对每个 import 的旧相对目标解析新位置。
    moved: dict[str, str] = {}  # 旧相对路径(不含lib/前缀) -> 新相对路径
    for old, new in MAP.items():
        moved[old] = new
    # lib 根保留文件
    for f in ['main.dart', 'app.dart']:
        moved[f] = f

    def resolve_old_target(imp: str, src_old_dir: str) -> str | None:
        """把 import 的相对目标（相对于源文件旧目录）解析为 lib 相对路径。"""
        # 去掉 ./ 或 ../ 前缀按目录拼接
        target = os.path.normpath(os.path.join(src_old_dir, imp))
        return target.replace('\\', '/')

    for dart in sorted(LIB.rglob('*.dart')):
        src = dart.read_text(encoding='utf-8')
        changed = False
        out_lines = []
        for line in src.splitlines():
            m = import_re.match(line)
            if not m:
                out_lines.append(line)
                continue
            prefix, _rel, target, suffix = m.groups()
            if target.startswith('package:'):
                out_lines.append(line)
                continue
            # 目标可能是相对路径（../models/x.dart）
            src_old = normalize_rel(dart.parent)
            lib_rel = resolve_old_target(target, src_old)
            if lib_rel in moved:
                new_rel = moved[lib_rel]
                new_import = f"import 'package:{PKG}/{new_rel}';"
                out_lines.append(new_import)
                changed = True
            else:
                out_lines.append(line)
        if changed:
            dart.write_text('\n'.join(out_lines) + '\n', encoding='utf-8', newline='')
            print(f'  import 重写: {dart.name}')


def main() -> int:
    apply = '--apply' in sys.argv
    dry = not apply
    print(f'架构迁移（{"执行" if apply else "预演"}）: {len(MAP)} 个文件')
    errors = 0
    for old, new in MAP.items():
        src = LIB / old
        dst = LIB / new
        if not src.exists():
            print(f'  ✗ 源缺失: {old}')
            errors += 1
            continue
        if dry:
            print(f'  → {old} => {new}')
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst))
        print(f'  ✓ {old} => {new}')
    if dry:
        print('预演完成（未移动）；加 --apply 执行')
        return 0 if errors == 0 else 1
    # 执行后：重写 import
    print('重写项目内 import 为 package: 路径...')
    rewrite_imports()
    print('迁移完成')
    return 0 if errors == 0 else 1


if __name__ == '__main__':
    sys.exit(main())

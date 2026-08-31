# -*- coding: utf-8 -*-
"""R4b 第二轮：doc_editor 再拆三个区间（编辑操作/选区工具条/资源管理）。
切片按当前行号（1-based，含头注释行）：
  A 编辑操作   [769, 1062)  -> doc_editor_editing.dart  (DocEditorEditing)
  B 选区工具条 [596, 769)   -> doc_editor_selection.dart (DocEditorSelection)
  C 资源管理   [555, 596)   -> 并入 doc_editor_selection.dart 头部 (DocEditorResources)
"""
import io

p = 'lib/features/doc/doc_editor.dart'
lines = io.open(p, encoding='utf-8').read().splitlines(keepends=True)

def find_line(prefix):
    for i, l in enumerate(lines):
        if l.startswith(prefix):
            return i
    raise AssertionError(f'not found: {prefix}')

a_start = find_line('  // ── 文本同步')
b_start = find_line('  // ── 焦点追踪')
c_start = find_line('  // ── 初始化')
assert a_start > b_start > c_start, (a_start, b_start, c_start)

edit_slice = lines[a_start:b_start]        # A
sel_slice = lines[b_start:a_start]         # B
res_slice = lines[c_start:b_start]         # C

HDR = (
    "// 由 Claude 团队生成 | Drawing Notes App\n"
    "// doc_editor 拆分（R4b 第二轮，架构审计 M1）：\n"
    "// extension on DocEditorState（同库 part，可访问私有成员）。\n\n"
    "part of 'doc_editor.dart';\n\n"
)

# 顺序：从大行号往小切，避免行号漂移
new_lines = lines[:c_start] + lines[a_start:]
# part 声明插入（最后一个 import 之后）
out = []
inserted = False
for i, l in enumerate(new_lines):
    out.append(l)
    if not inserted and l.startswith('import ') and (
        i + 1 >= len(new_lines) or not new_lines[i + 1].startswith('import ')
    ):
        out.append("part 'doc_editor_editing.dart';\n")
        out.append("part 'doc_editor_selection.dart';\n")
        inserted = True
assert inserted, 'part decl'
io.open(p, 'w', encoding='utf-8', newline='\n').write(''.join(out))

# selection part：resources + selection 两个 extension
sel_content = (
    HDR
    + 'extension DocEditorResources on DocEditorState {\n'
    + ''.join(res_slice)
    + '}\n\n'
    + 'extension DocEditorSelection on DocEditorState {\n'
    + ''.join(sel_slice)
    + '}\n'
)
io.open('lib/features/doc/doc_editor_selection.dart', 'w',
        encoding='utf-8', newline='\n').write(sel_content)

# editing part
edit_content = (
    HDR
    + 'extension DocEditorEditing on DocEditorState {\n'
    + ''.join(edit_slice)
    + '}\n'
)
io.open('lib/features/doc/doc_editor_editing.dart', 'w',
        encoding='utf-8', newline='\n').write(edit_content)

print(f'OK editing={len(edit_slice)} selection={len(sel_slice)} '
      f'resources={len(res_slice)} main={len(out)}')

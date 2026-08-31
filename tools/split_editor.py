# -*- coding: utf-8 -*-
"""R4b：doc_editor.dart 拆分——blocks 渲染与 toolbar 移入 extension part。
方法体逐字节搬运（行区间切片），主文件保留 State 骨架与生命周期。
"""
import io

p = 'lib/features/doc/doc_editor.dart'
lines = io.open(p, encoding='utf-8').read().splitlines(keepends=True)

# 行号（1-based）→ 0-based
# 区间 A：blocks 渲染 = 1394(空文档提示 doc comment) .. 1995(hintText 方法结束 `  }`)
# 区间 B：toolbar = `  // ── 工具栏` 注释行 .. 文件尾倒数第一行 `}`（类闭合）之前
start_a = None
for i, l in enumerate(lines):
    if l.startswith('  /// 空文档提示'):
        start_a = i
        break
assert start_a is not None, 'start_a'
# 区间 A 结束：_hintTextForBlockType 的收尾 `  }`（其后是空行 + `  // ── 工具栏`）
end_a = None
for i in range(start_a, len(lines)):
    if lines[i].startswith('  // ── 工具栏'):
        end_a = i  # 指向工具栏注释行
        break
assert end_a is not None, 'end_a'
# 去掉 end_a 前的空行（归工具栏区）
while lines[end_a - 1].strip() == '':
    end_a -= 1

block_slice = lines[start_a:end_a]

# 区间 B：从工具栏注释行到类闭合 `}` 之前
start_b = end_a
end_b = None
for i in range(start_b, len(lines)):
    if lines[i] == '}\n' or lines[i] == '}':
        end_b = i
        break
assert end_b is not None, 'end_b'
toolbar_slice = lines[start_b:end_b]

# 类闭合行保留在主文件
tail_close = lines[end_b:]

# 主文件：删除两个区间
new_main = lines[:start_a] + [lines[start_b - 0] for _ in ()] + []  # placeholder
new_main = lines[:start_a]
# start_a 到 end_b 之间全部移除，但保留类闭合与之后的顶层内容
# 注意 end_b 之后可能还有 `}` 后的顶层内容（本文件应为空）
new_main = lines[:start_a] + tail_close

# part 声明插入主文件（最后一个 import 之后）
out_main = []
inserted = False
for i, l in enumerate(new_main):
    out_main.append(l)
    if not inserted and l.startswith('import ') and (
        i + 1 >= len(new_main) or not new_main[i + 1].startswith('import ')
    ):
        out_main.append("part 'doc_editor_blocks.dart';\n")
        out_main.append("part 'doc_editor_toolbar.dart';\n")
        inserted = True
assert inserted, 'part decl'
io.open(p, 'w', encoding='utf-8', newline='\n').write(''.join(out_main))

# part 文件
hdr = (
    "// 由 Claude 团队生成 | Drawing Notes App\n"
    "// doc_editor 拆分（R4b，架构审计 M1）：块渲染区。\n"
    "// extension on DocEditorState（同库 part，可访问私有成员）；\n"
    "// 生命周期方法与字段仍留在 doc_editor.dart 主文件。\n\n"
    "part of 'doc_editor.dart';\n\n"
    "extension DocEditorBlocks on DocEditorState {\n"
)
io.open(
    'lib/features/doc/doc_editor_blocks.dart', 'w', encoding='utf-8', newline='\n'
).write(hdr + ''.join(block_slice) + '}\n')

hdr2 = (
    "// 由 Claude 团队生成 | Drawing Notes App\n"
    "// doc_editor 拆分（R4b，架构审计 M1）：底部工具栏。\n\n"
    "part of 'doc_editor.dart';\n\n"
    "extension DocEditorToolbar on DocEditorState {\n"
)
io.open(
    'lib/features/doc/doc_editor_toolbar.dart', 'w', encoding='utf-8', newline='\n'
).write(hdr2 + ''.join(toolbar_slice) + '}\n')

print(f'OK blocks={len(block_slice)} lines, toolbar={len(toolbar_slice)} lines, '
      f'main now {len(out_main)} lines')

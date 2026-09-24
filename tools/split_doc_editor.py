# F9 doc_editor.dart 成员级域拆分（括号深度感知；幂等：先还原再重建）
import io, re, subprocess

path = 'lib/features/doc/doc_editor.dart'
# 1) 从 git HEAD 还原原始版本
subprocess.run(['git', 'checkout', '--', path], check=True)
lines = io.open(path, encoding='utf-8').read().split('\n')

# 2) F7 import 改写（契约上移到 core/documents）
rules = [
    ('package:drawing_notes_app/features/doc/domain/note_block_doc.dart',
     'package:drawing_notes_app/core/documents/note_block_doc.dart'),
    ('package:drawing_notes_app/features/doc/domain/note_block.dart',
     'package:drawing_notes_app/core/documents/note_block.dart'),
    ('package:drawing_notes_app/features/doc/domain/note_attachment.dart',
     'package:drawing_notes_app/core/documents/note_attachment.dart'),
]
lines = [l if not any(a in l for a, _ in rules) else
         [l.replace(a, b) for a, b in rules if a in l][0]
         for l in lines]

BS = chr(92)  # backslash，避免 heredoc/内联转义问题


def depth_profile(ls):
    prof = []
    d = 0
    in_block_comment = False
    for l in ls:
        start = d
        i = 0
        instr = None
        while i < len(l):
            c = l[i]
            if instr:
                if c == BS:
                    i += 2
                    continue
                if c == instr:
                    instr = None
            elif in_block_comment:
                if l.startswith('*/', i):
                    in_block_comment = False
                    i += 2
                    continue
            elif c in ('"', "'"):
                instr = c
            elif l.startswith('//', i):
                break
            elif l.startswith('/*', i):
                in_block_comment = True
                i += 2
                continue
            elif c == '{':
                d += 1
            elif c == '}':
                d -= 1
            i += 1
        prof.append((start, d))
    return prof


prof = depth_profile(lines)
cls_start = next(i for i, l in enumerate(lines) if l.startswith('class DocEditorState '))
cls_depth = prof[cls_start][0]
cls_end = next(i for i in range(cls_start + 1, len(lines))
               if prof[i][1] == cls_depth and lines[i].rstrip().endswith('}'))

member_re = re.compile(
    r'(?:Future<[^>]*>|Future|void|NoteBlockDoc|NoteBlock|bool|int|String|Widget|List<[^>]*>)\s+(_?\w+)[<(]')
members = []  # (name, start, end) 含前导注释；0-based inclusive
i = cls_start + 1
while i <= cls_end:
    if prof[i][0] == cls_depth + 1:
        m = member_re.match(lines[i].strip())
        if m:
            name = m.group(1)
            # 成员终点 = 深度首次回落到类体层的行（含单行/表达式体成员）
            end = next((j for j in range(i, cls_end + 1)
                        if prof[j][1] == cls_depth + 1), cls_end)
            s = i - 1
            while s > cls_start and (lines[s].strip().startswith('//')
                                     or lines[s].strip() == ''):
                s -= 1
            s += 1
            if name.startswith('_'):
                members.append((name, s, end))
            i = end + 1
            continue
    i += 1

HISTORY = {'_scheduleCosmeticRefresh', '_commitHistory', '_commitHistoryCoalesced',
           '_notifyDirtyOnce', '_flushPendingHistory', '_onTitleEdited', '_notifySave',
           '_buildRootFromDoc', '_buildDocFromState', '_restoreDoc', '_applyRootChange',
           '_manualSave'}
BLOCKOPS = {'_indentBlock', '_outdentBlock', '_checkSlashTrigger', '_openSlashMenu',
            '_closeSlashMenu', '_onSlashMenuSelected'}
UI = {'_buildTitleField', '_containsId', '_buildOutlineDrawer', '_showExitDialog'}

buckets = {'history': [], 'blockops': [], 'ui': []}
for name, s, e in members:
    if name in HISTORY:
        buckets['history'].append((s, e))
    elif name in BLOCKOPS:
        buckets['blockops'].append((s, e))
    elif name in UI:
        buckets['ui'].append((s, e))

found = {n for n, _, _ in members}
missing = (HISTORY | BLOCKOPS | UI) - found
if missing:
    print('MISSING:', sorted(missing))
    raise SystemExit(1)
print('members mapped:', len(members))


def seg(rngs):
    out = []
    for s, e in rngs:
        if out:
            out.append('')
        out.extend(lines[s:e + 1])
    while out and out[-1].strip() == '':
        out.pop()
    return out


PARTS = [
    ('lib/features/doc/doc_editor_history.dart', 'history',
     '// 历史/保存域（O1 拆分自 doc_editor.dart）：历史快照入栈与合帧、脏通知\n'
     '// 边沿、标题编辑、恢复与根变更应用、手动保存。public API 与字段、静态\n'
     '// 延迟留在本体。行为零变化。',
     '/// 历史/保存域私有助手（拆分自 doc_editor.dart）。\n'
     'extension _DocEditorHistory on DocEditorState {'),
    ('lib/features/doc/doc_editor_block_ops.dart', 'blockops',
     '// 块操作域（O1 拆分自 doc_editor.dart）：缩进/反缩进、斜杠菜单触发与\n'
     '// 分派。行为零变化。',
     '/// 块操作域私有助手（拆分自 doc_editor.dart）。\n'
     'extension _DocEditorBlockOps on DocEditorState {'),
    ('lib/features/doc/doc_editor_ui.dart', 'ui',
     '// 大纲/对话框域（O1 拆分自 doc_editor.dart）：标题输入框、大纲抽屉、\n'
     '// 退出确认。public outline/scrollToBlock 留在本体。行为零变化。',
     '/// 大纲/对话框域私有助手（拆分自 doc_editor.dart）。\n'
     'extension _DocEditorUi on DocEditorState {'),
]
for fname, key, note, extline in PARTS:
    body = seg(buckets[key])
    io.open(fname, 'w', encoding='utf-8', newline='\n').write(
        "part of 'doc_editor.dart';\n\n" + note + '\n\n' + extline + '\n'
        + '\n'.join(body) + '\n}\n')
    text = io.open(fname, encoding='utf-8').read()
    assert text.count('{') == text.count('}'), fname + ' braces'
    print('wrote', fname, len(body), 'lines')

remove = sorted([(s, e) for k in buckets.values() for (s, e) in k], reverse=True)
keep = lines[:]
for s, e in remove:
    del keep[s:e + 1]

cleaned = []
blanks = 0
for l in keep:
    blanks = blanks + 1 if l.strip() == '' else 0
    if blanks <= 2:
        cleaned.append(l)
keep = cleaned

last_import = max(i for i, l in enumerate(keep) if l.startswith('import '))
keep[last_import + 1:last_import + 1] = [
    '',
    '// O1 域分权（F9，2026-09-24）：历史保存/块操作/大纲对话框三域 part。',
    '// 新增同域私有逻辑请落对应 part；public API、字段、静态与 build 留在本体。',
    "part 'doc_editor_history.dart';",
    "part 'doc_editor_block_ops.dart';",
    "part 'doc_editor_ui.dart';",
]
host = '\n'.join(keep)
assert host.count('{') == host.count('}'), 'host braces'
io.open(path, 'w', encoding='utf-8', newline='\n').write(host)
print('host now', len(keep), 'lines; balanced')

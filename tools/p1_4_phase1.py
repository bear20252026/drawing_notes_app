# -*- coding: utf-8 -*-
"""按成员名把 DocEditorState 的方法拆到 part extension 文件（花括号匹配，先收集后删除）。"""
import io, re

SRC = 'lib/features/doc/doc_editor.dart'
text = io.open(SRC, encoding='utf-8').read()

groups = {
    'doc_editor_focus.dart': ['_onFocusChange', '_duplicateFocusedBlock',
        '_deleteFocusedBlock', '_buildSelectionToolbar', '_selectionToolbarIcon',
        '_selectionToolbarDivider', '_syncText'],
    'doc_editor_richtext.dart': ['_changeBlockType', '_toggleTodo',
        '_computeBodySignature', '_getSpansForFocusedBlock', '_spansFromBlock',
        '_spansToProps', '_updateSpans', '_toggleBold', '_toggleItalic',
        '_toggleUnderline', '_insertLink', '_checkSlashTrigger',
        '_openSlashMenu', '_closeSlashMenu', '_onSlashMenuSelected',
        '_manualSave'],
    'doc_editor_outline.dart': ['outline', '_containsId', 'scrollToBlock',
        '_buildOutlineDrawer'],
    'doc_editor_blocks.dart': ['_indentBlock', '_outdentBlock'],
}

def find_member(name):
    pat = re.compile(r'^  (?:[A-Za-z_][\w<>,\s?]*\s)?' + re.escape(name) + r'\(', re.M)
    m = pat.search(text)
    if not m:
        return None
    start = m.start()
    i = text.index('{', m.end())
    depth = 0
    j = i
    in_str = None
    while j < len(text):
        c = text[j]
        prev = text[j-1] if j else ''
        if in_str:
            if c == in_str and prev != '\\':
                in_str = None
        elif c in ('"', "'"):
            in_str = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                j += 1
                break
        j += 1
    end = j
    s2 = start
    while s2 > 0 and text[s2-1] == '\n':
        pl = text.rfind('\n', 0, s2-1)
        pline = text[pl+1:s2-1].strip()
        if pline.startswith('///') or pline.startswith('//'):
            s2 = pl + 1
        else:
            break
    return (s2, end, name)

# 先收集全部片段（基于原文，避免边删边查）
collected = {}
cuts = []
for fname, names in groups.items():
    spans = []
    for n in names:
        r = find_member(n)
        if r is None:
            print('MISS', fname, n)
            continue
        spans.append(r)
    spans.sort()
    collected[fname] = [(sp, ep) for sp, ep, n in spans]
    cuts.extend(spans)

# 从后往前删除
for sp, ep in sorted(cuts, key=lambda t: -t[0]):
    text = text[:sp] + text[ep:]

# part 声明插入到最后一个顶层 import 之后
tl = text.splitlines(keepends=True)
last = 0
for i, l in enumerate(tl):
    if l.startswith('import '):
        last = i + 1
tl.insert(last, ''.join("part '%s';\n" % f for f in groups))
text = ''.join(tl)

io.open(SRC, 'w', encoding='utf-8', newline='\n').write(text)

# 写 part 文件（再次扫描原片段文本 = 从收集时的 cut 记录中拿不到原文了；
# 因此收集阶段直接保存原文）
print('phase-1 done (deletion + part decls)')

# -*- coding: utf-8 -*-
"""P1-7：把页面文件内的私有 Widget/Painter 类搬入 part 文件（花括号匹配）。"""
import io, re, sys

def split_classes(src, part_file, class_names, part_doc):
    text = io.open(src, encoding='utf-8').read()
    snippets = {}
    cuts = []
    for name in class_names:
        pat = re.compile(r'^class ' + re.escape(name) + r'\b', re.M)
        m = pat.search(text)
        if not m:
            print('MISS', name)
            continue
        start = m.start()
        # 包含前导 doc 注释
        s2 = start
        while s2 > 0 and text[s2-1] == '\n':
            pl = text.rfind('\n', 0, s2-1)
            pline = text[pl+1:s2-1].strip()
            if pline.startswith('///') or pline.startswith('//'):
                s2 = pl + 1
            else:
                break
        j = text.index('{', m.end())
        depth, k = 0, j
        while k < len(text):
            c = text[k]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    k += 1
                    break
            k += 1
        # 吃掉尾随空行
        while k < len(text) and text[k] == '\n':
            k += 1
        snippets[name] = text[s2:k]
        cuts.append((s2, k))

    for sp, ep in sorted(cuts, key=lambda t: -t[0]):
        text = text[:sp] + text[ep:]

    # part 声明插入到最后一个顶层 import 之后
    tl = text.splitlines(keepends=True)
    last = 0
    for i, l in enumerate(tl):
        if l.startswith('import '):
            last = i + 1
    tl.insert(last, "part '%s';\n" % part_file)
    text = ''.join(tl)
    io.open(src, 'w', encoding='utf-8', newline='\n').write(text)

    body = "part of '%s';\n\n" % os.path.basename(src)
    body += '// %s\n\n' % part_doc
    for name in class_names:
        if name in snippets:
            body += snippets[name] + '\n'
    io.open(os.path.join(os.path.dirname(src), part_file), 'w', encoding='utf-8', newline='\n').write(body)
    print('OK', src, '->', part_file)

if __name__ == '__main__':
    if sys.argv[1] == 'alldocs':
        split_classes(
            'lib/features/all_docs/presentation/all_docs_page.dart',
            'all_docs_page_widgets.dart',
            ['_MainContent', '_DocsToolbar', '_DocsTabBar', '_SortedDocList',
             '_GroupedDocList', '_SectionHeader', '_EmptyState', '_TabEmptyState'],
            '列表区/工具条/空态等展示组件（自 all_docs_page.dart 拆出）。')
    elif sys.argv[1] == 'edgeless':
        split_classes(
            'lib/features/notes/presentation/edgeless_page.dart',
            'edgeless_page_widgets.dart',
            ['_FrameCard', '_CornerHandle', '_CornerHandleState',
             '_EdgelessGridPainter', '_ConnectorPainter', '_GroupPainter',
             '_ConnectBanner', '_ToolPanel', '_ElementPainter'],
            '画布卡片/角柄/横幅/工具面板/绘制器（自 edgeless_page.dart 拆出）。')

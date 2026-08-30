# -*- coding: utf-8 -*-
import os, re

moves = ['page_chart_item.dart', 'page_connector.dart', 'page_image_item.dart',
         'shape_item.dart', 'text_item.dart', 'shape_endpoint_binding.dart']
dst_dir = 'lib/core/canvas_model'
os.makedirs(dst_dir, exist_ok=True)

# 1) 移动文件
for f in moves:
    os.rename(os.path.join('lib/features/drawing/domain', f), os.path.join(dst_dir, f))

# 2) 全库替换 import 路径（lib + test）
count = 0
for base in ['lib', 'test']:
    for root, dirs, files in os.walk(base):
        for f in files:
            if not f.endswith('.dart'):
                continue
            p = os.path.join(root, f)
            s = io.open(p, encoding='utf-8', errors='ignore').read()
            orig = s
            for name in moves:
                s = s.replace('features/drawing/domain/' + name,
                              'core/canvas_model/' + name)
            if s != orig:
                io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
                count += 1
print('updated files:', count)

# 3) shape_item 内部对 binding 的引用路径已在替换中处理；验证
s = io.open(os.path.join(dst_dir, 'shape_item.dart'), encoding='utf-8').read()
print('shape_item imports:')
for line in s.splitlines():
    if line.startswith('import') or line.startswith('export'):
        print('  ', line.strip())

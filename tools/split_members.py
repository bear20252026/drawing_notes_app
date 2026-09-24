# F9 通用成员级拆分：按括号深度感知解析类体，把指定私有方法迁入 part extension。
# 用法: python tools/split_members.py <config.json>
# 幂等：每次从 git HEAD 还原目标文件后重建（注意：调用前该文件不能有未提交的
# 其他改动需要保留；F7 之类 import 改写请放进 config.rules 一并套用）。
import io, json, re, subprocess, sys

cfg = json.load(io.open(sys.argv[1], encoding='utf-8'))
path = cfg['path']
subprocess.run(['git', 'checkout', '--', path], check=True)
lines = io.open(path, encoding='utf-8').read().split('\n')

rules = [(r['from'], r['to']) for r in cfg.get('rules', [])]
if rules:
    lines = [l if not any(a in l for a, _ in rules) else
             [l.replace(a, b) for a, b in rules if a in l][0]
             for l in lines]

BS = chr(92)


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
cls_start = next(i for i, l in enumerate(lines) if l.startswith(cfg['classDecl']))
cls_depth = prof[cls_start][0]
cls_end = next(i for i in range(cls_start + 1, len(lines))
               if prof[i][1] == cls_depth and lines[i].rstrip().endswith('}'))
member_re = re.compile(cfg['memberRegex'])

members = []
i = cls_start + 1
while i <= cls_end:
    if prof[i][0] == cls_depth + 1:
        m = member_re.match(lines[i].strip())
        if m:
            name = m.group(1)
            # 成员终点 = 深度回落到类体层、且以 ';' 或 '}' 收尾的首行
            # （兼容多行表达式体成员：无括号时深度恒为类体层，需看语句终止符；
            #   判定前剥掉行尾 // 注释，避免 `... ; // 注释` 误判）
            def _code_tail(j):
                return re.sub(r'(?<!:)//.*$', '', lines[j]).rstrip()
            end = cls_end
            for j in range(i, cls_end + 1):
                if prof[j][1] == cls_depth + 1 and _code_tail(j).endswith((';', '}')):
                    end = j
                    break
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

buckets = {p['file']: [] for p in cfg['parts']}
for name, s, e in members:
    for p in cfg['parts']:
        if name in p['members']:
            buckets[p['file']].append((s, e))
            break

all_targets = set()
for p in cfg['parts']:
    all_targets |= set(p['members'])
found = {n for n, _, _ in members}
missing = all_targets - found
if missing:
    print('MISSING in', path, ':', sorted(missing))
    raise SystemExit(1)
# 不得重复归桶
counted = [n for n, _, _ in members if n in all_targets]
if len(counted) != len(all_targets):
    print('DUPLICATE bucketing in', path)
    raise SystemExit(1)
print(path, 'members mapped:', len(members))


def seg(rngs):
    out = []
    for s, e in rngs:
        if out:
            out.append('')
        out.extend(lines[s:e + 1])
    while out and out[-1].strip() == '':
        out.pop()
    return out


host_base = path.replace(BS, '/').rsplit('/', 1)[-1]
dir_of = path.replace(BS, '/').rsplit('/', 1)[0]
for p in cfg['parts']:
    fname = dir_of + '/' + p['file']
    body = seg(buckets[p['file']])
    io.open(fname, 'w', encoding='utf-8', newline='\n').write(
        "part of '" + host_base + "';\n\n" + p['note'] + '\n\n'
        + '/// ' + p['extDoc'] + '\n'
        + 'extension ' + p['extName'] + ' on ' + cfg['className'] + ' {\n'
        + '\n'.join(body) + '\n}\n')
    text = io.open(fname, encoding='utf-8').read()
    assert text.count('{') == text.count('}'), p['file'] + ' braces'
    print('wrote', p['file'], len(body), 'lines')

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
part_lines = ['']
part_lines += cfg.get('hostNote', [])
for p in cfg['parts']:
    part_lines.append("part '" + p['file'] + "';")
keep[last_import + 1:last_import + 1] = part_lines
host = '\n'.join(keep)
assert host.count('{') == host.count('}'), 'host braces'
io.open(path, 'w', encoding='utf-8', newline='\n').write(host)
print('host now', len(keep), 'lines; balanced')

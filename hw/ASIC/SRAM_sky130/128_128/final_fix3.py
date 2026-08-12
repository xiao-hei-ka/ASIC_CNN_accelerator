#!/usr/bin/env python3
import os, sys, re
SP_LIB = '/home/ICer/miniconda3/lib/python3.9/site-packages/openram/technology/sky130/sp_lib'
sys.argv = ['fix', '-t', 'sky130']
os.environ['OPENRAM_HOME'] = '/home/ICer/miniconda3/lib/python3.9/site-packages/openram/compiler'
os.environ['OPENRAM_TECH'] = '/home/ICer/miniconda3/lib/python3.9/site-packages/openram/technology'
os.environ['PDK_ROOT'] = '/home/ICer/pdk'
sys.path.insert(0, os.environ['OPENRAM_HOME'])
import openram
(OPTS, args) = openram.parse_args()
openram.init_openram(config_file='/home/ICer/oram_run/config_sram_small.py')
from openram.tech import cell_properties as props

def fix_one(sp, expect, label):
    orig = open(sp).read()
    txt = orig
    if 'VDD' in expect and not re.search(r'\bVDD\b', txt):
        txt = re.sub(r'\bvdd\b', 'VDD', txt)
    if 'GND' in expect and not re.search(r'\bGND\b', txt):
        txt = re.sub(r'\bgnd\b', 'GND', txt)
    lines = txt.split('\n')
    changed = (txt != orig)
    for i, line in enumerate(lines):
        if line.startswith('.subckt'):
            parts = line.split()
            name = parts[1] if len(parts) > 1 else ''
            ports_here = parts[2:]
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ''
            if not ports_here and nxt and not nxt.startswith(('.', '*', 'X')):
                ports_here = nxt.split()
                lines[i + 1] = ''
                changed = True
            if ports_here != expect:
                missing = [p for p in expect if not re.search(r'\b' + re.escape(p) + r'\b', txt)]
                if missing:
                    print('DIFF-NET:', label, name, 'expect', expect, 'actual', ports_here, 'MISSING:', missing)
                    return
                lines[i] = '.subckt ' + name + ' ' + ' '.join(expect)
                changed = True
            if changed:
                open(sp, 'w').write('\n'.join(lines))
                print('FIXED  :', label, ports_here, '->', expect)
            else:
                print('OK     :', label)
            return
    print('NOSUBCKT:', label)

for attr in dir(props):
    if attr.startswith('_'):
        continue
    try:
        v = getattr(props, attr)
    except Exception:
        continue
    if not (hasattr(v, 'port_names') and hasattr(v, 'hard_cell') and v.hard_cell):
        continue
    name = props.names.get(attr, None)
    if not name:
        continue
    if isinstance(name, list):
        idx = OPTS.num_rw_ports + OPTS.num_r_ports + OPTS.num_w_ports - 1
        name = name[min(idx, len(name) - 1)]
    sp = os.path.join(SP_LIB, name + '.sp')
    if not os.path.exists(sp):
        print('MISSING-SPICE:', attr, name)
        continue
    fix_one(sp, v.port_names, attr)
print('== done ==')

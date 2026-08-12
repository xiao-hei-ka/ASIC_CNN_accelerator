#!/usr/bin/env python3
import re
p = '/home/ICer/miniconda3/lib/python3.9/site-packages/openram/compiler/sram.py'
txt = open(p).read()
open(p + '.bak', 'w').write(txt)
txt = re.sub(r'# Save a functional simulation file.*?print_time\("Spice writing", datetime\.datetime\.now\(\), start_time\)',
             'pass  # functional skipped\n        print_time("Spice writing", datetime.datetime.now(), start_time)',
             txt, flags=re.S)
txt = re.sub(r'# Save stimulus and measurement file.*?print_time\("DELAY", datetime\.datetime\.now\(\), start_time\)',
             'pass  # delay skipped\n        print_time("DELAY", datetime.datetime.now(), start_time)',
             txt, flags=re.S)
open(p, 'w').write(txt)
print('PATCHED sram.py (functional+delay skipped)')

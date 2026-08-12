#!/bin/bash
# =============================================================================
# gen_sram.sh - SkyWater 130nm (sky130) SRAM 一键生成脚本 (OpenRAM)
# 用法: ./gen_sram.sh <word_size> <num_words> [output_name]
# 例:   ./gen_sram.sh 128 256            -> 生成 256x128 SRAM
#       ./gen_sram.sh 32 1024 sram_itcm  -> 生成 1024x32, 模块名 sram_itcm
# 幂等: 环境/PDK 已装则自动跳过; 可反复运行
# =============================================================================
set -e

WORD_SIZE=${1:-128}
NUM_WORDS=${2:-256}
OUT_NAME=${3:-sram_1rw_${NUM_WORDS}x${WORD_SIZE}}

# ---------- "种子" (可复现指纹, 请勿修改) ----------
OPENRAM_VERSION=1.2.48                 # OpenRAM 固定版本 (pip)
SRAM_LIB_COMMIT=dd64256961317205343a3fd446908b42bafba388  # sky130_fd_bd_sram 固定 commit
CONDA_URL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-py39_4.12.0-Linux-x86_64.sh"
PIP_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
WORK=${WORK:-/home/ICer}
PDK_ROOT=$WORK/pdk

echo ">>> 生成 $OUT_NAME  =  ${NUM_WORDS} words x ${WORD_SIZE} bits (sky130, OpenRAM $OPENRAM_VERSION)"

# ---------- 1. Python 环境 (幂等) ----------
if [ ! -x $WORK/miniconda3/bin/python3 ]; then
  echo ">>> [1/7] 安装 miniconda ..."
  curl -sL $CONDA_URL -o /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p $WORK/miniconda3
fi
PY=$WORK/miniconda3/bin/python3
if ! $PY -c "import openram" 2>/dev/null; then
  echo ">>> [1/7] pip 安装 openram==$OPENRAM_VERSION ..."
  $PY -m pip install -i $PIP_INDEX openram==$OPENRAM_VERSION
fi

# ---------- 2. sky130 PDK 占位文件 (分析模型模式只需存在性) ----------
mkdir -p $PDK_ROOT/sky130A/libs.tech/ngspice $PDK_ROOT/sky130A/libs.tech/magic $PDK_ROOT/sky130A/libs.tech/netgen
[ -f $PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice ] || echo placeholder > $PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice
[ -f $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc ]    || echo placeholder > $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc
[ -f $PDK_ROOT/sky130A/libs.tech/netgen/setup.tcl ]         || echo placeholder > $PDK_ROOT/sky130A/libs.tech/netgen/setup.tcl

# ---------- 3. cell 库下载 (固定 commit = 种子) ----------
SRAM_DIR=$PDK_ROOT/sky130_fd_bd_sram-$SRAM_LIB_COMMIT
if [ ! -d $SRAM_DIR ]; then
  echo ">>> [2/7] 下载 sky130_fd_bd_sram @ $SRAM_LIB_COMMIT ..."
  cd $PDK_ROOT
  curl -sL "https://codeload.github.com/vlsida/sky130_fd_bd_sram/tar.gz/$SRAM_LIB_COMMIT" -o sram.tar.gz
  tar -xzf sram.tar.gz
fi

# ---------- 4. cells 安装到 OpenRAM 工艺目录 ----------
TECH=$($PY -c "import openram,os;print(os.path.join(os.path.dirname(openram.__file__),'technology','sky130'))")
mkdir -p $TECH/gds_lib $TECH/sp_lib $TECH/lvs_lib $TECH/maglef_lib
echo ">>> [3/7] 安装 cells -> $TECH"
cp -f $SRAM_DIR/cells/*/*.gds $TECH/gds_lib/ 2>/dev/null
for f in $SRAM_DIR/cells/*/*.spice; do cp -f "$f" "$TECH/sp_lib/$(basename "$f" .spice).sp"; done
cp -f $SRAM_DIR/cells/*/*.lvs.spice $TECH/lvs_lib/ 2>/dev/null
cp -f $SRAM_DIR/cells/*/*.maglef $TECH/maglef_lib/ 2>/dev/null

# ---------- 5. config 文件 ----------
mkdir -p $WORK/oram_run
cat > $WORK/oram_run/config_$OUT_NAME.py <<EOF
from openram import OPTS
word_size = $WORD_SIZE
num_words = $NUM_WORDS
tech_name = OPTS.tech_name
nominal_corner_only = True
num_spare_rows = 1
num_spare_cols = 1
check_lvsdrc = False
route_supplies = False
output_name = "$OUT_NAME"
EOF

# ---------- 6. 端口修复 + save patch (内嵌, 幂等) ----------
echo ">>> [4/7] 修复 cell 端口 (sky130_fd_bd_sram 与 OpenRAM 端口对齐) ..."
$PY - <<PYEOF
import os, re, sys
os.environ['OPENRAM_HOME'] = '$WORK/miniconda3/lib/python3.9/site-packages/openram/compiler'
os.environ['OPENRAM_TECH'] = '$WORK/miniconda3/lib/python3.9/site-packages/openram/technology'
os.environ['PDK_ROOT'] = '$PDK_ROOT'
sys.path.insert(0, os.environ['OPENRAM_HOME'])
sys.argv = ['fix', '-t', 'sky130']
import openram
OPTS, args = openram.parse_args()
openram.init_openram(config_file='$WORK/oram_run/config_$OUT_NAME.py')
from openram.tech import cell_properties as props
SP = '$WORK/miniconda3/lib/python3.9/site-packages/openram/technology/sky130/sp_lib'
fixed = 0
for attr in dir(props):
    if attr.startswith('_'): continue
    v = getattr(props, attr)
    if not (hasattr(v, 'port_names') and hasattr(v, 'hard_cell') and v.hard_cell): continue
    name = props.names.get(attr)
    if not name: continue
    if isinstance(name, list):
        idx = OPTS.num_rw_ports + OPTS.num_r_ports + OPTS.num_w_ports - 1
        name = name[min(idx, len(name) - 1)]
    sp = os.path.join(SP, name + '.sp')
    if not os.path.exists(sp):
        print('skip(no spice):', attr); continue
    txt = open(sp).read()
    orig = txt
    expect = v.port_names
    if 'VDD' in expect and not re.search(r'\bVDD\b', txt):
        txt = re.sub(r'\bvdd\b', 'VDD', txt)
    if 'GND' in expect and not re.search(r'\bGND\b', txt):
        txt = re.sub(r'\bgnd\b', 'GND', txt)
    lines = txt.split('\n')
    changed = (txt != orig)
    for i, line in enumerate(lines):
        if line.startswith('.subckt'):
            toks = line.split()
            cell_name = toks[1] if len(toks) > 1 else ''
            ports_here = toks[2:] if len(toks) > 2 else []
            if not ports_here and i + 1 < len(lines):
                nxt = lines[i + 1].strip()
                if nxt and not nxt.startswith(('.', '*', 'X')):
                    ports_here = nxt.split()
            if ports_here != expect:
                lines[i] = '.subckt ' + cell_name + ' ' + ' '.join(expect)
                if not ports_here and i + 1 < len(lines) and lines[i + 1].strip() and not lines[i + 1].strip().startswith(('.', '*', 'X')):
                    lines[i + 1] = ''
                changed = True
            break
    if changed:
        open(sp, 'w').write('\n'.join(lines))
        fixed += 1
        print('fixed:', attr)
print('total fixed:', fixed)
PYEOF

echo ">>> [5/7] patch OpenRAM save (跳过 functional/delay, 前端只出 .v/.lib) ..."
$PY - <<PYEOF
import re
p = '$WORK/miniconda3/lib/python3.9/site-packages/openram/compiler/sram.py'
txt = open(p).read()
if 'FUNCTIONAL_SKIPPED' not in txt:
    txt = re.sub(r'# Save a functional simulation file.*?print_time\("Spice writing", datetime\.datetime\.now\(\), start_time\)',
                 'pass # FUNCTIONAL_SKIPPED\n            print_time("Spice writing", datetime.datetime.now(), start_time)',
                 txt, flags=re.S)
    txt = re.sub(r'# Save stimulus and measurement file.*?print_time\("DELAY", datetime\.datetime\.now\(\), start_time\)',
                 'pass # DELAY_SKIPPED\n            print_time("DELAY", datetime.datetime.now(), start_time)',
                 txt, flags=re.S)
    open(p, 'w').write(txt)
    print('sram.py patched')
else:
    print('sram.py already patched')
PYEOF

# ---------- 7. 生成 ----------
echo ">>> [6/7] 运行 OpenRAM (布局较重, 256x128 约需 100 分钟) ..."
export OPENRAM_HOME=$WORK/miniconda3/lib/python3.9/site-packages/openram/compiler
export OPENRAM_TECH=$WORK/miniconda3/lib/python3.9/site-packages/openram/technology
export PDK_ROOT=$PDK_ROOT
export PYTHONPATH=$OPENRAM_HOME
cd $WORK/oram_run
rm -rf out_$OUT_NAME && mkdir -p out_$OUT_NAME
timeout 9000 $PY $WORK/miniconda3/lib/python3.9/site-packages/openram/sram_compiler.py -t sky130 -n -p $WORK/oram_run/out_$OUT_NAME config_$OUT_NAME.py

echo ">>> [7/7] 完成! 输出目录: $WORK/oram_run/out_$OUT_NAME/"
ls -la $WORK/oram_run/out_$OUT_NAME/

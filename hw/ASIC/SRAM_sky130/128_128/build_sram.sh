#!/bin/bash
# ============================================================
# SkyWater 130nm (sky130) SRAM 生成脚本 (OpenRAM 1.2.48)
# 用法: bash build_sram.sh <word_size> <num_words> [output_name]
# 例  : bash build_sram.sh 128 128 sram_1rw_128x128
#        bash build_sram.sh 32  256 sram_1rw_256x32
# 产物: .v (仿真模型) / .lib (时序库) / .gds .lef .sp .html
# 前置: OpenRAM 装在 miniconda3, sky130 cells 已就位(见 README)
# ============================================================
set -e

WS=${1:?用法: build_sram.sh <word_size> <num_words> [output_name]}
NW=${2:?用法: build_sram.sh <word_size> <num_words> [output_name]}
NAME=${3:-sram_1rw_${NW}x${WS}}

ORAM=/home/ICer/miniconda3/lib/python3.9/site-packages/openram
OFF=/home/ICer/pdk/sram_official/sky130_fd_bd_sram-dd64256961317205343a3fd446908b42bafba388
TECH=$ORAM/technology/sky130
OUT=/home/ICer/oram_run/out_${NAME}

echo "[1/5] 安装 sky130 cell 视图 (gds/spice/lvs/maglef)"
rm -f $TECH/gds_lib/* $TECH/sp_lib/* $TECH/lvs_lib/* $TECH/maglef_lib/*
cp -f $OFF/cells/*/*.gds    $TECH/gds_lib/ 2>/dev/null || true
for f in $OFF/cells/*/*.spice; do cp -f "$f" "$TECH/sp_lib/$(basename "$f" .spice).sp"; done
cp -f $OFF/cells/*/*.lvs.spice $TECH/lvs_lib/ 2>/dev/null || true
cp -f $OFF/cells/*/*.maglef   $TECH/maglef_lib/ 2>/dev/null || true

echo "[2/5] 修复 cell 端口 (OpenRAM 1.2.48 与 sky130_fd_bd_sram 配对补丁)"
cd /home/ICer && /home/ICer/miniconda3/bin/python3 /home/ICer/final_fix3.py

echo "[3/5] 跳过 functional/delay 特性化 (一次性 patch, 已打则跳过)"
if [ ! -f $ORAM/compiler/sram.py.bak ]; then
    /home/ICer/miniconda3/bin/python3 /home/ICer/patch_save.py
else
    echo "sram.py 已打过补丁"
fi

echo "[4/5] 生成配置: ${NAME} (${NW} words x ${WS} bits)"
mkdir -p /home/ICer/oram_run
printf 'from openram import OPTS\nword_size = %s\nnum_words = %s\ntech_name = OPTS.tech_name\nnominal_corner_only = True\nnum_spare_rows = 1\nnum_spare_cols = 1\ncheck_lvsdrc = False\nroute_supplies = False\noutput_name = "%s"\n' \
    "$WS" "$NW" "$NAME" > /home/ICer/oram_run/config_gen.py

echo "[5/5] 运行 OpenRAM (${NW}x${WS} 约需数分钟~1小时, 大尺寸请耐心)"
export OPENRAM_HOME=$ORAM/compiler
export OPENRAM_TECH=$ORAM/technology
export PDK_ROOT=/home/ICer/pdk
export PYTHONPATH=$OPENRAM_HOME
cd /home/ICer/oram_run
rm -rf $OUT && mkdir -p $OUT
timeout 3500 /home/ICer/miniconda3/bin/python3 $ORAM/sram_compiler.py -t sky130 -n -p $OUT config_gen.py 2>&1 | tail -6

echo "== 完成, 产物在 $OUT =="
ls -la $OUT/

#==============================================================
#  CNN 加速器 ASIC 仿真 Makefile（VCS + Verdi）
#
#  所有生成物都集中在 sim_prj/ 目录（该目录已 gitignore）
#
#  用法（在 simulation/ 目录下执行）：
#    make compile   只编译（产物在 sim_prj/simv）
#    make run       编译 + 运行仿真（日常就用这个）
#    make verdi     打开 Verdi 看波形（需要图形界面）
#    make clean     删除整个 sim_prj/，回到干净状态
#    make flist     生成 sim_prj/filelist.f（学习用）
#
#==============================================================

# ---- 0. 工作目录：所有产物都往这里写，一个目录即可 gitignore ----
WORK_DIR = sim_prj

# ---- 1. 工具路径（一般不用改） ----
VCS_HOME   = /home/synopsys/vcs-mx/O-2018.09-1
VERDI_HOME = /home/synopsys/verdi/Verdi_O-2018.09-SP2

# ---- 2. 源文件 ----
RTL_DIR = ../hdl
TB_DIR  = sim_hdl
RTL = \
	$(RTL_DIR)/cdc.sv \
	$(RTL_DIR)/sync_fifo.sv \
	$(RTL_DIR)/reset_synchronizer.sv \
	$(RTL_DIR)/para_sram.sv \
	$(RTL_DIR)/sram_mgr.sv \
	$(RTL_DIR)/axi4_frame_parser.sv \
	$(RTL_DIR)/axi4_lite_interface.sv \
	$(RTL_DIR)/axi4_lite_parser.sv \
	$(RTL_DIR)/core.sv \
	$(RTL_DIR)/top.sv
TB = \
	$(TB_DIR)/tb_cmd.sv \
	$(TB_DIR)/tb_ram.sv \
	$(TB_DIR)/tb_top.sv

# ---- 3. SRAM 模型：两个只能选一个！----
SRAM_MODEL = $(TB_DIR)/tb_sram_1rw_256x128.v

# ---- 4. 仿真参数 ----
TOP     = tb_top        # 仿真顶层模块名
SIM_BIN = simv          # 编译产物的名字（可执行文件）

# ---- 5. 绝对路径化：命令要 cd 进 sim_prj 执行，源文件必须给全路径 ----
RTL_ABS  = $(abspath $(RTL))
TB_ABS   = $(abspath $(TB))
SRAM_ABS = $(abspath $(SRAM_MODEL))
INC_ABS  = $(abspath $(RTL_DIR))

# ---- 6. 目标定义 ----
.PHONY: all compile run verdi clean flist
# 注意：$(WORK_DIR) 是【真实的目录目标】，绝不能写进 .PHONY 名单

all: run                 # 直接敲 make 就等于 make run

# 保证 sim_prj/ 目录存在（不存在才创建）
$(WORK_DIR):
	mkdir -p $@

compile: $(WORK_DIR)
	cd $(WORK_DIR) && $(VCS_HOME)/bin/vcs -full64 -sverilog +v2k \
	-timescale=1ns/1ps \
	-debug_access+all \
	-P $(VERDI_HOME)/share/PLI/VCS/LINUX64/novas.tab \
	$(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a \
	+incdir+$(INC_ABS) \
	$(SRAM_ABS) $(RTL_ABS) $(TB_ABS) \
	-top $(TOP) -j8 -l compile.log -o $(SIM_BIN)

run: compile
	cd $(WORK_DIR) && ./$(SIM_BIN) -l run.log

flist: $(WORK_DIR)
	@echo "+incdir+$(INC_ABS)" > $(WORK_DIR)/filelist.f
	@for f in $(RTL_ABS) $(TB_ABS) $(SRAM_ABS); do echo $$f >> $(WORK_DIR)/filelist.f; done
	@echo "已生成 $(WORK_DIR)/filelist.f，内容："
	@cat $(WORK_DIR)/filelist.f

verdi: flist
	cd $(WORK_DIR) && $(VERDI_HOME)/bin/verdi -f filelist.f -top $(TOP) -ssf wave.fsdb &

clean:
	rm -rf $(WORK_DIR)

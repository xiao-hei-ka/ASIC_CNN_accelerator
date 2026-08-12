================================================================
SkyWater 130nm (sky130) SRAM 交付包
生成工具: OpenRAM 1.2.48 (analytical delay model, TT/1.8V/25C)
生成日期: 2026-08-07
================================================================

【一、交付文件】
  sram_1rw_128x128.v                  Verilog 行为仿真模型 (128位宽主交付)
  sram_1rw_128x128_TT_1p8V_25C.lib    Liberty 时序库 (DC综合/PT用)
  sram_1rw_128x128.html               datasheet (端口/时序文档, 浏览器打开)
  sram_1rw_128x128.py                 OpenRAM 配置 (128x128 固定配置)
  build_sram.sh                       生成脚本 (改尺寸重生成用)
  final_fix3.py / patch_save.py       生成所需补丁 (勿删)
  README.txt                          本说明

【二、例化方法】
  sram_1rw_128x128 u_sram (
      .clk0      (clk),
      .csb0      (csb),          // 低有效片选
      .web0      (web),          // 低有效写使能
      .spare_wen0(1'b0),         // 冗余列写使能, 不用接 0
      .addr0     (addr[7:0]),    // 128 深度, 0~127
      .din0      ({1'b0, din[127:0]}),   // 见注意1
      .dout0     ({spare_q, dout[127:0]})
  );

  注意1: 因 sky130 阵列要求 1 列冗余(spare), din0/dout0 实为 129 位
         [128:0]; 正常 128 位数据接 [127:0], 最高位不用时接 0。
         直接连 128 位宽会报端口宽度不匹配。
  注意2: 电源脚 vccd1/vssd1 由 `ifdef USE_POWER_PINS 控制,
         普通仿真/综合【不要】define, 例化时也不要写这两个脚。
         仅做 UPF 低功耗流程时才需要。

【三、仿真用法】
  编译时在 VCS 命令行列出 .v 文件即可 (纯行为模型, 无工艺依赖):
      vcs -sverilog tb_top.v sram_1rw_128x128.v -o simv && ./simv
  项目文件多了建议建 filelist.f:
      // filelist.f
      tb_top.v
      sram_1rw_128x128.v
      vcs -sverilog -f filelist.f
  VCS 会自动解析例化依赖, 文件顺序无所谓。
  低功耗提醒: 停时钟(时钟门控)可清零动态功耗且保数据;
  漏电需断 VDD (但会丢数据, 本宏无 retention 引脚)。

【四、如何改尺寸重新生成 (复现配方)】
  前置环境 (已装在虚拟机, 用户 ICer @ 192.168.1.35):
    - miniconda3 + Python 3.9 + OpenRAM 1.2.48 (pip)
    - sky130_fd_bd_sram 官方 commit dd64256 (cells 已装到
      site-packages/openram/technology/sky130/{gds_lib,sp_lib,...})
  生成任意尺寸 (build_sram.sh 是参数化脚本, 传参决定尺寸):
      bash build_sram.sh <word_size> <num_words> [output_name]
      例: bash build_sram.sh 128 256 sram_1rw_256x128   # 32KB
      例: bash build_sram.sh 32  1024 sram_1rw_1024x32  # 4KB
  产物输出到 /home/ICer/oram_run/out_<name>/, 拷到共享文件夹即可。
  注意: 尺寸越大越慢 (128x128 约 50 分钟, 纯 Python 布局布线)。

【五、Git 管理建议】
  小产物 (.v/.lib/.html, 共 ~14KB) 建议直接提交, clone 即用;
  大/中间产物 (.gds/.lef/.sp, MB 级) 建议 gitignore;
  生成配方 (build_sram.sh + 补丁 + 本 README) 必须提交 (唯一不可再生资产)。

【六、已知限制 (诚实声明)】
  - .lib 时序为 OpenRAM 分析模型估算值, 非流片级/非 PVT 全角;
    若要真实时序需 SPICE 特性化 (需 ngspice + 完整 sky130 PDK)。
  - .v 中 DELAY/T_HOLD 为占位值, 功能仿真正确, 时序以 .lib 为准。
================================================================

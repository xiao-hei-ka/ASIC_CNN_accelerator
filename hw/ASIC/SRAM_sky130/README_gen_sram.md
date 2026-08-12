# Sky130 SRAM 生成脚本 (OpenRAM)

本目录的 `.v` / `.lib` 是**生成产物**，建议加入 `.gitignore`。
真正要提交进仓库的是 **`gen_sram.sh`**——任何人 clone 后一条命令即可重新生成任意尺寸的 SRAM。

## 用法

```bash
bash gen_sram.sh <word_size> <num_words> [output_name]

# 例:
bash gen_sram.sh 128 256            # 生成 256 深 x 128 位宽 (本次交付的配置)
bash gen_sram.sh 32 1024 sram_itcm  # 生成 1024x32, 模块名 sram_itcm
bash gen_sram.sh 128 512            # 生成 512x128
```

输出: `~/oram_run/out_<name>/` 下生成 `.v`(仿真模型), `.lib`(时序库), `.gds/.lef/.sp`(后端), `.html`(datasheet)

## 种子 (可复现指纹, 脚本内已固定, 勿改)

| 组件 | 版本/commit |
|---|---|
| OpenRAM | 1.2.48 (pip, 清华源) |
| sky130_fd_bd_sram | `dd64256961317205343a3fd446908b42bafba388` (vlsida 官方 commit) |
| Python | 3.9 (miniconda py39_4.12.0, 兼容 CentOS7 glibc2.17) |
| 工艺 | SkyWater sky130A (130nm 开源 PDK) |

## 特性说明

- **幂等**: 环境/PDK 已装自动跳过, 可反复运行; 首次运行会自动装 miniconda + openram
- **自动修复**: 自动对齐 sky130_fd_bd_sram cell 端口与 OpenRAM 期望 (dff/nand/sense_amp/write_driver)
- **前端模式**: 自动 patch OpenRAM 跳过 functional/delay 特性化 (无 ngspice 也能跑), 用分析模型出 .lib
- **尺寸注意**: sky130 阵列约束需要 1 行 + 1 列 spare, 因此
  `DATA_WIDTH = word_size + 1` (最高 1 位是冗余列, 例化时接 0),
  `ADDR_WIDTH = ceil(log2(num_words)) + 1` (最高 1 位是冗余行, 例化时不用)

## 例化模板 (以 256x128 为例)

```verilog
sram_1rw_256x128 u_sram (
    .clk0      (clk),
    .csb0      (csb),          // 低有效片选
    .web0      (web),          // 低有效写使能
    .spare_wen0(1'b0),
    .addr0     (addr[8:0]),    // 只用 [7:0] 即 0~255
    .din0      ({1'b0, din[255:0]}),
    .dout0     ({spare_q, dout[255:0]})
);
```

## 已知限制

- `.lib` 时序为 OpenRAM **分析模型估算值**, 非流片级时序 (流片需 foundry 真实 SRAM)
- 生成耗时与容量成正比: 256x128 (~1.7h), 128x128 (~50min), 256x32 (~8min)
- 需要能访问 GitHub (codeload.github.com); 下载慢可先手动放好
  `~/pdk/sky130_fd_bd_sram-<commit>/` 目录, 脚本会自动跳过下载

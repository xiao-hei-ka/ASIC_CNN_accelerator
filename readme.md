# ASIC_CNN_accelerator

## 项目概述

这是一个基于ASIC的异构协同CNN算子加速器项目。硬件侧通过AXI4-lite与CPU进行状态交互，通过DMA读取DDR中原始数据与参数后，将计算结果写回DDR。

## 开发日志

- [log.md](doc/log.md)

## ASIC微架构图示







## 详细设计报告
- [detailed design.md](doc/detailed_design.md)

## 运行环境

- 运行环境：[environment.md](doc/environment.md)
- python所需库：[requirements.txt](sw/python/requirements.txt)

## 踩坑记录

- [踩坑记录.md](doc/踩坑记录.md)


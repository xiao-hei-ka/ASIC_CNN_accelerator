#!/bin/bash

MODULE_NAME="u-dma-buf"
# 之前安装脚本中指定的存放路径
KO_PATH="/lib/modules/$(uname -r)/extra/${MODULE_NAME}.ko"

# "=== 开始彻底卸载 $MODULE_NAME 驱动 ==="

# 1. 从当前运行的内核中卸载（拔出插件）
if lsmod | grep -q "^${MODULE_NAME}"; then
    # "-> 正在从内存中卸载模块..."
    sudo rmmod $MODULE_NAME
    if [ $? -ne 0 ]; then
        echo "卸载失败！可能有程序（如你的C程序）正在占用 /dev/udmabuf0，请先关闭它们。"
        exit 1
    fi
fi

# 2. 删除系统目录下的物理驱动文件
if [ -f "$KO_PATH" ]; then
    # "-> 正在删除底层驱动文件..."
    sudo rm -f "$KO_PATH"
fi

# 3. 刷新内核依赖树（告诉 Linux 这个驱动已经没了）
# "-> 正在刷新内核依赖..."
sudo depmod -a

# 4. 最终验证
if modinfo $MODULE_NAME > /dev/null 2>&1; then
    echo "卸载出现异常，系统仍能检测到该驱动。"
fi

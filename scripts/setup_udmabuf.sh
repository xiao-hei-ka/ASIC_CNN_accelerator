#!/bin/bash

# 定义要分配的内存大小 (1048576 = 2MB)
MEM_SIZE=2097152
MODULE_NAME="u-dma-buf"

# "=== 1. 检查系统是否已安装 $MODULE_NAME 驱动 ==="
if ！ modinfo $MODULE_NAME > /dev/null 2>&1; then
    echo " 系统未安装udmabuf驱动，开始自动编译安装..."
    
    # 1. 安装编译依赖
    echo "-> 正在安装内核头文件和编译工具..."
    sudo apt update
    sudo apt install -y linux-headers-$(uname -r) build-essential git
    
    # 2. 下载源码 (清理旧目录，使用国内加速源)
    echo "-> 正在下载源码..."
    cd ~
    rm -rf udmabuf_src_tmp
    git clone https://gitclone.com/github.com/ikwzm/udmabuf.git udmabuf_src_tmp
    cd udmabuf_src_tmp
    
    # 3. 编译
    echo "-> 正在编译内核模块..."
    make
    
    # 4. 手动安装 (绕过 Makefile 的 bug)
    echo "-> 正在将模块安装到内核目录..."
    sudo mkdir -p /lib/modules/$(uname -r)/extra
    sudo cp u-dma-buf.ko /lib/modules/$(uname -r)/extra/
    
    # 5. 刷新内核依赖
    sudo depmod -a
    
    # 6. 清理临时文件
    cd ~
    rm -rf udmabuf_src_tmp
    echo "✅ 驱动编译安装完成！"
fi

# "=== 2. 唤醒驱动并分配物理内存 ==="
# 先尝试卸载旧的（防止重复加载报错）
sudo rmmod $MODULE_NAME 2>/dev/null
# 加载驱动并分配内存
sudo modprobe $MODULE_NAME udmabuf0=$MEM_SIZE

echo "=== 3. 验证结果 ==="
if [ -e /dev/udmabuf0 ]; then
    echo "设备节点已生成: /dev/udmabuf0"
    PHYS_ADDR=$(cat /sys/class/u-dma-buf/udmabuf0/phys_addr)
    echo "绝对物理地址: $PHYS_ADDR， 大小: $MEM_SIZE Byte"
else
    echo "失败！未能生成设备节点。"
fi

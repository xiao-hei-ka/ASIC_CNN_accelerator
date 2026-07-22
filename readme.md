# kv260-cnn-gemm-accelerator
## 项目概述
这是一个基于AMD Kria KV260 Vision AI Starter Kit开发板的异构协同CNN算子加速器项目。旨在通过SOC内ps、pl的异构协同，高效优化CNN运算。

## 模型概述
基于LeNet-5神经网络，使用python脚本，以MNIST数据集为输入，训练了一个0-9数字识别模型。并对模型权重进行INT8量化，对模型偏置进行INT32量化，以便部署于SOC。

- 输入：28*28像素图像
- 输出：10个评分通道，对应0-9数字

## 运行环境
- 运行环境：[environment.md](doc/environment.md)
- python所需库：[requirements.txt](sw/python/requirements.txt)

## 开发日志
- [log.md](doc/log.md)

## 模型架构
- **输入**：`28*28`像素单通道图像

- **Conv1**：
  - 6个`1*5*5`卷积核
  - 步长：`1`
  - 无填充
  - 输出：6个`24*24`特征图

- **pool1**：
  - `2*2`池化窗口
  - 采用平均池化
  - 步长：`2`
  - 无填充
  - 输出：6个`12*12`特征图

- **conv2**
  - 16个`6*5*5`卷积核
  - 步长：`1`
  - 无填充
  - 输出：16个`8*8`特征图

- **pool2**
  - `2*2`池化窗口
  - 采用平均池化
  - 步长：`2`
  - 无填充
  - 输出：16个`4*4`特征图，等价于256维向量

- **FC1**
  - 输出：120维向量

- **FC2**
  - 输出：84维向量

- **FC3**
  - 输出：10维向量

- **激活函数**
	- python训练、推理时，采用ReLU
	- SoC上推理时，对硬件内整数进行[zero_point, 255]限位

## 训练与量化
### **数据集准备**
    
使用MNIST数据集。

- 文件格式：.npz文件。

- 数据内容：0-9数字图像，其中60000张作为训练集，10000张作为测试集。单通道，28*28，像素值0-255.

- 文件位置：sw/python/model_training/data/MNIST/mnist.npz

  data目录已加入`.gitignore`列表，[点击这里](http://study.xiaoheika.cc/)可进入我的个人网站获取。
### **训练过程**

- step1：由python初始化权重、偏置。

- step2：使用训练集分批次进行前向传播、计算损失、反向传播（计算梯度）、更新参数（采用Adam算法）。

- step3：使用测试集测试模型准确率。

- step4：

  - step4.1：更新截止到当前轮次模型最高准确率对应的模型weight（权重）与bias（偏置）。

  - step4.2：

    - 若当前准确率已达98%，或已进行20轮训练，训练结束。
    - 否则在上一轮参数基础上进入step2，进行下一轮训练。

### **量化**
#### 1.硬件计算中的浮点数的表示法

在训练中得到的weight与bias，均为浮点数格式。而在NPU上将浮点数运算近似转化为整数运算，可以在只牺牲一点点精度的情况下，大幅提高推理速度，增加带宽，减小功耗。用离散的整数值近似表示连续小数值的过程叫做量化。

真实的$weight$、$input$、$bias$值与其在硬件中的整数值具有如下对应关系：
$$
x_{r} = \mathrm{s_{x}} \times (x - Z_x)
$$
$$
w_{r} = \mathrm{s_{w}} \times (w - Z_w)
$$
$$
b_{r} = \mathrm{s_{x}} \times \mathrm{s_{w}} \times b
$$
其中：
- $x_{r}、w_{r}、b_{r}$ 分别表示该层神经网络真实input与weight。
- $x、w、b$ 表示分别表示该层神经网络位于硬件中参与运算的输入值与权重。
- $s_{x}、s_{w}$ 为输入值与权重的scale（缩放因子），为浮点数。
- $Z_x、Z_w$为输入值与权重的zero_point（零点）。

于是有，每层神经网络激活函数的理论输入为：

$$
\begin{aligned}
x_{(i+1)r\_in} &= \mathrm{s_{xi}} \times \mathrm{s_{wi}} \times
\Big( \sum_i (x_i - Z_{xi})(w_i - Z_{wi}) + b_{i} \Big) \\
&=  \mathrm{s_{x(i+1)}} \times (x^*_{i+1} - Z_{x(i+1)})
\end{aligned}
$$

其中$x^*_{i+1}$为理论的下一层神经网络在硬件上的输入。

#### 2.激活值校准

实际上由于$x_{i+1}$必须为整数，硬件计算中实际输入为：

$$
\begin{aligned}
x_{(i+1)\_in} &= \Big\lfloor\frac{\mathrm{s_x} \times \mathrm{s_w} }{\mathrm{s_{x(i+1)}}}\Big( \sum_i (x_i - Z_{xi})(w_i - Z_{wi}) + b_{i} \Big)\Big\rceil+Z_{x(i+1)}\\
&= \frac{M_0\Big( \sum_i (x_i - Z_{xi})(w_i - Z_{wi}) + b_{i} \Big)}{2^s}+Z_{x(i+1)}
\end{aligned}
$$

其中$M_0$为整数系数，$s$为计算结果需要右移的次数

#### 3.归一化
设s' = s - 31, 若：

$$
M_{norm}=\frac{\mathrm{s_x} \times \mathrm{s_w} }{\mathrm{s_{x(i+1)}}}\times2^{s'}\in[0.5,1)
$$

则有：
$$
M_{norm}\times2^{31}=\frac{\mathrm{s_x} \times \mathrm{s_w} }{\mathrm{s_{x(i+1)}}}\times2^{s}\in[2^{30},2^{31})
$$

即通过归一化得到的$s'$可最大限度保留精度。

#### 4.对称量化

为提高硬件运算效率，在训练时$w_r$采用了对称量化，即 $Z_{w}=0$。设：

$$
b'_{i} = b_{i} -\sum_i Z_{xi}w_i
$$

于是有：

$$
\begin{aligned}
x_{(i+1)\_in} &= \frac{M_0\Big( \sum_i x_iw_i + (b_{i} -\sum_i Z_{xi}w_i) \Big)}{2^s}+Z_{x(i+1)}\\
&= \frac{M_0\Big( \sum_i x_iw_i + b'_{i} \Big)}{2^{s'+31}}+Z_{x(i+1)}
\end{aligned}
$$

即：

$$
Z'_{xi} = 0
$$

使用 $Z'_{xi}=0$ 和 $b'_{i}$ 作为等效值进一步增加硬件计算效率。

训练后静态量化
scale（缩放因子）
zero_point（零点）
量化
激活值校准

#### 5.激活函数输出
激活函数对硬件中整数进行[0,255]限位，即：
$$
x_{i+1} = \text{clamp}\Bigg( \frac{M_0\Big( \sum_i x_iw_i + b'_{i} \Big)}{2^{s'+31}}+Z_{x(i+1)},\ \ Z_{x(i+1)},\ 255 \Bigg)
$$

#### 6.模型生成结果
- 浮点模型的测试集准确率：98.08%

- 模型参数所在目录：models/hardware
  
	models目录已加入`.gitignore`列表，[点击这里](http://study.xiaoheika.cc/)可进入我的个人网站获取。

- 各类型参数存储状态：

| 公式中参数名称 | 模型文件中参数名称 | 所在文件的文件名 | 存储状态 |
|---|---|---|---|
| $M_0$ | requant_multipliers | model_config.json | 卷积层为 per-channel 量化，<br>全连接层为 per-tensor 量化|
| $w_i$ | 无，纯二进制文件 | conv1_weight.bin<br>conv2_weight.bin<br>fc1_weight.bin<br>fc2_weight.bin<br>fc3_weight.bin | 卷积核内先行后列，全连接层按序号排列，每weight以int_8紧密排列 |
| $b'_i$ | 无，纯二进制文件 | conv1_bias.bin<br>conv2_bias.bin<br>fc1_bias.bin<br>fc2_bias.bin<br>fc3_bias.bin | 按序号排列，每bias以int_32（小端模式）紧密排列 |
| $s'$ | requant_shifts | model_config.json | 卷积层为 per-channel 量化，<br>全连接层为 per-tensor 量化 |
| $Z_{x(i+1)}$ | output_zero_point | model_config.json | 每个layer中所有$Z_{x(i+1)}$ 一致 |

#### 7.后续硬件推理时，一个细节点的固化
- 所有除法运算均采用四舍五入

import torch  # PyTorch核心库
import torch.nn as nn  # 神经网络模块（包含各种层的定义）
import torch.optim as optim  # 优化器模块（用于更新网络权重）
from torch.utils.data import Dataset, DataLoader  # 数据加载工具
import numpy as np  # 用于处理numpy数组
import os
from torch.ao.quantization import QuantStub, DeQuantStub  # 量化入口/出口
from torch.ao.quantization import QConfig
from torch.ao.quantization.observer import (
    MovingAverageMinMaxObserver,
    MovingAveragePerChannelMinMaxObserver,
)


# ============================================================
# 第一部分：数据加载与预处理
# ============================================================

class MNISTDataset(Dataset):
    """
    自定义数据集类 - PyTorch加载数据的标准方式

    继承torch.utils.data.Dataset，需要实现三个方法：
    - __init__: 初始化，加载数据到内存
    - __len__: 返回数据集大小
    - __getitem__: 根据索引返回一个样本
    """

    def __init__(self, images, labels):
        """
        初始化数据集

        参数:
            images: numpy数组，形状为(N, 28, 28)，N是样本数量
            labels: numpy数组，形状为(N,)，每个值是0-9的数字
        """
        # 数据预处理步骤：
        # 1. torch.from_numpy(): 将numpy数组转换为PyTorch张量(Tensor)
        # 2. .float(): 转换为浮点数类型（神经网络需要浮点运算）
        # 3. .unsqueeze(1): 添加通道维度，从(N,28,28)变为(N,1,28,28)
        #    卷积层要求输入格式：(批次大小, 通道数, 高度, 宽度)
        # 4. / 255.0: 归一化到[0,1]范围，加速训练收敛
        self.images = torch.from_numpy(images).float().unsqueeze(1) / 255.0

        # 标签转换为长整型（分类任务的标准类型）
        self.labels = torch.from_numpy(labels).long()

    def __len__(self):
        """返回数据集的样本数量"""
        return len(self.labels)

    def __getitem__(self, idx):
        """
        根据索引返回一个样本

        DataLoader会自动调用这个方法来批量获取数据
        返回: (图像张量, 标签)
        """
        return self.images[idx], self.labels[idx]


def load_mnist(npz_path):
    """
    从.npz文件加载MNIST数据集

    .npz是numpy的压缩文件格式，可以存储多个数组
    MNIST标准格式包含：
    - x_train: 训练图像 (60000, 28, 28)
    - y_train: 训练标签 (60000,)
    - x_test: 测试图像 (10000, 28, 28)
    - y_test: 测试标签 (10000,)
    """

    # 这一行得到一个numpy.lib.npyio.NpzFile对象，该对象可以通过key来取里面的数组
    data = np.load(npz_path)

    # 提取四个数组
    x_train = data['x_train']  # 60000张28x28的灰度图像
    y_train = data['y_train']  # 60000个标签（0-9）
    x_test = data['x_test']  # 10000张测试图像
    y_test = data['y_test']  # 10000个测试标签

    print(f"训练集: {x_train.shape}, 测试集: {x_test.shape}")
    return x_train, y_train, x_test, y_test


# ============================================================
# 第二部分：神经网络定义 - LeNet-5架构
# ============================================================

class LeNet5(nn.Module):
    """
    LeNet-5卷积神经网络 - 1998年Yann LeCun提出的经典架构

    网络结构（5层可训练层）：
    输入: 1@28x28 → Conv1 → Pool1 → Conv2 → Pool2 → FC1 → FC2 → FC3 → 10类
    """

    def __init__(self):
        """定义网络的所有层"""
        super().__init__()

        # ===== 量化入口/出口（静态量化必须）=====
        # quant: 把浮点输入转成量化张量
        # dequant: 把量化输出转回浮点
        # 浮点训练时它俩是"透明"的，什么都不做；量化后才起作用
        self.quant = QuantStub()
        self.dequant = DeQuantStub()

        # ===== 第1层：卷积层 =====
        # 输入: 1通道(灰度图), 输出: 6个特征图, 卷积核: 5x5
        # 输出尺寸: (28-5+1)=24, 即 6@24x24
        self.conv1 = nn.Conv2d(in_channels=1, out_channels=6, kernel_size=5)

        # ===== 第2层：池化层 =====
        # 2x2平均池化, 输出: 6@12x12
        self.pool1 = nn.AvgPool2d(kernel_size=2, stride=2)

        # ===== 第3层：卷积层 =====
        # 输入: 6通道, 输出: 16通道, 卷积核: 5x5
        # 输出尺寸: (12-5+1)=8, 即 16@8x8
        self.conv2 = nn.Conv2d(in_channels=6, out_channels=16, kernel_size=5)

        # ===== 第4层：池化层 =====
        # 输出: 16@4x4 = 256维向量（展平后）
        self.pool2 = nn.AvgPool2d(kernel_size=2, stride=2)

        # ===== 第5层：全连接层 =====
        # 输入: 16*4*4=256维, 输出: 120维
        self.fc1 = nn.Linear(in_features=16 * 4 * 4, out_features=120)

        # ===== 第6层：全连接层 =====
        # 输入: 120维, 输出: 84维
        self.fc2 = nn.Linear(in_features=120, out_features=84)

        # ===== 第7层：输出层 =====
        # 输入: 84维, 输出: 10维（10个数字类别0-9）
        self.fc3 = nn.Linear(in_features=84, out_features=10)

    def forward(self, x):
        """
        前向传播函数

        参数:
            x: 输入张量，形状为(batch_size, 1, 28, 28)
        返回:
            输出张量，形状为(batch_size, 10)
        """
        # 入口：把浮点输入量化（浮点训练时透明）
        x = self.quant(x)

        # 第1层：卷积 + ReLU激活
        x = torch.relu(self.conv1(x))  # (batch,1,28,28) → (batch,6,24,24)

        # 第2层：池化
        x = self.pool1(x)              # → (batch,6,12,12)

        # 第3层：卷积 + ReLU激活
        x = torch.relu(self.conv2(x))  # → (batch,16,8,8)

        # 第4层：池化
        x = self.pool2(x)              # → (batch,16,4,4)

        # 展平
        x = x.reshape(x.size(0), -1)   # → (batch,256)（量化张量用reshape，view会因stride报错）

        # 第5层：全连接 + ReLU
        x = torch.relu(self.fc1(x))    # → (batch,120)

        # 第6层：全连接 + ReLU
        x = torch.relu(self.fc2(x))    # → (batch,84)

        # 第7层：输出层
        x = self.fc3(x)                # → (batch,10)

        # 出口：把量化结果转回浮点（浮点训练时透明）
        x = self.dequant(x)
        return x



# ============================================================
# 第三部分：模型训练
# ============================================================

def train_model(model, train_loader, test_loader, epochs=10, device='cpu', save_path='data/models/lenet5_best.pth'):
    """
    训练神经网络直到达到98%准确率

    参数:
        model: 要训练的神经网络
        train_loader: 训练数据加载器
        test_loader: 测试数据加载器
        epochs: 最大训练轮数（一轮 = 遍历一次全部训练数据）
        device: 'cpu'或'cuda'（GPU）
        save_path: 模型保存路径

    返回:
        best_acc: 达到的最佳准确率
    """

    # 确保保存目录存在
    os.makedirs(os.path.dirname(save_path), exist_ok=True)

    # ===== 定义损失函数 =====
    # CrossEntropyLoss: 交叉熵损失，用于多分类任务
    # 它结合了Softmax和负对数似然损失
    # 输入: 原始得分(logits)，输出: 标量损失值
    criterion = nn.CrossEntropyLoss()

    # ===== 定义优化器 =====
    # Adam: 自适应学习率优化算法，比传统SGD收敛更快
    # model.parameters(): 获取所有需要训练的参数（权重和偏置）
    # lr: 学习率，控制每次参数更新的步长
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    # 将模型移动到指定设备（CPU或GPU）
    model.to(device)
    best_acc = 0.0  # 记录最佳准确率

    # ===== 训练循环 =====
    for epoch in range(epochs):
        # ----- 训练阶段 -----
        model.train()  # 设置为训练模式（启用Dropout、BatchNorm等）
        train_loss = 0.0

        # 遍历训练数据
        # train_loader每次返回一个批次(batch)的数据
        for images, labels in train_loader:
            # 将数据移动到设备
            images, labels = images.to(device), labels.to(device)

            # 1. 清零梯度
            # PyTorch默认会累积梯度，每次反向传播前需要清零
            optimizer.zero_grad()

            # 2. 前向传播：输入数据，得到预测结果
            outputs = model(images)  # (batch_size, 10)

            # 3. 计算损失：比较预测和真实标签
            loss = criterion(outputs, labels)

            # 4. 反向传播：计算梯度（每个参数对损失的偏导数）
            loss.backward()

            # 5. 更新参数：根据梯度调整权重
            optimizer.step()

            # 累积损失（用于统计）
            train_loss += loss.item()

        # ----- 测试阶段 -----
        model.eval()  # 设置为评估模式（关闭Dropout、BatchNorm等）
        correct = 0  # 正确预测的数量
        total = 0  # 总样本数

        # torch.no_grad(): 不计算梯度，节省内存和计算
        with torch.no_grad():
            for images, labels in test_loader:
                images, labels = images.to(device), labels.to(device)

                # 前向传播
                outputs = model(images)  # (batch_size, 10)

                # 获取预测类别
                # torch.max返回(最大值, 最大值的索引)
                # dim=1表示在第1维（类别维）上取最大
                predicted = torch.argmax(outputs, 1)

                # 统计准确率
                total += labels.size(0)
                correct += (predicted == labels).sum().item()

        # 计算准确率
        accuracy = 100 * correct / total

        # 打印本轮训练结果
        print(f'Epoch [{epoch + 1}/{epochs}], '
              f'Loss: {train_loss / len(train_loader):.4f}, '
              f'Accuracy: {accuracy:.2f}%')

        # 保存最佳模型
        if accuracy > best_acc:
            best_acc = accuracy
            # torch.save: 保存模型权重到文件
            # state_dict(): 获取所有参数的字典
            torch.save(model.state_dict(), save_path)
            print(f'  -> 保存最佳模型 (准确率: {best_acc:.2f}%)')

        # 达到目标准确率，提前停止
        if accuracy >= 98.0:
            print(f'\n✓ 达到目标准确率 98%！最终准确率: {accuracy:.2f}%')
            break

    return best_acc


# ============================================================
# 第四部分：INT8量化（模型压缩）
# ============================================================
def get_symmetric_qconfig():
    """
    权重对称 + 激活非对称的量化配置。

    - 激活：quint8 非对称（onednn强制要求无符号，zero_point非0）
    - 权重：qint8 per-channel对称（zero_point恒为0）

    权重对称后，硬件不用处理权重零点交叉项；
    激活的零点会在导出时离线折进bias，硬件运行时也不用管。
    """
    activation = MovingAverageMinMaxObserver.with_args(
        dtype=torch.quint8,
        qscheme=torch.per_tensor_affine,   # 非对称，满足onednn
    )
    weight = MovingAveragePerChannelMinMaxObserver.with_args(
        dtype=torch.qint8,
        qscheme=torch.per_channel_symmetric,  # 对称，zero_point=0
    )
    return QConfig(activation=activation, weight=weight)


def quantize_model(model, test_loader, device='cpu'):
    """
    执行PTQ (Post-Training Quantization) - 训练后量化

    量化原理：
    - 浮点数(FP32)：32位，范围广，精度高，但占内存大、计算慢
    - 整数(INT8)：8位，范围小，精度低，但占内存小（1/4）、计算快
    - 量化公式: int8_value = round(fp32_value / scale) + zero_point
    - 反量化公式: fp32_value = (int8_value - zero_point) * scale

    PTQ流程：
    1. 在训练好的模型中插入"观察器"(Observer)
    2. 用校准数据运行模型，观察器收集每层激活值的统计信息
    3. 根据统计信息计算scale和zero_point
    4. 将FP32权重和激活转换为INT8

    参数:
        model: 训练好的浮点模型
        test_loader: 用于校准的数据
        device: 'cpu'（量化只支持CPU）
    """
    model.to(device)
    model.eval()

    # ===== 关键：自动选择可用的量化后端引擎 =====
    # 有些PyTorch构建（尤其Windows）不带fbgemm，需要按实际支持的引擎选
    supported = torch.backends.quantized.supported_engines
    print(f"当前PyTorch支持的量化引擎: {supported}")
    if 'fbgemm' in supported:
        engine = 'fbgemm'      # x86服务器/桌面首选
    elif 'x86' in supported:
        engine = 'x86'         # 新版PyTorch的统一x86后端
    elif 'qnnpack' in supported:
        engine = 'qnnpack'     # ARM/移动端后端，也能在x86跑
    else:
        engine = supported[0]  # 兜底：用列表里第一个
    torch.backends.quantized.engine = engine
    print(f"使用量化引擎: {engine}")

    # ===== 步骤1：设置量化配置（对称量化，zero_point全为0）=====
    # 用自定义对称配置替代默认的非对称配置，硬件requantize可省去零点处理
    model.qconfig = get_symmetric_qconfig()

    # ===== 步骤2：准备量化（插入观察器）=====
    # prepare会：
    # 1. 在每个卷积层、全连接层后插入Observer
    # 2. Observer会记录激活值的最小值、最大值等统计信息
    # inplace=False: 不修改原模型，返回新模型
    model_prepared = torch.quantization.prepare(model, inplace=False)

    # ===== 步骤3：校准（收集统计信息）=====
    # 用一部分数据运行模型，让Observer收集信息
    # 通常100-1000个样本就足够
    print("\n开始校准量化参数...")
    with torch.no_grad():
        for i, (images, labels) in enumerate(test_loader):
            if i >= 100:  # 只用100个batch校准
                break
            images = images.to(device)
            # 前向传播，Observer在后台记录
            model_prepared(images)

    # ===== 步骤4：转换为量化模型 =====
    # convert会：
    # 1. 根据Observer收集的统计信息计算scale和zero_point
    # 2. 将FP32权重转换为INT8
    # 3. 替换算子为量化版本（如nn.Conv2d → nn.quantized.Conv2d）
    model_quantized = torch.quantization.convert(model_prepared, inplace=False)

    # ===== 步骤5：测试量化后的准确率 =====
    # 量化会带来精度损失，通常损失<1%
    correct = 0
    total = 0
    with torch.no_grad():
        for images, labels in test_loader:
            images = images.to(device)
            labels = labels.to(device)
            outputs = model_quantized(images)
            _, predicted = torch.max(outputs.data, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()

    quant_accuracy = 100 * correct / total
    print(f'量化后准确率: {quant_accuracy:.2f}%')

    return model_quantized

def export_for_hardware(model_quantized, output_dir='data/models/hardware'):
    """
    导出硬件能用的格式：
    - 权重/偏置存成 .bin 二进制文件（纯字节，C语言能直接读）
    - 量化参数存成 .json 文件（人类可读的配置）
    
    KV260上的C程序会：
    1. 读JSON知道每层的形状、缩放参数
    2. 读.bin文件拿到权重数组，直接memcpy到DDR
    """
    import os
    import json
    import numpy as np
    
    # 创建输出目录
    os.makedirs(output_dir, exist_ok=True)
    print(f"\n导出硬件模型到目录: {output_dir}/")
    
    # 用来存所有层的配置
    model_config = {
        'model_name': 'LeNet5',
        'input_shape': [1, 28, 28],    # MNIST图像尺寸
        'num_classes': 10,
        'layers': []                    # 每层的详细信息
    }
    
    # 记录每层的输出scale（下一层需要用）
    layer_scales = {}
    
    # ===== 第一步：找到输入量化的scale（网络第一层的输入scale）=====
    # PyTorch量化模型在最开始有个QuantStub，它的输出scale就是输入图像的scale
    input_scale = None
    input_zero_point = None
    for name, module in model_quantized.named_modules():
        # convert后QuantStub变成Quantize模块，按名字'quant'找它，读真实scale
        if name == 'quant' and hasattr(module, 'scale'):
            input_scale = float(module.scale)
            input_zero_point = int(module.zero_point)
            print(f"输入量化参数: scale={input_scale:.6f}, zero_point={input_zero_point}")
            break
    
    # 如果没找到QuantStub，用第一个量化层的输入scale（通常是1/255）
    if input_scale is None:
        input_scale = 1.0 / 255.0
        input_zero_point = 0
        print(f"使用默认输入量化: scale={input_scale:.6f}, zero_point={input_zero_point}")
    
    model_config['input_scale'] = float(input_scale)
    model_config['input_zero_point'] = int(input_zero_point)
    
    # 当前层的输入scale（第一层用input_scale，后续层用上一层的输出scale）
    current_input_scale = input_scale
    current_input_zero_point = input_zero_point   # 新增：追踪输入零点
    # ===== 第二步：遍历每一层，导出权重和参数 =====
    layer_count = 0
    for name, module in model_quantized.named_modules():
        # 只处理卷积层和全连接层（这两种层有权重）
        layer_type = None
        if isinstance(module, torch.nn.quantized.Conv2d):
            layer_type = 'conv2d'
        elif isinstance(module, torch.nn.quantized.Linear):
            layer_type = 'linear'
        else:
            continue  # 跳过池化层、激活层等
        
        print(f"\n处理第 {layer_count+1} 层: {name} ({layer_type})")
        
        # ----- 2.1 提取权重（INT8整数） -----
        weight_quantized = module.weight()  # 这是量化后的张量
        weight_int8 = weight_quantized.int_repr().numpy().astype(np.int8)  # 转成numpy的int8数组
        print(f"  权重形状: {weight_int8.shape}")
        
        # ----- 2.2 提取权重的scale和zero_point -----
        # PyTorch的fbgemm对卷积用per-channel量化（每个输出通道一个scale）
        # 对全连接用per-tensor量化（整个权重矩阵一个scale）
        if weight_quantized.qscheme() in (torch.per_channel_affine, torch.per_channel_symmetric):
            # per-channel: 每个输出通道有独立的scale
            weight_scales = weight_quantized.q_per_channel_scales().numpy()
            weight_zero_points = weight_quantized.q_per_channel_zero_points().numpy().astype(np.int32)
            print(f"  权重量化: per-channel, {len(weight_scales)}个通道")
        else:
            # per-tensor: 整个权重一个scale
            weight_scales = np.array([weight_quantized.q_scale()])
            weight_zero_points = np.array([weight_quantized.q_zero_point()]).astype(np.int32)
            print(f"  权重量化: per-tensor")
        
        # ----- 2.3 提取偏置，并把输入zero_point折进去 -----
        # 权重对称(Zw=0)后，真值 = Sw·Sx·[Σ(w·x) - Zx·Σw] + bias_fp
        # 把 -Zx·Σw 折进bias，硬件运行时就不用处理输入零点了。
        # bias量化到acc域：bias_int = round(bias_fp / (Sw·Sx))
        bias_scale = weight_scales * current_input_scale  # 每通道一个(per-channel)

        if module.bias() is not None:
            bias_fp = module.bias().detach().numpy()
            bias_int32 = np.round(bias_fp / bias_scale).astype(np.int64)
        else:
            bias_int32 = np.zeros(weight_int8.shape[0], dtype=np.int64)

        # 计算每个输出通道的权重和 Σw，用于折叠输入zero_point
        # 权重形状: conv=[out,in,kh,kw], linear=[out,in]，对除第0维外求和
        weight_sum_per_out = weight_int8.reshape(weight_int8.shape[0], -1).sum(axis=1).astype(np.int64)

        # 折叠：bias_int - Zx·Σw
        bias_int32 = bias_int32 - int(current_input_zero_point) * weight_sum_per_out
        bias_int32 = bias_int32.astype(np.int32)
        print(f"  偏置形状: {bias_int32.shape}（已量化并折入输入零点）")
        
        # ----- 2.4 提取输出的scale和zero_point -----
        output_scale = float(module.scale)
        output_zero_point = int(module.zero_point)
        print(f"  输出量化: scale={output_scale:.6f}, zero_point={output_zero_point}")
        
        # ----- 2.5 计算requantize参数（M0和shift）-----
        # 硬件计算流程：
        # 1. 脉动阵列算出 acc = Σ(w_int8 * x_int8)，这是INT32
        # 2. 需要转回INT8输出：out_int8 = (acc * M0) >> shift + zero_point
        # 其中 M0 和 shift 是把浮点乘法 M = (weight_scale * input_scale / output_scale) 
        # 转成定点运算的参数
        
        real_multipliers = weight_scales * current_input_scale / output_scale
        multipliers = []  # M0（INT32）
        shifts = []       # shift（INT32）
        
        for M in real_multipliers:
            M0, shift = compute_requantize_params(M)
            multipliers.append(M0)
            shifts.append(shift)
        
        print(f"  Requantize: {len(multipliers)}个通道的(M0, shift)参数")
        
        # ----- 2.6 保存权重和偏置到二进制文件 -----
        weight_filename = f'{name.replace(".", "_")}_weight.bin'
        bias_filename = f'{name.replace(".", "_")}_bias.bin'
        
        weight_int8.tofile(os.path.join(output_dir, weight_filename))
        bias_int32.tofile(os.path.join(output_dir, bias_filename))
        
        print(f"  已保存: {weight_filename} ({weight_int8.nbytes} bytes)")
        print(f"  已保存: {bias_filename} ({bias_int32.nbytes} bytes)")
        
        # ----- 2.7 记录这层的配置到JSON -----
        layer_info = {
            'layer_id': layer_count,
            'name': name,
            'type': layer_type,
            'weight_file': weight_filename,
            'bias_file': bias_filename,
            'weight_shape': list(weight_int8.shape),  # [out_ch, in_ch, kh, kw] for conv
            'bias_shape': list(bias_int32.shape),
            
            # 量化参数
            'input_scale': float(current_input_scale),
            'input_zero_point': 0,  # 通常ReLU后输出是uint8，zero_point=0
            'weight_scales': weight_scales.tolist(),
            'weight_zero_points': weight_zero_points.tolist(),
            'output_scale': output_scale,
            'output_zero_point': output_zero_point,
            
            # Requantize参数（硬件用）
            'requant_multipliers': multipliers,  # M0数组
            'requant_shifts': shifts,             # shift数组
        }
        
        # 如果是卷积层，还要记录卷积核大小、步长等
        if layer_type == 'conv2d':
            layer_info['kernel_size'] = list(module.kernel_size)
            layer_info['stride'] = list(module.stride)
            layer_info['padding'] = list(module.padding)
        
        model_config['layers'].append(layer_info)
        
        # 更新：下一层的输入scale就是这层的输出scale
        current_input_scale = output_scale
        current_input_zero_point = output_zero_point   # 新增：下一层输入零点=本层输出零点
        layer_count += 1
    
    # ===== 第三步：保存JSON配置文件 =====
    json_filename = os.path.join(output_dir, 'model_config.json')
    with open(json_filename, 'w') as f:
        json.dump(model_config, f, indent=2)
    
    print(f"\n✓ 配置文件已保存: {json_filename}")
    print(f"✓ 共导出 {layer_count} 层")
    print(f"✓ 硬件可用的模型文件已准备好在 {output_dir}/ 目录")
    
    return model_config


def compute_requantize_params(real_multiplier):
    """
    把浮点乘数M转成硬件能用的定点参数 (M0, shift)
    
    原理：
    - 硬件不能做浮点乘法，只能做整数乘法和移位
    - 把 M 表示成 M ≈ M0 / 2^shift 的形式
    - 其中 M0 是一个INT32，满足 0.5 ≤ M0/2^31 < 1
    
    例子：
    - M = 0.003 → M0 = 1610612736, shift = 39
      因为 1610612736 / 2^39 ≈ 0.003
    
    硬件计算时：
    output = (accumulator * M0) >> (31 + shift)
    """
    if real_multiplier == 0:
        return 0, 0
    
    # 把M调整到[0.5, 1)区间，记录调整的次数就是shift
    shift = 0
    M = real_multiplier
    
    while M < 0.5:
        M *= 2.0
        shift += 1
    
    while M >= 1.0:
        M /= 2.0
        shift -= 1
    
    # M现在在[0.5, 1)区间，乘以2^31得到INT32
    M0 = int(round(M * (1 << 31)))
    
    # 边界情况：如果M非常接近1，M0可能=2^31，需要调整
    if M0 == (1 << 31):
        M0 = M0 // 2
        shift -= 1
    
    return M0, shift


# ============================================================
# 第五部分：主程序入口
# ============================================================

def main():
    """主函数 - 执行完整流程"""

    # ===== 统一的模型输出目录 =====
    # 所有生成的模型文件都放在 data/models/ 下
    # 这样在项目根目录写 .gitignore 忽略 data/ 即可避免模型占用仓库空间
    MODELS_DIR = 'data/models'
    os.makedirs(MODELS_DIR, exist_ok=True)

    # 各文件的完整路径
    float_model_path = os.path.join(MODELS_DIR, 'lenet5_best.pth')      # 浮点模型
    quant_model_path = os.path.join(MODELS_DIR, 'lenet5_int8.pth')      # 量化模型
    hardware_dir = os.path.join(MODELS_DIR, 'hardware')                 # 硬件导出目录

    # ===== 设备选择 =====
    # 检查是否有可用的GPU（CUDA）
    # GPU训练速度比CPU快10-100倍
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f'使用设备: {device}')

    # ===== 阶段1：加载数据 =====
    print("\n[1/4] 加载MNIST数据...")
    # 这里x_表示图像，y_表示标签。
    x_train, y_train, x_test, y_test = load_mnist('data/MNIST/mnist.npz')

    # 创建Dataset对象
    train_dataset = MNISTDataset(x_train, y_train)
    test_dataset = MNISTDataset(x_test, y_test)

    # 创建DataLoader对象
    # DataLoader的作用：
    # 1. 自动分批(batch)
    # 2. 自动打乱(shuffle)
    # 3. 多进程加载数据（num_workers）
    # 4. 自动将数据组装成张量
    train_loader = DataLoader(
        train_dataset,
        batch_size=64,  # 每批64个样本（太小训练慢，太大显存不够）
        shuffle=True    # 打乱顺序（提高泛化能力）
    )
    test_loader = DataLoader(
        test_dataset,
        batch_size=1000,  # 测试时可以用更大的batch
        shuffle=False     # 测试不需要打乱
    )

    # ===== 阶段2：创建并训练模型 =====
    print("\n[2/4] 训练LeNet-5模型...")
    model = LeNet5()
    print(model)  # 打印网络结构

    # 训练模型（save_path指向data/models目录）
    best_acc = train_model(
        model,
        train_loader,
        test_loader,
        epochs=20,               # 最多训练20轮（通常5-10轮就能达到98%）
        device=device,
        save_path=float_model_path
    )

    # 加载最佳模型（训练过程中自动保存的）
    model.load_state_dict(torch.load(float_model_path))
    print(f"\n✓ 浮点模型已保存: {float_model_path} (准确率: {best_acc:.2f}%)")

    # ===== 阶段3：量化模型 =====
    print("\n[3/4] 执行INT8量化...")
    # 注意：PyTorch的量化只支持CPU
    # 把模型搬回CPU量化
    model_cpu = model.to('cpu')
    model_quantized = quantize_model(model_cpu, test_loader, device='cpu')

    # 保存量化模型（PyTorch格式，用于调试或后续复现）
    torch.save(model_quantized.state_dict(), quant_model_path)
    print(f"✓ 量化模型已保存: {quant_model_path}")

    # ===== 阶段4：导出硬件模型 =====
    print("\n[4/4] 导出硬件模型...")
    model_config = export_for_hardware(model_quantized, output_dir=hardware_dir)

    # ===== 完成总结 =====
    print("\n" + "=" * 50)
    print("✓ 完成！生成的文件（全部在 data/models/ 下）:")
    print(f"  - {float_model_path}: 浮点模型权重 (FP32)")
    print(f"  - {quant_model_path}: INT8量化模型 (PyTorch格式)")
    print(f"  - {hardware_dir}/model_config.json: 硬件配置文件")
    print(f"  - {hardware_dir}/*.bin: 各层权重和偏置的二进制文件")
    print("=" * 50)
    print("\n提示：在项目根目录的 .gitignore 中加入一行 'data/' 即可忽略所有模型文件")


# ============================================================
# 程序入口
# ============================================================

if __name__ == '__main__':
    """
    Python标准写法：
    - 直接运行此脚本时，__name__ == '__main__'，会执行main()
    - 作为模块导入时，__name__ == '模块名'，不会执行main()
    """
    main()

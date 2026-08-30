import numpy as np
import json
import os

# ============================================================
# 量化算子 - 严格按四条规则；激活为 uint8 [0,255]
# ============================================================

def requantize(acc, M0, shift, out_zp):
    """要求2、3: 用M0/shift重量化，round-half-up。硬件右移 = 31 + shift"""
    total = 31 + shift                       # M0是Q31定点
    acc = (acc.astype(np.int64) * M0 + (np.int64(1) << (total - 1))) >> total
    return np.clip(acc + out_zp, 0, 255)     # 要求：激活uint8

def quant_input(x_fp, scale, zp):
    """要求4: 输入量化 round-half-up；输入已归一化到[0,1]"""
    return np.clip(np.floor(x_fp / scale + 0.5) + zp, 0, 255).astype(np.int32)

def conv2d(x, w, b, M0, shift, out_zp, stride=1, padding=0):
    """卷积(im2col) + 重量化。x:(C_in,H,W) w:(C_out,C_in,kh,kw)"""
    C_in, H, W = x.shape
    C_out, _, kh, kw = w.shape
    H_out = (H + 2*padding - kh) // stride + 1
    W_out = (W + 2*padding - kw) // stride + 1
    if padding > 0:
        x = np.pad(x, ((0,0),(padding,padding),(padding,padding)), constant_values=0)

    # im2col: (C_in*kh*kw, H_out*W_out)
    col = np.empty((C_in*kh*kw, H_out*W_out), dtype=np.int32)
    idx = 0
    for c in range(C_in):
        for i in range(kh):
            for j in range(kw):
                patch = x[c, i:i+H_out*stride:stride, j:j+W_out*stride:stride]
                col[idx] = patch.reshape(-1)
                idx += 1

    w_flat = w.reshape(C_out, -1).astype(np.int32)   # (C_out, C_in*kh*kw)
    acc = w_flat @ col + b[:, None]                  # (C_out, H_out*W_out) int32
    acc = requantize(acc, M0[:, None], shift[:, None], out_zp)
    return acc.reshape(C_out, H_out, W_out).astype(np.int32)

def avgpool2x2(x):
    """要求1: 平均池化 (sum+2)//4"""
    s = x[:, 0::2, 0::2] + x[:, 0::2, 1::2] + x[:, 1::2, 0::2] + x[:, 1::2, 1::2]
    return ((s + 2) // 4).astype(np.int32)

def linear(x, w, b, M0, shift, out_zp):
    """全连接 + 重量化。x:(in,) w:(out,in)"""
    acc = w.astype(np.int32) @ x + b                 # (out,) int32
    if M0.size == 1:                                 # per-tensor
        acc = requantize(acc, M0[0], shift[0], out_zp)
    else:                                            # per-channel
        acc = requantize(acc, M0, shift, out_zp)
    return acc.astype(np.int32)

def relu(x, zp):
    """ReLU: 量化域里就是 max(x, zero_point)"""
    return np.maximum(x, zp).astype(np.int32)

# ============================================================
# 加载模型 + 前向
# ============================================================

def load_model(model_dir):
    with open(os.path.join(model_dir, 'model_config.json'), encoding='utf-8') as f:
        cfg = json.load(f)
    if cfg.get('activation_dtype') != 'uint8':
        raise RuntimeError('model_config中的激活数据类型不是uint8')
    if cfg.get('weight_dtype') != 'int8':
        raise RuntimeError('model_config中的权重数据类型不是int8')
    if cfg.get('weight_layout') != '[cout_group][K][cout_lane]':
        raise RuntimeError('model_config中的权重布局与当前硬件布局不一致')
    params = {}
    expected_input_zero_point = cfg['input_zero_point']
    for layer in cfg['layers']:
        name = layer['name']
        weight_shape = tuple(layer['weight_shape'])
        out_channels = weight_shape[0]
        k_size = int(np.prod(weight_shape[1:], dtype=np.int64))
        padded_out_channels = ((out_channels + 7) // 8) * 8
        if layer.get('padded_out_channels') != padded_out_channels:
            raise RuntimeError(f'{name}补齐输出通道数错误')
        if layer.get('weight_layout') != '[cout_group][K][cout_lane]':
            raise RuntimeError(f'{name}权重布局标记错误')
        if layer['type'] == 'conv2d':
            expected_k_order = '(kernel_y,kernel_x,cin)'
        elif name == 'fc1':
            expected_k_order = '(y,x,cin)'
        else:
            expected_k_order = '(input_neuron)'
        if layer.get('weight_k_order') != expected_k_order:
            raise RuntimeError(f'{name}的K方向顺序标记错误')
        if layer.get('input_zero_point') != expected_input_zero_point:
            raise RuntimeError(f'{name}的输入zero point与上一层输出不连续')
        if layer.get('input_zero_point_folded_into_bias') is not True:
            raise RuntimeError(f'{name}没有标记输入zero point已折入偏置')
        if len(layer['weight_scales']) != out_channels:
            raise RuntimeError(f'{name}权重不是per-channel量化')
        if any(zp != 0 for zp in layer['weight_zero_points']):
            raise RuntimeError(f'{name}存在非零权重zero point')
        if len(layer['requant_multipliers']) != out_channels or \
                len(layer['requant_shifts']) != out_channels:
            raise RuntimeError(f'{name}的重定量化参数数量错误')

        # 文件中的权重按[cout_group][K][cout_lane]存储；先还原为
        # [真实输出通道][硬件K]，再还原成PyTorch计算使用的维度顺序。
        weight_raw = np.fromfile(
            os.path.join(model_dir, layer['weight_file']), dtype='<i1'
        )
        expected_weight_count = padded_out_channels * k_size
        if weight_raw.size != expected_weight_count:
            raise RuntimeError(
                f'{name}权重文件大小错误：期望{expected_weight_count} Byte，'
                f'实际{weight_raw.size} Byte'
            )
        w_flat_padded = weight_raw.reshape(
            padded_out_channels // 8, k_size, 8
        ).transpose(0, 2, 1).reshape(padded_out_channels, k_size)
        if np.any(w_flat_padded[out_channels:] != 0):
            raise RuntimeError(f'{name}补齐输出通道中存在非零权重')
        w_flat_hw = w_flat_padded[:out_channels]

        if layer['type'] == 'conv2d':
            _, in_channels, kernel_h, kernel_w = weight_shape
            w = w_flat_hw.reshape(
                out_channels, kernel_h, kernel_w, in_channels
            ).transpose(0, 3, 1, 2).copy()
        elif name == 'fc1':
            w = w_flat_hw.reshape(out_channels, 4, 4, 16) \
                         .transpose(0, 3, 1, 2).reshape(weight_shape).copy()
        else:
            w = w_flat_hw.reshape(weight_shape)
        bias_raw = np.fromfile(
            os.path.join(model_dir, layer['bias_file']), dtype='<i4'
        )
        expected_bias_count = int(np.prod(layer['bias_shape'], dtype=np.int64))
        if bias_raw.size != expected_bias_count:
            raise RuntimeError(f'{name}偏置文件大小错误')
        b = bias_raw.reshape(layer['bias_shape'])
        params[name] = {
            'w': w, 'b': b,
            'M0': np.array(layer['requant_multipliers'], dtype=np.int64),
            'shift': np.array(layer['requant_shifts'], dtype=np.int64),
            'out_zp': layer['output_zero_point'],
        }
        if layer['type'] == 'conv2d':
            params[name]['stride'] = layer['stride'][0]
            params[name]['padding'] = layer['padding'][0]
        expected_input_zero_point = layer['output_zero_point']
    return cfg, params

def forward(img_fp, cfg, params):
    """img_fp: (28,28) 原始像素[0,255]"""
    x = quant_input(img_fp / 255.0, cfg['input_scale'], cfg['input_zero_point'])
    x = x.reshape(1, 28, 28)                         # (C,H,W)

    p = params['conv1']
    x = conv2d(x, p['w'], p['b'], p['M0'], p['shift'], p['out_zp'], p['stride'], p['padding'])
    x = relu(x, p['out_zp'])
    x = avgpool2x2(x)

    p = params['conv2']
    x = conv2d(x, p['w'], p['b'], p['M0'], p['shift'], p['out_zp'], p['stride'], p['padding'])
    x = relu(x, p['out_zp'])
    x = avgpool2x2(x)

    x = x.reshape(-1)                                # flatten

    p = params['fc1']; x = relu(linear(x, p['w'], p['b'], p['M0'], p['shift'], p['out_zp']), p['out_zp'])
    p = params['fc2']; x = relu(linear(x, p['w'], p['b'], p['M0'], p['shift'], p['out_zp']), p['out_zp'])
    p = params['fc3']; x = linear(x, p['w'], p['b'], p['M0'], p['shift'], p['out_zp'])
    return x

# ============================================================
# 测准确率
# ============================================================

def test_accuracy(model_dir, npz_path):
    cfg, params = load_model(model_dir)
    data = np.load(npz_path)
    x_test, y_test = data['x_test'], data['y_test']
    correct = 0
    for i in range(len(y_test)):
        if np.argmax(forward(x_test[i].astype(np.float64), cfg, params)) == y_test[i]:
            correct += 1
        if (i+1) % 1000 == 0:
            print(f'  {i+1}/{len(y_test)}  当前准确率 {100.0*correct/(i+1):.2f}%')
    print(f'\n准确率: {100.0*correct/len(y_test):.2f}% ({correct}/{len(y_test)})')
    return correct, len(y_test)

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, '..', '..', '..'))
    MODEL_DIR = os.path.join(project_root, 'models', 'hardware')
    MNIST_PATH = os.path.join(script_dir, 'data', 'MNIST', 'mnist.npz')
    test_accuracy(MODEL_DIR, MNIST_PATH)

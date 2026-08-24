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
    with open(os.path.join(model_dir, 'model_config.json')) as f:
        cfg = json.load(f)
    params = {}
    for layer in cfg['layers']:
        name = layer['name']
        w = np.fromfile(os.path.join(model_dir, layer['weight_file']), dtype=np.int8).reshape(layer['weight_shape'])
        b = np.fromfile(os.path.join(model_dir, layer['bias_file']), dtype=np.int32).reshape(layer['bias_shape'])
        params[name] = {
            'w': w, 'b': b,
            'M0': np.array(layer['requant_multipliers'], dtype=np.int64),
            'shift': np.array(layer['requant_shifts'], dtype=np.int64),
            'out_zp': layer['output_zero_point'],
        }
        if layer['type'] == 'conv2d':
            params[name]['stride'] = layer['stride'][0]
            params[name]['padding'] = layer['padding'][0]
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

if __name__ == '__main__':
    MODEL_DIR = r'E:\prj\ASIC_CNN_accelerator\models\hardware'
    MNIST_PATH = r'E:\prj\ASIC_CNN_accelerator\sw\python\model_training\data\MNIST\mnist.npz'
    test_accuracy(MODEL_DIR, MNIST_PATH)

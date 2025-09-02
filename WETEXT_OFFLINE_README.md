# WeText模型离线化说明

## 问题描述
原项目在macOS系统上运行IndexTTS时，会自动从 `www.modelscope.cn` 下载wetext模型，导致网络连接错误：
```
Failed to resolve 'www.modelscope.cn'
```

## 解决方案
已成功实现wetext模型的离线化，避免运行时从网络下载模型。

## 文件变更

### 1. 新增文件
- `download_wetext_model.py` - 模型下载脚本
- `test_offline_wetext.py` - 离线模式测试脚本  
- `models/wetext/` - 本地模型文件目录
- `WETEXT_OFFLINE_README.md` - 本说明文档

### 2. 修改文件
- `indextts/utils/front.py` - 修改TextNormalizer.load()方法，优先使用本地模型

## 本地模型结构
```
models/wetext/
├── zh/tn/              # 中文文本标准化模型
│   ├── tagger.fst      # 标签器 (0.8MB)
│   └── verbalizer.fst  # 语言化器 (0.1MB)
└── en/tn/              # 英文文本标准化模型
    ├── tagger.fst      # 标签器 (5.0MB)
    └── verbalizer.fst  # 语言化器 (1.7MB)
```

## 使用方法

### 自动下载模型（推荐）
```bash
python3 download_wetext_model.py
```

### 测试离线模式
```bash
python3 test_offline_wetext.py
```

### 手动下载模型
如果自动下载失败，可以：
1. 在有网络的环境中运行下载脚本
2. 从其他机器复制models/wetext目录
3. 寻找wetext模型的镜像源

## 工作原理

1. **优先本地模型**：修改后的代码会首先检查本地模型目录是否存在
2. **降级在线下载**：如果本地模型不存在，才会尝试在线下载
3. **路径映射**：直接指定tagger.fst和verbalizer.fst文件路径，避免snapshot_download调用

## 技术细节

### 原始调用链
```
IndexTTS → TextNormalizer.load() → wetext.Normalizer() → 
snapshot_download("pengzhendong/wetext") → modelscope.cn API
```

### 离线调用链  
```
IndexTTS → TextNormalizer.load() → wetext.Normalizer(local_paths) → 
本地FST文件
```

## 测试结果
✅ 模型下载成功：所有必需的FST文件已下载  
✅ 离线模式工作正常：文本标准化功能正常  
✅ IndexTTS集成成功：可以正常使用本地模型  

## 示例测试
- 输入：`IndexTTS正式发布1.0版本了`  
- 输出：`IndexTTS正式发布一点零版本了`

- 输入：`现在是2025年1月22日`
- 输出：`现在是二零二五年一月二十二日`

现在项目可以在完全离线的环境中运行，不再依赖modelscope.cn的网络连接。
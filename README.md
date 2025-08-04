# Claude Video Translator

一个功能完整的视频字幕提取、翻译和配音工具链，使用 OpenAI Whisper、Claude AI 和 IndexTTS 实现视频的智能处理。

## 🚀 主要功能

- **智能字幕提取**：使用 Whisper 自动识别语言并提取字幕
- **AI 翻译**：集成 Claude AI 进行高质量字幕翻译
- **语音合成**：使用 IndexTTS 生成自然流畅的中文配音
- **视频后处理**：自动生成带字幕和配音的最终视频
- **断点续传**：支持处理失败后的断点续传功能
- **多语言支持**：支持多种源语言和目标语言

## 📁 项目结构

### 核心脚本

- **`get_srt_by_wisper.py`** - 新版字幕提取脚本，集成智能优化
- **`process_video_part1.sh`** - 视频预处理（音频提取 + 字幕识别）
- **`translate_by_claude.sh`** - 使用 Claude AI 翻译字幕
- **`process_video_part2.sh`** - 视频后处理（TTS + 字幕 + 最终合成）
- **`process_video_part2_plus.sh`** - 增强版视频后处理

### 辅助工具

- **`genmarkdown_by_claude.sh`** - 生成视频内容的 Markdown 文档
- **`post_to_bilibili.sh`** - 发布到哔哩哔哩
- **`post_to_xiaohongshu.sh`** - 发布到小红书
- **`download_and_process.sh`** - 下载并处理视频的完整流程
- **`getvideo.sh`** - 视频下载工具

## 🛠️ 环境依赖

### 必需软件

1. **FFmpeg** - 音视频处理
2. **Python 3.8+** - 脚本运行环境
3. **OpenAI Whisper** - 语音识别
   ```bash
   pip install openai-whisper
   ```
4. **Claude CLI** - AI 翻译服务
5. **IndexTTS** - 中文语音合成

### Python 依赖

```bash
pip install -r requirements.txt
```

## 📝 使用方法

### 1. 字幕提取（新版）

使用新版优化脚本提取字幕：

```bash
# 自动语言检测
python3 get_srt_by_wisper.py video.mp4

# 指定语言
python3 get_srt_by_wisper.py video.mp4 -l en

# 指定输出文件
python3 get_srt_by_wisper.py video.mp4 -o output.srt
```

### 2. 完整处理流程

#### 步骤一：视频预处理
```bash
# 自动语言检测，翻译为中文
./process_video_part1.sh video.mp4

# 指定英语，翻译为日语
./process_video_part1.sh -l en --olang ja video.mp4

# 处理高清视频
./process_video_part1.sh -hd video_hd.webm

# 强制重新处理
./process_video_part1.sh -f video.mp4
```

#### 步骤二：字幕翻译
```bash
# 翻译为中文（默认）
./translate_by_claude.sh video.mp4

# 翻译为其他语言
./translate_by_claude.sh --olang en video.mp4

# 添加自定义 prompt
./translate_by_claude.sh -p "请保持技术术语准确" video.mp4
```

#### 步骤三：视频后处理
```bash
# 基础后处理
./process_video_part2.sh video.mp4

# 使用自定义语音和语速
./process_video_part2.sh -v custom_voice.wav -s 1.3 video.mp4

# 调整字幕大小
./process_video_part2.sh --fsize 18 video.mp4
```

### 3. 一键处理

```bash
# 下载并完整处理
./download_and_process.sh "YouTube_URL"
```

## ⚙️ 配置说明

### 语言代码支持

- `auto` - 自动识别
- `en` - 英语
- `zh` - 中文
- `ja` - 日语
- `ko` - 韩语
- `fr` - 法语
- `de` - 德语
- `es` - 西班牙语
- `ru` - 俄语

### 处理模式

- **普通模式**：标准质量处理
- **高清模式 (-hd)**：处理高清分离的音视频文件
- **强制模式 (-f)**：忽略已有文件，重新处理所有步骤

## 📊 新版字幕提取特性

`get_srt_by_wisper.py` 相比原版脚本的改进：

1. **智能语言检测**：自动识别音频语言并应用相应优化策略
2. **多语言优化**：
   - 中日韩语言使用 aggressive segmentation 配置
   - 其他语言使用词级时间戳的整句分割
3. **字幕优化**：
   - 自动合并短句
   - 智能时间戳调整
   - 噪音过滤
4. **更好的错误处理**：完善的依赖检查和错误提示
5. **统一接口**：简化的命令行参数

## 🔄 工作流程

```
原视频 → 音频提取 → Whisper识别 → 字幕优化 → Claude翻译 → TTS配音 → 视频合成 → 最终输出
```

### 临时文件结构

```
{video_name}_temp/
├── original_audio.wav          # 提取的音频
├── step2_whisper.srt          # Whisper识别的字幕
├── step3_translated.srt       # Claude翻译的字幕
├── step5_chinese_audio.wav    # TTS生成的配音
└── xiaohongshu.md            # 生成的文档
```

## 🚨 注意事项

1. **断点续传**：脚本自动检测已有文件，支持从中断处继续
2. **文件命名**：支持分离下载的音视频文件（如 `_hd_video.webm` 和 `_hd_audio.webm`）
3. **资源占用**：Whisper 和 TTS 处理需要较多计算资源
4. **API 限制**：Claude API 有调用频率限制

## 🔧 故障排除

### 常见问题

1. **Whisper 安装失败**
   ```bash
   pip install --upgrade openai-whisper
   ```

2. **FFmpeg 未找到**
   ```bash
   # macOS
   brew install ffmpeg
   
   # Ubuntu
   sudo apt install ffmpeg
   ```

3. **Claude CLI 配置**
   ```bash
   # 设置 API Key
   export ANTHROPIC_API_KEY="your_api_key"
   ```

## 📄 许可证

本项目使用 MIT 许可证。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📚 更新日志

### v2.0 (最新)
- ✨ 新增 `get_srt_by_wisper.py` 统一字幕提取脚本
- 🚀 简化了 `process_video_part1.sh` 的复杂逻辑
- 🎯 改进了多语言支持和字幕优化算法
- 🔧 优化了错误处理和用户体验

### v1.0
- 🎉 初始版本发布
- 📝 基础的视频字幕提取、翻译和配音功能
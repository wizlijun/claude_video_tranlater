# 🎬 智能视频翻译配音系统

一个基于 AI 的全自动视频翻译配音系统，支持多平台视频下载、语音识别、智能翻译、TTS 配音和小红书文案生成。

## ✨ 主要功能

### 📥 多平台视频下载
- **YouTube** (youtube.com, youtu.be) - 支持高清视频下载
- **Instagram** (instagram.com) - 支持帖子视频下载
- **Bilibili** (bilibili.com) - 支持B站视频下载
- **本地视频** - 支持各种格式 (.mp4, .mkv, .webm, .mov 等)

### 🎙️ 智能语音处理
- **自动语音识别** - 基于 Whisper 的高精度语音识别
- **多语言支持** - 支持自动检测和手动指定语言
- **字幕优化** - 智能合并和优化字幕时间轴

### 🌍 AI 翻译
- **Claude AI 翻译** - 基于 Claude 的高质量翻译
- **多语言输出** - 支持中文、英语、日语、韩语等多种语言
- **自定义 Prompt** - 可添加专业术语和翻译指导

### 🎯 TTS 配音
- **IndexTTS 配音** - 基于 IndexTTS 的高质量语音合成
- **语音克隆** - 支持参考语音文件进行声音克隆
- **可调参数** - 语速、字幕大小等参数可调

### 📝 营销文案生成
- **小红书文案** - 自动生成符合小红书风格的营销文案
- **B站发布** - 自动发布到 B站（可选）

## 🚀 快速开始

### 安装依赖

确保系统已安装以下依赖：
- `yt-dlp` - 视频下载
- `ffmpeg` - 视频处理
- `whisper` - 语音识别
- `IndexTTS` - 语音合成
- `Claude API` - AI 翻译

### 基本用法

```bash
# 处理 YouTube 视频
./download_and_process.sh https://www.youtube.com/watch?v=VIDEO_ID

# 处理本地视频文件
./download_and_process.sh my_video.mp4

# 指定语言和参数
./download_and_process.sh -l en --olang ja -v female.wav https://youtu.be/VIDEO_ID
```

## 📋 命令行参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `-l, --language` | 原视频语言 | auto |
| `--olang` | 翻译输出语言 | zh |
| `-v, --voice` | 参考语音文件 | bruce.wav |
| `-s, --speed` | 语速倍数 | 1.5 |
| `--fsize` | 字幕字体大小 | 15 |
| `-o, --output` | 输出文件名前缀 | 自动生成 |
| `-p, --prompt` | 自定义翻译提示 | 无 |
| `-h, --help` | 显示帮助信息 | - |

## 🌐 支持的语言

- `auto` - 自动识别
- `en` - 英语
- `zh` - 中文
- `ja` - 日语
- `ko` - 韩语
- `fr` - 法语
- `de` - 德语
- `es` - 西班牙语
- `ru` - 俄语
- 其他 - 参考 Whisper 支持的语言代码

## 📖 使用示例

### 网络视频处理

```bash
# 基础用法
./download_and_process.sh https://www.youtube.com/watch?v=VIDEO_ID

# 指定原语言为英语
./download_and_process.sh -l en https://youtu.be/VIDEO_ID

# 翻译为日语
./download_and_process.sh -l en --olang ja https://youtu.be/VIDEO_ID

# 使用自定义语音和参数
./download_and_process.sh -v female.wav -s 2.0 --fsize 18 https://youtu.be/VIDEO_ID

# 添加自定义翻译提示
./download_and_process.sh -p "这是一个技术教程视频" https://youtu.be/VIDEO_ID
```

### 本地视频处理

```bash
# 处理本地视频文件
./download_and_process.sh knife.mp4

# 指定输出名称和自定义提示
./download_and_process.sh -p "bushcraft专有名词不做翻译" -o "knife" knife.mp4

# 英语转日语
./download_and_process.sh -l en --olang ja knife.mp4
```

## 🔄 处理流程

系统会自动执行以下步骤：

1. **📥 视频下载/检测** - 自动识别输入类型并下载网络视频
2. **🎬 视频预处理** - 音频提取、语音识别、字幕优化
3. **🤖 AI 翻译** - 使用 Claude AI 翻译字幕到目标语言
4. **📝 文案生成** - 生成小红书营销文案
5. **🎯 TTS 配音** - 使用 IndexTTS 生成配音视频
6. **📤 自动发布** - 可选择自动发布到 B站

## 📁 输出文件

处理完成后，系统会生成以下文件：

```
{视频名称}_temp/
├── step3_optimized.srt      # 优化后的原始字幕
├── step3.5_translated.srt   # 翻译后的字幕
├── xiaohongshu.md          # 小红书文案
└── 其他临时文件...

{视频名称}_final.mp4         # 最终配音视频
```

## ⚙️ 高级功能

### 高清视频处理
系统会自动检测并下载高清版本用于最终输出，确保视频质量。

### 字幕优化
支持智能合并短字幕片段，优化观看体验。

### 声音克隆
支持使用参考语音文件进行声音克隆，生成个性化配音。

### B站自动发布
可选择自动发布到 B站，包括标题、描述、标签等信息的自动生成。

## 🛠️ 技术栈

- **视频下载**: yt-dlp + Edge Cookie
- **语音识别**: OpenAI Whisper
- **AI 翻译**: Claude API
- **语音合成**: IndexTTS
- **视频处理**: FFmpeg
- **文案生成**: Claude AI

## 📞 联系方式

issues 留言

## 📄 许可证

本项目遵循相关开源许可证，详情请查看各个组件的许可证信息。

---

**注意**: 请确保遵守各平台的服务条款，合理使用本工具。
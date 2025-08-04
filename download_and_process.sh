#!/bin/bash

# 严格模式，任何命令失败则脚本退出
set -e

# --- 解析命令行参数 ---
show_help() {
    echo "用法: $0 [选项] <视频URL|本地视频文件>"
    echo ""
    echo "选项:"
    echo "  -l, --language LANG    设置原视频语言 (默认: auto)"
    echo "  --olang LANG          设置翻译输出语言 (默认: zh)"
    echo ""
    echo "  -v, --voice FILE       设置参考语音文件 (默认: bruce.wav)"
    echo "  -s, --speed RATE       设置语速倍数 (默认: 1.5)"
    echo "  --fsize SIZE          设置字幕字体大小 (默认: 15)"
    echo "  -o, --output NAME     指定输出文件名前缀（不含扩展名）"
    echo "  -p, --prompt TEXT     添加自定义prompt到翻译指令末尾"
    echo "  --proxy               使用代理下载（http://127.0.0.1:1087）"
    echo "  -h, --help            显示帮助信息"
    echo ""
    echo "语言代码:"
    echo "  auto    自动识别"
    echo "  en      英语"
    echo "  zh      中文"
    echo "  ja      日语"
    echo "  ko      韩语"
    echo "  fr      法语"
    echo "  de      德语"
    echo "  es      西班牙语"
    echo "  ru      俄语"
    echo "  其他    参考whisper支持的语言代码"
    echo ""
    echo "支持的平台:"
    echo "  - YouTube (youtube.com, youtu.be)"
    echo "  - Instagram (instagram.com)"
    echo "  - Bilibili (bilibili.com)"
    echo "  - 本地视频文件 (.mp4, .mkv, .webm, .mov等)"
    echo ""
    echo "示例:"
    echo "  # 网络视频处理"
    echo "  $0 https://www.youtube.com/watch?v=VIDEO_ID"
    echo "  $0 -l en https://youtu.be/VIDEO_ID"
    echo "  $0 -l en --olang ja https://youtu.be/VIDEO_ID"
    echo "  $0 --olang en https://www.youtube.com/watch?v=VIDEO_ID"
    echo "  $0 -nm https://www.instagram.com/p/POST_ID/"
    echo "  $0 https://www.bilibili.com/video/BV1234567890/"
    echo "  $0 -l zh -nm https://www.youtube.com/watch?v=VIDEO_ID"
    echo "  $0 -v female.wav -s 2.0 --fsize 18 https://youtu.be/VIDEO_ID"
    echo "  $0 -o custom_name https://youtu.be/VIDEO_ID"
    echo "  $0 -p \"这是一个技术教程视频\" https://youtu.be/VIDEO_ID"
    echo "  $0 --proxy https://youtu.be/VIDEO_ID"
    echo ""
    echo "  # 本地视频文件处理"
    echo "  $0 knife.mp4"
    echo "  $0 -p \"bushcraft专有名词不做翻译\" -o \"knife\" knife.mp4"
    echo "  $0 -l en --olang ja knife.mp4"
    echo "  $0 -l en -v female.wav my_video.mp4"
    echo ""
    echo "功能说明:"
    echo "  1. 自动检测输入类型（网络URL或本地文件）"
    echo "  2. 使用yt-dlp和Edge浏览器Cookie下载网络视频（如需要）"
    echo "  3. 自动执行视频预处理（音频提取、语音识别、字幕优化）"
    echo "  4. 使用Claude AI自动翻译字幕为指定语言"
    echo "  5. 生成小红书营销文案"
    echo "  6. 使用IndexTTS生成配音视频（含字幕）"
}

# 初始化变量
LANGUAGE="auto"
OUTPUT_LANGUAGE="zh"
NO_MERGE=false
VOICE_FILE=""
SPEECH_RATE=""
SUBTITLE_SIZE=""
OUTPUT_NAME=""
CUSTOM_PROMPT=""
USE_PROXY=false
VIDEO_URL=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--language)
            LANGUAGE="$2"
            shift 2
            ;;
        --olang)
            OUTPUT_LANGUAGE="$2"
            shift 2
            ;;
        -nm|--no-merge)
            NO_MERGE=true
            shift
            ;;
        -v|--voice)
            VOICE_FILE="$2"
            shift 2
            ;;
        -s|--speed)
            SPEECH_RATE="$2"
            shift 2
            ;;
        --fsize)
            SUBTITLE_SIZE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_NAME="$2"
            shift 2
            ;;
        -p|--prompt)
            CUSTOM_PROMPT="$2"
            shift 2
            ;;
        --proxy)
            USE_PROXY=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$VIDEO_URL" ]; then
                VIDEO_URL="$1"
            else
                echo "错误：只能指定一个视频URL或文件"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查输入参数
if [ -z "$VIDEO_URL" ]; then
    echo "错误：请提供一个视频URL或本地视频文件作为参数。"
    show_help
    exit 1
fi

# 检查是否是本地文件
IS_LOCAL_FILE=false
if [ -f "$VIDEO_URL" ]; then
    IS_LOCAL_FILE=true
    echo "检测到本地视频文件: $VIDEO_URL"
elif [[ "$VIDEO_URL" =~ ^https?:// ]] || [[ "$VIDEO_URL" =~ ^www\. ]]; then
    IS_LOCAL_FILE=false
    echo "检测到网络视频URL: $VIDEO_URL"
else
    echo "错误：无效的输入 - 既不是有效的本地文件，也不是有效的URL"
    echo "本地文件: $VIDEO_URL 不存在"
    echo "URL格式: 不符合 http(s):// 或 www. 开头"
    exit 1
fi

# 检查必要的脚本是否存在
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GETVIDEO_SCRIPT="$SCRIPT_DIR/getvideo.sh"
PROCESS_PART1_SCRIPT="$SCRIPT_DIR/process_video_part1.sh"
TRANSLATE_SCRIPT="$SCRIPT_DIR/translate_by_claude.sh"
GENMARKDOWN_SCRIPT="$SCRIPT_DIR/genmarkdown_by_claude.sh"
PROCESS_PART2_SCRIPT="$SCRIPT_DIR/process_video_part2.sh"

if [ ! -f "$GETVIDEO_SCRIPT" ]; then
    echo "错误：getvideo.sh 脚本不存在：$GETVIDEO_SCRIPT"
    exit 1
fi

if [ ! -f "$PROCESS_PART1_SCRIPT" ]; then
    echo "错误：process_video_part1.sh 脚本不存在：$PROCESS_PART1_SCRIPT"
    exit 1
fi

if [ ! -f "$TRANSLATE_SCRIPT" ]; then
    echo "错误：translate_by_claude.sh 脚本不存在：$TRANSLATE_SCRIPT"
    exit 1
fi

if [ ! -f "$GENMARKDOWN_SCRIPT" ]; then
    echo "错误：genmarkdown_by_claude.sh 脚本不存在：$GENMARKDOWN_SCRIPT"
    exit 1
fi

if [ ! -f "$PROCESS_PART2_SCRIPT" ]; then
    echo "错误：process_video_part2.sh 脚本不存在：$PROCESS_PART2_SCRIPT"
    exit 1
fi

# 确保脚本可执行
chmod +x "$GETVIDEO_SCRIPT"
chmod +x "$PROCESS_PART1_SCRIPT"
chmod +x "$TRANSLATE_SCRIPT"
chmod +x "$GENMARKDOWN_SCRIPT"
chmod +x "$PROCESS_PART2_SCRIPT"

echo "🚀 开始完整视频处理流程"
if [ "$IS_LOCAL_FILE" = true ]; then
    echo "本地视频文件: $VIDEO_URL"
else
    echo "视频URL: $VIDEO_URL"
fi
echo "原语言设置: $LANGUAGE"
echo "输出语言设置: $OUTPUT_LANGUAGE"
if [ "$NO_MERGE" = true ]; then
    echo "字幕优化: 跳过（使用原始Whisper输出）"
else
    echo "字幕优化: 启用（智能合并优化）"
fi
if [ -n "$VOICE_FILE" ]; then
    echo "语音文件: $VOICE_FILE"
fi
if [ -n "$SPEECH_RATE" ]; then
    echo "语速倍数: $SPEECH_RATE"
fi
if [ -n "$SUBTITLE_SIZE" ]; then
    echo "字幕大小: $SUBTITLE_SIZE"
fi
if [ -n "$OUTPUT_NAME" ]; then
    echo "输出文件名: $OUTPUT_NAME"
fi
if [ -n "$CUSTOM_PROMPT" ]; then
    echo "自定义Prompt: $CUSTOM_PROMPT"
fi
if [ "$USE_PROXY" = true ]; then
    echo "代理模式: 启用 (http://127.0.0.1:1087)"
else
    echo "代理模式: 禁用"
fi
echo ""
echo "📋 处理步骤:"
if [ "$IS_LOCAL_FILE" = true ]; then
    echo "  1. 跳过视频下载（使用本地文件）"
    echo "  1.5. 跳过字幕下载（本地文件）"
else
    echo "  1. 下载视频"
    echo "  1.5. 尝试下载视频字幕"
fi
echo "  2. 音频提取和语音识别"
echo "  3. AI翻译字幕到${OUTPUT_LANGUAGE}"
echo "  4. 生成小红书文案"
echo "  5. 生成TTS配音视频"
echo "=================================================="

# 步骤1: 下载视频或使用本地文件
echo ""
if [ "$IS_LOCAL_FILE" = true ]; then
    echo "📥 步骤 1/5: 使用本地视频文件..."
    DOWNLOADED_FILE="$VIDEO_URL"
    echo "✅ 本地视频文件: $DOWNLOADED_FILE"
else
    echo "📥 步骤 1/5: 下载视频..."

    # 构建getvideo.sh的参数
    GETVIDEO_ARGS=()
    if [ -n "$OUTPUT_NAME" ]; then
        GETVIDEO_ARGS+=("-o" "$OUTPUT_NAME")
    fi
    if [ "$USE_PROXY" = true ]; then
        GETVIDEO_ARGS+=("--proxy")
    fi
    GETVIDEO_ARGS+=("$VIDEO_URL")

    # 显示执行命令
    echo "执行命令: $GETVIDEO_SCRIPT ${GETVIDEO_ARGS[*]}"
    echo ""

    # 实时显示下载进度，同时捕获输出用于提取文件名
    echo "🔄 开始实时下载..."
    echo "=================================================="

    # 创建临时文件保存输出
    DOWNLOAD_LOG=$(mktemp)

    # 临时禁用严格模式以捕获下载脚本的退出码
    set +e

    # 使用 tee 同时显示进度和保存输出
    "$GETVIDEO_SCRIPT" "${GETVIDEO_ARGS[@]}" 2>&1 | tee "$DOWNLOAD_LOG"
    DOWNLOAD_EXIT_CODE=$?

    set -e

    echo ""
    echo "=================================================="

    if [ $DOWNLOAD_EXIT_CODE -ne 0 ]; then
        echo "❌ 视频下载失败（退出码: $DOWNLOAD_EXIT_CODE）"
        echo ""
        echo "📋 可能的解决方案："
        echo "1. 检查网络连接和代理设置"
        echo "2. 确保URL有效且视频可访问"
        echo "3. 对于Instagram，请按照上面的手动下载指南操作"
        echo "4. 手动下载视频后，直接运行:"
        echo "   ./process_video_part1.sh \"你的视频文件.mp4\""
        rm -f "$DOWNLOAD_LOG"
        exit 1
    fi

    # 从保存的输出中提取文件名
    DOWNLOADED_FILE=$(grep "^DOWNLOADED_FILE:" "$DOWNLOAD_LOG" | tail -n 1 | sed 's/^DOWNLOADED_FILE://')

    # 如果没有找到标记的文件名，尝试从最后一行提取
    if [ -z "$DOWNLOADED_FILE" ]; then
        DOWNLOADED_FILE=$(tail -n 1 "$DOWNLOAD_LOG" 2>/dev/null || echo "")
    fi

    # 清理临时文件
    rm -f "$DOWNLOAD_LOG"

    # 验证文件是否存在且不为空
    if [ ! -f "$DOWNLOADED_FILE" ] || [ ! -s "$DOWNLOADED_FILE" ]; then
        echo "❌ 下载的视频文件不存在或为空: $DOWNLOADED_FILE"
        echo ""
        echo "尝试查找最新下载的视频文件..."
        # 尝试找到最新的视频文件
        LATEST_VIDEO=$(ls -t *.mp4 *.mkv *.webm *.mov 2>/dev/null | head -1)
        if [ -f "$LATEST_VIDEO" ] && [ -s "$LATEST_VIDEO" ]; then
            echo "找到最新视频文件: $LATEST_VIDEO"
            DOWNLOADED_FILE="$LATEST_VIDEO"
        else
            echo "❌ 未找到有效的视频文件"
            echo ""
            echo "请手动下载视频后运行:"
            echo "  ./process_video_part1.sh \"你的视频文件.mp4\""
            exit 1
        fi
    fi

    echo "✅ 视频下载成功: $DOWNLOADED_FILE"
fi

# 获取生成的文件信息（提前计算用于字幕下载）
BASENAME=$(basename "${DOWNLOADED_FILE%.*}")
TEMP_DIR="$(pwd)/${BASENAME}_temp"

# 步骤1.5: 尝试下载字幕
echo ""
if [ "$IS_LOCAL_FILE" = true ]; then
    echo "📄 步骤 1.5/5: 跳过字幕下载（本地文件）..."
    WHISPER_SRT=""
else
    echo "📄 步骤 1.5/5: 尝试下载视频字幕..."
    
    # 构建getvideo.sh字幕下载的参数
    GETVIDEO_SRT_ARGS=("-srt")
    if [ -n "$OUTPUT_NAME" ]; then
        GETVIDEO_SRT_ARGS+=("-o" "$OUTPUT_NAME")
    fi
    if [ "$USE_PROXY" = true ]; then
        GETVIDEO_SRT_ARGS+=("--proxy")
    fi
    GETVIDEO_SRT_ARGS+=("$VIDEO_URL")
    
    # 显示执行命令
    echo "执行命令: $GETVIDEO_SCRIPT ${GETVIDEO_SRT_ARGS[*]}"
    echo ""
    
    # 创建临时文件保存字幕下载输出
    SUBTITLE_LOG=$(mktemp)
    
    # 临时禁用严格模式以捕获字幕下载脚本的退出码
    set +e
    
    # 使用 tee 同时显示进度和保存输出
    "$GETVIDEO_SCRIPT" "${GETVIDEO_SRT_ARGS[@]}" 2>&1 | tee "$SUBTITLE_LOG"
    SUBTITLE_EXIT_CODE=$?
    
    set -e
    
    echo ""
    echo "=================================================="
    
    if [ $SUBTITLE_EXIT_CODE -eq 0 ]; then
        # 从保存的输出中提取字幕文件名
        WHISPER_SRT=$(grep "^DOWNLOADED_FILE:" "$SUBTITLE_LOG" | tail -n 1 | sed 's/^DOWNLOADED_FILE://')
        
        # 如果没有找到标记的文件名，尝试查找.srt文件
        if [ -z "$WHISPER_SRT" ]; then
            WHISPER_SRT=$(find . -maxdepth 1 -name "*.srt" -type f -newerct '5 seconds ago' | head -1)
        fi
        
        # 验证字幕文件是否存在且不为空
        if [ -f "$WHISPER_SRT" ] && [ -s "$WHISPER_SRT" ]; then
            echo "✅ 字幕下载成功: $WHISPER_SRT"
        else
            echo "⚠️  字幕下载完成但未找到有效字幕文件"
            WHISPER_SRT=""
        fi
    elif [ $SUBTITLE_EXIT_CODE -eq 2 ]; then
        echo "ℹ️  该视频没有可用的字幕文件"
        WHISPER_SRT=""
    else
        echo "⚠️  字幕下载失败（退出码: $SUBTITLE_EXIT_CODE）"
        WHISPER_SRT=""
    fi
    
    # 清理临时文件
    rm -f "$SUBTITLE_LOG"
fi


# 步骤2: 处理视频（第一阶段）
echo ""
echo "🎬 步骤 2/5: 执行视频预处理..."

# 构建process_video_part1.sh的参数
PART1_ARGS=()
if [ "$LANGUAGE" != "auto" ]; then
    PART1_ARGS+=("-l" "$LANGUAGE")
fi
if [ "$OUTPUT_LANGUAGE" != "zh" ]; then
    PART1_ARGS+=("--olang" "$OUTPUT_LANGUAGE")
fi
if [ "$NO_MERGE" = true ]; then
    PART1_ARGS+=("-nm")
fi

# 检查是否存在字幕文件
VIDEO_BASENAME=$(basename "${DOWNLOADED_FILE%.*}")
STANDARD_SRT_FILE="${VIDEO_BASENAME}.srt"
DOWNLOADED_SUBTITLE_FILE=""

# 检查是否有下载成功的字幕文件
if [ -f "$WHISPER_SRT" ] && [ -s "$WHISPER_SRT" ]; then
    echo "✅ 检测到下载的字幕文件: $WHISPER_SRT"
    echo "🔄 将使用下载的字幕文件跳过语音识别..."
    DOWNLOADED_SUBTITLE_FILE="$WHISPER_SRT"
elif [ -f "$STANDARD_SRT_FILE" ] && [ -s "$STANDARD_SRT_FILE" ]; then
    echo "✅ 检测到已有SRT字幕文件: $STANDARD_SRT_FILE"
    echo "🔄 将使用现有SRT字幕文件跳过语音识别..."
    DOWNLOADED_SUBTITLE_FILE="$STANDARD_SRT_FILE"
fi

# 如果有字幕文件，添加到参数中
if [ -n "$DOWNLOADED_SUBTITLE_FILE" ]; then
    PART1_ARGS+=("-srt" "$DOWNLOADED_SUBTITLE_FILE")
fi

PART1_ARGS+=("$DOWNLOADED_FILE")

# 显示将要执行的命令
echo "执行命令: $PROCESS_PART1_SCRIPT ${PART1_ARGS[*]}"
echo ""

# 执行第一阶段处理，数组自动处理引用
"$PROCESS_PART1_SCRIPT" "${PART1_ARGS[@]}"

if [ $? -ne 0 ]; then
    echo "❌ 视频预处理失败"
    exit 1
fi

# 获取生成的文件信息（已在字幕下载阶段定义）
OPTIMIZED_SRT="$TEMP_DIR/step3_optimized.srt"
TRANSLATED_SRT="$TEMP_DIR/step3.5_translated.srt"
XIAOHONGSHU_MD="$TEMP_DIR/xiaohongshu.md"

# 步骤3: AI翻译字幕
echo ""
if [ -f "$TRANSLATED_SRT" ] && [ -s "$TRANSLATED_SRT" ]; then
    echo "🤖 步骤 3/5: ⏭️  跳过AI翻译字幕（已存在: $TRANSLATED_SRT）"
else
    echo "🤖 步骤 3/5: AI翻译字幕..."

    # 构建translate_by_claude.sh的参数
    TRANSLATE_ARGS=()
    if [ "$OUTPUT_LANGUAGE" != "zh" ]; then
        TRANSLATE_ARGS+=("--olang" "$OUTPUT_LANGUAGE")
    fi
    if [ -n "$CUSTOM_PROMPT" ]; then
        TRANSLATE_ARGS+=("-p" "$CUSTOM_PROMPT")
    fi
    TRANSLATE_ARGS+=("$DOWNLOADED_FILE")

    # 显示执行命令
    echo "执行命令: $TRANSLATE_SCRIPT ${TRANSLATE_ARGS[*]}"
    echo ""

    if ! "$TRANSLATE_SCRIPT" "${TRANSLATE_ARGS[@]}"; then
        echo "❌ 字幕翻译失败"
        echo ""
        echo "📝 可以手动翻译后继续:"
        echo "1. 编辑字幕文件: nano \"$OPTIMIZED_SRT\""
        echo "2. 手动运行后续步骤:"
        echo "   ./genmarkdown_by_claude.sh \"$DOWNLOADED_FILE\""
        echo "   ./process_video_part2.sh \"$DOWNLOADED_FILE\""
        exit 1
    fi

    echo "✅ 字幕翻译完成"
fi

# 步骤4: 生成小红书文案
echo ""
if [ -f "$XIAOHONGSHU_MD" ] && [ -s "$XIAOHONGSHU_MD" ]; then
    echo "📝 步骤 4/5: ⏭️  跳过小红书文案生成（已存在: $XIAOHONGSHU_MD）"
else
    echo "📝 步骤 4/5: 生成小红书文案..."
    echo "执行命令: $GENMARKDOWN_SCRIPT \"$DOWNLOADED_FILE\" \"$VIDEO_URL\""
    echo ""

    if ! "$GENMARKDOWN_SCRIPT" "$DOWNLOADED_FILE" "$VIDEO_URL"; then
        echo "❌ 文案生成失败"
        echo ""
        echo "📝 可以跳过此步骤，继续生成视频:"
        echo "   ./process_video_part2.sh \"$DOWNLOADED_FILE\""
        # 文案生成失败不退出，继续处理视频
    else
        echo "✅ 小红书文案生成完成"
    fi
fi

# 步骤5: 生成TTS配音视频
echo ""
echo "🎬 步骤 5/5: 生成配音视频..."

# 检查下载的视频文件是否为高清版本
VIDEO_FOR_PART2="$DOWNLOADED_FILE"
if [[ ! "$DOWNLOADED_FILE" =~ _hd\..*$ ]]; then
    echo ""
    echo "🔍 检测到当前视频不是高清版本，正在下载高清视频用于最终处理..."
    echo "当前视频: $DOWNLOADED_FILE"
    
    # 生成HD视频文件名（基于原文件名添加_hd）
    BASENAME=$(basename "${DOWNLOADED_FILE%.*}")
    EXTENSION="${DOWNLOADED_FILE##*.}"
    HD_VIDEO_FILE="${BASENAME}_hd.${EXTENSION}"
    
    echo "目标HD视频文件: $HD_VIDEO_FILE"
    
    # 检查HD视频是否已经存在
    if [ -f "$HD_VIDEO_FILE" ] && [ -s "$HD_VIDEO_FILE" ]; then
        echo "✅ HD视频文件已存在: $HD_VIDEO_FILE"
        VIDEO_FOR_PART2="$HD_VIDEO_FILE"
    else
        # 创建临时文件保存高清下载输出
        HD_DOWNLOAD_LOG=$(mktemp)
        
        # 临时禁用严格模式以捕获下载脚本的退出码
        set +e
        
        # 构建高清下载参数
        HD_GETVIDEO_ARGS=("-hd")
        if [ -n "$OUTPUT_NAME" ]; then
            HD_GETVIDEO_ARGS+=("-o" "$OUTPUT_NAME")
        else
            HD_GETVIDEO_ARGS+=("-o" "$BASENAME")
        fi
        if [ "$USE_PROXY" = true ]; then
            HD_GETVIDEO_ARGS+=("--proxy")
        fi
        HD_GETVIDEO_ARGS+=("$VIDEO_URL")
        
        # 下载高清视频
        echo "执行命令: $GETVIDEO_SCRIPT ${HD_GETVIDEO_ARGS[*]}"
        echo ""
        "$GETVIDEO_SCRIPT" "${HD_GETVIDEO_ARGS[@]}" 2>&1 | tee "$HD_DOWNLOAD_LOG"
        HD_DOWNLOAD_EXIT_CODE=$?
        
        set -e
        
        if [ $HD_DOWNLOAD_EXIT_CODE -eq 0 ]; then
            # 从输出中提取高清视频文件名
            HD_DOWNLOADED_FILE=$(grep "^DOWNLOADED_FILE:" "$HD_DOWNLOAD_LOG" | tail -n 1 | sed 's/^DOWNLOADED_FILE://')
            
            if [ -z "$HD_DOWNLOADED_FILE" ]; then
                HD_DOWNLOADED_FILE=$(tail -n 1 "$HD_DOWNLOAD_LOG" 2>/dev/null || echo "")
            fi
            
            # 检查HD下载结果并处理视频格式转换
            HD_AUDIO_FILE=""
            
            # 检查是否有分离的视频和音频文件
            if [ -f "$HD_DOWNLOADED_FILE" ] && [ -s "$HD_DOWNLOADED_FILE" ]; then
                # 获取文件基础名（去掉扩展名）
                HD_BASE_NAME=$(basename "$HD_DOWNLOADED_FILE" | sed 's/\.[^.]*$//')
                
                # 检查是否是分离下载的视频文件
                if [[ "$HD_DOWNLOADED_FILE" == *"_hd_video."* ]]; then
                    # 分离下载模式：查找对应的音频文件
                    echo "🔍 检测到分离下载的HD视频文件: $HD_DOWNLOADED_FILE"
                    
                    # 查找对应的音频文件
                    AUDIO_PATTERNS=(
                        "${HD_BASE_NAME/_video/_audio}.webm"
                        "${HD_BASE_NAME/_video/_audio}.m4a"
                    )
                    
                    for pattern in "${AUDIO_PATTERNS[@]}"; do
                        if [ -f "$pattern" ] && [ -s "$pattern" ]; then
                            HD_AUDIO_FILE="$pattern"
                            echo "✅ 找到对应的音频文件: $HD_AUDIO_FILE"
                            break
                        fi
                    done
                    
                    # 如果直接匹配失败，尝试通配符搜索
                    if [ -z "$HD_AUDIO_FILE" ]; then
                        echo "🔍 使用通配符搜索音频文件..."
                        for audio_file in $(dirname "$HD_DOWNLOADED_FILE")/*_hd_audio.*; do
                            if [ -f "$audio_file" ] && [ -s "$audio_file" ]; then
                                HD_AUDIO_FILE="$audio_file"
                                echo "✅ 找到音频文件: $HD_AUDIO_FILE"
                                break
                            fi
                        done
                    fi
                    
                    if [ -n "$HD_AUDIO_FILE" ]; then
                        # 使用ffmpeg合并视频和音频
                        echo "🔄 使用ffmpeg合并HD视频和音频..."
                        echo "   视频: $HD_DOWNLOADED_FILE"
                        echo "   音频: $HD_AUDIO_FILE"
                        echo "   输出: $HD_VIDEO_FILE"
                        
                        # 检查ffmpeg是否可用
                        if ! command -v ffmpeg &> /dev/null; then
                            echo "❌ ffmpeg未安装，无法合并视频和音频"
                            echo "   请安装ffmpeg: brew install ffmpeg"
                            echo "   使用原视频继续处理: $DOWNLOADED_FILE"
                        elif ffmpeg -i "$HD_DOWNLOADED_FILE" -i "$HD_AUDIO_FILE" \
                                 -c:v copy -c:a aac -shortest \
                                 "$HD_VIDEO_FILE" -y \
                                 -hide_banner -loglevel warning; then
                            echo "✅ HD视频合并成功: $HD_VIDEO_FILE"
                            
                            # 获取文件信息
                            HD_SIZE=$(du -h "$HD_VIDEO_FILE" | cut -f1)
                            echo "   合并后文件大小: $HD_SIZE"
                            
                            # 清理分离的临时文件
                            echo "🧹 清理分离的临时文件..."
                            rm -f "$HD_DOWNLOADED_FILE" "$HD_AUDIO_FILE"
                            
                            VIDEO_FOR_PART2="$HD_VIDEO_FILE"
                        else
                            echo "❌ HD视频合并失败，使用原视频继续处理"
                            rm -f "$HD_VIDEO_FILE"  # 清理可能的不完整文件
                        fi
                    else
                        echo "⚠️  未找到对应的音频文件，无法合并HD视频"
                        echo "   使用原视频继续处理: $DOWNLOADED_FILE"
                    fi
                    
                elif [[ "$HD_DOWNLOADED_FILE" == *.mp4 ]] || [[ "$HD_DOWNLOADED_FILE" == *.mkv ]]; then
                    # 合并下载模式：直接转换格式（如果需要）
                    echo "✅ 高清视频下载成功: $HD_DOWNLOADED_FILE"
                    
                    if [[ "$HD_DOWNLOADED_FILE" == *.mp4 ]]; then
                        # 已经是mp4格式，直接重命名
                        if [ "$HD_DOWNLOADED_FILE" != "$HD_VIDEO_FILE" ]; then
                            echo "🔄 重命名HD视频文件: $HD_DOWNLOADED_FILE -> $HD_VIDEO_FILE"
                            mv "$HD_DOWNLOADED_FILE" "$HD_VIDEO_FILE"
                        fi
                        VIDEO_FOR_PART2="$HD_VIDEO_FILE"
                    else
                        # 转换为mp4格式
                        echo "🔄 转换HD视频格式为mp4: $HD_DOWNLOADED_FILE -> $HD_VIDEO_FILE"
                        
                        # 检查ffmpeg是否可用
                        if ! command -v ffmpeg &> /dev/null; then
                            echo "❌ ffmpeg未安装，无法转换视频格式"
                            echo "   请安装ffmpeg: brew install ffmpeg"
                            echo "   使用原视频继续处理: $DOWNLOADED_FILE"
                        elif ffmpeg -i "$HD_DOWNLOADED_FILE" \
                                 -c:v libx264 -c:a aac -preset fast \
                                 "$HD_VIDEO_FILE" -y \
                                 -hide_banner -loglevel warning; then
                            echo "✅ HD视频格式转换成功: $HD_VIDEO_FILE"
                            
                            # 获取文件信息
                            HD_SIZE=$(du -h "$HD_VIDEO_FILE" | cut -f1)
                            echo "   转换后文件大小: $HD_SIZE"
                            
                            # 清理原始文件
                            rm -f "$HD_DOWNLOADED_FILE"
                            
                            VIDEO_FOR_PART2="$HD_VIDEO_FILE"
                        else
                            echo "❌ HD视频格式转换失败，使用原视频继续处理"
                            rm -f "$HD_VIDEO_FILE"  # 清理可能的不完整文件
                        fi
                    fi
                else
                    echo "⚠️  未知的HD视频文件格式: $HD_DOWNLOADED_FILE"
                    echo "   使用原视频继续处理: $DOWNLOADED_FILE"
                fi
            else
                echo "⚠️  高清视频下载失败，使用原视频继续处理: $DOWNLOADED_FILE"
            fi
        else
            echo "⚠️  高清视频下载失败，使用原视频继续处理: $DOWNLOADED_FILE"
        fi
        
        # 清理临时文件
        rm -f "$HD_DOWNLOAD_LOG"
    fi
else
    echo "✅ 当前视频已是高清版本: $DOWNLOADED_FILE"
fi

echo ""
echo "🎬 使用视频文件进行TTS处理: $VIDEO_FOR_PART2"

# 构建process_video_part2.sh的参数
PART2_ARGS=()
if [ "$OUTPUT_LANGUAGE" != "zh" ]; then
    PART2_ARGS+=("--olang" "$OUTPUT_LANGUAGE")
fi
if [ -n "$VOICE_FILE" ]; then
    PART2_ARGS+=("-v" "$VOICE_FILE")
fi
if [ -n "$SPEECH_RATE" ]; then
    PART2_ARGS+=("-s" "$SPEECH_RATE")
fi
if [ -n "$SUBTITLE_SIZE" ]; then
    PART2_ARGS+=("--fsize" "$SUBTITLE_SIZE")
fi
PART2_ARGS+=("$VIDEO_FOR_PART2")

# 显示将要执行的命令
echo "执行命令: $PROCESS_PART2_SCRIPT ${PART2_ARGS[*]}"
echo ""

# 执行TTS视频生成，数组自动处理引用
if ! "$PROCESS_PART2_SCRIPT" "${PART2_ARGS[@]}"; then
    echo "❌ 配音视频生成失败"
    exit 1
fi

echo "✅ 配音视频生成完成"

# 获取生成的文件信息
BASENAME=$(basename "${VIDEO_FOR_PART2%.*}")
TEMP_DIR="$(pwd)/${BASENAME}_temp"
OPTIMIZED_SRT="$TEMP_DIR/step3_optimized.srt"
TRANSLATED_SRT="$TEMP_DIR/step3.5_translated.srt"
XIAOHONGSHU_MD="$TEMP_DIR/xiaohongshu.md"
FINAL_VIDEO="${BASENAME}_final.mp4"

echo ""
echo "=================================================="
echo "🎉 完整视频处理流程完成！"
echo ""
echo "📁 生成的文件:"
echo "  原始视频: $DOWNLOADED_FILE"
if [ "$VIDEO_FOR_PART2" != "$DOWNLOADED_FILE" ]; then
    echo "  高清视频: $VIDEO_FOR_PART2"
fi
echo "  工作目录: $TEMP_DIR"
echo "  原始字幕: $OPTIMIZED_SRT"
if [ -f "$TRANSLATED_SRT" ]; then
    echo "  翻译字幕: $TRANSLATED_SRT"
fi
if [ -f "$XIAOHONGSHU_MD" ]; then
    echo "  小红书文案: $XIAOHONGSHU_MD"
fi
if [ -f "$FINAL_VIDEO" ]; then
    echo "  最终视频: $FINAL_VIDEO"
fi
echo ""
echo "📋 处理摘要:"
echo "  ✅ 1. 视频下载成功"
echo "  ✅ 2. 音频提取和语音识别完成"
echo "  ✅ 3. AI翻译字幕完成"
if [ -f "$XIAOHONGSHU_MD" ]; then
    echo "  ✅ 4. 小红书文案生成完成"
else
    echo "  ⚠️ 4. 小红书文案生成失败（已跳过）"
fi
if [ -f "$FINAL_VIDEO" ]; then
    echo "  ✅ 5. 配音视频生成完成"
else
    echo "  ❌ 5. 配音视频生成失败"
fi
echo ""
echo "💡 提示:"
echo "  - 所有文件保存在 $TEMP_DIR 目录中"
echo "  - 最终视频已包含配音和字幕"
if [ -f "$XIAOHONGSHU_MD" ]; then
    echo "  - 小红书文案已生成，可直接用于发布"
fi
echo "=================================================="

# 步骤6: 自动发布到B站
if [ -f "$FINAL_VIDEO" ] && [ -f "$XIAOHONGSHU_MD" ]; then
    echo ""
    echo "🚀 步骤 6/6: 自动发布到B站..."
    echo ""
    
    # 检查是否安装了B站发布脚本
    BILIBILI_SCRIPT="./post_to_bilibili.sh"
    if [ ! -f "$BILIBILI_SCRIPT" ]; then
        echo "⚠️  B站发布脚本不存在: $BILIBILI_SCRIPT"
        echo "请确保 post_to_bilibili.sh 存在于同一目录"
    else
        # 提取小红书文案内容
        if [ -f "$XIAOHONGSHU_MD" ]; then
            # 提取标题（第一行去掉#号，前面加[Bushcraft]，过滤特殊字符）
            FIRST_LINE=$(head -n 1 "$XIAOHONGSHU_MD" | sed 's/^#\s*//' | sed 's/["'"'"'`$]//g')
            BILIBILI_TITLE="[Bushcraft] $FIRST_LINE"
            
            # 提取描述（全文内容，过滤特殊字符）
            BILIBILI_DESC=$(cat "$XIAOHONGSHU_MD" | sed 's/["'"'"'`$]//g')
            
            # 提取转载来源（最后一行，过滤特殊字符）
            BILIBILI_SOURCE=$(tail -n 1 "$XIAOHONGSHU_MD" | sed 's/["'"'"'`$]//g')
            
            echo "📋 B站发布信息："
            echo "  标题: $BILIBILI_TITLE"
            echo "  来源: $BILIBILI_SOURCE"
            echo "  视频: $FINAL_VIDEO"
            echo ""
            
            # 询问是否发布到B站
            echo "是否自动发布到B站？[y/N]"
            read -r PUBLISH_CONFIRM
            if [[ "$PUBLISH_CONFIRM" =~ ^[Yy]$ ]]; then
                echo ""
                echo "📤 正在发布到B站..."
                echo ""
                echo "🔧 调用命令信息："
                echo "   脚本: $BILIBILI_SCRIPT"
                echo "   视频: $FINAL_VIDEO"
                echo "   标题: $BILIBILI_TITLE"
                echo "   描述: $(echo "$BILIBILI_DESC" | head -1 | cut -c1-50 2>/dev/null || echo "描述获取失败")..."
                echo "   来源: $BILIBILI_SOURCE"
                echo "   版权: 2 (转载)"
                echo "   标签: Bushcraft,野外生存,户外,生存技能,野营"
                echo "   分区: 250"
                echo ""
                echo "📋 完整命令行："
                echo "   $BILIBILI_SCRIPT \\"
                echo "     \"$FINAL_VIDEO\" \\"
                echo "     --title \"$BILIBILI_TITLE\" \\"
                echo "     --desc \"$(echo "$BILIBILI_DESC" | head -1 | cut -c1-30 2>/dev/null || echo "描述获取失败")...\" \\"
                echo "     --source \"$BILIBILI_SOURCE\" \\"
                echo "     --copyright 2 \\"
                echo "     --tags \"Bushcraft,野外生存,户外,生存技能,野营\" \\"
                echo "     --tid 250"
                echo ""
                echo "🚀 开始执行上传..."
                echo "=================================================="
                
                # 创建临时文件保存上传输出
                UPLOAD_LOG=$(mktemp)
                
                # 构建B站发布命令，添加调试模式
                set +e  # 临时禁用严格模式以捕获退出码
                "$BILIBILI_SCRIPT" \
                    "$FINAL_VIDEO" \
                    --title "$BILIBILI_TITLE" \
                    --desc "$BILIBILI_DESC" \
                    --source "$BILIBILI_SOURCE" \
                    --copyright 2 \
                    --tags "Bushcraft,野外生存,户外,生存技能,野营" \
                    --tid 250 \
                    --debug 2>&1 | tee "$UPLOAD_LOG"
                UPLOAD_EXIT_CODE=$?
                set -e  # 重新启用严格模式
                
                echo ""
                echo "=================================================="
                
                if [ $UPLOAD_EXIT_CODE -eq 0 ]; then
                    echo "🎉 B站发布成功！"
                    echo "✅ 完整流程已完成：下载 -> 处理 -> 发布"
                else
                    echo "❌ B站发布失败（退出码: $UPLOAD_EXIT_CODE）"
                    echo ""
                    echo "📋 详细错误信息："
                    echo "$(tail -20 "$UPLOAD_LOG")"
                    echo "💡 您可以手动运行（带调试信息）："
                    echo "   $BILIBILI_SCRIPT \"$FINAL_VIDEO\" \\"
                    echo "     --title \"$BILIBILI_TITLE\" \\"
                    echo "     --desc \"$(echo "$BILIBILI_DESC" | head -1)...\" \\"
                    echo "     --source \"$BILIBILI_SOURCE\" \\"
                    echo "     --copyright 2 \\"
                    echo "     --tags \"Bushcraft,野外生存,户外,生存技能,野营\" \\"
                    echo "     --tid 250 \\"
                    echo "     --debug"
                fi
                
                # 清理临时日志文件
                rm -f "$UPLOAD_LOG"
            else
                echo ""
                echo "⏭️  跳过B站发布"
                echo "💡 如需手动发布，请运行（带调试信息）："
                echo "   $BILIBILI_SCRIPT \"$FINAL_VIDEO\" \\"
                echo "     --title \"$BILIBILI_TITLE\" \\"
                echo "     --desc \"$(echo "$BILIBILI_DESC" | head -1)...\" \\"
                echo "     --source \"$BILIBILI_SOURCE\" \\"
                echo "     --copyright 2 \\"
                echo "     --tags \"Bushcraft,野外生存,户外,生存技能,野营\" \\"
                echo "     --tid 250 \\"
                echo "     --debug"
            fi
        else
            echo "⚠️  小红书文案文件不存在，无法提取发布信息"
        fi
    fi
else
    if [ ! -f "$FINAL_VIDEO" ]; then
        echo ""
        echo "⚠️  最终视频未生成，跳过B站发布"
    fi
    if [ ! -f "$XIAOHONGSHU_MD" ]; then
        echo ""
        echo "⚠️  小红书文案未生成，跳过B站发布"
    fi
fi

echo ""
echo "=================================================="
echo "🎯 完整流程总结："
echo "  ✅ 1. 视频下载成功"
echo "  ✅ 2. 音频提取和语音识别完成"
echo "  ✅ 3. AI翻译字幕完成"
if [ -f "$XIAOHONGSHU_MD" ]; then
    echo "  ✅ 4. 小红书文案生成完成"
else
    echo "  ⚠️ 4. 小红书文案生成失败"
fi
if [ -f "$FINAL_VIDEO" ]; then
    echo "  ✅ 5. 配音视频生成完成"
else
    echo "  ❌ 5. 配音视频生成失败"
fi
echo "  📤 6. B站发布：$([ -f "$FINAL_VIDEO" ] && [ -f "$XIAOHONGSHU_MD" ] && echo "可用" || echo "已跳过")"
echo "=================================================="
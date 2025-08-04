#!/bin/bash

# 严格模式，任何命令失败则脚本退出
set -e

# --- 配置 ---
SUBTITLE_MARGIN_V=50

# --- 脚本开始 ---

# --- 解析命令行参数 ---
show_help() {
    echo "用法: $0 [选项] <视频文件名>"
    echo ""
    echo "选项:"
    echo "  -l, --language LANG    设置原视频语言 (默认: auto)"
    echo "  --olang LANG          设置翻译输出语言 (默认: zh)"
    echo "  -nm, --no-merge       （已废弃，stable-ts直接生成优化分割）"
    echo "  -hd                   处理高清视频文件"
    echo "  -f, --force           强制重新处理所有步骤（忽略已有文件）"
    echo "  -srt input.srt        使用指定的SRT字幕文件"
    echo "  -h, --help            显示帮助信息"
    echo ""
    echo "断点续传说明:"
    echo "  - 脚本会自动检查临时目录中的已有文件"
    echo "  - 如果步骤的输出文件已存在且非空，则跳过该步骤"
    echo "  - 使用 -f/--force 参数可强制重新处理所有步骤"
    echo "  - 手动删除临时目录可重新开始所有步骤"
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
    echo "示例:"
    echo "  $0 video.mp4                      # 自动识别语言，翻译为中文"
    echo "  $0 -l en video.mp4               # 指定英语，翻译为中文"
    echo "  $0 -l en --olang ja video.mp4    # 指定英语，翻译为日语"
    echo "  $0 --olang en video.mp4          # 自动识别语言，翻译为英语"
    echo "  $0 -hd video_hd_video.webm       # 处理高清分离视频文件"
    echo "  $0 -srt input.srt video.mp4      # 使用指定的SRT字幕文件"
}

# 初始化变量
LANGUAGE="auto"
OUTPUT_LANGUAGE="zh"
NO_MERGE=false
HD_MODE=false
FORCE=false
INPUT_VIDEO=""
INPUT_SRT=""

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
        -hd)
            HD_MODE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -srt)
            INPUT_SRT="$2"
            INPUT_SRT=""
            #这里不使用这个参数
            shift 2
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
            if [ -z "$INPUT_VIDEO" ]; then
                INPUT_VIDEO="$1"
            else
                echo "错误：只能指定一个视频文件"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查输入参数
if [ -z "$INPUT_VIDEO" ]; then
    echo "错误：请提供一个视频文件名作为参数。"
    show_help
    exit 1
fi
BASENAME=$(basename "${INPUT_VIDEO%.*}")

# 标准化临时目录名：移除所有视频相关后缀以确保目录共享
# 移除 _hd_video, _video, _hd 等后缀，获取基础文件名
TEMP_BASE_NAME="$BASENAME"
if [[ "$TEMP_BASE_NAME" == *"_hd_video" ]]; then
    TEMP_BASE_NAME="${TEMP_BASE_NAME%_hd_video}"
elif [[ "$TEMP_BASE_NAME" == *"_video" ]]; then
    TEMP_BASE_NAME="${TEMP_BASE_NAME%_video}"
elif [[ "$TEMP_BASE_NAME" == *"_hd" ]]; then
    TEMP_BASE_NAME="${TEMP_BASE_NAME%_hd}"
fi

# 临时文件定义
TEMP_DIR="$(pwd)/${TEMP_BASE_NAME}_temp"
echo "使用临时目录: $TEMP_DIR"
EXTRACTED_AUDIO="$TEMP_DIR/original_audio.wav"
ORIGINAL_SRT="$TEMP_DIR/step2_whisper.srt"

# 检查是否存在分离下载的音频文件
SEPARATE_AUDIO_FILE=""
AUDIO_BASE_NAME=$(basename "${INPUT_VIDEO%.*}")

# 改进的分离音频文件检测逻辑
if [[ "$INPUT_VIDEO" == *"_video.webm" ]]; then
    # 如果输入是普通分离视频文件，查找对应的音频文件
    AUDIO_BASE_NAME=$(basename "${INPUT_VIDEO%_video.webm}")
    SEPARATE_AUDIO_FILE="${AUDIO_BASE_NAME}_audio.webm"
elif [[ "$INPUT_VIDEO" == *"_hd_video.webm" ]]; then
    # 如果输入是HD分离视频文件，查找对应的音频文件
    AUDIO_BASE_NAME=$(basename "${INPUT_VIDEO%_hd_video.webm}")
    SEPARATE_AUDIO_FILE="${AUDIO_BASE_NAME}_hd_audio.webm"
else
    # 根据HD模式和文件名智能查找音频文件
    AUDIO_BASE_NAME=$(basename "${INPUT_VIDEO%.*}")
    
    # 移除可能的_hd后缀来获取基础名称
    BASE_NAME_CLEAN=$(echo "$AUDIO_BASE_NAME" | sed 's/_hd$//')
    
    if [ "$HD_MODE" = true ]; then
        # HD模式：优先查找HD音频文件
        SEARCH_PATTERNS=(
            "${AUDIO_BASE_NAME}_hd_audio.webm"
            "${BASE_NAME_CLEAN}_hd_audio.webm"
            "${AUDIO_BASE_NAME}_audio.webm"
            "${BASE_NAME_CLEAN}_audio.webm"
        )
    else
        # 普通模式：优先查找普通音频文件
        SEARCH_PATTERNS=(
            "${AUDIO_BASE_NAME}_audio.webm"
            "${BASE_NAME_CLEAN}_audio.webm"
            "${AUDIO_BASE_NAME}_hd_audio.webm"
            "${BASE_NAME_CLEAN}_hd_audio.webm"
        )
    fi
    
    # 按优先级查找音频文件
    for pattern in "${SEARCH_PATTERNS[@]}"; do
        if [ -f "$pattern" ]; then
            SEPARATE_AUDIO_FILE="$pattern"
            break
        fi
    done
fi

# 创建临时工作目录（保留已有内容）
mkdir -p "$TEMP_DIR"

# 检查是否已有处理过的文件
SKIP_AUDIO_EXTRACTION=false
SKIP_WHISPER=false

# 如果用户提供了SRT文件，直接使用
if [ -n "$INPUT_SRT" ]; then
    echo "🔄 使用用户提供的SRT文件: $INPUT_SRT"
    if [ ! -f "$INPUT_SRT" ]; then
        echo "错误：指定的SRT文件不存在: $INPUT_SRT"
        exit 1
    fi
    # 复制用户SRT文件到标准位置
    cp "$INPUT_SRT" "$ORIGINAL_SRT"
    echo "✅ SRT文件已复制到: $ORIGINAL_SRT"
    SKIP_AUDIO_EXTRACTION=true
    SKIP_WHISPER=true
elif [ "$FORCE" = true ]; then
    echo "🔄 强制模式：清理已有文件并重新处理所有步骤..."
    rm -f "$EXTRACTED_AUDIO" "$ORIGINAL_SRT"
else
    # 检查已有文件
    if [ -f "$EXTRACTED_AUDIO" ] && [ -s "$EXTRACTED_AUDIO" ]; then
        echo "✅ 检测到已提取的音频文件: $EXTRACTED_AUDIO"
        SKIP_AUDIO_EXTRACTION=true
    fi

    if [ -f "$ORIGINAL_SRT" ] && [ -s "$ORIGINAL_SRT" ]; then
        echo "✅ 检测到已生成的字幕文件: $ORIGINAL_SRT"
        SKIP_WHISPER=true
    fi

    # 如果所有文件都已存在，直接跳过
    if [ "$SKIP_AUDIO_EXTRACTION" = true ] && [ "$SKIP_WHISPER" = true ]; then
        echo ""
        echo "🔍 所有处理步骤的输出文件都已存在，自动跳过所有步骤"
        echo "（使用 -f/--force 参数可强制重新处理）"
    fi
fi

echo "2步骤视频预处理开始: $INPUT_VIDEO"
if [ -n "$INPUT_SRT" ]; then
    echo "字幕来源: 用户提供的SRT文件 ($INPUT_SRT)"
else
    echo "输入语言设置: $LANGUAGE"
    echo "字幕提取: 使用get_srt_by_wisper.py优化处理"
fi
echo "输出语言设置: $OUTPUT_LANGUAGE"
if [ "$HD_MODE" = true ]; then
    echo "处理模式: 高清模式"
else
    echo "处理模式: 普通模式"
fi
echo "=================================================="

# 步骤1: 音频准备
if [ "$SKIP_AUDIO_EXTRACTION" = true ]; then
    echo "步骤 1/2: ⏭️  跳过音频提取（使用已有文件: $EXTRACTED_AUDIO）"
else
    if [ -f "$SEPARATE_AUDIO_FILE" ] && [ -s "$SEPARATE_AUDIO_FILE" ]; then
        echo "步骤 1/2: 检测到分离的音频文件，直接使用..."
        if [[ "$SEPARATE_AUDIO_FILE" == *"_hd_audio.webm" ]]; then
            echo "  🔊 使用高清分离音频文件: $SEPARATE_AUDIO_FILE"
            echo "  📈 优势：使用原始高质量音频，识别精度更高"
        else
            echo "  🔊 使用分离音频文件: $SEPARATE_AUDIO_FILE"
            echo "  📈 优势：使用原始分离音频，识别精度较高"
        fi
        
        # 转换分离的音频文件为Whisper需要的格式
        ffmpeg -i "$SEPARATE_AUDIO_FILE" -vn -acodec pcm_s16le -ar 16000 "$EXTRACTED_AUDIO" -y -hide_banner -loglevel error
        if [ ! -f "$EXTRACTED_AUDIO" ]; then
            echo "错误：音频格式转换失败。"
            exit 1
        fi
        echo "✓ 音频格式转换完成: $EXTRACTED_AUDIO"
        echo "  📈 优势：使用原始高质量音频，识别精度更高"
    else
        echo "步骤 1/2: 从视频提取音频..."
        echo "  📹 从视频文件提取音频: $INPUT_VIDEO"
        
        ffmpeg -i "$INPUT_VIDEO" -vn -acodec pcm_s16le -ar 16000 "$EXTRACTED_AUDIO" -y -hide_banner -loglevel error
        if [ ! -f "$EXTRACTED_AUDIO" ]; then
            echo "错误：音频提取失败。"
            exit 1
        fi
        echo "✓ 音频提取完成: $EXTRACTED_AUDIO"
    fi
fi

# 步骤2: 音频识别为SRT字幕文件
if [ "$SKIP_WHISPER" = true ]; then
    echo "步骤 2/2: ⏭️  跳过Whisper识别（使用已有文件: $ORIGINAL_SRT）"
else
    echo "步骤 2/2: 使用get_srt_by_wisper.py进行字幕提取..."
    
    # 构建get_srt_by_wisper.py的参数
    if [ -f "$EXTRACTED_AUDIO" ] && [ -s "$EXTRACTED_AUDIO" ]; then
        # 如果有提取的音频文件，直接使用音频文件
        INPUT_FILE="$EXTRACTED_AUDIO"
        echo "  使用提取的音频文件: $INPUT_FILE"
    else
        # 否则使用原视频文件
        INPUT_FILE="$INPUT_VIDEO"
        echo "  使用原视频文件: $INPUT_FILE"
    fi
    
    # 调用get_srt_by_wisper.py
    if [ "$LANGUAGE" = "auto" ]; then
        python3 get_srt_by_wisper.py "$INPUT_FILE" -o "$ORIGINAL_SRT"
    else
        python3 get_srt_by_wisper.py "$INPUT_FILE" -l "$LANGUAGE" -o "$ORIGINAL_SRT"
    fi
    
    if [ ! -f "$ORIGINAL_SRT" ] || [ ! -s "$ORIGINAL_SRT" ]; then
        echo "错误：get_srt_by_wisper.py执行失败，未生成SRT文件。"
        exit 1
    fi
    
    echo "✓ SRT字幕识别完成: $ORIGINAL_SRT"
    echo "  ✓ 使用get_srt_by_wisper.py的优化字幕提取和处理"
fi
    
# 通用的SRT文件检查
if [ ! -f "$ORIGINAL_SRT" ]; then
    echo "错误：字幕生成失败。"
    exit 1
fi

# 显示处理结果
echo "=================================================="
echo "✅ 第一阶段处理完成！"
echo "输入视频: $INPUT_VIDEO"
if [ "$HD_MODE" = true ]; then
    echo "处理模式: 高清模式"
fi
echo "临时文件保存在: $TEMP_DIR/"
echo ""
echo "处理步骤完成："
if [ -f "$SEPARATE_AUDIO_FILE" ] && [ -s "$SEPARATE_AUDIO_FILE" ]; then
    if [[ "$SEPARATE_AUDIO_FILE" == *"_hd_audio.webm" ]]; then
        echo "1. ✓ 使用分离的高清音频文件"
    else
        echo "1. ✓ 使用分离的音频文件"
    fi
    echo "   音频文件: $SEPARATE_AUDIO_FILE"
else
    echo "1. ✓ 从视频提取音频"
fi
echo "2. ✓ 使用get_srt_by_wisper.py进行优化字幕提取和处理"
echo ""
echo "📝 下一步："
echo "1. 翻译字幕: ./translate_by_claude.sh --olang $OUTPUT_LANGUAGE \"$INPUT_VIDEO\""
echo "   - 将 $ORIGINAL_SRT 翻译为 step3_translated.srt ($OUTPUT_LANGUAGE)"
echo "2. 生成文档: ./genmarkdown_by_claude.sh \"$INPUT_VIDEO\""
echo "   - 从 step3_translated.srt 生成 Markdown 文档"
echo "3. 视频处理: ./process_video_part2.sh --olang $OUTPUT_LANGUAGE \"$INPUT_VIDEO\""
echo "   - 使用 step3_translated.srt 生成带字幕的视频"
echo ""
echo "💡 提示："
echo "  - 使用了get_srt_by_wisper.py的智能语言检测和优化配置"
echo "  - 字幕已进行整句分割和时间戳优化处理"
echo "  - 支持多语言自动检测和相应的优化策略"
echo "  - 所有后续脚本都会使用 step3_translated.srt 文件"
echo "================================================="=
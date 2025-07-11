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
}

# 初始化变量
LANGUAGE="auto"
OUTPUT_LANGUAGE="zh"
NO_MERGE=false
HD_MODE=false
FORCE=false
INPUT_VIDEO=""

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

# 如果强制模式，清理所有已有文件
if [ "$FORCE" = true ]; then
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
echo "输入语言设置: $LANGUAGE"
echo "输出语言设置: $OUTPUT_LANGUAGE"
if [ "$HD_MODE" = true ]; then
    echo "处理模式: 高清模式"
else
    echo "处理模式: 普通模式"
fi
echo "字幕分割: 使用whisper+整句分割优化"
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

# 中文/日文/韩文优化的Whisper函数 - 直接生成SRT
whisper_zh() {
    local audio_file="$1"
    local output_dir="$2"
    local language="$3"
    
    echo "  使用优化的中文/日文/韩文Whisper配置（aggressive segmentation）..."
    echo "  参数: --no_speech_threshold 0.3 --logprob_threshold -0.8 --compression_ratio_threshold 1.8"
    echo "  直接生成SRT格式，跳过后续优化处理"
    
    if [ "$language" = "auto" ]; then
        whisper "$audio_file" \
            --model small \
            --output_format srt \
            --output_dir "$output_dir" \
            --no_speech_threshold 0.3 \
            --logprob_threshold -0.8 \
            --compression_ratio_threshold 1.8 \
            --temperature 0 \
            --initial_prompt "Generate full sentence punctuation based on the language. 补全标点符号"
    else
        whisper "$audio_file" \
            --model small \
            --language "$language" \
            --output_format srt \
            --output_dir "$output_dir" \
            --no_speech_threshold 0.3 \
            --logprob_threshold -0.8 \
            --compression_ratio_threshold 1.8 \
            --temperature 0 \
            --initial_prompt "Generate full sentence punctuation based on the language. 补全标点符号"
    fi
}

# 步骤2: 音频识别为SRT字幕文件
if [ "$SKIP_WHISPER" = true ]; then
    echo "步骤 2/2: ⏭️  跳过Whisper识别（使用已有文件: $ORIGINAL_SRT）"
else
    echo "步骤 2/2: 使用Whisper识别音频为SRT字幕（智能模式选择）..."

    # 智能处理模式：先检测语言，然后选择处理方式
    DETECTED_LANGUAGE=""
    USED_ZH_CONFIG=false
    
    if [ "$LANGUAGE" = "auto" ]; then
        echo "  第一步：快速检测语言..."
        # 使用快速转录前30秒来检测语言
        DETECT_OUTPUT=$(whisper "$EXTRACTED_AUDIO" \
            --model small \
            --output_format txt \
            --output_dir /tmp \
            --clip_timestamps "0,30" \
            --verbose False 2>&1 || true)
        
        # 从输出中提取检测到的语言（支持多种格式）
        DETECTED_LANGUAGE_RAW=$(echo "$DETECT_OUTPUT" | grep -i "detected language" | sed -n 's/.*detected language[: ]*\([A-Za-z]*\).*/\1/ip' | head -1)
        
        # 如果第一种方法失败，尝试其他格式
        if [ -z "$DETECTED_LANGUAGE_RAW" ]; then
            DETECTED_LANGUAGE_RAW=$(echo "$DETECT_OUTPUT" | grep -i "language.*:" | sed -n 's/.*language[: ]*\([A-Za-z]*\).*/\1/ip' | head -1)
        fi
        
        # 调试信息：显示检测输出的相关行（仅在检测失败时）
        if [ -z "$DETECTED_LANGUAGE_RAW" ]; then
            echo "  调试：语言检测输出："
            echo "$DETECT_OUTPUT" | grep -i "language\|detected" | head -3
        fi
        
        # 将语言名称映射为语言代码
        case "$DETECTED_LANGUAGE_RAW" in
            "Chinese"|"chinese")
                DETECTED_LANGUAGE="zh"
                ;;
            "Japanese"|"japanese")
                DETECTED_LANGUAGE="ja"
                ;;
            "Korean"|"korean")
                DETECTED_LANGUAGE="ko"
                ;;
            "English"|"english")
                DETECTED_LANGUAGE="en"
                ;;
            "Spanish"|"spanish")
                DETECTED_LANGUAGE="es"
                ;;
            "French"|"french")
                DETECTED_LANGUAGE="fr"
                ;;
            "German"|"german")
                DETECTED_LANGUAGE="de"
                ;;
            "Russian"|"russian")
                DETECTED_LANGUAGE="ru"
                ;;
            *)
                # 如果是已经是代码格式或未知语言，直接使用
                DETECTED_LANGUAGE="$DETECTED_LANGUAGE_RAW"
                ;;
        esac
        
        # 清理临时检测文件
        rm -f /tmp/*.txt 2>/dev/null || true
        
        if [ -z "$DETECTED_LANGUAGE" ]; then
            # 如果语言检测失败，使用标准配置
            echo "  语言检测失败，使用标准whisper配置..."
            whisper "$EXTRACTED_AUDIO" \
                --model small \
                --output_format json \
                --output_dir "$TEMP_DIR" \
                --word_timestamps True \
                --temperature 0 \
                --initial_prompt "Generate full sentence punctuation based on the language. 补全标点符号"
        else
            if [ "$DETECTED_LANGUAGE_RAW" != "$DETECTED_LANGUAGE" ]; then
                echo "  检测到语言: $DETECTED_LANGUAGE_RAW -> $DETECTED_LANGUAGE"
            else
                echo "  检测到语言: $DETECTED_LANGUAGE"
            fi
            # 根据检测到的语言选择合适的配置
            if [[ "$DETECTED_LANGUAGE" =~ ^(zh|ja|ko)$ ]]; then
                echo "  检测到中文/日文/韩文，使用优化配置"
                whisper_zh "$EXTRACTED_AUDIO" "$TEMP_DIR" "$DETECTED_LANGUAGE"
                USED_ZH_CONFIG=true
            else
                echo "  使用标准Whisper配置"
                whisper "$EXTRACTED_AUDIO" \
                    --model small \
                    --language "$DETECTED_LANGUAGE" \
                    --output_format json \
                    --output_dir "$TEMP_DIR" \
                    --word_timestamps True \
                    --temperature 0 \
                    --initial_prompt "Generate full sentence punctuation based on the language. 补全标点符号"
            fi
        fi
    else
        echo "  指定语言: $LANGUAGE"
        # 根据用户指定的语言选择合适的配置
        if [[ "$LANGUAGE" =~ ^(zh|ja|ko)$ ]]; then
            echo "  检测到中文/日文/韩文，使用优化配置"
            whisper_zh "$EXTRACTED_AUDIO" "$TEMP_DIR" "$LANGUAGE"
            USED_ZH_CONFIG=true
        else
            echo "  使用标准Whisper配置"
            whisper "$EXTRACTED_AUDIO" \
                --model small \
                --language "$LANGUAGE" \
                --output_format json \
                --output_dir "$TEMP_DIR" \
                --word_timestamps True \
                --temperature 0 \
                --initial_prompt "Generate full sentence punctuation based on the language. 补全标点符号"
        fi
    fi

    # 处理不同的输出格式
    if [ "$USED_ZH_CONFIG" = true ]; then
        # 中文/日文/韩文已直接生成SRT，重命名为标准文件名
        echo "  中文/日文/韩文已直接生成SRT，重命名为标准文件名..."
        AUDIO_BASENAME=$(basename "$EXTRACTED_AUDIO" .wav)
        WHISPER_SRT="$TEMP_DIR/${AUDIO_BASENAME}.srt"
        if [ -f "$WHISPER_SRT" ]; then
            mv "$WHISPER_SRT" "$ORIGINAL_SRT"
        else
            echo "错误：whisper_zh未生成SRT文件"
            exit 1
        fi
    else
        # 其他语言需要JSON处理
        # 将whisper输出重命名为固定文件名
        AUDIO_BASENAME=$(basename "$EXTRACTED_AUDIO" .wav)
        TEMP_JSON="$TEMP_DIR/whisper_output.json"
        mv "$TEMP_DIR/${AUDIO_BASENAME}.json" "$TEMP_JSON"

        # 使用Python脚本进行整句级分割（基于词级时间戳）
        echo "  进行整句级分割处理（基于词级精确时间戳）..."
        python3 << EOF
import re
import json

def format_srt_time(seconds):
    """Convert seconds to SRT time format"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"

# Read JSON file with word-level timestamps
with open('$TEMP_JSON', 'r') as f:
    data = json.load(f)

# Extract all words with timestamps
all_words = []
for segment in data['segments']:
    if 'words' in segment:
        for word_info in segment['words']:
            all_words.append({
                'word': word_info['word'].strip(),
                'start': word_info['start'],
                'end': word_info['end']
            })

# Combine all text and split into sentences
full_text = ' '.join([word['word'] for word in all_words])
print(f"Processing {len(all_words)} words...")

# Split into sentences supporting both half-width (.!?) and full-width (。！？) punctuation
sentences = re.split(r'([.!?。！？])', full_text)

# Merge sentences with their punctuation
merged_sentences = []
i = 0
while i < len(sentences):
    sentence = sentences[i].strip()
    if i + 1 < len(sentences) and sentences[i + 1] in '.!?。！？':
        sentence += sentences[i + 1]
        i += 2
    else:
        i += 1
    if sentence:
        merged_sentences.append(sentence.strip())

print(f"Found {len(merged_sentences)} sentences")

# Map each sentence to word-level timestamps
sentence_segments = []
word_index = 0

for sentence_idx, sentence in enumerate(merged_sentences):
    # Split sentence into words for matching (remove both half-width and full-width punctuation)
    sentence_words = sentence.replace('.', '').replace('!', '').replace('?', '').replace('。', '').replace('！', '').replace('？', '').split()
    
    # Find corresponding words in the word list
    sentence_start_time = None
    sentence_end_time = None
    matched_word_count = 0
    
    # Search for the sentence words in the word list
    search_start = word_index
    for i in range(search_start, len(all_words)):
        word_text = all_words[i]['word'].replace('.', '').replace('!', '').replace('?', '').replace('。', '').replace('！', '').replace('？', '').replace(',', '').replace('，', '').strip()
        
        # Try to match with sentence words
        if matched_word_count < len(sentence_words):
            target_word = sentence_words[matched_word_count].replace(',', '').replace('，', '').strip()
            
            # Flexible matching (handle case and punctuation differences)
            if word_text.lower() == target_word.lower():
                if sentence_start_time is None:
                    sentence_start_time = all_words[i]['start']
                sentence_end_time = all_words[i]['end']
                matched_word_count += 1
                word_index = i + 1
                
                # If we've matched all words in this sentence, break
                if matched_word_count >= len(sentence_words):
                    break
    
    # Fallback: if we couldn't match words precisely, estimate timing
    if sentence_start_time is None or sentence_end_time is None:
        if sentence_idx == 0:
            sentence_start_time = all_words[0]['start'] if all_words else 0
        else:
            sentence_start_time = sentence_segments[-1]['end'] if sentence_segments else 0
        
        # Estimate end time based on sentence length
        if sentence_end_time is None:
            avg_duration = 0.5  # average time per word
            estimated_duration = len(sentence_words) * avg_duration
            sentence_end_time = sentence_start_time + estimated_duration
    
    sentence_segments.append({
        'start': sentence_start_time,
        'end': sentence_end_time,
        'text': sentence,
        'matched_words': matched_word_count,
        'total_words': len(sentence_words)
    })
    
    print(f"Sentence {sentence_idx + 1}: '{sentence[:50]}...' -> {matched_word_count}/{len(sentence_words)} words matched")

# Write new SRT file
with open('$ORIGINAL_SRT', 'w') as f:
    for i, segment in enumerate(sentence_segments, 1):
        f.write(f"{i}\n")
        f.write(f"{format_srt_time(segment['start'])} --> {format_srt_time(segment['end'])}\n")
        f.write(f"{segment['text']}\n\n")

print(f"Created word-timestamp-based SRT with {len(sentence_segments)} segments")
print("Sample segments:")
for i, seg in enumerate(sentence_segments[:3], 1):
    print(f"{i}: [{format_srt_time(seg['start'])} --> {format_srt_time(seg['end'])}] {seg['text']}")

# Statistics
total_matched = sum(seg['matched_words'] for seg in sentence_segments)
total_words = sum(seg['total_words'] for seg in sentence_segments)
if total_words > 0:
    print(f"Word matching accuracy: {total_matched}/{total_words} ({100*total_matched/total_words:.1f}%)")
EOF

        if [ ! -f "$ORIGINAL_SRT" ]; then
            echo "错误：Whisper语音识别或整句分割失败。"
            exit 1
        fi
        
        # 清理临时JSON文件
        rm -f "$TEMP_JSON"
    fi
        
        echo "✓ SRT字幕识别完成: $ORIGINAL_SRT"
        if [ "$USED_ZH_CONFIG" = true ]; then
            echo "  ✓ 使用优化的中文/日文/韩文配置+整句分割（aggressive segmentation + 词级时间戳）"
        else
            echo "  ✓ 使用whisper+整句分割获得优化的sentence-based分割（词级时间戳）"
        fi
    fi
    
    # 通用的SRT文件检查
    if [ ! -f "$ORIGINAL_SRT" ]; then
        echo "错误：Whisper语音识别失败。"
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
if [ "$USED_ZH_CONFIG" = true ]; then
    echo "2. ✓ 使用优化的中文/日文/韩文Whisper配置+整句级分割SRT（词级时间戳）"
else
    echo "2. ✓ 使用Whisper识别为优化的整句级分割SRT（词级时间戳）"
fi
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
if [ "$USED_ZH_CONFIG" = true ]; then
    echo "  - 使用了针对中文/日文/韩文优化的aggressive segmentation配置"
    echo "  - 字幕分割更适合亚洲语言的语音特点（词级时间戳）"
else
    echo "  - 字幕已使用whisper+整句分割进行优化（词级时间戳）"
fi
if [ "$USED_ZH_CONFIG" = false ]; then
    echo "  - 每行字幕对应一个完整句子，时间戳基于实际词语音边界"
    echo "  - 支持中文、日文等全角标点符号（。！？）的句子分割"
fi
echo "  - 自动语言检测：中文/日文/韩文使用优化配置"
echo "  - 所有后续脚本都会使用 step3_translated.srt 文件"
echo "=================================================="
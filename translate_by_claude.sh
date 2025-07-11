#!/bin/bash

# 严格模式，任何命令失败则脚本退出
set -e

# --- 解析命令行参数 ---
show_help() {
    echo "用法: $0 [选项] <视频文件名>"
    echo ""
    echo "选项:"
    echo "  --olang LANG          设置翻译目标语言 (默认: zh)"
    echo "  -p, --prompt TEXT     添加自定义prompt到翻译指令末尾"
    echo "  -h, --help            显示帮助信息"
    echo ""
    echo "说明:"
    echo "  本脚本使用 Claude 命令行工具翻译字幕文件"
    echo "  将 step2_whisper.srt 翻译为指定语言并保存为 step3_translated.srt"
    echo ""
    echo "前置条件:"
    echo "  1. 已安装 Claude 命令行工具"
    echo "  2. 已运行 process_video_part1.sh 生成 step2_whisper.srt"
    echo ""
    echo "语言代码:"
    echo "  zh      中文"
    echo "  en      英语"
    echo "  ja      日语"
    echo "  ko      韩语"
    echo "  其他    支持的语言代码"
    echo ""
    echo "示例:"
    echo "  $0 video.mp4                         # 翻译为中文"
    echo "  $0 --olang en video.mp4              # 翻译为英语"
    echo "  $0 --olang ja video.mp4              # 翻译为日语"
    echo "  $0 --olang zh -p \"技术教程\" video.mp4  # 翻译为中文并添加提示"
}

# 初始化变量
INPUT_VIDEO=""
OUTPUT_LANGUAGE="zh"
CUSTOM_PROMPT=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --olang)
            OUTPUT_LANGUAGE="$2"
            shift 2
            ;;
        -p|--prompt)
            CUSTOM_PROMPT="$2"
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

# 检查Claude命令是否可用
if ! command -v claude &> /dev/null; then
    echo "错误：Claude 命令行工具未安装或不在 PATH 中。"
    echo ""
    echo "请安装 Claude 命令行工具："
    echo "参考: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi

BASENAME=$(basename "${INPUT_VIDEO%.*}")
TEMP_DIR="${BASENAME}_temp"
INPUT_SRT="$TEMP_DIR/step2_whisper.srt"
OUTPUT_SRT="$TEMP_DIR/step3.5_translated.srt"

# 检查输入文件是否存在
if [ ! -d "$TEMP_DIR" ]; then
    echo "错误：临时目录 $TEMP_DIR 不存在。"
    echo "请先运行: ./process_video_part1.sh \"$INPUT_VIDEO\""
    exit 1
fi

if [ ! -f "$INPUT_SRT" ]; then
    echo "错误：字幕文件 $INPUT_SRT 不存在。"
    echo "请先运行: ./process_video_part1.sh \"$INPUT_VIDEO\""
    exit 1
fi

# 语言映射函数
get_language_name() {
    case "$1" in
        zh) echo "中文" ;;
        en) echo "英语" ;;
        ja) echo "日语" ;;
        ko) echo "韩语" ;;
        fr) echo "法语" ;;
        de) echo "德语" ;;
        es) echo "西班牙语" ;;
        ru) echo "俄语" ;;
        it) echo "意大利语" ;;
        pt) echo "葡萄牙语" ;;
        *) echo "$1" ;;
    esac
}

LANGUAGE_NAME=$(get_language_name "$OUTPUT_LANGUAGE")

echo "🔄 开始翻译字幕文件"
echo "输入文件: $INPUT_SRT"
echo "输出文件: $OUTPUT_SRT"
echo "目标语言: $LANGUAGE_NAME ($OUTPUT_LANGUAGE)"
echo "使用工具: Claude 命令行"
echo "=================================================="

# 检查输入文件行数
INPUT_LINES=$(wc -l < "$INPUT_SRT")
echo "字幕文件行数: $INPUT_LINES 行"

# 根据行数选择处理方式（25条字幕 = 100行）
if [ "$INPUT_LINES" -gt 100 ]; then
    echo "📄 文件较大（>100行），使用分批翻译模式（每批25条字幕/100行）"
    echo "=================================================="
    
    # 使用简单的分行处理
    echo "📖 开始分批翻译处理..."
    
    # 计算批次数（每25条字幕 = 100行）
    LINES_PER_BATCH=100
    TOTAL_BATCHES=$(( (INPUT_LINES + LINES_PER_BATCH - 1) / LINES_PER_BATCH ))
    
    ESTIMATED_SUBTITLES=$((INPUT_LINES / 4))
    echo "文件共 $INPUT_LINES 行（约 $ESTIMATED_SUBTITLES 条字幕），分为 $TOTAL_BATCHES 批"
    
    # 创建临时翻译目录
    TRANSLATE_TEMP_DIR="$TEMP_DIR/translate_temp"
    mkdir -p "$TRANSLATE_TEMP_DIR"
    
    # 检查是否有之前的翻译进度
    EXISTING_BATCHES=0
    if [ -d "$TRANSLATE_TEMP_DIR" ]; then
        EXISTING_BATCHES=$(ls "$TRANSLATE_TEMP_DIR"/batch_*.srt 2>/dev/null | wc -l)
        if [ $EXISTING_BATCHES -gt 0 ]; then
            echo "🔄 发现 $EXISTING_BATCHES 个已完成的批次，将断点继续"
        fi
    fi
    
    echo "=================================================="
    
    SUCCESS_BATCHES=0
    FAILED_BATCHES=()
    SKIPPED_BATCHES=0
    
    for batch_num in $(seq 1 $TOTAL_BATCHES); do
        START_LINE=$(( (batch_num - 1) * LINES_PER_BATCH + 1 ))
        END_LINE=$(( batch_num * LINES_PER_BATCH ))
        
        # 定义批次临时文件
        BATCH_TEMP_FILE="$TRANSLATE_TEMP_DIR/batch_$(printf "%03d" $batch_num).srt"
        
        # 检查批次是否已经翻译过
        if [ -f "$BATCH_TEMP_FILE" ] && [ -s "$BATCH_TEMP_FILE" ]; then
            echo "📝 批次 $batch_num/$TOTAL_BATCHES (行 $START_LINE-$END_LINE) - ⏭️  已完成，跳过"
            SUCCESS_BATCHES=$((SUCCESS_BATCHES + 1))
            SKIPPED_BATCHES=$((SKIPPED_BATCHES + 1))
        else
            echo "📝 翻译批次 $batch_num/$TOTAL_BATCHES (行 $START_LINE-$END_LINE)..."
            
            # 提取当前批次的行
            BATCH_CONTENT=$(sed -n "${START_LINE},${END_LINE}p" "$INPUT_SRT")
            
            if [ -n "$BATCH_CONTENT" ]; then
                # 翻译当前批次
                BATCH_PROMPT="请将以下SRT字幕片段翻译为${LANGUAGE_NAME}，严格保持SRT格式（序号、时间轴、内容、空行）。只输出翻译后的SRT内容，不要添加解释，使用清晰简洁的口语表达："
                if [ -n "$CUSTOM_PROMPT" ]; then
                    BATCH_PROMPT="$BATCH_PROMPT $CUSTOM_PROMPT"
                fi
                
                # 重试机制
                MAX_RETRIES=3
                RETRY_COUNT=0
                BATCH_SUCCESS=false
                FAILURE_REASONS=()
                
                while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$BATCH_SUCCESS" = false ]; do
                    TEMP_BATCH_RESULT=$(mktemp)
                    TEMP_ERROR_LOG=$(mktemp)
                    
                    if echo "$BATCH_CONTENT" | claude --model claude-sonnet-4-20250514 "$BATCH_PROMPT" > "$TEMP_BATCH_RESULT" 2>"$TEMP_ERROR_LOG"; then
                        if [ -s "$TEMP_BATCH_RESULT" ]; then
                            # 提取纯SRT内容，跳过Claude的回复格式
                            if grep -q -- "-->" "$TEMP_BATCH_RESULT"; then
                                # 找到第一个数字序号行开始提取
                                if grep -q "^[0-9]\+$" "$TEMP_BATCH_RESULT"; then
                                    SRT_START=$(grep -n "^[0-9]\+$" "$TEMP_BATCH_RESULT" | head -1 | cut -d: -f1)
                                    if [ -n "$SRT_START" ]; then
                                        tail -n +$SRT_START "$TEMP_BATCH_RESULT" > "${TEMP_BATCH_RESULT}.clean"
                                        mv "${TEMP_BATCH_RESULT}.clean" "$TEMP_BATCH_RESULT"
                                    fi
                                fi
                                
                                # 再次验证结果
                                if grep -q -- "-->" "$TEMP_BATCH_RESULT"; then
                                    # 保存到临时批次文件
                                    cp "$TEMP_BATCH_RESULT" "$BATCH_TEMP_FILE"
                                    echo "    ✅ 批次 $batch_num 翻译成功"
                                    SUCCESS_BATCHES=$((SUCCESS_BATCHES + 1))
                                    BATCH_SUCCESS=true
                                fi
                            fi
                        fi
                    fi
                    
                    if [ "$BATCH_SUCCESS" = false ]; then
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                        
                        # 分析失败原因
                        FAILURE_REASON=""
                        if [ ! -s "$TEMP_BATCH_RESULT" ]; then
                            FAILURE_REASON="Claude返回空结果"
                        elif ! grep -q -- "-->" "$TEMP_BATCH_RESULT"; then
                            FAILURE_REASON="输出不包含SRT时间轴格式"
                        elif ! grep -q "^[0-9]\+$" "$TEMP_BATCH_RESULT"; then
                            FAILURE_REASON="输出不包含有效的SRT序号"
                        elif [ -s "$TEMP_ERROR_LOG" ]; then
                            ERROR_MSG=$(head -1 "$TEMP_ERROR_LOG")
                            FAILURE_REASON="Claude命令错误: $ERROR_MSG"
                        else
                            FAILURE_REASON="未知错误"
                        fi
                        
                        FAILURE_REASONS+=("第${RETRY_COUNT}次: $FAILURE_REASON")
                        
                        rm -f "$TEMP_BATCH_RESULT" "$TEMP_ERROR_LOG"
                        
                        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                            echo "    ⚠️  批次 $batch_num 第 $RETRY_COUNT 次尝试失败: $FAILURE_REASON"
                            echo "    🔄 等待2秒后重试..."
                            sleep 2
                        fi
                    fi
                done
                
                if [ "$BATCH_SUCCESS" = false ]; then
                    echo "    ❌ 批次 $batch_num 翻译失败（已重试 $MAX_RETRIES 次）"
                    echo "    失败原因:"
                    for reason in "${FAILURE_REASONS[@]}"; do
                        echo "      - $reason"
                    done
                    FAILED_BATCHES+=($batch_num)
                    # 记录失败的批次内容以便后续处理
                    echo "$BATCH_CONTENT" > "$TRANSLATE_TEMP_DIR/failed_batch_$(printf "%03d" $batch_num).srt"
                fi
            fi
        fi
        
        # 显示进度
        PROGRESS=$((batch_num * 100 / TOTAL_BATCHES))
        echo "    📊 进度: $PROGRESS% ($batch_num/$TOTAL_BATCHES)"
        echo ""
    done
    
    # 合并所有批次文件到最终输出
    echo "🔗 合并所有批次到最终文件..."
    > "$OUTPUT_SRT"
    
    for batch_num in $(seq 1 $TOTAL_BATCHES); do
        BATCH_TEMP_FILE="$TRANSLATE_TEMP_DIR/batch_$(printf "%03d" $batch_num).srt"
        if [ -f "$BATCH_TEMP_FILE" ]; then
            # 添加批次内容
            cat "$BATCH_TEMP_FILE" >> "$OUTPUT_SRT"
            
            # 确保批次间有正确的空行分隔（检查文件是否以空行结尾）
            if [ -s "$BATCH_TEMP_FILE" ]; then
                # 检查文件最后一行是否为空行
                LAST_LINE=$(tail -1 "$BATCH_TEMP_FILE")
                if [ -n "$LAST_LINE" ]; then
                    # 如果最后一行不是空行，添加一个空行
                    echo >> "$OUTPUT_SRT"
                fi
            fi
        fi
    done
    
    # 清理最终文件格式，确保末尾有正确的空行
    if [ -f "$OUTPUT_SRT" ] && [ -s "$OUTPUT_SRT" ]; then
        # 检查文件是否以空行结尾，如果不是则添加一个空行
        LAST_CHAR=$(tail -c 1 "$OUTPUT_SRT")
        if [ -n "$LAST_CHAR" ]; then
            echo >> "$OUTPUT_SRT"
        fi
        
        # 移除文件末尾的多余空行（只保留一个） - 使用简单方法，详细清理在后面的Python部分
        # 注意：复杂的sed命令可能导致无限循环，已移除
    fi
    
    echo "=================================================="
    echo "📊 翻译统计:"
    echo "  总行数: $INPUT_LINES"
    echo "  总批次数: $TOTAL_BATCHES"
    echo "  成功批次: $SUCCESS_BATCHES"
    echo "  跳过批次: $SKIPPED_BATCHES (断点继续)"
    echo "  失败批次: $((TOTAL_BATCHES - SUCCESS_BATCHES))"
    
    if [ ${#FAILED_BATCHES[@]} -gt 0 ]; then
        echo "  失败批次号: ${FAILED_BATCHES[*]}"
        echo ""
        echo "❌ 部分批次翻译失败，脚本退出"
        echo "失败的批次内容已保存在: $TRANSLATE_TEMP_DIR/failed_batch_*.srt"
        echo "请检查网络连接和Claude API状态后重试"
        exit 1
    fi
    
    if [ $SKIPPED_BATCHES -gt 0 ]; then
        echo ""
        echo "💡 提示：发现 $SKIPPED_BATCHES 个已完成批次，已跳过重复翻译"
        echo "如需重新翻译，请删除临时目录: rm -rf \"$TRANSLATE_TEMP_DIR\""
    fi
    
else
    echo "📄 文件较小（≤100行），使用整体翻译模式"
    echo "=================================================="
    
    # 准备翻译提示词
    TRANSLATION_PROMPT="请将以下SRT字幕文件翻译为${LANGUAGE_NAME}，严格保持原有的SRT格式（包括序号、时间轴、空行）。只输出翻译后的SRT内容，不要添加任何解释，使用清晰简洁的口语表达"
    if [ -n "$CUSTOM_PROMPT" ]; then
        TRANSLATION_PROMPT="$TRANSLATION_PROMPT $CUSTOM_PROMPT"
    fi

    echo ""
    echo "📝 正在调用 Claude 进行翻译..."
    echo "提示词: $TRANSLATION_PROMPT"
    echo ""

    # 创建临时文件用于存储翻译结果
    TEMP_OUTPUT=$(mktemp)
    MAX_RETRIES=3
    RETRY_COUNT=0
    TRANSLATION_SUCCESS=false
    FAILURE_REASONS=()

    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$TRANSLATION_SUCCESS" = false ]; do
        echo "🔄 尝试 $((RETRY_COUNT + 1))/$MAX_RETRIES..."
        
        TEMP_ERROR_LOG=$(mktemp)
        
        # 使用Claude命令行工具进行翻译
        if cat "$INPUT_SRT" | claude --model claude-sonnet-4-20250514 "$TRANSLATION_PROMPT" > "$TEMP_OUTPUT" 2>"$TEMP_ERROR_LOG"; then
            # 检查输出文件是否有内容
            if [ -s "$TEMP_OUTPUT" ]; then
                # 提取SRT内容，跳过Claude的欢迎信息
                if grep -q -- "-->" "$TEMP_OUTPUT"; then
                    # 找到第一个包含数字序号的行开始提取
                    SRT_START=$(grep -n "^[0-9]\+$" "$TEMP_OUTPUT" | head -1 | cut -d: -f1)
                    if [ -n "$SRT_START" ]; then
                        # 从找到的行开始提取到文件末尾
                        tail -n +$SRT_START "$TEMP_OUTPUT" > "${TEMP_OUTPUT}.clean"
                        mv "${TEMP_OUTPUT}.clean" "$TEMP_OUTPUT"
                    fi
                    
                    # 最终验证是否有时间轴格式
                    if grep -q -- "-->" "$TEMP_OUTPUT"; then
                        mv "$TEMP_OUTPUT" "$OUTPUT_SRT"
                        echo "✅ 翻译成功！"
                        TRANSLATION_SUCCESS=true
                        rm -f "$TEMP_ERROR_LOG"
                        break
                    fi
                fi
            fi
        fi
        
        if [ "$TRANSLATION_SUCCESS" = false ]; then
            RETRY_COUNT=$((RETRY_COUNT + 1))
            
            # 分析失败原因
            FAILURE_REASON=""
            if [ ! -s "$TEMP_OUTPUT" ]; then
                FAILURE_REASON="Claude返回空结果"
            elif ! grep -q -- "-->" "$TEMP_OUTPUT"; then
                FAILURE_REASON="输出不包含SRT时间轴格式"
            elif ! grep -q "^[0-9]\+$" "$TEMP_OUTPUT"; then
                FAILURE_REASON="输出不包含有效的SRT序号"
            elif [ -s "$TEMP_ERROR_LOG" ]; then
                ERROR_MSG=$(head -1 "$TEMP_ERROR_LOG")
                FAILURE_REASON="Claude命令错误: $ERROR_MSG"
            else
                FAILURE_REASON="未知错误"
            fi
            
            FAILURE_REASONS+=("第${RETRY_COUNT}次: $FAILURE_REASON")
            
            rm -f "$TEMP_ERROR_LOG"
            
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "❌ 第 $RETRY_COUNT 次尝试失败: $FAILURE_REASON"
                echo "🔄 等待3秒后重试..."
                sleep 3
            fi
        fi
    done

    if [ "$TRANSLATION_SUCCESS" = false ]; then
        echo "❌ 整体翻译失败（已重试 $MAX_RETRIES 次）"
        echo "失败原因:"
        for reason in "${FAILURE_REASONS[@]}"; do
            echo "  - $reason"
        done
        echo ""
        echo "请检查网络连接和Claude API状态后重试"
        rm -f "$TEMP_OUTPUT"
        exit 1
    fi
    
    # 清理临时文件
    rm -f "$TEMP_OUTPUT"
fi

# 最终格式清理（对所有翻译模式都适用）
if [ -f "$OUTPUT_SRT" ] && [ -s "$OUTPUT_SRT" ]; then
    echo "🔧 清理SRT格式..."
    
    # 确保文件以空行结尾
    LAST_CHAR=$(tail -c 1 "$OUTPUT_SRT")
    if [ -n "$LAST_CHAR" ]; then
        echo >> "$OUTPUT_SRT"
    fi
    
    # 移除多余的空行，确保SRT块之间只有一个空行
    python3 << EOF
import re

with open('$OUTPUT_SRT', 'r', encoding='utf-8') as f:
    content = f.read()

# 规范化SRT格式：确保每个字幕块之间只有一个空行
# 移除多余的空行，然后重新添加正确的分隔
blocks = re.split(r'\n\s*\n+', content.strip())
cleaned_blocks = []

for block in blocks:
    block = block.strip()
    if block:
        cleaned_blocks.append(block)

# 用单个空行连接所有块，末尾添加一个空行
result = '\n\n'.join(cleaned_blocks) + '\n'

with open('$OUTPUT_SRT', 'w', encoding='utf-8') as f:
    f.write(result)
EOF
fi

# 验证输出文件
if [ ! -f "$OUTPUT_SRT" ] || [ ! -s "$OUTPUT_SRT" ]; then
    echo "❌ 翻译失败，输出文件不存在或为空"
    exit 1
fi

echo "=================================================="
echo "🎉 字幕翻译完成！"
echo ""
echo "📋 处理摘要:"
echo "  视频文件: $INPUT_VIDEO"
echo "  工作目录: $TEMP_DIR"
echo "  原始字幕: $INPUT_SRT"
echo "  翻译字幕: $OUTPUT_SRT"
echo ""
echo "💡 提示："
echo "  - 请检查翻译质量是否满足要求"
echo "  - 如需调整，可手动编辑翻译文件"
echo "  - 翻译文件可用于后续的TTS处理步骤"
echo "=================================================="
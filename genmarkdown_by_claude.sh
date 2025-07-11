#!/bin/bash

# 严格模式，任何命令失败则脚本退出
set -e

# --- 解析命令行参数 ---
show_help() {
    echo "用法: $0 [选项] <视频文件名> [原始URL]"
    echo ""
    echo "选项:"
    echo "  -h, --help            显示帮助信息"
    echo ""
    echo "说明:"
    echo "  本脚本使用 Claude 命令行工具根据字幕生成小红书文案"
    echo "  将 step3.5_translated.srt 转换为小红书风格的标题和文案"
    echo "  输出保存为 xiaohongshu.md"
    echo ""
    echo "前置条件:"
    echo "  1. 已安装 Claude 命令行工具"
    echo "  2. 已运行翻译脚本生成 step3.5_translated.srt"
    echo ""
    echo "示例:"
    echo "  $0 video.mp4"
    echo "  $0 video.mp4 \"https://www.youtube.com/watch?v=VIDEO_ID\""
    echo "  $0 \"My Video (2024).mp4\""
}

# 初始化变量
INPUT_VIDEO=""
SOURCE_URL=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
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
            elif [ -z "$SOURCE_URL" ]; then
                SOURCE_URL="$1"
            else
                echo "错误：最多只能指定视频文件和原始URL两个参数"
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
INPUT_SRT="$TEMP_DIR/step3.5_translated.srt"
OUTPUT_MD="$TEMP_DIR/xiaohongshu.md"

# 检查输入文件是否存在
if [ ! -d "$TEMP_DIR" ]; then
    echo "错误：临时目录 $TEMP_DIR 不存在。"
    echo "请先运行完整的视频处理流程："
    echo "1. ./download_and_process.sh \"$INPUT_VIDEO\""
    echo "2. ./translate_by_claude.sh \"$INPUT_VIDEO\""
    exit 1
fi

if [ ! -f "$INPUT_SRT" ]; then
    echo "错误：翻译字幕文件 $INPUT_SRT 不存在。"
    echo "请先运行翻译脚本: ./translate_by_claude.sh \"$INPUT_VIDEO\""
    exit 1
fi

echo "📝 开始生成小红书文案"
echo "输入文件: $INPUT_SRT"
echo "输出文件: $OUTPUT_MD"
echo "使用工具: Claude 命令行"
echo "=================================================="

# 检查输入文件并创建前50条的摘要
echo "📖 准备字幕摘要用于生成文案..."

# 提取前50条字幕用于生成文案
TEMP_SUMMARY=$(mktemp)
python3 -c "
import re

def extract_first_n_subtitles(filename, n=50):
    '''提取前N条字幕'''
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 按双换行符分割条目
    entries = re.split(r'\n\s*\n', content.strip())
    entries = [entry.strip() for entry in entries if entry.strip()]
    
    # 只取前N条
    selected_entries = entries[:n]
    
    print(f'原文件有 {len(entries)} 条字幕，提取前 {len(selected_entries)} 条用于生成文案')
    
    # 重新组合
    result = '\n\n'.join(selected_entries)
    return result

summary_content = extract_first_n_subtitles('$INPUT_SRT', 50)
with open('$TEMP_SUMMARY', 'w', encoding='utf-8') as f:
    f.write(summary_content)
" 

SUMMARY_SIZE=$(wc -c < "$TEMP_SUMMARY")
echo "摘要文件大小: $SUMMARY_SIZE 字节"

# 准备生成文案的提示词
GENERATION_PROMPT="我要发小红书，请根据字幕生成一段标题和小红书文案，注意识别专业领域，用专业但又幽默的海明威式的表达方式，标题30汉字以内，文案200汉字以内，注意排版易于阅读，生成结果格式如下 # title
body"

echo ""
echo "🤖 正在调用 Claude 生成小红书文案..."
echo "提示词: $GENERATION_PROMPT"
echo ""

# 创建临时文件用于存储生成结果
TEMP_OUTPUT=$(mktemp)

# 使用Claude命令行工具生成文案
# 将字幕摘要作为输入，通过管道传递给Claude
if cat "$TEMP_SUMMARY" | claude --model claude-sonnet-4-20250514 "$GENERATION_PROMPT" > "$TEMP_OUTPUT" 2>&1; then
    # 检查输出文件是否有内容
    if [ -s "$TEMP_OUTPUT" ]; then
        # 提取实际的markdown内容，跳过Claude的欢迎信息
        if grep -q "#" "$TEMP_OUTPUT"; then
            # 找到第一个包含标题标记的行开始提取
            MD_START=$(grep -n "^#" "$TEMP_OUTPUT" | head -1 | cut -d: -f1)
            if [ -n "$MD_START" ]; then
                # 从找到的行开始提取到文件末尾
                tail -n +$MD_START "$TEMP_OUTPUT" > "${TEMP_OUTPUT}.clean"
                mv "${TEMP_OUTPUT}.clean" "$TEMP_OUTPUT"
            fi
            
            # 最终验证是否包含markdown格式
            if grep -q "#" "$TEMP_OUTPUT"; then
                mv "$TEMP_OUTPUT" "$OUTPUT_MD"
                
                # 如果提供了源URL，在文件末尾添加来源信息
                if [ -n "$SOURCE_URL" ]; then
                    echo "" >> "$OUTPUT_MD"
                    echo "翻译自: $SOURCE_URL" >> "$OUTPUT_MD"
                fi
                echo "✅ 小红书文案生成完成！"
                echo ""
                echo "📊 生成结果预览:"
                echo "=================="
                head -10 "$OUTPUT_MD"
                echo "=================="
                echo ""
                echo "📁 文件位置:"
                echo "  小红书文案: $OUTPUT_MD"
                echo "  文件大小: $(wc -c < "$OUTPUT_MD") 字节"
                echo ""
                echo "📝 下一步操作:"
                echo "1. 查看完整文案内容:"
                echo "   cat \"$OUTPUT_MD\""
                echo ""
                echo "2. 编辑文案（如需调整）:"
                echo "   nano \"$OUTPUT_MD\""
                echo ""
                echo "3. 复制文案内容用于发布:"
                echo "   pbcopy < \"$OUTPUT_MD\"  # macOS复制到剪贴板"
                echo ""
                echo "💡 提示："
                echo "  - 文案已针对小红书平台优化"
                echo "  - 标题控制在30汉字以内"
                echo "  - 正文控制在200汉字以内"
                echo "  - 使用专业且幽默的海明威式表达"
            else
                echo "❌ 生成内容格式错误，不是有效的Markdown格式"
                echo ""
                echo "Claude 输出内容:"
                head -20 "$TEMP_OUTPUT"
                echo ""
                echo "请检查："
                echo "1. Claude 是否正确理解了生成任务"
                echo "2. 输入的SRT文件内容是否完整"
                echo "3. 是否需要调整提示词"
                rm -f "$TEMP_OUTPUT"
                exit 1
            fi
        else
            echo "❌ Claude 返回的内容中没有找到标题标记"
            echo ""
            echo "Claude 输出内容:"
            head -20 "$TEMP_OUTPUT"
            echo ""
            echo "可能的原因："
            echo "1. Claude 没有理解Markdown格式要求"
            echo "2. 输入内容过于复杂或过长"
            echo "3. 网络连接问题导致输出不完整"
            rm -f "$TEMP_OUTPUT"
            exit 1
        fi
    else
        echo "❌ Claude 没有返回任何输出"
        echo ""
        echo "可能的原因："
        echo "1. Claude 命令执行失败"
        echo "2. 网络连接问题"
        echo "3. API 限制或配额问题"
        echo "4. 输入文件过大"
        rm -f "$TEMP_OUTPUT"
        exit 1
    fi
else
    echo "❌ Claude 命令执行失败"
    echo ""
    echo "错误输出:"
    cat "$TEMP_OUTPUT"
    echo ""
    echo "请检查："
    echo "1. Claude 命令行工具是否正确安装和配置"
    echo "2. 网络连接是否正常"
    echo "3. API 密钥是否有效"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# 清理临时文件
rm -f "$TEMP_OUTPUT" "$TEMP_SUMMARY"

echo "=================================================="
echo "🎉 小红书文案生成完成！"
echo ""
echo "📋 处理摘要:"
echo "  视频文件: $INPUT_VIDEO"
echo "  工作目录: $TEMP_DIR"
echo "  输入字幕: $INPUT_SRT"
echo "  输出文案: $OUTPUT_MD"
echo ""
echo "💡 提示："
echo "  - 文案已根据视频内容定制生成"
echo "  - 适合小红书平台的表达风格"
echo "  - 如需调整可直接编辑markdown文件"
echo "  - 发布前建议检查专业术语准确性"
echo "=================================================="
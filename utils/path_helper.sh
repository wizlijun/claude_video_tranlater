#!/bin/bash
# 路径辅助工具函数
# 用于查找IndexTTS和语音文件的相对路径

# 查找IndexTTS安装目录
find_index_tts_path() {
    local possible_paths=("indextts" "index-tts" "../indextts" "../index-tts" ".")
    
    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ] && ([ -f "$path/setup.py" ] || [ -f "$path/pyproject.toml" ] || [ -f "$path/cli.py" ]); then
            echo "$path"
            return 0
        fi
    done
    
    echo ""
    return 1
}

# 查找语音文件路径
find_voice_file_path() {
    local voice_file="$1"
    
    # If it's an absolute path and exists, use it directly
    if [[ "$voice_file" == /* ]] && [ -f "$voice_file" ]; then
        echo "$voice_file"
        return 0
    fi
    
    # Otherwise, search in relative paths
    local possible_paths=("." "indextts" "index-tts" "../indextts" "../index-tts")
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path/$voice_file" ]; then
            echo "$path/$voice_file"
            return 0
        fi
    done
    
    echo ""
    return 1
}

# 获取IndexTTS执行命令
get_index_tts_command() {
    local text="$1"
    local voice_file="$2"
    local output_file="$3"
    local device="${4:-mps}"
    
    # 查找IndexTTS路径
    local index_tts_path
    index_tts_path=$(find_index_tts_path)
    
    if [ -z "$index_tts_path" ]; then
        echo "❌ 错误：找不到IndexTTS安装目录"
        return 1
    fi
    
    # 查找语音文件
    local voice_path
    voice_path=$(find_voice_file_path "$voice_file")
    
    if [ -z "$voice_path" ]; then
        echo "❌ 错误：找不到语音文件 $voice_file"
        return 1
    fi
    
    # 生成命令 - 假设虚拟环境已在脚本启动时激活
    if [ "$index_tts_path" = "." ]; then
        echo "MPS_FALLBACK=0 PYTHONPATH=\$PYTHONPATH:\$(pwd)/indextts python3 indextts/cli.py \"$text\" --voice \"$voice_path\" --output \"$output_file\" --device $device --model_dir checkpoints --config checkpoints/config.yaml"
    else
        echo "cd $index_tts_path && MPS_FALLBACK=0 PYTHONPATH=\$PYTHONPATH:\$(pwd) python3 cli.py \"$text\" --voice \"$voice_path\" --output \"$output_file\" --device $device --model_dir ../checkpoints --config ../checkpoints/config.yaml"
    fi
    
    return 0
}
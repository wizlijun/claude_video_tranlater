#!/bin/bash

# Test script for clause-based subtitle extraction using Whisper
# Tests 5 different configurations optimized for clause segmentation

echo "=== Whisper Clause-Based Subtitle Extraction Test ==="
echo "Input file: test.wav"
echo "Target: Clause-based segmentation like extracted_text.txt"
echo "Testing 5 different parameter combinations..."
echo ""

# Check if input file exists
if [ ! -f "test.wav" ]; then
    echo "ERROR: test.wav not found!"
    exit 1
fi

echo "File size: $(ls -lh test.wav | awk '{print $5}')"
echo ""

# Remove existing output files
rm -f clause*.srt test0.srt test05.srt

echo "=== Configuration 0: Whisper with sentence-based splitting (word-level timestamps) ==="
echo "Command: whisper test.wav --model small --language en --word_timestamps True + word-based sentence timing"
start_time=$(date +%s)

# First generate JSON with word-level timestamps
echo "  生成带词级时间戳的JSON输出..."
whisper test.wav \
    --model small \
    --output_format json \
    --output_dir . \
    --word_timestamps True \
    --temperature 0 \
    --initial_prompt "Generate full sentence punctuation based on the language."

# Rename the output to a temporary file
mv test.json temp_whisper_test0.json
cp temp_whisper_test0.json debug_temp_whisper_test0.json


# Post-process to create sentence-based SRT with word-level precise timestamps
python3 << 'EOF'
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
with open('temp_whisper_test0.json', 'r') as f:
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
print(f"Full text: {full_text}")

# Split into sentences, keeping track of punctuation (including full-width punctuation)
# Supports both half-width (.!?) and full-width (。！？) punctuation
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
with open('test0.srt', 'w') as f:
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
print(f"Word matching accuracy: {total_matched}/{total_words} ({100*total_matched/total_words:.1f}%)")
EOF

# Clean up temporary file
rm -f temp_whisper_test0.json

end_time=$(date +%s)
echo "Generated: test0.srt (Time: $((end_time - start_time))s)"
if [ -f "test0.srt" ]; then
    echo ""
    echo "=== Subtitle Information for test0.srt ==="
    echo "Total lines: $(wc -l < test0.srt)"
    echo "Total subtitle entries: $(grep -c "^[0-9]*$" test0.srt)"
    echo ""
    echo "Displaying each subtitle entry:"
    entry=0
    while read -r line; do
        if [[ "$line" =~ ^[0-9]+$ ]]; then
            entry=$((entry + 1))
            echo "Entry $entry:"
        elif [[ "$line" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
            echo "  Time: $line"
        elif [[ -n "$line" ]]; then
            echo "  Text: $line"
        fi
    done < test0.srt
fi
echo ""

echo "=== Configuration 0.5: Whisper with clause-based splitting ==="
echo "Command: whisper test.wav --model small --language en --word_timestamps True + clause splitting"
start_time=$(date +%s)
whisper test.wav \
    --model small \
    --output_format txt \
    --output_dir . \
    --word_timestamps True \
    --temperature 0

# First generate SRT with proper timestamps using whisper
whisper test.wav \
    --model small \
    --output_format srt \
    --output_dir . \
    --word_timestamps True \
    --temperature 0

# Rename the output to a temporary file
mv test.srt temp_whisper.srt

# Post-process to create clause-based SRT with real timestamps
python3 << 'EOF'
import re

def parse_srt_time(time_str):
    """Convert SRT time format to seconds"""
    parts = time_str.replace(',', '.').split(':')
    hours = int(parts[0])
    minutes = int(parts[1])
    seconds = float(parts[2])
    return hours * 3600 + minutes * 60 + seconds

def format_srt_time(seconds):
    """Convert seconds to SRT time format"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"

# Read original SRT file and extract text with timestamps
segments = []
with open('temp_whisper.srt', 'r') as f:
    content = f.read().strip()

# Parse SRT blocks
srt_blocks = content.split('\n\n')
for block in srt_blocks:
    lines = block.strip().split('\n')
    if len(lines) >= 3:
        index = lines[0]
        time_line = lines[1]
        text_lines = lines[2:]
        
        # Parse timestamps
        start_time, end_time = time_line.split(' --> ')
        start_seconds = parse_srt_time(start_time)
        end_seconds = parse_srt_time(end_time)
        
        # Join text lines
        text = ' '.join(text_lines)
        
        segments.append({
            'start': start_seconds,
            'end': end_seconds,
            'text': text
        })

# Combine all text and split into clauses
full_text = ' '.join([seg['text'] for seg in segments])
clauses = re.split(r'([.!?,])', full_text)

# Merge clauses with their punctuation
merged_clauses = []
i = 0
while i < len(clauses):
    clause = clauses[i].strip()
    if i + 1 < len(clauses) and clauses[i + 1] in '.!?,':
        clause += clauses[i + 1]
        i += 2
    else:
        i += 1
    if clause:
        merged_clauses.append(clause.strip())

# Map clauses to timestamps
clause_segments = []
total_start = segments[0]['start'] if segments else 0
total_end = segments[-1]['end'] if segments else 60

# Distribute clauses proportionally across the total time
total_chars = sum(len(clause) for clause in merged_clauses)
current_time = total_start

for clause in merged_clauses:
    clause_chars = len(clause)
    # Proportional time allocation based on character count
    clause_duration = (clause_chars / total_chars) * (total_end - total_start)
    
    start_time = current_time
    end_time = current_time + clause_duration
    
    clause_segments.append({
        'start': start_time,
        'end': end_time,
        'text': clause
    })
    
    current_time = end_time

# Write new SRT file
with open('test05.srt', 'w') as f:
    for i, segment in enumerate(clause_segments, 1):
        f.write(f"{i}\n")
        f.write(f"{format_srt_time(segment['start'])} --> {format_srt_time(segment['end'])}\n")
        f.write(f"{segment['text']}\n\n")

print(f"Created clause-based SRT with {len(clause_segments)} segments")
print("Sample segments:")
for i, seg in enumerate(clause_segments[:3], 1):
    print(f"{i}: [{format_srt_time(seg['start'])} --> {format_srt_time(seg['end'])}] {seg['text']}")
EOF

# Clean up temporary file
rm -f temp_whisper.srt

end_time=$(date +%s)
echo "Generated: test05.srt (Time: $((end_time - start_time))s)"
if [ -f "test05.srt" ]; then
    echo ""
    echo "=== Subtitle Information for test05.srt ==="
    echo "Total lines: $(wc -l < test05.srt)"
    echo "Total subtitle entries: $(grep -c "^[0-9]*$" test05.srt)"
    echo ""
    echo "Displaying each subtitle entry:"
    entry=0
    while read -r line; do
        if [[ "$line" =~ ^[0-9]+$ ]]; then
            entry=$((entry + 1))
            echo "Entry $entry:"
        elif [[ "$line" =~ ^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
            echo "  Time: $line"
        elif [[ -n "$line" ]]; then
            echo "  Text: $line"
        fi
    done < test05.srt
fi
echo ""

echo "=== Configuration 1: Small model + Aggressive segmentation ==="
echo "Command: whisper test.wav --model small --word_timestamps True --no_speech_threshold 0.3 --logprob_threshold -0.8"
start_time=$(date +%s)
whisper test.wav \
    --model small \
    --output_format srt \
    --output_dir . \
    --word_timestamps True \
    --no_speech_threshold 0.3 \
    --logprob_threshold -0.8 \
    --compression_ratio_threshold 1.8 \
    --temperature 0
end_time=$(date +%s)
mv test.srt clause1.srt
echo "Generated: clause1.srt (Time: $((end_time - start_time))s)"
echo ""

echo "=== Configuration 2: Small model + VAD segmentation ==="
echo "Command: whisper test.wav --model small --word_timestamps True --condition_on_previous_text False --hallucination_silence_threshold 2"
start_time=$(date +%s)
whisper test.wav \
    --model small \
    --output_format srt \
    --output_dir . \
    --word_timestamps True \
    --condition_on_previous_text False \
    --hallucination_silence_threshold 2 \
    --no_speech_threshold 0.4 \
    --temperature 0
end_time=$(date +%s)
mv test.srt clause2.srt
echo "Generated: clause2.srt (Time: $((end_time - start_time))s)"
echo ""

echo "=== Configuration 3: Small model + Short clip timestamps ==="
echo "Command: whisper test.wav --model small --word_timestamps True --clip_timestamps 0,10,20,30,40,50,60,70,80"
start_time=$(date +%s)
whisper test.wav \
    --model small \
    --output_format srt \
    --output_dir . \
    --word_timestamps True \
    --clip_timestamps "0,10,20,30,40,50,60,70,80" \
    --no_speech_threshold 0.3 \
    --temperature 0
end_time=$(date +%s)
mv test.srt clause3.srt
echo "Generated: clause3.srt (Time: $((end_time - start_time))s)"
echo ""

echo "=== Configuration 4: Small model + Enhanced detection ==="
echo "Command: whisper test.wav --model small --word_timestamps True --compression_ratio_threshold 1.5 --logprob_threshold -0.5"
start_time=$(date +%s)
whisper test.wav \
    --model small \
    --output_format srt \
    --output_dir . \
    --word_timestamps True \
    --compression_ratio_threshold 1.5 \
    --logprob_threshold -0.5 \
    --no_speech_threshold 0.2 \
    --condition_on_previous_text False \
    --temperature 0
end_time=$(date +%s)
mv test.srt clause4.srt
echo "Generated: clause4.srt (Time: $((end_time - start_time))s)"
echo ""

echo "=== Configuration 5: Small model + Ultra-fine segmentation ==="
echo "Command: whisper test.wav --model small --word_timestamps True --no_speech_threshold 0.1 --hallucination_silence_threshold 1"
start_time=$(date +%s)
whisper test.wav \
    --model small \
    --output_format srt \
    --output_dir . \
    --word_timestamps True \
    --no_speech_threshold 0.1 \
    --hallucination_silence_threshold 1 \
    --compression_ratio_threshold 1.2 \
    --logprob_threshold -1.0 \
    --temperature 0
end_time=$(date +%s)
mv test.srt clause5.srt
echo "Generated: clause5.srt (Time: $((end_time - start_time))s)"
echo ""

echo "=== All clause-based configurations completed ==="
echo "Generated files:"
if [ -f "test0.srt" ]; then
    echo "test0.srt - $(wc -l < test0.srt) lines"
fi
if [ -f "test05.srt" ]; then
    echo "test05.srt - $(wc -l < test05.srt) lines"
fi
for i in {1..5}; do
    if [ -f "clause${i}.srt" ]; then
        echo "clause${i}.srt - $(wc -l < clause${i}.srt) lines"
    fi
done

echo ""
echo "=== Timing Summary ==="
echo "Configuration 0: Whisper with sentence-based splitting (real timestamps)"
echo "Configuration 0.5: Whisper with clause-based splitting (real timestamps)"
echo "Configuration 1: Small model + Aggressive segmentation"
echo "Configuration 2: Small model + VAD segmentation"
echo "Configuration 3: Small model + Short clip timestamps"
echo "Configuration 4: Small model + Enhanced detection"
echo "Configuration 5: Small model + Ultra-fine segmentation"

echo ""
echo "Preview of each configuration (first 10 lines):"
if [ -f "test0.srt" ]; then
    echo ""
    echo "=== test0.srt (Sentence-based) ==="
    head -10 test0.srt
fi
if [ -f "test05.srt" ]; then
    echo ""
    echo "=== test05.srt (Clause-based) ==="
    head -10 test05.srt
fi
for i in {1..5}; do
    if [ -f "clause${i}.srt" ]; then
        echo ""
        echo "=== clause${i}.srt ==="
        head -10 clause${i}.srt
    fi
done

echo ""
echo "Reference format from extracted_text.txt:"
echo "- Each line should be a semantic clause"
echo "- Natural pauses at commas, conjunctions"
echo "- Complete thoughts per subtitle"
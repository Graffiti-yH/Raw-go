#!/bin/bash
# RAW 文件整理工具 - Mac .command 深度递归+修图禁区隔离版

# ==========================================
# 🚨 Mac .command 专属核心修复 🚨
# 确保无论是通过终端执行，还是在 Finder 中双击运行，
# 都能精准将工作目录锁定在当前 .command 文件所在的物理文件夹。
# ==========================================
cd "$(dirname "$0")" || exit 1
CURRENT_DIR=$(pwd)

SCRIPT_NAME=$(basename "$0")

echo "=========================================="
echo "📸 RAW 文件整理工具 (Mac .command 安全隔离版)"
echo "=========================================="
echo "工作目录: ${CURRENT_DIR}"
echo ""

# 🚨 安全熔断机制：防止误在系统根目录或家目录执行
if [ "${CURRENT_DIR}" = "/" ] || [ "${CURRENT_DIR}" = "$HOME" ]; then
    echo "❌ 危险：检测到脚本尝试在系统根目录或家目录执行！"
    echo "请将此 .command 文件移动到你真正需要整理的照片文件夹内再双击运行。"
    read -p "按回车键退出..."
    exit 1
fi

RAW_EXTS="cr3 nef raw arw dng cr2 orf rw2"

# ========== 核心逻辑：定义哪些目录是绝对不准进入的禁区 ==========
is_prune_dir() {
    local dir_name=$(basename "$1")
    if [[ "$dir_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [ "$dir_name" = "CaptureOne" ] || [ "$dir_name" = "Griffiti" ] || [ "$dir_name" = "其他" ]; then
        return 0
    fi
    return 1
}

# ========== 第一步：解除未整理区域的尼康锁定 ==========
echo "🔓 1/5 正在深度扫描并解除尼康锁定文件..."
LOCKED_COUNT=0
while IFS= read -r -d '' file; do
    if [ -f "$file" ]; then
        chflags nouchg "$file" 2>/dev/null
        chmod +w "$file" 2>/dev/null
        ((LOCKED_COUNT++))
    fi
done < <(find "$CURRENT_DIR" -type d \( -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" -o -name "CaptureOne" -o -name "Griffiti" -o -name "其他" \) -prune -o -type f -iname "*.nef" -print0 2>/dev/null)
echo "   ✅ 已解除 $LOCKED_COUNT 个锁定文件"

# ========== 第二步：深度扁平化目录（精准绕行历史已整理目录与 Griffiti） ==========
echo ""
echo "📂 2/5 深度扁平化外部目录（自动挖掘深层新照片，绕过已整理文件夹与 Griffiti）..."

TEMP_FILE_LIST="/tmp/flatten_list_$$.txt"
> "$TEMP_FILE_LIST"

find "$CURRENT_DIR" -mindepth 2 \
    \( -type d \( -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" -o -name "CaptureOne" -o -name "Griffiti" -o -name "其他" \) -prune \) \
    -o \( -type f -print0 \) > "$TEMP_FILE_LIST" 2>/dev/null

TOTAL_FLATTEN=$(cat "$TEMP_FILE_LIST" | tr -cd '\0' | wc -c | tr -d ' ')
CURRENT=0

while IFS= read -r -d '' file; do
    [ -z "$file" ] && continue
    CURRENT=$((CURRENT + 1))
    printf "\r   提取深层文件: %d/%d" "$CURRENT" "$TOTAL_FLATTEN"
    
    base=$(basename "$file")
    target="$CURRENT_DIR/$base"
    
    if [ -e "$target" ]; then
        if [[ "$base" == *.* ]]; then
            name="${base%.*}"
            ext="${base##*.}"
        else
            name="$base"
            ext=""
        fi
        count=1
        if [ -n "$ext" ]; then
            while [ -e "$CURRENT_DIR/${name}${count}.${ext}" ]; do ((count++)); done
            target="$CURRENT_DIR/${name}${count}.${ext}"
        else
            while [ -e "$CURRENT_DIR/${name}${count}" ]; do ((count++)); done
            target="$CURRENT_DIR/${name}${count}"
        fi
    fi
    mv "$file" "$target" 2>/dev/null
done < "$TEMP_FILE_LIST"
printf "\n"
rm -f "$TEMP_FILE_LIST"

find "$CURRENT_DIR" -type d \( -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" -o -name "CaptureOne" -o -name "Griffiti" -o -name "其他" \) -prune -o -type d -empty -delete 2>/dev/null
echo "   ✅ 外部目录扁平化提取完成"

# ========== 第三步：清理外部备份 ==========
echo ""
echo "🧹 3/5 清理当前根目录下临时备份..."
find "$CURRENT_DIR" -maxdepth 1 -name "*_original" -type f -delete 2>/dev/null
echo "   ✅ 清理完成"

# ========== 第四步：整理 RAW 文件 ==========
echo ""
echo "🔄 4/5 整理新导入的 RAW 文件..."

RAW_LIST="/tmp/raw_move_$$.txt"
> "$RAW_LIST"
for ext in $RAW_EXTS; do
    find "$CURRENT_DIR" -maxdepth 1 -type f -iname "*.$ext" >> "$RAW_LIST"
done
TOTAL_RAW=$(wc -l < "$RAW_LIST" | tr -d ' ')
CURRENT=0

while IFS= read -r file; do
    [ -z "$file" ] && continue
    CURRENT=$((CURRENT + 1))
    printf "\r   归类 RAW: %d/%d" "$CURRENT" "$TOTAL_RAW"
    
    filename=$(basename "$file")
    date_val=$(exiftool -d "%Y-%m-%d" -DateTimeOriginal -s3 "$file" 2>/dev/null)
    [ -z "$date_val" ] && date_val=$(exiftool -d "%Y-%m-%d" -CreateDate -s3 "$file" 2>/dev/null)
    
    if [ -n "$date_val" ]; then
        target_dir="$CURRENT_DIR/$date_val"
        mkdir -p "$target_dir"
        target_file="$target_dir/$filename"
        if [ -e "$target_file" ]; then
            name="${filename%.*}"
            ext="${filename##*.}"
            count=1
            while [ -e "$target_dir/${name}_${count}.${ext}" ]; do ((count++)); done
            target_file="$target_dir/${name}_${count}.${ext}"
        fi
        mv "$file" "$target_file" 2>/dev/null
    else
        echo "   ⚠️ 无法获取日期: $filename"
    fi
done < "$RAW_LIST"
printf "\n"
rm -f "$RAW_LIST"

find "$CURRENT_DIR" -maxdepth 1 -type d -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" | while read date_dir; do
    dir_name=$(basename "$date_dir")
    prefix=$(echo "$dir_name" | tr -d "-")
    RENAME_LIST="/tmp/rename_$$.txt"
    > "$RENAME_LIST"
    
    for ext in $RAW_EXTS; do
        find "$date_dir" -maxdepth 1 -type f -iname "*.$ext" | while read file; do
            filename=$(basename "$file")
            if [[ "$filename" =~ ^${prefix}_[0-9]{4}\. ]]; then
                continue
            fi
            time_val=$(exiftool -DateTimeOriginal -d "%Y%m%d_%H%M%S" -s3 "$file" 2>/dev/null)
            [ -z "$time_val" ] && time_val=$(exiftool -CreateDate -d "%Y%m%d_%H%M%S" -s3 "$file" 2>/dev/null)
            [ -z "$time_val" ] && time_val="19700101_000000"
            echo "$time_val|$file" >> "$RENAME_LIST"
        done
    done
    
    if [ -s "$RENAME_LIST" ]; then
        sort -t"|" -k1,1 "$RENAME_LIST" | while IFS="|" read time_val file; do
            filename=$(basename "$file")
            ext="${file##*.}"
            ext_lower=$(echo "$ext" | tr "[:upper:]" "[:lower:]")
            count=$(find "$date_dir" -maxdepth 1 -type f -name "${prefix}_[0-9][0-9][0-9][0-9].${ext_lower}" 2>/dev/null | wc -l | tr -d ' ')
            idx=$((count + 1))
            new_name=$(printf "%s_%04d.%s" "$prefix" "$idx" "$ext_lower")
            new_path="$date_dir/$new_name"
            if [ "$file" != "$new_path" ] && [ ! -e "$new_path" ]; then
                mv "$file" "$new_path"
            fi
        done
    fi
    rm -f "$RENAME_LIST"
done

# ========== 第五步：移动外部非 RAW 文件 ==========
echo ""
echo "📦 5/5 移动当前目录下非 RAW 杂物..."
OTHER_DIR="$CURRENT_DIR/其他"
mkdir -p "$OTHER_DIR"
OTHER_LIST="/tmp/other_$$.txt"
find "$CURRENT_DIR" -maxdepth 1 -type f ! -iname "*.cr3" ! -iname "*.nef" ! -iname "*.raw" ! -iname "*.arw" ! -iname "*.dng" ! -iname "*.cr2" ! -iname "*.orf" ! -iname "*.rw2" > "$OTHER_LIST"
TOTAL_OTHER=$(wc -l < "$OTHER_LIST" | tr -d ' ')
CURRENT=0
while IFS= read -r file; do
    CURRENT=$((CURRENT + 1))
    printf "\r   移动其他: %d/%d" "$CURRENT" "$OTHER_COUNT"
    filename=$(basename "$file")
    [[ "$filename" == "$SCRIPT_NAME" || "$filename" == ".raw_md5_log.txt" || "$filename" == *.command ]] && continue
    target_file="$OTHER_DIR/$filename"
    if [ ! -e "$target_file" ]; then
        mv "$file" "$OTHER_DIR/" 2>/dev/null
    else
        name="${filename%.*}"
        ext="${filename##*.}"
        count=1
        while [ -e "$OTHER_DIR/${name}${count}.${ext}" ]; do ((count++)); done
        mv "$file" "$OTHER_DIR/${name}${count}.${ext}" 2>/dev/null
    fi
done < "$OTHER_LIST"
printf "\n"
rm -f "$OTHER_LIST"

echo ""
echo "=========================================="
echo "🎉 Mac 增量整理完成！(Griffiti 隔离区已生效)"
echo "=========================================="
read -p "按回车键退出..."

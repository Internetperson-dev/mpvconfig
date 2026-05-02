#!/bin/bash
# Auto-detect NEW Persona 5 Strikers dialogue by black box + text presence
# Properly skips trick frames (full black screens with no text)
# Saves full 16:9 gameplay screenshots with YYYY-MM-DD_HH-MM-SS format
# Usage: ./detect_dialogue.sh <video_file> [output_dir] [recording_start_datetime]

VIDEO="${1:?Usage: $0 <video_file> [output_dir] [recording_start_datetime]}"
OUTDIR="${2:-.}"
RECORD_START="${3:-}"

INTERVAL=1                # Sample every N seconds
BOTTOM_HEIGHT=280         # P5 Strikers dialogue box height
MIN_GAP=2                 # Min seconds between saves
BLACK_TOL=50              # Color tolerance for near-black pixels

mkdir -p "$OUTDIR"

# Get video info
W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$VIDEO")
H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VIDEO")
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" 2>/dev/null | cut -d. -f1)
[ -z "$D" ] && { echo "Error: Could not get video duration"; exit 1; }

# Calculate recording start datetime
if [ -n "$RECORD_START" ]; then
    START_EPOCH=$(date -d "$RECORD_START" +%s 2>/dev/null || echo "")
    [ -z "$START_EPOCH" ] && { echo "Error: Invalid datetime format. Use 'YYYY-MM-DD HH:MM:SS'"; exit 1; }
else
    START_EPOCH=$(stat -c %Y "$VIDEO" 2>/dev/null || date +%s)
fi

echo "Persona 5 Strikers Dialogue Detector (Improved)"
echo "Video: ${W}x${H}, Duration: ${D}s"
echo "Looking for black dialogue box with text in bottom ${BOTTOM_HEIGHT}px"
echo ""

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

DETECTED=0
LAST_SAVE=0

for ts in $(seq 0 $INTERVAL $D); do
    # Skip if too close to last saved dialogue
    [ $((ts - LAST_SAVE)) -lt $MIN_GAP ] && continue

    FRAME_EPOCH=$((START_EPOCH + ts))
    DATETIME=$(date -d @$FRAME_EPOCH '+%Y-%m-%d_%H-%M-%S' 2>/dev/null || echo "unknown_${ts}s")

    # Extract bottom portion and analyze with Python
    ffmpeg -y -ss "$ts" -i "$VIDEO" -vframes 1 \
        -vf "crop=${W}:${BOTTOM_HEIGHT}:0:$((H-BOTTOM_HEIGHT))" \
        -f rawvideo -pix_fmt rgb24 "$TMP/bottom.raw" 2>/dev/null
    
    [ ! -f "$TMP/bottom.raw" ] && continue

    # Python analysis: check for black box + white text
    RESULT=$(python3 -c "
import sys
data = open('$TMP/bottom.raw','rb').read()
w = $W
h = $BOTTOM_HEIGHT
tol = $BLACK_TOL
total = w * h

# Count black pixels and white pixels (text)
black = 0
white = 0  # pixels that are bright (text)
for i in range(0, len(data)-2, 3):
    r, g, b = data[i], data[i+1], data[i+2]
    if r <= tol and g <= tol and b <= tol:
        black += 1
    elif r >= 200 and g >= 200 and b >= 200:  # White text
        white += 1

black_ratio = black / total
white_ratio = white / total

# Dialogue detection logic:
# 1. Must have significant black (the box) - at least 10%
# 2. Must have white pixels (the text) - at least 0.5%
# 3. Skip if ALL black (trick frame) - white pixels < 0.1%

if black_ratio >= 0.10 and white_ratio >= 0.005:
    print('DETECTED')
elif black_ratio >= 0.85 and white_ratio < 0.001:
    print('TRICK')
else:
    print('NO')
" 2>/dev/null)

    if [ "$RESULT" = "DETECTED" ]; then
        FILENAME="$OUTDIR/p5s_dlg_${DATETIME}.jpg"
        ffmpeg -y -ss "$ts" -i "$VIDEO" -vframes 1 -q:v 2 "$FILENAME" 2>/dev/null
        echo "[$ts""s] Dialogue detected -> p5s_dlg_${DATETIME}.jpg"
        DETECTED=$((DETECTED+1))
        LAST_SAVE=$ts
    fi
done

echo ""
echo "Found $DETECTED dialogue frames in: $OUTDIR"

#!/bin/bash

# --- FFmpeg Video Processing Script ---
# This script rotates, scales (if UHD), and prepends a video,
# then encodes the final output to HEVC (x265) 10-bit with QuickTime compatibility.
# It uses ProRes as an intermediate format for quality preservation.
#
# It automatically detects and utilizes Apple VideoToolbox hardware acceleration,
# falling back to software encoding if not available.

# --- Usage ---
# Save this script as, e.g., 'process_video.sh'.
# Make it executable: chmod +x process_video.sh
# Run it: ./process_video.sh "input_video.mp4"
# Skip thumbnail generation: ./process_video.sh "input_video.mp4" --skip-thumbnails
# Skip rotation/re-encode: ./process_video.sh "input_video.mp4" --skip-rotation
# Skip banner video: ./process_video.sh "input_video.mp4" --skip-banner
# Set quality: ./process_video.sh "input_video.mp4" --quality high
# Keep intermediate ProRes file: ./process_video.sh "input_video.mp4" --keep-intermediate
# Combine options: ./process_video.sh "input_video.mp4" --skip-thumbnails --quality best --keep-intermediate --skip-banner
#
# Note: 'RotateYourPhoneHD.mp4' must be in the 'media' subdirectory.

# --- Script Location ---
# Get the directory where the script is located, resolving symlinks.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# --- Show Usage Information ---
show_usage() {
    cat << EOF
RotateYourPhone - FFmpeg-based Video Processing Script

Usage: $0 <input_video_file> [OPTIONS]

Options:
  --skip-thumbnails     Skip thumbnail generation
  --skip-rotation       Skip rotation and ProRes conversion (use existing intermediate file)
  --skip-banner         Skip adding the intro banner video
  --quality <level>     Set quality level (fast, medium, high, or best) [default: best]
  --keep-intermediate   Keep the intermediate ProRes file after processing
  --disable-hwaccel     Disable hardware acceleration and force software encoding
  -o <output_dir>       Specify output directory [default: current directory]
  --help                Display this help message and exit

Examples:
  $0 "MyVideo.mp4"
  $0 "MyVideo.mp4" --quality high --skip-thumbnails
  $0 "MyVideo.mp4" --keep-intermediate -o ~/Videos/Output
EOF
}

# --- Script Configuration ---
PREFIX_VIDEO="${SCRIPT_DIR}/media/RotateYourPhoneHD.mp4"

# --- Output Directory ---
OUTPUT_DIR=""
# --- Argument Parsing ---
SKIP_THUMBNAILS=false
SKIP_ROTATION=false
SKIP_BANNER=false
KEEP_INTERMEDIATE=false
DISABLE_HWACCEL=false
INPUT_FILE=""
QUALITY_LEVEL="best" # Default quality: fast, medium, high, best

while (( "$#" )); do
  case "$1" in
    --help)
      show_usage
      exit 0
      ;;
    --skip-thumbnails)
      SKIP_THUMBNAILS=true
      shift
      ;;
    --skip-rotation)
      SKIP_ROTATION=true
      shift
      ;;
    --skip-banner)
      SKIP_BANNER=true
      SKIP_ROTATION=false  # Force rotation when skipping banner
      shift
      ;;
    --keep-intermediate)
      KEEP_INTERMEDIATE=true
      shift
      ;;
    --disable-hwaccel)
      DISABLE_HWACCEL=true
      shift
      ;;
    --quality)
      if [ -n "$2" ] && ! [[ "$2" == --* ]]; then
        QUALITY_LEVEL="$2"
        shift 2
      else
        echo "Error: --quality requires an argument (fast, medium, high, or best)."
        show_usage
        exit 1
      fi
      ;;
    -o)
      if [ -n "$2" ] && ! [[ "$2" == --* ]]; then
        OUTPUT_DIR="$2"
        shift 2
      else
        echo "Error: -o requires an output directory argument."
        show_usage
        exit 1
      fi
      ;;
    -*) # Unknown option
      echo "Warning: Unrecognized option: $1"
      show_usage
      exit 1
      ;;
    *) # Positional argument (input file)
      if [ -z "$INPUT_FILE" ]; then
        INPUT_FILE="$1"
        shift
      else
        echo "Error: Too many input files or unrecognized argument: $1"
        show_usage
        exit 1
      fi
      ;;
  esac
done

# --- Input Validation ---
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "Error: FFmpeg and ffprobe are required but not found. Please install them."
    exit 1
fi

if [ -z "$INPUT_FILE" ]; then
  echo "Error: No input video file provided."
  show_usage
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found."
    exit 1
fi

if ! $SKIP_BANNER && [ ! -f "$PREFIX_VIDEO" ]; then
    echo "Error: Prefix video '$PREFIX_VIDEO' not found. Ensure it exists in the 'media' subdirectory."
    exit 1
fi

if [ -n "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR" || { echo "Error: Could not create output directory '$OUTPUT_DIR'"; exit 1; }
else
  OUTPUT_DIR="."
fi

INPUT_BASE_NAME="$(basename "$INPUT_FILE")"
INPUT_BASE="${INPUT_BASE_NAME%.*}"

# --- Hardware Acceleration Detection ---
echo "--- Checking for hardware acceleration ---"
USE_VIDEOTOOLBOX=false
if ! $DISABLE_HWACCEL; then
  if ffmpeg -v quiet -encoders | grep -q 'hevc_videotoolbox'; then
    USE_VIDEOTOOLBOX=true
    echo "Apple VideoToolbox found. Hardware acceleration enabled."
  else
    echo "Apple VideoToolbox not found. Falling back to software encoding (libx265/prores_ks)."
  fi
else
  echo "Hardware acceleration disabled by user. Using software encoding."
fi
echo ""

# --- Encoder Parameters ---
PRORES_ENCODER=""
PRORES_OPTS=()
HEVC_ENCODER=""
HEVC_PIXEL_FORMAT=""
HEVC_OPTS=()
FINAL_PRESET=""
FINAL_CRF=""

if $USE_VIDEOTOOLBOX; then
  # Hardware Accelerated Encoder Settings (Apple VideoToolbox)
  PRORES_ENCODER="prores_videotoolbox"
  PRORES_OPTS=("-profile:v" "3") # HQ Profile
  HEVC_ENCODER="hevc_videotoolbox"
  HEVC_PIXEL_FORMAT="p010le" # 10-bit HEVC

  case "$QUALITY_LEVEL" in
    fast)   HEVC_OPTS=("-b:v" "8M");;
    medium) HEVC_OPTS=("-b:v" "12M");;
    high)   HEVC_OPTS=("-b:v" "15M");;
    best)   HEVC_OPTS=("-b:v" "20M");;
    *) echo "Error: Invalid quality level '$QUALITY_LEVEL'." >&2; exit 1;;
  esac
else
  # Software Encoder Settings (libx265, prores_ks)
  PRORES_ENCODER="prores_ks"
  PRORES_OPTS=("-profile:v" "3") # HQ Profile
  HEVC_ENCODER="libx265"
  HEVC_PIXEL_FORMAT="yuv420p10le" # 10-bit HEVC

  case "$QUALITY_LEVEL" in
    fast)   FINAL_CRF=13; FINAL_PRESET="fast";;
    medium) FINAL_CRF=12; FINAL_PRESET="medium";;
    high)   FINAL_CRF=11; FINAL_PRESET="slow";;
    best)   FINAL_CRF=10; FINAL_PRESET="slower";;
    *) echo "Error: Invalid quality level '$QUALITY_LEVEL'." >&2; exit 1;;
  esac
  HEVC_OPTS=("-crf" "$FINAL_CRF" "-preset" "$FINAL_PRESET")
fi

# --- Output Filenames ---
INTERMEDIATE_PRORES_FILE="${OUTPUT_DIR}/${INPUT_BASE}_rotated_prores.mov"
FINAL_HEVC_OUTPUT_FILE="${OUTPUT_DIR}/${INPUT_BASE}-RotateYourPhone-${QUALITY_LEVEL}.mp4"

echo "--- Starting Video Processing ---"
echo "Input: '$INPUT_FILE'"
echo "Output: '$FINAL_HEVC_OUTPUT_FILE'"
echo "Quality: $QUALITY_LEVEL"
echo ""

# --- Get Source Video Properties ---
echo "--- Detecting source video properties ---"
VIDEO_FRAMERATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
VIDEO_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
VIDEO_HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
INPUT_METADATA_ROTATION=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=rotate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | head -n 1)

if [ -z "$VIDEO_FRAMERATE" ] || [ -z "$VIDEO_WIDTH" ] || [ -z "$VIDEO_HEIGHT" ]; then
  echo "Error: Could not detect video properties. Aborting."
  exit 1
fi
echo "Detected: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}, ${VIDEO_FRAMERATE} fps, Metadata Rotation: ${INPUT_METADATA_ROTATION:-0} degrees"
echo ""

# --- Determine Video Filters ---
IS_4K=false
if { [ "$VIDEO_WIDTH" -eq 3840 ] && [ "$VIDEO_HEIGHT" -eq 2160 ]; } || \
   { [ "$VIDEO_WIDTH" -eq 2160 ] && [ "$VIDEO_HEIGHT" -eq 3840 ]; }; then
  IS_4K=true
fi

PRORES_VF_FILTER=""
THUMBNAILS_VF_FILTER=""
ROTATION_NOTES=""

# Apply initial correction based on metadata or dimensions
INITIAL_CORRECTION_FILTER=""
if [ -n "$INPUT_METADATA_ROTATION" ] && [ "$INPUT_METADATA_ROTATION" -ne 0 ]; then
  if [ "$INPUT_METADATA_ROTATION" -eq 90 ]; then
    INITIAL_CORRECTION_FILTER="transpose=1"
    ROTATION_NOTES="Applying 90-degree rotation (metadata)."
  elif [ "$INPUT_METADATA_ROTATION" -eq 270 ] || [ "$INPUT_METADATA_ROTATION" -eq -90 ]; then
    INITIAL_CORRECTION_FILTER="transpose=2"
    ROTATION_NOTES="Applying 270-degree rotation (metadata)."
  elif [ "$INPUT_METADATA_ROTATION" -eq 180 ]; then
    INITIAL_CORRECTION_FILTER="transpose=2,transpose=2"
    ROTATION_NOTES="Applying 180-degree rotation (metadata)."
  else
    ROTATION_NOTES="Unsupported metadata rotation ($INPUT_METADATA_ROTATION deg). No initial correction."
  fi
else
  if [ "$VIDEO_HEIGHT" -gt "$VIDEO_WIDTH" ]; then
    INITIAL_CORRECTION_FILTER="transpose=1" # Correct portrait to landscape for further processing
    ROTATION_NOTES="Portrait video detected. Applying initial 90-degree rotation."
  else
    ROTATION_NOTES="Video is landscape or square. No initial correction."
  fi
fi

# Build main video processing filter (PRORES_VF_FILTER)
if [ -n "$INITIAL_CORRECTION_FILTER" ]; then
    PRORES_VF_FILTER="$INITIAL_CORRECTION_FILTER"
fi
PRORES_VF_FILTER+="${PRORES_VF_FILTER:+,}transpose=1" # Force 90 deg clockwise for final output
ROTATION_NOTES+=" Then, forcing an additional 90-degree rotation for the final video output."

# Apply scaling if 4K
if $IS_4K; then
  PRORES_VF_FILTER="scale=1920:1080${PRORES_VF_FILTER:+,}$PRORES_VF_FILTER"
  ROTATION_NOTES+=" Input is 4K; scaling to HD (1920x1080)."
else
  ROTATION_NOTES+=" Input is not 4K; no scaling applied."
fi

# Build thumbnail filter (THUMBNAILS_VF_FILTER)
THUMBNAILS_VF_FILTER="$INITIAL_CORRECTION_FILTER"

# Scale thumbnails to HD if input is 4K
if $IS_4K; then
  TEMP_WIDTH_AFTER_CORRECTION=$VIDEO_WIDTH
  TEMP_HEIGHT_AFTER_CORRECTION=$VIDEO_HEIGHT
  
  if [ -n "$INITIAL_CORRECTION_FILTER" ] && (echo "$INITIAL_CORRECTION_FILTER" | grep -q "transpose=[12]"); then
      TEMP_WIDTH_AFTER_CORRECTION=$VIDEO_HEIGHT
      TEMP_HEIGHT_AFTER_CORRECTION=$VIDEO_WIDTH
  fi

  if [ "$TEMP_WIDTH_AFTER_CORRECTION" -gt "$TEMP_HEIGHT_AFTER_CORRECTION" ]; then # Landscape after correction
      THUMBNAIL_HD_SCALE="scale='min(1920,iw)':min'(1080,ih)':force_original_aspect_ratio=decrease"
  else # Portrait after correction
      THUMBNAIL_HD_SCALE="scale='min(1080,iw)':min'(1920,ih)':force_original_aspect_ratio=decrease"
  fi

  THUMBNAILS_VF_FILTER+="${THUMBNAILS_VF_FILTER:+,}$THUMBNAIL_HD_SCALE"
fi

echo "$ROTATION_NOTES"
echo "ProRes/Video Filter: '$PRORES_VF_FILTER'"
echo "Thumbnail Filter: '$THUMBNAILS_VF_FILTER'"
echo ""

# Determine target resolution for concatenation
TEMP_WIDTH=$VIDEO_WIDTH
TEMP_HEIGHT=$VIDEO_HEIGHT

if [ -n "$INITIAL_CORRECTION_FILTER" ] && (echo "$INITIAL_CORRECTION_FILTER" | grep -q "transpose=[12]"); then
    TEMP_WIDTH=$VIDEO_HEIGHT
    TEMP_HEIGHT=$VIDEO_WIDTH
fi

TEMP_WIDTH_AFTER_FORCE_ROTATE=$TEMP_HEIGHT
TEMP_HEIGHT_AFTER_FORCE_ROTATE=$TEMP_WIDTH

if $IS_4K; then
  TARGET_WIDTH=1080
  TARGET_HEIGHT=1920
else
    TARGET_WIDTH=$TEMP_WIDTH_AFTER_FORCE_ROTATE
    TARGET_HEIGHT=$TEMP_HEIGHT_AFTER_FORCE_ROTATE
fi

echo "Target concatenation resolution: ${TARGET_WIDTH}x${TARGET_HEIGHT}"
echo ""

# --- Thumbnail Generation ---
if ! $SKIP_THUMBNAILS; then
  echo "--- Generating optimized thumbnails ---"
  DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
  if [ -z "$DURATION" ]; then
    echo "Warning: Could not get video duration. Skipping thumbnail generation."
  else
    for i in $(seq 0 19); do
      PERCENTAGE=$((i * 5))
      TIMESTAMP=$(awk "BEGIN { printf \"%.3f\", $DURATION * $PERCENTAGE / 100 }")
      # Generate three thumbnails with different x offsets
      for idx in 0 1 2; do
        case $idx in
          0) CROP_FILTER="${THUMBNAILS_VF_FILTER:+$THUMBNAILS_VF_FILTER,}crop=608:1080:0+300:0"; THUMBNAIL_OUTPUT_FILE="${OUTPUT_DIR}/${INPUT_BASE}-Thumb-${PERCENTAGE}p-0.png";;
          1) CROP_FILTER="${THUMBNAILS_VF_FILTER:+$THUMBNAILS_VF_FILTER,}crop=608:1080"; THUMBNAIL_OUTPUT_FILE="${OUTPUT_DIR}/${INPUT_BASE}-Thumb-${PERCENTAGE}p-1.png";;
          2) CROP_FILTER="${THUMBNAILS_VF_FILTER:+$THUMBNAILS_VF_FILTER,}crop=608:1080:0+1012:0"; THUMBNAIL_OUTPUT_FILE="${OUTPUT_DIR}/${INPUT_BASE}-Thumb-${PERCENTAGE}p-2.png";;
        esac
        echo "Generating thumbnail at ${TIMESTAMP}s (${PERCENTAGE}%, idx $idx): '$THUMBNAIL_OUTPUT_FILE'"
        ffmpeg -ss "$TIMESTAMP" -i "$INPUT_FILE" \
          -vf "$CROP_FILTER" \
          -frames:v 1 -q:v 2 -y "$THUMBNAIL_OUTPUT_FILE" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
          echo "Warning: Failed to generate thumbnail '$THUMBNAIL_OUTPUT_FILE'."
        fi
      done
    done
    echo "--- Thumbnail generation complete ---"
  fi
  echo ""
else
  echo "--- Skipping thumbnail generation ---"
  echo ""
fi

# --- Step 1: Rotate/Scale and Convert to ProRes ---
if ! $SKIP_ROTATION; then
  echo "--- Step 1/2: Processing to ProRes intermediate file... ---"
  echo "Applying video filter: '${PRORES_VF_FILTER}'"
  
  INPUT_HAS_AUDIO=false
  if ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$INPUT_FILE" | grep -q audio; then
    INPUT_HAS_AUDIO=true
  fi

  FFMPEG_PRORES_CMD=(ffmpeg -hwaccel auto -i "$INPUT_FILE")
  if [ -n "$PRORES_VF_FILTER" ]; then
      FFMPEG_PRORES_CMD+=(-vf "$PRORES_VF_FILTER")
  fi

  FFMPEG_PRORES_CMD+=(-c:v "$PRORES_ENCODER" "${PRORES_OPTS[@]}")
  if $INPUT_HAS_AUDIO; then
      FFMPEG_PRORES_CMD+=(-c:a pcm_s16le -ar 48000)
  else
      FFMPEG_PRORES_CMD+=(-an -map_metadata -1) # No audio, and remove metadata to ensure no empty audio track info
  fi

  FFMPEG_PRORES_CMD+=(-y "$INTERMEDIATE_PRORES_FILE")

  time "${FFMPEG_PRORES_CMD[@]}"

  if [ $? -ne 0 ]; then
    echo "Error: FFmpeg failed during ProRes conversion. Aborting."
    exit 1
  fi
  echo "--- ProRes intermediate file created: '$INTERMEDIATE_PRORES_FILE' ---"
  echo ""
else
  echo "--- Skipping ProRes conversion ---"
  if [ ! -f "$INTERMEDIATE_PRORES_FILE" ]; then
    echo "Error: --skip-rotation was used, but intermediate file '$INTERMEDIATE_PRORES_FILE' not found."
    exit 1
  else
    echo "Using existing intermediate file: '$INTERMEDIATE_PRORES_FILE'."
  fi
  echo ""
fi

# --- Step 2: Encode to HEVC 10-bit (with or without banner) ---
if $SKIP_BANNER; then
  echo "--- Step 2/2: Encoding rotated video to HEVC 10-bit (banner skipped)... ---"
  
  # Check if intermediate file has audio
  INTERMEDIATE_HAS_AUDIO=false
  if ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$INTERMEDIATE_PRORES_FILE" | grep -q audio; then
    # Specifically check if the audio stream actually has a duration.
    # An empty audio stream might still show up as 'audio' codec_type.
    AUDIO_DURATION=$(ffprobe -v error -select_streams a:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INTERMEDIATE_PRORES_FILE")
    if (( $(echo "$AUDIO_DURATION > 0" | bc -l) )); then
      INTERMEDIATE_HAS_AUDIO=true
    fi
  fi
  
  # Direct encode from ProRes to HEVC without banner
  FINAL_MAP_AUDIO=()
  if $INTERMEDIATE_HAS_AUDIO; then
    echo "Source file has audio. Including it in the final output."
    FINAL_MAP_AUDIO=("-map" "0:a" "-c:a" "aac" "-ar" "48000" "-b:a" "192k")
  else
    echo "Source file has no audio. Final output will be video-only."
    FINAL_MAP_AUDIO=("-an") # No audio
  fi
  
  time ffmpeg -i "$INTERMEDIATE_PRORES_FILE" \
    -map 0:v \
    "${FINAL_MAP_AUDIO[@]}" \
    -c:v "$HEVC_ENCODER" \
    -tag:v hvc1 \
    -pix_fmt "$HEVC_PIXEL_FORMAT" \
    "${HEVC_OPTS[@]}" \
    -r "$VIDEO_FRAMERATE" \
    -y \
    "$FINAL_HEVC_OUTPUT_FILE"
    
else
  echo "--- Step 2/2: Concatenating with banner and encoding to HEVC 10-bit... ---"

  # Check if intermediate file has audio
  INTERMEDIATE_HAS_AUDIO=false
  if ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$INTERMEDIATE_PRORES_FILE" | grep -q audio; then
    # Specifically check if the audio stream actually has a duration.
    # An empty audio stream might still show up as 'audio' codec_type.
    AUDIO_DURATION=$(ffprobe -v error -select_streams a:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INTERMEDIATE_PRORES_FILE")
    if (( $(echo "$AUDIO_DURATION > 0" | bc -l) )); then
      INTERMEDIATE_HAS_AUDIO=true
    fi
  fi

  # Scale prefix video to match intermediate file dimensions for concatenation
  # Build concatenation filter complex based on audio presence of intermediate file
  # The prefix video (RotateYourPhoneHD.mp4) is assumed to ALWAYS have audio.
  # Therefore, [0:a] (audio from input 0, which is PREFIX_VIDEO) will always be present.
  CONCAT_FILTER_COMPLEX="[0:v]scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:force_original_aspect_ratio=decrease,pad=${TARGET_WIDTH}:${TARGET_HEIGHT}:(ow-iw)/2:(oh-ih)/2[v0];"
  if $INTERMEDIATE_HAS_AUDIO; then
    echo "Intermediate file has audio. Including it in the concatenation."
    CONCAT_FILTER_COMPLEX+="[v0][0:a][1:v][1:a]concat=n=2:v=1:a=1[v][a]"
  else
    # Intermediate does not have audio, but we still need to include the prefix video's audio.
    # The final audio stream will come only from the prefix video.
    echo "Intermediate file has no audio. Concatenating video streams only."
    CONCAT_FILTER_COMPLEX+="[v0][1:v]concat=n=2:v=1:a=0[v]"
  fi 
  echo "Using filter complex: '$CONCAT_FILTER_COMPLEX'"

  FINAL_MAP_AUDIO=()
  if ! $INTERMEDIATE_HAS_AUDIO; then
    FINAL_MAP_AUDIO=("-map" "0:a") # Map audio only from the first input (prefix video)
  else
    FINAL_MAP_AUDIO=("-map" "[a]") # Map audio output from the concat filter
  fi

  time ffmpeg -i "$PREFIX_VIDEO" -i "$INTERMEDIATE_PRORES_FILE" \
    -filter_complex "$CONCAT_FILTER_COMPLEX" \
    -map "[v]" "${FINAL_MAP_AUDIO[@]}" \
    -c:v "$HEVC_ENCODER" \
    -tag:v hvc1 \
    -pix_fmt "$HEVC_PIXEL_FORMAT" \
    "${HEVC_OPTS[@]}" \
    -r "$VIDEO_FRAMERATE" \
    -c:a aac \
    -ar 48000 \
    -b:a 192k \
    -y \
    "$FINAL_HEVC_OUTPUT_FILE"
fi

if [ $? -ne 0 ]; then
  echo "Error: FFmpeg failed during final HEVC encoding. Aborting."
  exit 1
fi
echo "--- Final HEVC 10-bit file created ---"
echo ""

# --- Cleanup ---
if ! $SKIP_ROTATION && ! $KEEP_INTERMEDIATE; then
  echo "--- Cleaning up intermediate file: '$INTERMEDIATE_PRORES_FILE' ---"
  rm "$INTERMEDIATE_PRORES_FILE"
elif $KEEP_INTERMEDIATE; then
  echo "--- Intermediate ProRes file retained as requested ---"
else
  echo "--- Intermediate ProRes file retained (rotation was skipped) ---"
fi

echo "--- Script finished successfully! ---"
echo "Your final video is: '$FINAL_HEVC_OUTPUT_FILE'"

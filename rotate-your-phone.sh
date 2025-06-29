#!/bin/bash

# --- FFmpeg Video Processing Script ---
# This script rotates an input video, prepends another video,
# and encodes the final output to HEVC (x265) 10-bit with QuickTime compatibility.
# It uses ProRes as an intermediate format to preserve quality.

# --- Usage ---
# Save this script as, for example, 'process_video.sh'
# Make it executable: chmod +x process_video.sh
# Run it: ./process_video.sh "FREYA_2024.mp4"
# To skip thumbnail generation: ./process_video.sh "FREYA_2024.mp4" --skip-thumbnails
# To skip rotation and re-encode: ./process_video.sh "FREYA_2024.mp4" --skip-rotation
# To specify quality: ./process_video.sh "FREYA_2024.mp4" --quality high
# To keep the intermediate ProRes file: ./process_video.sh "FREYA_2024.mp4" --keep-intermediate
# Combine options: ./process_video.sh "FREYA_2024.mp4" --skip-thumbnails --quality best --keep-intermediate
# Note: The script expects 'RotateYourPhoneHD.mp4' to exist in the 'media' subdirectory relative to the script location.
# If you want to use a different prefix video, replace the file in the 'media' directory or update the PREFIX_VIDEO variable in the script.
#
# The script will always look for the prefix video in:
#   <script_directory>/media/RotateYourPhoneHD.mp4
# regardless of your current working directory.

# --- Script Location ---
# Get the directory where the script is located, resolving symlinks
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# --- Script Configuration ---
# The video file to prepend at the beginning of your rotated video.
# This file should exist in the 'media' subdirectory relative to the script location.
# Example: /path/to/script/media/RotateYourPhoneHD.mp4
PREFIX_VIDEO="${SCRIPT_DIR}/media/RotateYourPhoneHD.mp4"

# --- Argument Parsing ---
SKIP_THUMBNAILS=false
SKIP_ROTATION=false
KEEP_INTERMEDIATE=false # New parameter to keep the intermediate ProRes file
INPUT_FILE=""
QUALITY_LEVEL="medium" # Default quality level

# Parse command line arguments
while (( "$#" )); do
  case "$1" in
    --skip-thumbnails)
      SKIP_THUMBNAILS=true
      shift
      ;;
    --skip-rotation)
      SKIP_ROTATION=true
      shift
      ;;
    --keep-intermediate) # Handle new argument
      KEEP_INTERMEDIATE=true
      shift
      ;;
    --quality)
      if [ -n "$2" ] && ! [[ "$2" == --* ]]; then
        QUALITY_LEVEL="$2"
        shift 2
      else
        echo "Error: --quality requires an argument (medium, high, or best)."
        exit 1
      fi
      ;;
    -*) # Unknown options
      echo "Warning: Unrecognized option: $1"
      shift
      ;;
    *) # Positional argument (input file)
      if [ -z "$INPUT_FILE" ]; then
        INPUT_FILE="$1"
        shift
      else
        echo "Warning: Too many input files or unrecognized argument: $1"
        echo "Usage: $0 <input_video_file> [--skip-thumbnails] [--skip-rotation] [--quality <level>] [--keep-intermediate]"
        exit 1
      fi
      ;;
  esac
done

# --- Input Validation ---
if [ -z "$INPUT_FILE" ]; then
  echo "Error: No input video file provided."
  echo "Usage: $0 <input_video_file> [--skip-thumbnails] [--skip-rotation] [--quality <level>] [--keep-intermediate]"
  exit 1
fi

# Extract the base name of the input file (e.g., "FREYA_2024" from "FREYA_2024.mp4")
INPUT_BASE="${INPUT_FILE%.*}"

# --- Determine Quality Parameters for Final HEVC Encoding ---
FINAL_CRF=""
FINAL_PRESET=""

case "$QUALITY_LEVEL" in
  fast)
    FINAL_CRF=13
    FINAL_PRESET="fast"
    ;;
  medium)
    FINAL_CRF=11
    FINAL_PRESET="medium"
    ;;
  high)
    FINAL_CRF=10
    FINAL_PRESET="medium"
    ;;
  best)
    FINAL_CRF=9
    FINAL_PRESET="medium"
    ;;
  *)
    echo "Error: Invalid quality level '$QUALITY_LEVEL'. Must be medium, high, or best."
    exit 1
    ;;
esac

# --- Define Output Filenames ---
# The intermediate file will be ProRes to avoid quality loss during rotation.
# Changed extension from .mp4 to .mov for better ProRes compatibility
INTERMEDIATE_PRORES_FILE="${INPUT_BASE}_rotated_prores.mov"
# The final output file will be HEVC 10-bit.
FINAL_HEVC_OUTPUT_FILE="${INPUT_BASE}-RotateYourPhone-${FINAL_CRF}-${FINAL_PRESET}.mp4"

echo "--- Starting Video Processing ---"
echo "Input file: '$INPUT_FILE'"
echo "Prefix video: '$PREFIX_VIDEO'"
echo "Intermediate ProRes file: '$INTERMEDIATE_PRORES_FILE'"
echo "Final HEVC 10-bit file: '$FINAL_HEVC_OUTPUT_FILE'"
if $SKIP_THUMBNAILS; then
  echo "Thumbnail generation will be skipped."
else
  echo "Thumbnails will be generated."
fi
if $SKIP_ROTATION; then
  echo "Rotation and ProRes conversion will be skipped (assuming '$INTERMEDIATE_PRORES_FILE' exists)."
else
  echo "Rotation and ProRes conversion will be performed."
fi
if $KEEP_INTERMEDIATE; then
  echo "Intermediate ProRes file will be kept."
else
  echo "Intermediate ProRes file will be removed."
fi
echo "Requested quality level: '$QUALITY_LEVEL'"
echo "Encoding with CRF: $FINAL_CRF, Preset: $FINAL_PRESET"
echo ""

# --- Get Source Video Properties (Framerate, Dimensions) ---
echo "--- Detecting source video properties ---"

# Detect average framerate
VIDEO_FRAMERATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
if [ -z "$VIDEO_FRAMERATE" ]; then
  echo "Error: Could not detect video framerate. Aborting."
  exit 1
fi
echo "Detected framerate: $VIDEO_FRAMERATE fps"

# Detect video width and height
VIDEO_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
VIDEO_HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")

if [ -z "$VIDEO_WIDTH" ] || [ -z "$VIDEO_HEIGHT" ]; then
  echo "Error: Could not detect video dimensions. Aborting."
  exit 1
fi
echo "Detected dimensions: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}"
echo ""

# --- Determine Video Filter for Rotation/Resizing ---
TRANSPOSE_FILTER="transpose=1" # Default filter for rotation
if [ "$VIDEO_WIDTH" -eq 3840 ] || [ "$VIDEO_HEIGHT" -eq 2160 ]; then
  # If source is 4K (3840x2160), rotate and then scale to 1080x1920
  # Note: transpose=1 rotates 90 degrees clockwise.
  # So 3840x2160 becomes 2160x3840, which then scales to 1080x1920.
  TRANSPOSE_FILTER="transpose=1,scale=1080:1920"
  echo "Detected 4K input. Applying rotation and scaling to 1080x1920."
else
  echo "Detected non-4K input. Applying rotation only."
fi
echo ""

# Detect rotation metadata
VIDEO_ROTATION=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=rotate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | head -n 1) # Capture first line only

# Determine if 4K
IS_4K=false
if { [ "$VIDEO_WIDTH" -eq 3840 ] && [ "$VIDEO_HEIGHT" -eq 2160 ]; } || \
   { [ "$VIDEO_WIDTH" -eq 2160 ] && [ "$VIDEO_HEIGHT" -eq 3840 ]; }; then
  IS_4K=true
fi

# Determine rotation and scaling filter for ProRes step
PRORES_VF_FILTER=""
ROTATION_NOTES=""

if [ -n "$VIDEO_ROTATION" ] && [ "$VIDEO_ROTATION" -ne 0 ]; then
  if [ "$VIDEO_ROTATION" -eq 90 ]; then
    PRORES_VF_FILTER="transpose=1" # Rotate 90 degrees clockwise
    ROTATION_NOTES="Detected 90 degree rotation. Applying 'transpose=1'."
  elif [ "$VIDEO_ROTATION" -eq 270 ] || [ "$VIDEO_ROTATION" -eq -90 ]; then
    PRORES_VF_FILTER="transpose=2" # Rotate 90 degrees counter-clockwise
    ROTATION_NOTES="Detected 270 degree rotation. Applying 'transpose=2'."
  elif [ "$VIDEO_ROTATION" -eq 180 ]; then
    PRORES_VF_FILTER="transpose=2,transpose=2" # Rotate 180 degrees
    ROTATION_NOTES="Detected 180 degree rotation. Applying 'transpose=2,transpose=2'."
  else
    ROTATION_NOTES="Unsupported rotation detected ($VIDEO_ROTATION degrees). Manual adjustment may be needed."
  fi
else
  ROTATION_NOTES="No rotation metadata detected or rotation is 0."
fi

# Add scaling if 4K and rotating, or if 4K and need to ensure standard HD output
# For simplicity, if input is 4K and we apply rotation, we will also scale to HD (1920x1080 or 1080x1920)
# This assumes the goal is to standardize to HD after processing.
if $IS_4K; then
    if [ -n "$PRORES_VF_FILTER" ]; then
        # If it was 3840x2160 (landscape 4K) rotated 90 degrees, it becomes 2160x3840 (portrait 4K). Scale to 1080x1920.
        # If it was 2160x3840 (portrait 4K) rotated 90 degrees, it becomes 3840x2160 (landscape 4K). Scale to 1920x1080.
        # The scale filter's dimensions must match the *post-rotation* dimensions if chaining filters.
        # A simple check: if the original width was greater than height, it was landscape.
        # After a 90-degree rotation, it will become portrait. So scale to 1080:1920.
        if [ "$VIDEO_WIDTH" -gt "$VIDEO_HEIGHT" ]; then # Original was landscape
            # After 90/270 rotation, it becomes portrait. After 180, it stays landscape.
            if [ "$VIDEO_ROTATION" -eq 90 ] || [ "$VIDEO_ROTATION" -eq 270 ] || [ "$VIDEO_ROTATION" -eq -90 ]; then
                PRORES_VF_FILTER+=",scale=1080:1920"
            else # 0 or 180 rotation, stays landscape
                PRORES_VF_FILTER+=",scale=1920:1080"
            fi
        else # Original was portrait
            # After 90/270 rotation, it becomes landscape. After 180, it stays portrait.
            if [ "$VIDEO_ROTATION" -eq 90 ] || [ "$VIDEO_ROTATION" -eq 270 ] || [ "$VIDEO_ROTATION" -eq -90 ]; then
                PRORES_VF_FILTER+=",scale=1920:1080"
            else # 0 or 180 rotation, stays portrait
                PRORES_VF_FILTER+=",scale=1080:1920"
            fi
        fi
        ROTATION_NOTES+=" Also scaling to HD dimensions after rotation."
    else
        # If 4K input but no rotation, we might still want to scale it down to HD for consistency.
        # This will scale 3840x2160 to 1920x1080, and 2160x3840 to 1080x1920.
        PRORES_VF_FILTER="scale=$((VIDEO_WIDTH / 2)):$((VIDEO_HEIGHT / 2))"
        ROTATION_NOTES="Detected 4K input without rotation. Scaling to HD."
    fi
else
    ROTATION_NOTES+=". No scaling applied for non-4K input."
fi
echo "$ROTATION_NOTES"
echo ""

# --- Thumbnail Generation (producing individual files) ---
if ! $SKIP_THUMBNAILS; then
  echo "--- Generating Optimized Thumbnails ---"

  # Get video duration using ffprobe for thumbnail timestamps
  DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
  if [ -z "$DURATION" ]; then
    echo "Error: Could not detect video duration for thumbnails. Aborting."
    exit 1
  fi
  echo "Video duration: $DURATION seconds"

  # Define crop parameters for the final thumbnail output (portrait aspect ratio)
  CROP_WIDTH=608
  CROP_HEIGHT=1080
  CROP_X=$(( (1920 - CROP_WIDTH) / 2 )) # Calculate x to center the crop
  CROP_Y=0

  THUMBNAIL_POST_FILTER="crop=${CROP_WIDTH}:${CROP_HEIGHT}:${CROP_X}:${CROP_Y}"
  if $IS_4K; then
    THUMBNAIL_POST_FILTER="scale=1920:1080,${THUMBNAIL_POST_FILTER}" # Scale 4K to HD first, then crop
    echo "Thumbnail source is 4K, scaling to 1920x1080 before cropping."
  else
    echo "Thumbnail source is HD, applying crop directly."
  fi
  echo ""

  for i in $(seq 0 10); do
    PERCENTAGE=$((i * 10))
    TIMESTAMP=$(awk "BEGIN { printf \"%.3f\", $DURATION * $PERCENTAGE / 100 }")
    if (( $(echo "$TIMESTAMP < 0" | bc -l) )); then TIMESTAMP=0; fi # Ensure timestamp is not negative

    THUMBNAIL_OUTPUT_FILE="${INPUT_BASE}-RotateYourPhone-Thumbnails-$(printf "%03d" "$PERCENTAGE").png"

    echo "Generating thumbnail at ${TIMESTAMP}s (${PERCENTAGE}%): '$THUMBNAIL_OUTPUT_FILE'"
    # Generate each thumbnail individually. This avoids the complex filter_complex_script
    # which was causing problems.
    ffmpeg -hwaccel auto -ss "$TIMESTAMP" -i "$INPUT_FILE" \
      -vf "$THUMBNAIL_POST_FILTER" \
      -frames:v 1 -q:v 2 -y "$THUMBNAIL_OUTPUT_FILE"

    if [ $? -ne 0 ]; then
      echo "Warning: Failed to generate thumbnail '$THUMBNAIL_OUTPUT_FILE'. Continuing..."
    fi
  done

  echo "--- Thumbnail generation complete ---"
  echo ""
else
  echo "--- Skipping thumbnail generation as requested ---"
  echo ""
fi

# --- Step 1: Rotate Input Video and Convert to ProRes (Conditional) ---
if ! $SKIP_ROTATION; then
  # This step ensures that the rotation is done without introducing generational quality loss,
  # as ProRes is a high-quality, virtually lossless intermediate codec.
  # It now conditionally resizes 4K input while rotating.
  echo "--- Step 1/2: Rotating '$INPUT_FILE' and converting to ProRes..."
  time ffmpeg -hwaccel auto -i "$INPUT_FILE" \
    -vf "$TRANSPOSE_FILTER" \
    -c:v prores_videotoolbox \
    -profile:v 3 \
    -c:a pcm_s16le \
    -ar 48000 \
    "$INTERMEDIATE_PRORES_FILE"

  # Check if the first ffmpeg command was successful
  if [ $? -ne 0 ]; then
    echo "Error: FFmpeg failed during ProRes conversion. Aborting."
    exit 1
  fi
  echo "--- ProRes intermediate file created: '$INTERMEDIATE_PRORES_FILE' ---"
  echo ""
else
  echo "--- Skipping rotation and ProRes conversion as requested. Using existing intermediate file. ---"
  # Check if the intermediate file actually exists if skipping rotation
  if [ ! -f "$INTERMEDIATE_PRORES_FILE" ]; then
    echo "Error: Cannot skip rotation. Intermediate ProRes file '$INTERMEDIATE_PRORES_FILE' not found."
    echo "Please run the script without --skip-rotation first, or ensure the file exists."
    exit 1
  fi
  echo ""
fi

# --- Step 2: Concatenate Videos and Encode to HEVC (x265) 10-bit ---
# This step takes the prefix video and the rotated ProRes video, concatenates them,
# and then encodes the result into a HEVC 10-bit file that is compatible with QuickTime.
# It now uses the detected source framerate and selected quality parameters.
echo "--- Step 2/2: Concatenating and encoding to HEVC 10-bit..."
time ffmpeg -hwaccel auto -i "$PREFIX_VIDEO" -i "$INTERMEDIATE_PRORES_FILE" \
  -filter_complex "[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[v][a]" \
  -map "[v]" -map "[a]" \
  -c:v hevc_videotoolbox \
  -tag:v hvc1 \
  -pix_fmt yuv420p10le \
  -preset "$FINAL_PRESET" \
  -crf "$FINAL_CRF" \
  -r "$VIDEO_FRAMERATE" \
  -c:a aac \
  -ar 48000 \
  -b:a 192k \
  "$FINAL_HEVC_OUTPUT_FILE"

# Check if the second ffmpeg command was successful
if [ $? -ne 0 ]; then
  echo "Error: FFmpeg failed during HEVC encoding. Aborting."
  exit 1
fi
echo "--- Final HEVC 10-bit file created: '$FINAL_HEVC_OUTPUT_FILE' ---"
echo ""

# --- Cleanup ---
# Remove the intermediate ProRes file to save space, as it's no longer needed.
# This step is only performed if rotation was not skipped (i.e., we just created the intermediate file)
# AND the --keep-intermediate flag was NOT used.
if ! $SKIP_ROTATION && ! $KEEP_INTERMEDIATE; then
  echo "--- Cleaning up intermediate file: '$INTERMEDIATE_PRORES_FILE' ---"
  rm "$INTERMEDIATE_PRORES_FILE"
elif $KEEP_INTERMEDIATE; then
  echo "--- Intermediate ProRes file retained as requested by --keep-intermediate. ---"
else
  echo "--- Intermediate ProRes file retained as rotation was skipped (it wasn't created in this run). ---"
fi


echo "--- Script finished successfully! ---"
echo "Your final video is located at: '$FINAL_HEVC_OUTPUT_FILE'"

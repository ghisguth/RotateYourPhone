#!/bin/bash

# --- Test Script Configuration ---
# For usage information, run: ./run-tests.sh --help
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

SCRIPT_TO_TEST="$(realpath $SCRIPT_DIR/../rotate-your-phone.sh)"

TEST_DATA_DIR="$(realpath $SCRIPT_DIR/test_data)"
EXPECTED_DATA_DIR="$(realpath $SCRIPT_DIR/expected_data)"
OUTPUT_DIR="$(realpath $SCRIPT_DIR)/output"

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Show Usage Information ---
show_usage() {
    cat << EOF
Usage: ./run-tests.sh [OPTIONS]

Options:
  --update-test-data   Updates the expected test data with the newly generated output
  --keep-test-output   Keeps the generated output files after tests complete
  --run-all            Runs all test scenarios
  --sanity-check       Runs only the 'best' scenario for quick verification
  --help               Display this help message and exit

By default, the script runs all hwaccel scenarios and only no-hwaccell-fast.
EOF
}

# --- Signal Handling ---
cleanup() {
    local exit_code=${1:-1}
    local message=${2:-"Test script interrupted by user (Ctrl+C)"}

    echo -e "\n${YELLOW}[INFO   ]${NC} $message. Cleaning up..."
    # Clean up resources if needed
    if [ -d "$OUTPUT_DIR" ] && [ "$KEEP_TEST_OUTPUT" = false ]; then
        rm -rf "$OUTPUT_DIR"
        echo -e "${GREEN}[SUCCESS]${NC} Cleanup complete."
    else
        echo -e "${YELLOW}[INFO   ]${NC} Output directory kept at: $OUTPUT_DIR"
    fi
    exit $exit_code
}

# Set up trap to catch Ctrl+C and other termination signals
trap 'cleanup 130 "Test script interrupted by user (Ctrl+C)"' SIGINT
trap 'cleanup 143 "Test script terminated"' SIGTERM

# --- Helper Functions ---

check_dependencies() {
    command -v ffmpeg &> /dev/null && command -v ffprobe &> /dev/null && command -v compare &> /dev/null
}

log_info() {
    echo -e "${YELLOW}[INFO   ]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR  ]${NC} $1"
    cleanup
}

log_debug() {
    echo -e "${BLUE}[DEBUG  ]${NC} $1"
}

# Function to run FFmpeg command quietly and check exit code
run_ffmpeg_command() {
    local cmd=("$@")
    "${cmd[@]}" > /dev/null 2>&1
    return $?
}

# Function to compare video properties using ffprobe
compare_video_properties() {
    local generated_video="$1"
    local expected_video="$2"
    local test_name="$3"

    log_info "Comparing video properties for $test_name..."

    # Print debug info for both files
    log_debug "ffprobe output for generated video ($generated_video):"
    ffprobe -v error -show_streams "$generated_video" | grep -E 'width|height|codec_name|pix_fmt|duration|bit_rate|avg_frame_rate' | while read line; do log_debug "  $line"; done
    log_debug "ffprobe output for expected video ($expected_video):"
    ffprobe -v error -show_streams "$expected_video" | grep -E 'width|height|codec_name|pix_fmt|duration|bit_rate|avg_frame_rate' | while read line; do log_debug "  $line"; done

    # Define properties to check
    # Note: Duration might vary slightly due to encoding, so it's often better to check if it's "close enough" or skip if not critical.
    # We will check dimensions, codec, and pixel format for now.
    PROPERTIES=("width" "height" "codec_name" "pix_fmt")

    for prop in "${PROPERTIES[@]}"; do
        GENERATED_VALUE=$(ffprobe -v error -select_streams v:0 -show_entries stream="$prop" -of default=noprint_wrappers=1:nokey=1 "$generated_video")
        EXPECTED_VALUE=$(ffprobe -v error -select_streams v:0 -show_entries stream="$prop" -of default=noprint_wrappers=1:nokey=1 "$expected_video")

        if [ "$GENERATED_VALUE" != "$EXPECTED_VALUE" ]; then
            echo -e "${RED}  FAIL: $prop mismatch for $test_name."
            echo -e "    Generated: $GENERATED_VALUE, Expected: $EXPECTED_VALUE${NC}"
            return 1
        fi
    done

    # Check duration (exact match, in seconds with 3 decimals)
    GENERATED_DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$generated_video" | awk '{printf "%.3f", $1}')
    EXPECTED_DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$expected_video" | awk '{printf "%.3f", $1}')
    if [ "$GENERATED_DURATION" != "$EXPECTED_DURATION" ]; then
        echo -e "${RED}  FAIL: Duration mismatch for $test_name."
        echo -e "    Generated: $GENERATED_DURATION, Expected: $EXPECTED_DURATION${NC}"
        return 1
    fi

    # Optional: Compare frame rate. Be careful with fractional frame rates and floating point comparisons.
    GENERATED_FPS_NUM=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$generated_video" | cut -d'/' -f1)
    GENERATED_FPS_DEN=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$generated_video" | cut -d'/' -f2)
    EXPECTED_FPS_NUM=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$expected_video" | cut -d'/' -f1)
    EXPECTED_FPS_DEN=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$expected_video" | cut -d'/' -f2)

    # Simple check for exact match of numerator/denominator for frame rate
    if [ "$GENERATED_FPS_NUM" != "$EXPECTED_FPS_NUM" ] || [ "$GENERATED_FPS_DEN" != "$EXPECTED_FPS_DEN" ]; then
        echo -e "${RED}  FAIL: Frame rate mismatch for $test_name."
        echo -e "    Generated: $GENERATED_FPS_NUM/$GENERATED_FPS_DEN, Expected: $EXPECTED_FPS_NUM/$EXPECTED_FPS_DEN${NC}"
        return 1
    fi

    # Check bitrate (within tolerance)
    GENERATED_BITRATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$generated_video")
    EXPECTED_BITRATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$expected_video")
    if [ -z "$GENERATED_BITRATE" ] || [ -z "$EXPECTED_BITRATE" ]; then
        echo -e "${YELLOW}  WARN: Bitrate not found for $test_name. Skipping bitrate check.${NC}"
    else
        # Calculate 20% tolerance
        TOLERANCE=$(awk "BEGIN {printf \"%.0f\", $EXPECTED_BITRATE * 0.2}")
        LOWER_BOUND=$(awk "BEGIN {printf \"%.0f\", $EXPECTED_BITRATE - $TOLERANCE}")
        UPPER_BOUND=$(awk "BEGIN {printf \"%.0f\", $EXPECTED_BITRATE + $TOLERANCE}")
        if [ "$GENERATED_BITRATE" -lt "$LOWER_BOUND" ] || [ "$GENERATED_BITRATE" -gt "$UPPER_BOUND" ]; then
            echo -e "${RED}  FAIL: Bitrate mismatch for $test_name."
            echo -e "    Generated: $GENERATED_BITRATE, Expected: $EXPECTED_BITRATE (Allowed: $LOWER_BOUND - $UPPER_BOUND)${NC}"
            return 1
        else
            log_success "  Bitrate matches for $test_name (Generated: $GENERATED_BITRATE, Expected: $EXPECTED_BITRATE, Allowed: $LOWER_BOUND - $UPPER_BOUND)."
        fi
    fi

    log_success "  Video properties match for $test_name."
    return 0
}

# Function to compare image files (thumbnails)
compare_images() {
    local generated_image="$1"
    local expected_image="$2"
    local test_name="$3"

    log_info "Comparing image: $test_name..."

    # Print debug info for both images using ImageMagick identify
    log_debug "ImageMagick properties for generated image ($generated_image):"
    identify -verbose "$generated_image" | grep -E 'Format:|Geometry:|Colorspace:|Depth:|Filesize:|Resolution:|Type:|Channel depth:' | while read line; do log_debug "  $line"; done
    log_debug "ImageMagick properties for expected image ($expected_image):"
    identify -verbose "$expected_image" | grep -E 'Format:|Geometry:|Colorspace:|Depth:|Filesize:|Resolution:|Type:|Channel depth:' | while read line; do log_debug "  $line"; done

    # Use ImageMagick's 'compare' for a more robust image comparison.
    # This allows for a tolerance in pixel differences, which is more suitable for
    # comparing images generated by video processing where minor variations might occur.
    # The comparison will be based on the RMSE (Root Mean Squared Error) metric,
    # which quantifies the difference between the two images.

    # Use 'compare' to get the RMSE (normalized root mean squared error)
    # The output of compare is like "123.45 (0.0018). We need the normalized value in parentheses.
    # We use command substitution `var=$(...)` to avoid the subshell issue with `read` and `sed` to remove parentheses.
    local rmse=$(compare -metric RMSE "$generated_image" "$expected_image" null: 2>&1 | awk '{print $2}' | sed 's/[()]//g')
    # Set a tolerance level for the RMSE value. This value might need adjustment
    # based on the specific requirements of the test images and processing.
    local tolerance=0.01  # Example tolerance: Allow up to 1% RMSE

    if (( $(echo "$rmse <= $tolerance" | bc -l) )); then
        log_success "  Image matches for $test_name (RMSE: $rmse <= $tolerance)."
        return 0  # Images are considered matching within tolerance
    else
        echo -e "${RED}  FAIL: Image mismatch for $test_name (RMSE: $rmse > $tolerance)."
        echo -e "    Generated: $generated_image, Expected: $expected_image, RMSE: $rmse, Tolerance: $tolerance${NC}"
        return 1  # Images differ beyond tolerance
    fi
}

# --- Setup Test Environment ---
setup_test_env() {
    log_info "Setting up test environment..."
    rm -rf "$OUTPUT_DIR" # Clean previous outputs
    log_info "Creating $OUTPUT_DIR..."
    mkdir -p "$OUTPUT_DIR" || log_error "Failed to create output directory."
    log_info "Copying test data to $OUTPUT_DIR..."
    cp "$TEST_DATA_DIR"/* "$OUTPUT_DIR"/ || log_error "Failed to copy test data."
    log_success "Test environment set up."
    echo ""
}

# --- Run Test Cases ---
run_test_case() {
    local input_file="$1"
    local expected_rotated_video="$2"
    local expected_thumbnail_base_name="$3"
    local test_name="$4"
    local quality_level="${5:-medium}"
    local skip_thumbnails="${6:-false}"
    local additional_arguments="${7:-}"
    local scenario_source="$8"
    local scenario_name="$9"
    local scenario_output_dir="${10}"

    log_info "\t#scenario: $scenario_name"
    log_info "\t#source: $scenario_source"
    log_info "\t#quality: $quality_level"
    log_info "\t#additional-arguments: $additional_arguments" 

    # Append --skip-thumbnails if skip_thumbnails is true
    if [ "$skip_thumbnails" = "true" ]; then
        additional_arguments="${additional_arguments} --skip-thumbnails"
    fi

    log_info "--- Running Test Case: $test_name ---"

    # Ensure scenario output directory exists
    mkdir -p "$scenario_output_dir"

    # Reference input from main output dir, output to scenario subdir
    local current_input_path="${OUTPUT_DIR}/${input_file}"
    local generated_rotated_video="${scenario_output_dir}/${input_file%.*}-RotateYourPhone-${quality_level}.mp4"
    local generated_thumbnail_base_name="${scenario_output_dir}/${input_file%.*}-Thumb-"

    # Execute the script under test
    log_info "Executing '$SCRIPT_TO_TEST' with '$current_input_path' in '$scenario_output_dir'..."
    if [ -n "$additional_arguments" ]; then
       "$SCRIPT_TO_TEST" "$current_input_path" --quality $quality_level $additional_arguments -o "$scenario_output_dir"
    else
       "$SCRIPT_TO_TEST" "$current_input_path" --quality $quality_level -o "$scenario_output_dir"
    fi

    local script_exit_code=$?
    if [ $script_exit_code -ne 0 ]; then
        log_error "Script '$SCRIPT_TO_TEST' failed for $test_name with exit code $script_exit_code."
    fi
    log_success "Script execution completed for $test_name."

    # Verify generated video file existence
    if [ ! -f "$generated_rotated_video" ]; then
        log_error "Generated video '$generated_rotated_video' not found for $test_name."
    fi
    log_success "All expected video output files exist for $test_name."

    # Update expected video if requested
    if $UPDATE_TEST_DATA; then
        echo "Updating expected video data for $test_name..."
        if [ "$scenario_name" == "$scenario_source" ]; then
            log_info "Updating expected video: $expected_rotated_video <- $generated_rotated_video"
            dirname="$(dirname "$expected_rotated_video")"
            mkdir -p "$dirname"  # Ensure the directory exists
            cp "$generated_rotated_video" "$expected_rotated_video"
        fi
    fi

    # Verify generated video file existence
    if [ ! -f "$expected_rotated_video" ]; then
        log_error "Expected video '$expected_rotated_video' not found for $test_name."
    fi

    # Verify video properties
    compare_video_properties "$generated_rotated_video" "$expected_rotated_video" "${test_name} Video" || log_error "Video property mismatch for $test_name."

    if [ "$skip_thumbnails" != "true" ]; then
      for name in 25p 50p; do
        for idx in 0 1 2; do
          log_info "Checking thumbnail for $name at index $idx..."

          local generated_thumbnail="${generated_thumbnail_base_name}${name}-${idx}.png"
          local expected_thumbnail="${expected_thumbnail_base_name}${name}-${idx}.png"

          # Verify generated image file existence
          if [ ! -f "$generated_thumbnail" ]; then
              log_error "Generated thumbnail '$generated_thumbnail' not found for $test_name."
          fi

          # Update expected thumbnail if requested
          if $UPDATE_TEST_DATA; then
              log_info "Updating expected thumbnail: $expected_thumbnail <- $generated_thumbnail"
              cp "$generated_thumbnail" "$expected_thumbnail"
          fi
          # Verify expected image file existence
          if [ ! -f "$expected_thumbnail" ]; then
              log_error "Expected thumbnail '$expected_thumbnail' not found for $test_name."
          fi

          # Verify thumbnail
          compare_images "$generated_thumbnail" "$expected_thumbnail" "${test_name} Thumbnail" || log_error "Thumbnail mismatch for $test_name."
        done
      done
    else
      log_info "Skipping thumbnail checks for $test_name as requested."
    fi

    log_success "--- Test Case Passed: $test_name ---"
    echo ""
}

# --- Argument Parsing for Test Script ---
UPDATE_TEST_DATA=false
KEEP_TEST_OUTPUT=false
RUN_ALL_SCENARIOS=false
SANITY_CHECK=false

# Parse arguments using while loop with case statement
while (( "$#" )); do
  case "$1" in
    --update-test-data)
      UPDATE_TEST_DATA=true
      shift
      ;;
    --keep-test-output)
      KEEP_TEST_OUTPUT=true
      shift
      ;;
    --run-all)
      RUN_ALL_SCENARIOS=true
      shift
      ;;
    --sanity-check)
      SANITY_CHECK=true
      shift
      ;;
    --help)
      show_usage
      exit 0
      ;;
    -*|--*=) # Handle invalid options
      echo -e "${RED}Error: Unsupported option $1${NC}" >&2
      show_usage
      cleanup 1 "Invalid argument"
      ;;
    *) # Handle positional arguments if needed in the future
      shift
      ;;
  esac
done

# --- Main Test Execution ---
main() {
    setup_test_env

    # Check dependencies
    if ! check_dependencies; then
        log_error "Error: FFmpeg, ffprobe, and/or ImageMagick's 'compare' are required but not found. Please install them."
    fi

    # Define all possible test scenarios: scenario_name|quality|skip_thumbnails|additional_arguments|scenario_source|test_files
    ALL_TEST_SCENARIOS=(
      # name|quality|skip_thumbnails|additional_args|scenario_source|test_files
      #"best|best|false||best|"
      "fast|fast|true||fast|"
      "medium|medium|true||medium|"
      "high|high|true||high|"
      "no-hwaccell-best|best|true|--disable-hwaccel|best|testHD1 testUHD1"
      "no-hwaccell-fast|fast|false|--disable-hwaccel|fast|testHD1 testUHD1"
      "no-hwaccell-medium|medium|true|--disable-hwaccel|medium|testHD1 testUHD1"
      "no-hwaccell-high|high|true|--disable-hwaccel|high|testHD1 testUHD1"
      "skip-banner|best|false|--skip-banner|skip-banner|"
    )

    # Select which test scenarios to run based on command line flags
    if $RUN_ALL_SCENARIOS; then
        log_info "Running all test scenarios"
        TEST_SCENARIOS=("${ALL_TEST_SCENARIOS[@]}")
    elif $SANITY_CHECK; then
        log_info "Running sanity check (only 'best' scenario)"
        # Filter to only include the 'best' scenario
        TEST_SCENARIOS=()
        for scenario in "${ALL_TEST_SCENARIOS[@]}"; do
            if [[ $scenario == best* ]]; then
                TEST_SCENARIOS+=("${scenario}testHD1 testHD3 testUHD1")
            fi
            if [[ $scenario == skip-banner* ]]; then
                TEST_SCENARIOS+=("${scenario}")
            fi
        done
    else
        log_info "Running all hwaccel scenarios and only no-hwaccell-fast scenario (use --run-all for all scenarios)"
        # Filter out all no-hwaccell scenarios except for no-hwaccell-fast
        TEST_SCENARIOS=()
        for scenario in "${ALL_TEST_SCENARIOS[@]}"; do
            if [[ $scenario != no-hwaccell-* ]] || [[ $scenario == *no-hwaccell-fast* ]]; then
                TEST_SCENARIOS+=("$scenario")
            fi
        done
    fi

    # Default list of test files if not specified in the scenario
    DEFAULT_TEST_FILES="testHD1 testHD2 testHD3 testUHD1 testUHD2 testUHD3"

    for scenario in "${TEST_SCENARIOS[@]}"; do
      IFS='|' read -r scenario_name quality_level skip_thumbnails additional_arguments scenario_source test_files <<< "$scenario"

      # Use default test files if none specified in the scenario
      if [ -z "$test_files" ]; then
        test_files="$DEFAULT_TEST_FILES"
      fi

      scenario_output_dir="$OUTPUT_DIR/$scenario_name"

      for base in $test_files; do
        if [[ $base == testHD* ]]; then
          test_label="HD Video Processing Test ($base)"
        else
          test_label="UHD Video Processing Test ($base)"
        fi
        # Only pass additional_arguments if non-empty
        if [ -n "$additional_arguments" ]; then
          run_test_case \
              "$base.mp4" \
              "${EXPECTED_DATA_DIR}/$scenario_source/${base}-rotated.mp4" \
              "${EXPECTED_DATA_DIR}/thumbnails/${base}-Thumb-" \
              "$test_label [$scenario_name]" \
              "$quality_level" \
              "$skip_thumbnails" \
              "$additional_arguments" \
              "$scenario_source" \
              "$scenario_name" \
              "$scenario_output_dir"
        else
          run_test_case \
              "$base.mp4" \
              "${EXPECTED_DATA_DIR}/$scenario_source/${base}-rotated.mp4" \
              "${EXPECTED_DATA_DIR}/thumbnails/${base}-Thumb-" \
              "$test_label [$scenario_name]" \
              "$quality_level" \
              "$skip_thumbnails" \
              "" \
              "$scenario_source" \
              "$scenario_name" \
              "$scenario_output_dir"
        fi
      done
    done

    log_info "All tests completed successfully!"
    if ! $KEEP_TEST_OUTPUT; then
        echo "--- Cleaning up output directory ---"
        rm -rf "$OUTPUT_DIR"
        log_success "Cleanup complete."
    else
        echo "You can check the generated files in the '$OUTPUT_DIR' directory."
    fi
}

# Execute main function
main
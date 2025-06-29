# RotateYourPhone

A robust FFmpeg-based video processing script for macOS that rotates, resizes, and prepends a custom intro to your videos, then encodes the result to high-quality HEVC (x265) 10-bit format compatible with QuickTime. The script is designed for creators who want to quickly convert landscape or 4K videos to vertical/portrait format for social media, with a branded intro and optimized output.

## Why Use This Script?

- **Automate tedious video rotation and reformatting tasks** for social media or mobile viewing.
- **Standardize your videos** with a consistent intro ("RotateYourPhoneHD.mp4") and output format.
- **Preserve quality** by using ProRes as an intermediate step before final HEVC encoding.
- **Batch process videos** with options to skip steps, control quality, and generate thumbnails.
- **No need to remember complex FFmpeg commands**—just run a single script.

## Features

- Rotates and resizes videos (e.g., 4K landscape to 1080x1920 portrait)
- Prepends a custom intro video (must be placed in `media/RotateYourPhoneHD.mp4`)
- Encodes final output to HEVC (x265) 10-bit, QuickTime compatible
- Generates optimized thumbnails at multiple timestamps
- Supports quality presets and optional intermediate file retention
- Smart handling of video rotation metadata and scaling

## Requirements

- macOS (tested on Apple Silicon M2 and newer)
- [FFmpeg](https://ffmpeg.org/) with HEVC and ProRes support (install via Homebrew: `brew install ffmpeg`)
- Bash shell (default on macOS)
- Place your intro video as `media/RotateYourPhoneHD.mp4` relative to the script

> **Note:** This script is designed and tested for Apple Silicon (M2 and newer) Macs. It may require modifications to work on Intel Macs or other platforms, especially regarding hardware-accelerated encoding (`hevc_videotoolbox`).

## Installation

1. Clone this repository:

   ```zsh
   git clone https://github.com/ghisguth/RotateYourPhone.git
   cd RotateYourPhone
   ```

2. Make the script executable:

   ```zsh
   chmod +x rotate-your-phone.sh
   ```

3. Ensure your intro video is in `media/RotateYourPhoneHD.mp4` (replace with your own if desired).

## Usage

Basic usage:

```zsh
./rotate-your-phone.sh "MyVideo.mp4"
```

### Options

- `--skip-thumbnails` &nbsp;&nbsp;&nbsp;&nbsp;Skip thumbnail generation
- `--skip-rotation` &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Skip rotation and ProRes conversion (use existing intermediate file)
- `--quality <level>` &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Set quality (`medium` [default], `high`, or `best`)
- `--keep-intermediate` &nbsp;&nbsp;Keep the intermediate ProRes file after processing

### Example Commands

- Process a video with default settings:

  ```zsh
  ./rotate-your-phone.sh "FREYA_2024.mp4"
  ```

- High quality, skip thumbnails:

  ```zsh
  ./rotate-your-phone.sh "FREYA_2024.mp4" --quality high --skip-thumbnails
  ```

- Keep the intermediate ProRes file:

  ```zsh
  ./rotate-your-phone.sh "FREYA_2024.mp4" --keep-intermediate
  ```

## Output

- Final video: `<input>-RotateYourPhone-<crf>-<preset>.mp4`
- Thumbnails: `<input>-RotateYourPhone-Thumbnails-XXX.png` (at 0%, 10%, ..., 100%)

## Customizing the Intro

Replace `media/RotateYourPhoneHD.mp4` with your own intro video. The script will always look for this file relative to its own location.

## License

MIT License. See [LICENSE](LICENSE) for details.

---

*Created by [Alexander Fedora](https://github.com/ghisguth). Contributions welcome!*
# NotZencoder

An FFmpeg-based video encoding implementation designed for browsers and mobile devices to transcode user-uploaded videos.

## Overview

NotZencoder provides video transcoding functionality using FFmpeg, outputting H.264/AAC encoded MP4 files optimized for web and mobile playback. It supports multiple resolution profiles, HLS segmentation, and thumbnail generation.

## Features

- **Multi-resolution encoding** - Automatically selects appropriate output profiles based on source video quality
- **HLS streaming** - Optional HTTP Live Streaming segment generation
- **Thumbnail generation** - Creates video thumbnails and WebVTT sprite sheets for preview scrubbing
- **Video analysis** - Extracts detailed metadata from source files using FFprobe

## Encoding Profiles

### Widescreen (16:9)
| Profile | Resolution | Video Bitrate | H.264 Profile |
|---------|------------|---------------|---------------|
| 360p | 640×360 | 600 kbps | Baseline |
| 540p | 960×540 | 1200 kbps | Baseline |
| 720p | 1280×720 | 2500 kbps | Main |
| 720p_hi | 1280×720 | 4500 kbps | Main |
| 1080p | 1920×1080 | 6000 kbps | High |

### Standard (4:3)
| Profile | Resolution | Video Bitrate | H.264 Profile |
|---------|------------|---------------|---------------|
| 240p | 320×240 | 340 kbps | Baseline |
| 480p | 640×480 | 600 kbps | Baseline |
| 576p | 720×576 | 900 kbps | Baseline |

## Dependencies

- **FFmpeg** - Video encoding and processing
- **FFprobe** - Media file analysis
- **qt-faststart** - MP4 atom repositioning for progressive playback
- **ImageMagick** - Thumbnail sprite sheet generation
- **Terrapin** - Ruby command-line execution wrapper

## Usage

### Analyze a video file
```ruby
metadata = NotZencoder.identify('/path/to/input.mp4')
# Returns hash with: video_codec, width, height, duration_in_ms, frame_rate, etc.
```

### Transcode a video
```ruby
result = NotZencoder.transcode(
  '/path/to/input.mp4',                 # input file
  '/path/to/output',                    # output directory
  'video_name',                         # output name (without extension)
  'https://cdn.example.com/videos',     # URL prefix
  NotZencoder::WIDESCREEN_720,          # encoding profile
  3600,                                 # time limit in seconds
  true                                  # create HLS segments
)
```

### Generate thumbnails
```ruby
files = NotZencoder.generate_thumbnails(
  '/path/to/input.mp4',
  '/path/to/thumbnails',
  150  # thumbnail height
)
# Returns array of generated thumbnail files including sprite.jpg and thumbnails.vtt
```

### Get appropriate profiles for a video
```ruby
video = Video.find(id)
profiles = NotZencoder.sane_profiles_for_video(video)
# Returns array of profiles matching source quality
```

## Output

Transcoded videos include:
- H.264 video codec (libx264)
- AAC audio codec (libvo_aacenc)
- MP4 container with fast-start for progressive download
- Optional HLS segments (.ts files) with M3U8 playlist

## Video Filters Applied

1. **Deinterlacing** - Automatic detection and deinterlacing (yadif)
2. **Denoising** - Light noise reduction (hqdn3d)
3. **Scaling** - Maintains aspect ratio with square pixels

require 'ostruct'
require 'fileutils'
require 'terrapin'

class NotZencoder
  KEYFRAME_INTERVAL = '90'.freeze # seconds
  SEGMENT_DURATION = '10'.freeze  # seconds
  SCENE_CHANGE_THRESHOLD = '0'.freeze
  VIDEO_CODEC = 'libx264'.freeze
  AUDIO_CODEC = 'libvo_aacenc'.freeze # not as good as libfdk or libfaac but built into ffmpeg

  WIDESCREEN_360 = OpenStruct.new(
        short_label: '360p',
        label: 'widescreen_360',
        h264_profile: 'baseline',
        video_bitrate: 600,
        audio_bitrate: '64k',
        deinterlace: 'detect',
        denoise: true,
        height: 360,
        width: 640
      )

  WIDESCREEN_540 = OpenStruct.new(
        short_label: '540p',
        label: 'widescreen_540',
        h264_profile: 'baseline',
        video_bitrate: 1200,
        audio_bitrate: '64k',
        deinterlace: 'detect',
        denoise: true,
        height: 540,
        width: 960
      )

  WIDESREEN_720 =  OpenStruct.new(
      short_label: '720p',
      label: 'widescreen_720',
      h264_profile: 'main',
      video_bitrate: 2500,
      audio_bitrate: '64k',
      deinterlace: 'detect',
      denoise: true,
      height: 720,
      width: 1280
    )

  WIDESCREEN_720_HI =  OpenStruct.new(
          short_label: '720p_hi',
          label: 'widescreen_720_hi',
          h264_profile: 'main',
          video_bitrate: 4500,
          audio_bitrate: '64k',
          deinterlace: 'detect',
          denoise: true,
          height: 720,
          width: 1280
        )

  WIDESCREEN_1080 =  OpenStruct.new(
        short_label: '1080p',
        label: 'widescreen_1080',
        h264_profile: 'high',
        video_bitrate: 6000,
        audio_bitrate: '128k',
        deinterlace: 'detect',
        denoise: true,
        height: 1080,
        width: 1920
      )

  WIDESCREEN_1080_HI = OpenStruct.new(
        short_label: '1080p_hi',
        label: 'widescreen_1080',
        h264_profile: 'high',
        video_bitrate: 9000,
        audio_bitrate: '128k',
        deinterlace: 'detect',
        denoise: true,
        height: 1080,
        width: 1920
      )

  STANDARD_576 = OpenStruct.new(
        short_label: '576p',
        label: 'standard_576',
        h264_profile: 'baseline',
        video_bitrate: 900,
        audio_bitrate: '64k',
        deinterlace: 'detect',
        denoise: true,
        height: 576,
        width: 720,

        minimum_height: 530
      )

  STANDARD_480 = OpenStruct.new(
        short_label: '480p',
        label: 'standard_480',
        h264_profile: 'baseline',
        video_bitrate: 600,
        audio_bitrate: '64k',
        deinterlace: 'detect',
        denoise: true,
        height: 480,
        width: 640
      )

  STANDARD_240 = OpenStruct.new(
        short_label: '240p',
        label: 'standard_240',
        h264_profile: 'baseline',
        video_bitrate: 340,
        audio_bitrate: '64k',
        deinterlace: 'detect',
        denoise: true,
        height: 240,
        width: 320
      )

  STANDARD_120 = OpenStruct.new(
        short_label: '120p',
        label: 'standard_120',
        h264_profile: 'baseline',
        video_bitrate: 150,
        audio_bitrate: '64k',
        deinterlace: 'detect',
        denoise: true,
        height: 120,
        width: 160
      )

  def self.widescreen_profiles
    [WIDESCREEN_360, WIDESCREEN_540, WIDESREEN_720, WIDESCREEN_720_HI, WIDESCREEN_1080]
  end

  def self.standard_profiles
    [STANDARD_240, STANDARD_480, STANDARD_576]
  end

  def self.fallback_profile
    STANDARD_120
  end

  # width is used as height is variable depending on aspect ratio, and not a true indicator of source frame size

  # -20px to catch almost good enough resolutions
  # allow for 25% bitrate variance

  # does this take into account non square pixels of SD ?
  # http://en.wikipedia.org/wiki/Standard-definition_television

  def self.sane_profiles_for_video(video)
    profiles = []

    # Anamorphic DVDs are not considered a widescreen source

    if video.widescreen?

      NotZencoder.widescreen_profiles.each do |profile|
        # allow for minor discrepencies, if bitrate is almost good enough then dont fall back to a lower profile that could have half the bitrate
        unless video.input.width > (profile.width - 20) && video.input.video_bitrate_in_kbps > (profile.video_bitrate * 0.8)
          next
        end

        # STANDARD_480 & STANDARD_576 have the same width, only encode to STANDARD_576 if PAL source (eg. Full Frame PAL, or Anamorphic PAL)
        profiles << profile unless profile.minimum_height && video.input.height < profile.minimum_height
      end

     else

       NotZencoder.standard_profiles.each do |profile|
         # allow for minor discrepencies, if bitrate is almost good enough then dont fall back to a lower profile that could have half the bitrate

         unless video.input.width > (profile.width - 20) && video.input.video_bitrate_in_kbps > (profile.video_bitrate * 0.8)
           next
         end

         profiles << profile unless profile.minimum_height && video.input.height < profile.minimum_height
       end

    end

     profiles << NotZencoder.fallback_profile if profiles.empty?

     profiles
  end

  def self.append_line_to_m3u8_index(line, index_file)
    File.open index_file, 'a' do |f|
      f.puts line
    end
  end

  def self.terminate_line_with_comma(string)
    string += ',' unless string.empty?
    string
  end

  def self.extract_value_for_key(output, key)
     output.scan(%r{^#{Regexp.escape(key)}=([0-9A-Za-z/.,:\t ]+)}).flatten.first
  end

  def self.identify(input_file)
      return nil unless File.exist?(input_file)

      file_size_in_bytes = File.size(input_file)

      # container format / duration

      line = Terrapin::CommandLine.new('ffprobe', ' -show_format  :input_file',
                                                    input_file:, swallow_stderr: true, expected_outcodes: [0, 1])

      begin
        out = line.run
      rescue Terrapin::ExitStatusError
        raise 'error'
      end

      format = extract_value_for_key(out, 'format_name') # consider TAG:major_brand=
      duration_in_s = extract_value_for_key(out, 'duration').to_i
      duration_in_ms = duration_in_s * 1000

      # video codec

      line = Terrapin::CommandLine.new('ffprobe', ' -i :input_file -show_streams -select_streams v',
                                                    input_file:, swallow_stderr: true, expected_outcodes: [0, 1])

       begin
         out = line.run
       rescue Terrapin::ExitStatusError
         raise 'error'
       end

      video_codec = extract_value_for_key(out, 'codec_name')
      video_bitrate = extract_value_for_key(out, 'bit_rate')
      video_bitrate_in_kbps = (video_bitrate.to_f / 1024.0).floor
      frame_rate_rational = extract_value_for_key(out, 'r_frame_rate')
      frame_rate_decimal = (frame_rate_rational.split('/')[0].to_f / frame_rate_rational.split('/')[1]).round(2)
      width = extract_value_for_key(out, 'width').to_i
      height = extract_value_for_key(out, 'height').to_i
      display_aspect_rational = extract_value_for_key(out, 'display_aspect_ratio')

      display_aspect_decimal = if ['0:1', '1:0', 'N/A'].include?(display_aspect_rational)
                                 (width.to_f / height).round(2)
                               else
                                 (display_aspect_rational.split(':')[0].to_f / display_aspect_rational.split(':')[1]).round(2)
                               end

      profile = extract_value_for_key(out, 'profile')
      nb_frames = extract_value_for_key(out, 'nb_frames')

      if video_bitrate == 'N/A'
        # bitrate estimate
        video_bitrate_in_kbps = ((file_size_in_bytes / 1024) / duration_in_s) * 8 # KiloBytes/Second * 8 = KiloBits/Second
      end

      # audio codec

      line = Terrapin::CommandLine.new('ffprobe', ' -i :input_file -show_streams -select_streams a',
                                                      input_file:, swallow_stderr: true, expected_outcodes: [0, 1])

      begin
        out = line.run
      rescue Terrapin::ExitStatusError
        raise 'error'
      end

      audio_codec = out.scan(/^codec_name=([0-9A-Za-z:\t .]+)/).flatten.first
      audio_sample_rate = out.scan(/^sample_rate=([0-9A-Za-z:\t .]+)/).flatten.first.to_i
      channels = out.scan(/^channels=([0-9A-Za-z:\t .]+)/).flatten.first.to_i
      audio_bitrate_in_kbps = out.scan(/^bit_rate=([0-9A-Za-z:\t .]+)/).flatten.first.to_i / 1024

      if RUBY_PLATFORM.include? 'linux'

        line = Terrapin::CommandLine.new('md5sum', ' -b :input_file',
                                                     input_file:, swallow_stderr: true)

        md5_checksum = line.run.split[0].strip

      else # OSX

        line = Terrapin::CommandLine.new('md5', ' -q :input_file',
                                                     input_file:, swallow_stderr: true)

        md5_checksum = line.run.strip

      end

      retval = OpenStruct.new(video_codec:,
                              profile:, # only applicable to h264
                              width:,
                              height:,
                              display_aspect_rational:,
                              display_aspect_decimal:,
                              video_bitrate_in_kbps:,
                              audio_codec:,
                              audio_sample_rate:,
                              channels:,
                              audio_bitrate_in_kbps:,
                              md5_checksum:,
                              frame_rate: frame_rate_decimal,
                              format:,
                              file_size_in_bytes:,
                              duration_in_ms:,
                              nb_frames:)

      retval.marshal_dump
  end

  def self.segment(input_file, output_dir, ve_name)
              destination_dir = "#{output_dir}/#{ve_name}"

              FileUtils.mkdir_p(destination_dir, 0o700)

              # need to chdir here to avoid using absolute paths in playlist.m3u8
              Dir.chdir(destination_dir)

              line = Terrapin::CommandLine.new('ffmpeg', ' -i :input_file -c copy -map 0 -vbsf h264_mp4toannexb -f segment -segment_time :segment_time  -segment_list :segment_list :segment_out',
                                                            input_file:,
                                                            segment_list: 'playlist.m3u8',
                                                            segment_out: 'segment%03d.ts',
                                                            segment_time: SEGMENT_DURATION)

               line.run

               Dir.chdir('..')
  end

  def self.ssms_to_hhmmssms(seconds)
    second_fractions = seconds.modulo(1).round(1)
    seconds = seconds.to_i

    minutes = seconds / 60
    seconds = seconds % 60

    hours = minutes / 60
    minutes = minutes % 60

    hours = format '%02d', hours
    minutes = format '%02d', minutes
    seconds = format '%02d', seconds

    second_fractions = second_fractions.to_s.split('.')[1][0]

    "#{hours}:#{minutes}:#{seconds}.#{second_fractions}00"
  end

  GENERATE_THUMBNAIL_COUNT = 30
  WEBVTT_FILENAME = 'thumbnails.vtt'.freeze
  FRAME_W = 150
  FRAME_H = 100

  def self.generate_thumbnails(input_file, output_dir, thumb_height)
    line = Terrapin::CommandLine.new('ffprobe', ' -show_format  :input_file',
                                                  input_file:, swallow_stderr: true)

    begin
      out = line.run
    rescue Terrapin::ExitStatusError
      raise 'error'
    end

    duration = extract_value_for_key(out, 'duration').to_i
    frame_estimate = duration * 25
    output_file = "#{output_dir}/%03d.jpg"
    frame_skip = (frame_estimate / GENERATE_THUMBNAIL_COUNT).ceil.to_s
    duration_skip = duration.to_f / GENERATE_THUMBNAIL_COUNT

    line = Terrapin::CommandLine.new('ffmpeg', " -i  :input_file -vsync 0 -qscale:v 2 -vf \"select=\'not(mod(n,:frame_skip))\', scale=:thumb_height:-1\" :output_file",
                                                  input_file:,
                                                  output_file:,
                                                  frame_skip:,
                                                  thumb_height: thumb_height.to_s,
                                                  swallow_stderr: true)

    begin
      line.run
    rescue Terrapin::ExitStatusError
      raise 'error'
    end

    # VTT thumbs
    thumbs = Dir.glob("#{output_dir}/*.jpg")
    thumbs.each do |thumb|
        system("convert -background black -resize 150x100 -gravity center -extent 150x100 #{thumb} #{thumb}.sprite")
    end
    system("convert #{output_dir}/*.sprite -append #{output_dir}/sprite.jpg")

    start_position = 0
    pos_x = 0
    pos_y = 0
    pos_w = FRAME_W
    pos_h = FRAME_H

    File.open WEBVTT_FILENAME, 'w' do |f|
      f.puts 'WEBVTT'
      f.puts ''
    end

    (0..GENERATE_THUMBNAIL_COUNT).each do |_frame|
      end_position = (start_position + duration_skip)
      end_positon_without_overlap = (end_position.to_f - 0.1).round(1)

      File.open WEBVTT_FILENAME, 'a' do |f|
        f.puts "#{ssms_to_hhmmssms(start_position)} --> #{ssms_to_hhmmssms(end_positon_without_overlap)}"
        f.puts "sprite.jpg#xywh=#{pos_x},#{pos_y},#{pos_w},#{pos_h}"
        f.puts ''
      end

      start_position = end_position
      pos_y += FRAME_H
    end

    files_to_upload = Dir.glob("#{output_dir}/*.jpg")
    files_to_upload << Dir.glob("#{output_dir}/*.vtt").first

    files_to_upload
  end

  def self.transcode(input_file, output_dir, ve_name, url_prefix, profile, timelimit, create_hls_segments)
       output_file_name = "#{ve_name}.mp4"

       video_filter = ''

       # filter sequence: deinterlace -> denoise ->  scaling is usually the best.

       if profile.deinterlace == 'detect'
         video_filter = terminate_line_with_comma(video_filter)
         video_filter += 'yadif=0:-1:0'
       end

       if profile.denoise
         video_filter = terminate_line_with_comma(video_filter)
         video_filter += 'hqdn3d=1.5:1.5:6:6'
       end

   #   This assumes we want to keep for example  1080p inputs at 1080 lines, which is not the case
   #   as it does not take into account aspect ratio ( eg cinemascope is 1920x816 )
   #   therefore, always use a constant width
   #
   #   #constant height
   #   if profile.height && !profile.width
   #     video_filter = terminate_line_with_comma(video_filter)
   #     #ensure divisible by 2
   #     video_filter = video_filter+"scale=trunc(oh*a/2)*2:#{profile.height}"
   #   end
   #
   #   #constant width
   #   if !profile.height && profile.width
   #     video_filter = terminate_line_with_comma(video_filter)
   #     #ensure divisible by 2
   #     video_filter = video_filter+"scale=#{profile.width}:trunc(ow/a/2)*2"
   #   end

       video_filter = terminate_line_with_comma(video_filter)

      # https://ffmpeg.org/trac/ffmpeg/ticket/2015  , scale + square pixels
       video_filter += "scale=#{profile.width}:trunc(#{profile.width}/dar/2)*2"

       vbv_maxrate = (profile.video_bitrate * 1.1).floor
       vbv_bufsize = (profile.video_bitrate * 1).floor

       output_file_path = "#{output_dir}/#{output_file_name}"

       #                         -maxrate      :vbv_maxrate          \
       #                         -bufsize      :vbv_bufsize          \

       line = Terrapin::CommandLine.new('ffmpeg', " -y            -i           :input_file      \
                                                                  -c:v          :video_codec          \
                                                                  -profile:v    :h264_profile         \
                                                                  -g            :keyframe_interval    \
                                                                  -b:v          :video_bitrate        \
                                                                  -vf           :video_filter         \
                                                                  -c:a          :audio_codec          \
                                                                  -ab           :audio_bitrate        \
                                                                  -timelimit    :timelimit            \
                                                                  :output_file",
                                         input_file:,
                                         video_codec: VIDEO_CODEC,
                                         h264_profile: profile.h264_profile,
                                         keyframe_interval: KEYFRAME_INTERVAL,
                                         sc_threshold: SCENE_CHANGE_THRESHOLD,
                                         video_bitrate: "#{profile.video_bitrate}k",
                                         vbv_maxrate: "#{vbv_maxrate}k",
                                         vbv_bufsize: "#{vbv_bufsize}k",
                                         video_filter:,
                                         audio_codec: AUDIO_CODEC,
                                         audio_bitrate: profile.audio_bitrate,
                                         timelimit: timelimit.to_s,
                                         output_file: output_file_path)

       begin
          line.run
       rescue Terrapin::ExitStatusError
          raise 'error'
       end

       line = Terrapin::CommandLine.new('qt-faststart', "#{output_file_path} #{output_file_path}.qtfast")

       begin
         line.run
       rescue Terrapin::ExitStatusError
         raise 'error'
       end

       begin
         FileUtils.move("#{output_file_path}.qtfast", output_file_path)
       rescue StandardError
         raise 'error'
       end

       if create_hls_segments
         Rails.logger.debug 'HLS Segment'
         segment(output_file_path, output_dir, ve_name)
       end

       ve = identify(output_file_path)

       ve['name'] = ve_name
       ve['file_name'] = output_file_name
       ve['label'] = profile.label
       ve['short_label'] = profile.short_label
       ve['url'] = "#{url_prefix}/#{output_file_name}"
       ve['state'] = 'finished'

       ve['hls'] = true if create_hls_segments

       ve
  end
end

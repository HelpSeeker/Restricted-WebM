"""
Collection of functions regarding video settings for ffmpeg.

Functions:
    downscale_height: Determine output video height
    drop_framerate: Determine output video frame rate
    video_bitrate: Get output video bitrate
    video_settings: Assemble ffmpeg video settings
"""

from utils.audio import audio_bitrate_sum

def video_bitrate(args, in_file, last, out_size, attempt):
    """
    Calculate final output video bitrate.
    Decision is based on:
        -) output duration
        -) complete audio bitrate
        -) file size limit
        -) Output size produced by the last bitrate

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information
        param3: Last used video bitrate (None if first attempt)
        param4: Last produced output size (None if first attempt)
        param5: Number of attempts made

    Returns:
        Output video bitrate used by libvpx
    """
    a_bitrate = 0
    out_dur = in_file.t_prop.out_dur

    # First attempt used theoretical bitrate
    # Following attempts are based on the last one
    if attempt == 0:
        if args.audio:
            a_bitrate = audio_bitrate_sum(args, in_file)
        bitrate = args.size*8*1000 / out_dur - a_bitrate
    else:
        bitrate = last * (args.size*1024**2 / out_size)
        diff = (bitrate-last) / last
        if -0.1 < diff < 0:
            bitrate = 0.9*last

    # Ensure min. 1Kbps bitrate
    if bitrate <= 1:
        bitrate = 1

    return int(bitrate)

def downscale_height(args, v_prop, bitrate, fps, stage):
    """
    Determine output video height based on a bpp value.
    This function is supposed to be executed in stages.
    Height reduction -> frame rate reduction -> height reduction ...

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input video information
        param3: Bitrate of the current attempt
        param4: Frame rate of the current attempt
        param5: Stage of height reduction (1 or 2)

    Returns:
        Output video height
    """
    in_height = v_prop.height
    out_height = in_height
    ratio = v_prop.ratio
    min_height = args.min_height*stage
    max_height = args.max_height

    if args.user_scale:
        return in_height
    if in_height < min_height:
        return in_height

    while True:
        bpp = bitrate*1000 / (fps*ratio*out_height**2)
        if bpp >= args.bpp:
            break
        out_height -= 10

    if out_height < min_height:
        out_height = min_height
    elif out_height > max_height:
        out_height = max_height

    return out_height

def drop_framerate(args, v_prop, bitrate, height):
    """
    Determine output video frame rate based on a bpp value.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input video information
        param3: Bitrate of the current attempt
        param4: Height of the current attempt

    Returns:
        Output video frame rate
    """
    in_fps = v_prop.fps
    out_fps = in_fps
    ratio = v_prop.ratio
    fps_list = [in_fps, 60, 30, 24, 22, 20, 18,
                16, 14, 12, 10, 8, 6, 4, 2, 1]

    if args.user_fps:
        return in_fps
    if in_fps < args.min_fps:
        return in_fps

    for fps in fps_list:
        bpp = bitrate*1000 / (fps*ratio*height**2)
        out_fps = fps
        if bpp >= args.bpp:
            break

    if out_fps > args.max_fps:
        out_fps = args.max_fps
    elif out_fps < args.min_fps:
        out_fps = args.min_fps

    return out_fps

def video_settings(args, mode, bitrate):
    """
    Assemble video settings for ffmpeg.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Current bitrate mode (0 - 2)
        param3: Bitrate of the current attempt

    Returns:
        Video settings for ffmpeg
    """
    settings = ["-c:v", "libvpx"]

    mode_opts = ["-b:v", str(bitrate) + "K"]
    if mode == 0:
        mode_opts.extend(["-qmax", "50"])
    elif mode == 2:
        mode_opts.extend(["-minrate:v", str(bitrate) + "K",
                          "-maxrate:v", str(bitrate) + "K"])
    elif mode > 2:
        raise ValueError("Invalid bitrate mode!")

    # TO-DO:
    # Test how strong temporal filtering influences high quality encodes
    # Figure out how/why alpha channel support cuts short GIFs during 2-pass
    if args.transparency:
        pix_opts = ["-pix_fmt", "yuva420p"]
        alt_ref_opts = ["-auto-alt-ref", "0"]
    else:
        pix_opts = ["-pix_fmt", "yuv420p"]
        alt_ref_opts = ["-auto-alt-ref", "1", "-lag-in-frames", "25",
                        "-arnr-maxframes", "15", "-arnr-strength", "6"]

    settings.extend(mode_opts)
    settings.extend(pix_opts)
    settings.extend(alt_ref_opts)

    return settings

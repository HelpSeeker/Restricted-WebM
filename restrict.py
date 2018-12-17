"""Convert all input videos to WebM with a specific size."""

from utils.parse import parsed_args
from utils.error import check_args
from utils.classes import InputVideo
from utils.convert import convert_file
from utils import info

if __name__ == "__main__":
    args = parsed_args()
    args.audio_filters = info.audio_filters(args.filter)
    args.video_filters = info.video_filters(args.filter)
    args.user_scale = "scale" in args.filter
    args.user_fps = "fps" in args.filter
    args.upper_limit = args.size * 1024**2
    args.lower_limit = args.size * 1024**2 * args.undershoot

    check_args(args)
    err_count = 0

    # Main conversion loop
    for in_path in args.input:
        in_file = InputVideo(args, in_path)

        print("+++\nFile: " + in_path)

        # Only convert if no internal error has been logged
        if not in_file.internal_error:
            convert_file(args, in_file)

        # Count error(s) that happened during the conversion
        if in_file.internal_error:
            print("An error occured!")
            err_count += 1

    # In case user doesn't notice prior error messages
    if err_count > 0:
        print("\n" + str(err_count) + " error(s) occurred.")
        print("Please check webm_error.log to see what happened.\n")

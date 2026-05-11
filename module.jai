#load "section_timer.jai";
#load "periodic_timer.jai";
#load "timer.jai";
#load "periodic_signal.jai";

// todo make functions that convert beteween times like sec to min to hour everything we'd ever need.

minutes_to_seconds :: (minutes : u32) -> u32 {
    return minutes * 60;
}

milliseconds_to_microseconds :: (ms : float) -> u32 {
    return xx (ms * 1000.0);
}

format_time :: (total_seconds: int) -> string {
    hours   := total_seconds / 3600;
    minutes := (total_seconds % 3600) / 60;
    seconds := total_seconds % 60;

    if hours > 0 {
        return tprint("%:%:%", hours, formatInt(minutes, minimum_digits=2), formatInt(seconds, minimum_digits=2));
    } else if minutes > 0 {
        return tprint("%:%", minutes, formatInt(seconds, minimum_digits=2));
    } else {
        return tprint("%", seconds);
    }
}

get_timestamp :: () -> string {
    now := current_time_consensus();
    cal := to_calendar(now, .LOCAL);

    total_us, success := to_microseconds(now);
    microseconds := total_us % 1_000_000;
    if microseconds < 0  microseconds += 1_000_000;

    return tprint("[%:%:%.%]",
        formatInt(cal.hour,   minimum_digits=2),
        formatInt(cal.minute, minimum_digits=2),
        formatInt(cal.second, minimum_digits=2),
        formatInt(microseconds, minimum_digits=6)
    );
}

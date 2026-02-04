#load "section_timer.jai";
#load "periodic_timer.jai";
#load "timer.jai";
#load "periodic_signal.jai";

// todo make functions that convert beteween times like sec to min to hour everything we'd ever need.

minutes_to_seconds :: (minutes : u32) -> u32 {
    return minutes * 60;
}

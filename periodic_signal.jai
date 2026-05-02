/*

A periodic signal is a tool to do something at a fixed frequency, when the signal is ready do the thing.

*/

Periodic_Signal :: struct {
    frequency_hz: float;

    // you don't have to pass in these when you make one.
    last_time: Apollo_Time;
    cycle_progress_at_last_ready_call: float;
}

ready :: (using ps: *Periodic_Signal) -> bool {
    current_time := current_time_monotonic();
    elapsed_time := cast(float) to_float64_seconds(current_time - last_time);
    period: float = 1.0 / frequency_hz;

    // update cycle progress [0, 1], clamped in case we've overrun
    // I think the way we do this means that it's never going to be having the value of 0
    // but it can have the value of 1, just keep that in mind
    cycle_progress_at_last_ready_call = min(elapsed_time / period, 1.0);

    time_up := elapsed_time >= period;

    if time_up {
        period_apollo := to_apollo(cast(float64) period);

        way_behind_schedule := elapsed_time > period * 3.0;

        if way_behind_schedule {
            // when we're not calling this function fast enough, then we would go into a state where this function
            // keeps returning true because the last_time += isn't getting us there for a while. This would make it
            // appear like the signal fires a bunch at once, which is also not good, instead we just do this to resume
            // normal cadence
            last_time = current_time;
        } else {
            // by doing this we're moving time ahead by exactly a period
            // as compared to assigning last_time to current time, this accounts
            // for the time since the signal would have been emitted, and when we call ready
            // if we're late, then that means that the next signal will come up sooner to account for it
            last_time += period_apollo;
        }
    }

    return time_up;
}

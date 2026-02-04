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

    // todo, if we're over the period we should probably play catchup
    if time_up
        last_time = current_time;

    return time_up;
}

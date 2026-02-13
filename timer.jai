Timer :: struct {
    duration_sec: float;       
    start_time: Apollo_Time;
    running := false;
}

start :: (using t: *Timer) {
    start_time = current_time_monotonic();
    running = true;
}

change_duration_and_start :: (using t : *Timer, duration_seconds: float) {
    duration_sec = duration_seconds;
    start(t);
}

stop :: (using t: *Timer) {
    running = false;
}

time_up :: (using t: *Timer, auto_stop := true) -> bool {
    // it might be beneficial to make it return true if it's not running or something for first iteration logic.
    if !running return false;
    
    current_time := current_time_monotonic();
    elapsed := cast(float) to_float64_seconds(current_time - start_time);
    
    if elapsed >= duration_sec {
        if auto_stop then running = false;
        return true;
    }
    
    return false;
}

time_up_or_not_running :: (using t: *Timer) -> bool {
    return !running || time_up(t);
}

get_elapsed :: (using t: *Timer) -> float {
    if !running return 0.0;
    
    current_time := current_time_monotonic();
    return cast(float) to_float64_seconds(current_time - start_time);
}

get_remaining :: (using t: *Timer) -> float {
    if !running return 0.0;
    
    remaining := duration_sec - get_elapsed(t);
    return max(remaining, 0.0);
}

get_progress :: (using t: *Timer) -> float {
    if !running return 0.0;
    if duration_sec <= 0.0 return 1.0;
    
    return min(get_elapsed(t) / duration_sec, 1.0);
}

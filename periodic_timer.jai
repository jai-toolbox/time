Periodic_Timer :: struct  {
    delta_times : [20] float;
    delta_time_index : u32;
    last_time : Apollo_Time;
    first_frame := true;
}

mark_cycle :: (using ft : *Periodic_Timer) {
    current_time := current_time_monotonic();
    if (first_frame) {
        last_time = current_time;
        first_frame = false;
    } else {
        delta_time := cast (float) to_float64_seconds(current_time - last_time);

        delta_time_index += 1;
        delta_time_index %= 20;
        delta_times[delta_time_index] = delta_time;
        last_time = current_time;
    }
}

get_average_delta_time :: (using ft : *Periodic_Timer) -> float {
    total_delta_time : float;
    for 0..19 total_delta_time += delta_times[it];
    return total_delta_time / 20;
}

#load "section_timer.jai";


#import "Basic";


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

Periodic_Signal :: struct {
    frequency_hz : float;
    // you don't have to pass this in when you make one.
    last_time : Apollo_Time;
}

ready :: (using ps : *Periodic_Signal) -> bool {
    current_time := current_time_monotonic();
    elapsed_time := cast (float) to_float64_seconds (current_time - last_time);
    period : float = 1.0 / frequency_hz;

    time_up := elapsed_time >= period; 

    // todo, if we're over the period we should probably play catchup
    if time_up
        last_time = current_time;

    return time_up;
}

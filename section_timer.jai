
/*

usage:

main :: () {
    timer: Section_Timer;
    init_section_timer(*timer);
    
    for frame: 0..100 {
        start_section(*timer, "tick");
        
        start_section(*timer, "update");
        sleep_milliseconds(1);
        end_section(*timer, "update");
        
        start_section(*timer, "rendering");
        sleep_milliseconds(5);
        end_section(*timer, "rendering");
            
        end_section(*timer, "tick");
    }
    
    averaged := get_averaged_sections(*timer);
    print_averaged_section(averaged.root);
}


*/


#import "Basic";
#import "Math";

// this represents the maximum number of sections this system can keep track of at once.
// in general if you're using this in a per-frame context then the number of sections gets reset at the end of every frame.
MAX_SECTIONS :: 64; 
MAX_HISTORY :: 20;
MAX_CHILDREN :: 16;
MAX_PATH_DEPTH :: 32;

Timed_Section :: struct {
    name: string;

    start_time: Apollo_Time;
    end_time: Apollo_Time;
    elapsed_seconds: float;
    
    children: [MAX_CHILDREN] * Timed_Section;
    child_count: u32;

    parent: *Timed_Section;
    
    completed: bool;
}

// pool are like arenas, but they arrays of objects that always exist.

Section_Timer :: struct {
    // instead of creating new timed sections we always pull from an existing pool of sections.
    section_pool: [MAX_SECTIONS] Timed_Section;
    pool_index: u32;
    
    // a collection of existing timed sections pointers indexed by the stack depth
    section_stack: [MAX_SECTIONS] *Timed_Section;
    stack_depth: u32;
    
    history: [MAX_HISTORY] *Timed_Section;

    // we hold an array of histories, a singular history is just a [MAX_SECTIONS] Timed_Section;
    // which represents the previous state of a section_pool
    history_pools: [MAX_HISTORY][MAX_SECTIONS] Timed_Section;
    history_index: u32;
    history_count: u32;
    
    /*
    If you're profiling a one shot program, then this is really just the root. 
    But most interesting programs loop for a while, and the current root makes sense 
    in this context as it refers to this frames timed section, which changes per frame.
    */
    current_root: *Timed_Section;
}

Averaged_Section :: struct {
    name: string;
    average_elapsed: float;
    min_elapsed: float;
    max_elapsed: float;
    
    children: [MAX_CHILDREN] *Averaged_Section;
    child_count: u32;
}

Averaged_Section_Result :: struct {
    root: *Averaged_Section;
    pool: [MAX_SECTIONS] Averaged_Section;
    pool_index: u32;
}

init_section_timer :: (using st: *Section_Timer) {
    pool_index = 0;
    stack_depth = 0;
    history_index = 0;
    history_count = 0;
    current_root = null;
}

start_section :: (using st: *Section_Timer, name: string) {
    assert(pool_index < MAX_SECTIONS, "Section pool exhausted");
    
    // acquire a new section from the pool
    // there is a guarentee that the pool index always points to a free section to use.
    section := *section_pool[pool_index];
    pool_index += 1;
    
    // reset the data of this section
    section.name = name;
    section.start_time = current_time_monotonic();
    section.end_time = .{};
    section.elapsed_seconds = 0;
    section.child_count = 0;
    section.parent = null;
    section.completed = false;
    
    for i: 0..MAX_CHILDREN-1 {
        section.children[i] = null;
    }
    
    has_parent := stack_depth > 0;
    if has_parent {
        parent := section_stack[stack_depth - 1];
        assert(parent.child_count < MAX_CHILDREN, "Too many children in section");
        parent.children[parent.child_count] = section;
        parent.child_count += 1;
        section.parent = parent;
    } else {
        st.current_root = section;
    }
    
    section_stack[stack_depth] = section;
    stack_depth += 1;
}

end_section :: (using st: *Section_Timer, name: string) {
    assert(stack_depth > 0, "No section to end");
    
    section_we_are_ending := section_stack[stack_depth - 1];
    assert(section_we_are_ending.name == name, "Section name mismatch: expected '%', got '%'", section_we_are_ending.name, name);
    
    section_we_are_ending.end_time = current_time_monotonic();
    section_we_are_ending.elapsed_seconds = cast(float) to_float64_seconds(section_we_are_ending.end_time - section_we_are_ending.start_time);
    section_we_are_ending.completed = true;
    
    stack_depth -= 1;
    
    // we only store the history of root level sections, this is important to remember!
    // current_root could be null if you try and end a section before one has begun.
    if stack_depth == 0 && current_root != null {
        save_current_root_section_to_history(st);
    }
}

save_current_root_section_to_history :: (using st: *Section_Timer) {

    dest_pool := *history_pools[history_index];
    copy_section_tree(current_root, dest_pool);
    
    // after copying it into the pool, because the root section is stored as the first entry we can get a pointer to it.
    history[history_index] = *(<<dest_pool)[0];
    
    // update the history index in a circular manner, when the number gets too big we clobber out the oldest one.
    history_index += 1;
    history_index %= MAX_HISTORY;
    
    // when we're under the max, then we increase, if we're at the max, we just clobber out an old one and maintain max size.
    if history_count < MAX_HISTORY {
        history_count += 1;
    }

    // we only ever process one root section at a time, here we are resetting the pool so the next section can have fresh mem.
    // this is like areana reset.
    pool_index = 0;
    current_root = null;
}

// note the root section is stored as the first entry in the pool.
copy_section_tree :: (src: *Timed_Section, dest_pool: *[MAX_SECTIONS] Timed_Section, pool_index_to_store_at: u32 = 0) -> pool_index_to_store_next_at: u32 {
    if src == null return pool_index_to_store_at;
    
    // here we're getting a Timed_Section
    dest := *(<<dest_pool)[pool_index_to_store_at];
    
    // copy over the data.
    dest.name = src.name;
    dest.start_time = src.start_time;
    dest.end_time = src.end_time;
    dest.elapsed_seconds = src.elapsed_seconds;
    dest.child_count = src.child_count;
    dest.completed = src.completed;
    dest.parent = null;
    
    for i: 0..MAX_CHILDREN-1 {
        dest.children[i] = null;
    }
    
    pool_index_to_store_next_at := pool_index_to_store_at + 1;
    
    // copy children over recursviely.
    for i: 0..cast(s64)src.child_count-1 {
        if src.children[i] != null {
            dest.children[i] = *(<<dest_pool)[pool_index_to_store_next_at ];
            pool_index_to_store_next_at = copy_section_tree(src.children[i], dest_pool, pool_index_to_store_next_at);
        }
    }
    
    return pool_index_to_store_next_at;
}

// path-based section finding using array of child indices
find_section_by_indices :: (root: *Timed_Section, indices: [] u32) -> *Timed_Section {
    current := root;
    for idx: indices {
        if current == null return null;
        if idx >= current.child_count return null;
        current = current.children[idx];
    }
    return current;
}

get_averaged_sections :: (using st: *Section_Timer) -> Averaged_Section_Result {
    result: Averaged_Section_Result;
    result.pool_index = 0;
    
    if history_count == 0 return result;
    
    // build averaged tree starting from root with empty path
    path: [MAX_PATH_DEPTH] u32;
    result.root = build_averaged_section_recursive(*result, history[0], st, path, 0);
    
    return result;
}

build_averaged_section_recursive :: (
    result: *Averaged_Section_Result, 
    template: *Timed_Section, 
    using st: *Section_Timer,
    path: [MAX_PATH_DEPTH] u32,
    path_len: u32
) -> *Averaged_Section {
    if template == null return null;
    
    assert(result.pool_index < MAX_SECTIONS, "Averaged section pool exhausted");
    
    dest := *result.pool[result.pool_index];
    result.pool_index += 1;
    
    dest.name = template.name;
    dest.child_count = template.child_count;
    
    for i: 0..MAX_CHILDREN-1 {
        dest.children[i] = null;
    }
    
    // gather timing data from all history entries using index path
    total_elapsed: float = 0;
    dest.min_elapsed = FLOAT32_MAX;
    dest.max_elapsed = 0;
    sample_count: u32 = 0;
    
    path_slice: [] u32;
    path_slice.data = path.data;
    path_slice.count = path_len;
    
    for i: 0..cast(s64)history_count-1 {
        section := find_section_by_indices(history[i], path_slice);
        if section != null && section.completed {
            total_elapsed += section.elapsed_seconds;
            if section.elapsed_seconds < dest.min_elapsed dest.min_elapsed = section.elapsed_seconds;
            if section.elapsed_seconds > dest.max_elapsed dest.max_elapsed = section.elapsed_seconds;
            sample_count += 1;
        }
    }
    
    if sample_count > 0 {
        dest.average_elapsed = total_elapsed / cast(float) sample_count;
    } else {
        dest.min_elapsed = 0;
    }
    
    // recursively process children, extending the path
    for i: 0..cast(s64)template.child_count-1 {
        if template.children[i] != null {
            child_path := path;
            child_path[path_len] = cast(u32)i;
            dest.children[i] = build_averaged_section_recursive(result, template.children[i], st, child_path, path_len + 1);
        }
    }
    
    return dest;
}

print_averaged_section :: (section: *Averaged_Section, indent: u32 = 0) {
    if section == null return;
    
    for i: 0..cast(s64)indent-1 print("  ");
    print("%: avg=%.3fms, min=%.3fms, max=%.3fms\n", 
          section.name, 
          section.average_elapsed * 1000, 
          section.min_elapsed * 1000, 
          section.max_elapsed * 1000);
    
    for i: 0..cast(s64)section.child_count-1 {
        print_averaged_section(section.children[i], indent + 1);
    }
}

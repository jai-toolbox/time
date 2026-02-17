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
    
    averaged: Averaged_Section_Result;
    get_averaged_sections(*timer, *averaged);
    print_averaged_section(averaged.root);
}

*/


#import "Basic";
#import "Math";
#load "fixed_pool.jai";

MAX_SECTIONS   :: 64;
MAX_HISTORY    :: 20;
MAX_CHILDREN   :: 16;
MAX_PATH_DEPTH :: 32;

Timed_Section :: struct {
    name: string;

    start_time: Apollo_Time;
    end_time: Apollo_Time;
    elapsed_seconds: float;
    
    // these are pointing into a pool in which this timed section exists.
    children: [MAX_CHILDREN] *Timed_Section;
    child_count: u32;

    parent: *Timed_Section;
    
    completed: bool;
}

Section_Timer :: struct {
    // gets wiped out whenever the root section finishes.
    working_pool_for_current_section_tree: Fixed_Pool(Timed_Section, MAX_SECTIONS);
    
    section_stack: [MAX_SECTIONS] *Timed_Section;
    stack_depth: u32;
    
    // circular buffer of completed section trees.
    // completed_tree_pools[i] owns all the nodes for completed_tree_roots[i].
    // They are paired by physical index, which is why this isn't a Circular_Array:
    // we need direct access to the destination pool before writing the entry.
    completed_tree_roots: [MAX_HISTORY] *Timed_Section;
    completed_tree_pools: [MAX_HISTORY] Fixed_Pool(Timed_Section, MAX_SECTIONS);
    completed_tree_write_index: u32;
    completed_tree_count: u32;
    
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
    pool: Fixed_Pool(Averaged_Section, MAX_SECTIONS);
}

init_section_timer :: (using st: *Section_Timer) {
    pool_reset(*working_pool_for_current_section_tree);
    stack_depth = 0;
    completed_tree_write_index = 0;
    completed_tree_count = 0;
    current_root = null;
}

start_section :: (using st: *Section_Timer, name: string) {
    section := pool_acquire(*working_pool_for_current_section_tree);
    
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
    
    if stack_depth == 0 && current_root != null {
        save_current_root_section_to_history(st);
        pool_reset(*working_pool_for_current_section_tree);
        current_root = null;
    }
}

save_current_root_section_to_history :: (using st: *Section_Timer) {
    dest_pool := *completed_tree_pools[completed_tree_write_index];
    pool_reset(dest_pool);
    copy_section_tree(current_root, dest_pool);
    
    // root is always the first item in the destination pool
    completed_tree_roots[completed_tree_write_index] = pool_get(dest_pool, 0);
    
    completed_tree_write_index += 1;
    completed_tree_write_index %= MAX_HISTORY;
    
    if completed_tree_count < MAX_HISTORY {
        completed_tree_count += 1;
    }

}

copy_section_tree :: (src: *Timed_Section, dest_pool: *Fixed_Pool(Timed_Section, MAX_SECTIONS)) {
    if src == null return;
    
    dest := pool_acquire(dest_pool);
    
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
    
    for i: 0..cast(s64)src.child_count-1 {
        if src.children[i] != null {
            // grab pointer to where the next acquire will land, then recurse
            dest.children[i] = pool_get(dest_pool, dest_pool.count);
            copy_section_tree(src.children[i], dest_pool);
        }
    }
}

find_section_by_indices :: (root: *Timed_Section, indices: [] u32) -> *Timed_Section {
    current := root;
    for idx: indices {
        if current == null return null;
        if idx >= current.child_count return null;
        current = current.children[idx];
    }
    return current;
}

get_averaged_sections :: (using st: *Section_Timer, result: *Averaged_Section_Result) {
    pool_reset(*result.pool);
    result.root = null;
    
    if completed_tree_count == 0 return;
    
    path: [MAX_PATH_DEPTH] u32;
    result.root = build_averaged_section_recursive(result, completed_tree_roots[0], st, path, 0);
}

build_averaged_section_recursive :: (
    result: *Averaged_Section_Result, 
    template: *Timed_Section, 
    using st: *Section_Timer,
    path: [MAX_PATH_DEPTH] u32,
    path_len: u32
) -> *Averaged_Section {
    if template == null return null;
    
    dest := pool_acquire(*result.pool);
    
    dest.name = template.name;
    dest.child_count = template.child_count;
    
    for i: 0..MAX_CHILDREN-1 {
        dest.children[i] = null;
    }
    
    total_elapsed: float = 0;
    dest.min_elapsed = FLOAT32_MAX;
    dest.max_elapsed = 0;
    sample_count: u32 = 0;
    
    path_slice: [] u32;
    path_slice.data = path.data;
    path_slice.count = path_len;
    
    for i: 0..cast(s64)completed_tree_count-1 {
        section := find_section_by_indices(completed_tree_roots[i], path_slice);
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
    
    for i: 0..cast(s64)template.child_count-1 {
        if template.children[i] != null {
            child_path := path;
            child_path[path_len] = cast(u32)i;
            dest.children[i] = build_averaged_section_recursive(result, template.children[i], st, child_path, path_len + 1);
        }
    }
    
    return dest;
}

print_averaged_section :: (section: *Averaged_Section, indent: u32 = 0, parent_avg_elapsed: float = 0.0) {
    if section == null return;
    
    for i: 0..cast(s64)indent-1 print("  ");
    print("%: avg=%ms, min=%ms, max=%ms", 
          section.name, 
          formatFloat(section.average_elapsed * 1000, trailing_width=3, zero_removal=.NO), 
          formatFloat(section.min_elapsed * 1000, trailing_width=3, zero_removal=.NO), 
          formatFloat(section.max_elapsed * 1000, trailing_width=3, zero_removal=.NO));
    
    if parent_avg_elapsed > 0.0 {
        pct := (section.average_elapsed / parent_avg_elapsed) * 100.0;
        print(" (%\%)", formatFloat(pct, trailing_width=1, zero_removal=.NO));
    }
    
    print("\n");
    
    for i: 0..cast(s64)section.child_count-1 {
        if section.children[i] == null continue;
        print_averaged_section(section.children[i], indent + 1, section.average_elapsed);
    }
}

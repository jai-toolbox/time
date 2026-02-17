/*
 Fixed_Pool

 A fixed-capacity, typed bump allocator. Hands out objects of type T from
 a pre-allocated array. Acquire sequentially, reset all at once.

   [used | used | used | free | free | free | free]
                         ^
                       count

   - pool_acquire: returns a pointer to the next free slot, bumps count.
   - pool_reset:   sets count back to 0, all slots available again.
   - pool_get:     random access to any slot by index.

 It's essentially a linear/arena allocator that only deals in one type,
 so you get typed pointers back, no alignment math, no casting. The
 compiler handles all of that because it's just an array.

 The main advantage over a dynamic array is pointer stability. A dynamic
 array can reallocate and move when it grows, invalidating any pointers
 you've handed out. Fixed_Pool's backing memory never moves, so pointers
 stay valid until reset. This matters when building pointer-heavy
 structures like trees or graphs from pooled objects.

 The tradeoff is that capacity is fixed at compile time. If you don't
 know how many objects you'll need, or you don't hand out pointers into
 the storage, a dynamic array or a general-purpose arena is a better fit.
*/


Fixed_Pool :: struct (T: Type, Capacity: s64) {
    items: [Capacity] T;
    count: u32;
}

pool_acquire :: (pool: *Fixed_Pool($T, $Capacity)) -> *T {
    assert(pool.count < Capacity, "Pool exhausted (capacity: %)", Capacity);
    item := *pool.items[pool.count];
    pool.count += 1;
    return item;
}

pool_get :: (pool: *Fixed_Pool($T, $Capacity), index: u32) -> *T {
    assert(index < Capacity, "Pool index out of bounds");
    return *pool.items[index];
}

pool_reset :: (pool: *Fixed_Pool) {
    pool.count = 0;
}

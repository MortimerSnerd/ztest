/// Common utilities and data structures. 
const std = @import("std");

pub const UErrors = error {
    CapacityExceeded,
    EmptySlice
};

/// Returns the maximum int value of the given enumeration.
/// Assumes lowest possible value is 0.
pub fn maxEnumVal(comptime T: type) comptime_int {
    var max: comptime_int = 0;
    for (@typeInfo(T).Enum.fields) |enumField| {
        if (enumField.value > max) {
            max = enumField.value;
        }
    }

    return max;
}

/// Static array that has a runtime length so items can be
/// pushed onto it.  Access the `items` field directly to 
/// get the slice directly.
/// 
/// Does not call deinit automatically on array items for
/// any operations, that' up to the caller.
/// 
/// WARNING: copying this struct will invalidate the items
/// slice.
pub fn StaticArray(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        // Slice of the current items.  Callers should access this
        // directly.
        items: []T = undefined,
        arr: [N]T = undefined,

        // Returns a StaticArray with the items zeroed.
        pub fn init() Self {
            var rv = Self{};
            rv.arr = std.mem.zeroes([N]T);
            rv.items = rv.arr[0..0];

            return rv;
        }

        /// Sets the number of items back to zero,
        /// without modifying the underlying array.
        /// Doesn't call deinit on cleared items.
        pub fn clear(a: *Self) void {
            a.items = rv.arr[0..0];
        }

        // Pushes an item on the end of the erray.
        // Can fail if there is no room for the new item.
        pub fn push(a: *Self, v: T) !void {
            if (a.items.len < a.arr.len) {
                a.arr[a.items.len] = v;
                a.items = a.arr[0..a.items.len+1];
            } else {
                return UErrors.CapacityExceeded;
            }
        }

        /// Pops the last item off the array and returns it,
        /// or returns an EmptySlice error if there are no items
        /// to pop.
        pub fn pop(a: *Self) !T {
            if (a.items.len > 0) {
                const rv = a.items[a.items.len-1];
                a.items = a.arr[0..a.items.len-1];
                return rv;
            } else {
                return UErrors.EmptySlice;
            }
        }
    };
}









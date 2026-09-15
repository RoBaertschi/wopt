package wasim_base

import "base:runtime"
import "base:intrinsics"

// The `new` procedure allocates memory for a type `T` from a `base.Arena`. The second argument is a type,
// not a value, and the value return is a pointer to a newly allocated value of that type using the specified allocator.
arena_push_new :: proc(a: ^Arena, $T: typeid, loc := #caller_location) -> (ptr: ^T) {
	return arena_push_new_aligned(a, T, align_of(T), loc)
}

// The `new_aligned` procedure allocates memory for a type `T` from a `base.Arena` with a specified `alignment`.
// The second argument is a type, not a value, and the value return is a pointer to a newly allocated value of
// that type using the specified allocator.
arena_push_new_aligned :: proc(a: ^Arena, $T: typeid, alignment: uint, loc := #caller_location) -> (ptr: ^T) {
	data := _arena_push_aligned(a, size_of(T), alignment)
	ptr = (^T)(raw_data(data))
	return
}

// The `new_clone` procedure allocates memory for a type `T` from a `base.Arena`. The second argument is a value that
// is to be copied to the allocated data. The value returned is a pointer to a newly allocated value of that type using the specified allocator.
arena_push_clone :: proc(a: ^Arena, data: $T, loc := #caller_location) -> (ptr: ^T) {
	ptr = arena_push_new_aligned(a, T, align_of(T), loc)
	if ptr != nil {
		ptr^ = data
	}
	return
}

// `make_slice` allocates and initializes a slice. Like `new`, the second argument is a type, not a value.
// Unlike `new`, `make`'s return value is the same as the type of its argument, not a pointer to it.
//
// Note: Prefer using the procedure group `make`.
arena_push_slice :: proc(a: ^Arena, $T: typeid/[]$E, #any_int len: int, loc := #caller_location) -> T {
	return arena_push_slice_aligned(a, T, len, align_of(E), loc)
}

arena_push_soa_aligned :: proc(a: ^Arena, $T: typeid/#soa[]$E, #any_int len, alignment: int) -> (array: T) {
	if 0 >= len {
		return
	}

	footer := runtime.raw_soa_footer(&array)

	if size_of(E) == 0 {
		footer.len = len
		return
	}

	max_align := max(alignment, align_of(E))

	ti := type_info_of(typeid_of(T))
	ti = runtime.type_info_base(ti)
	si := &ti.variant.(runtime.Type_Info_Struct)

	field_count := uintptr(len(E) when intrinsics.type_is_array(E) else intrinsics.type_struct_field_count(E))

	total_size := 0
	for i in 0..<field_count {
		type := si.types[i].variant.(runtime.Type_Info_Multi_Pointer).elem
		total_size += type.size * len
		total_size = runtime.align_forward_int(total_size, max_align)
	}

	new_bytes := _arena_push_aligned(a, uint(total_size), uint(max_align))

	if new_bytes == nil {
		return
	}
	new_data := raw_data(new_bytes)

	offset := 0
	for i in 0..<field_count {
		type := si.types[i].variant.(runtime.Type_Info_Multi_Pointer).elem

		offset = runtime.align_forward_int(offset, max_align)

		([^]rawptr)(&array)[i] = rawptr(uintptr(new_data) + uintptr(offset))
		offset += type.size * len
	}
	footer.len = len

	return
}

arena_push_soa_slice :: proc(a: ^Arena, $T: typeid/#soa[]$E, len: int) -> (array: T) {
	return arena_push_soa_aligned(a, T, len, align_of(E))
}

// `make_aligned` allocates and initializes a slice. Like `new`, the second argument is a type, not a value.
// Unlike `new`, `make`'s return value is the same as the type of its argument, not a pointer to it.
//
// Note: Prefer using the procedure group `make`.
arena_push_slice_aligned :: proc(a: ^Arena, $T: typeid/[]$E, #any_int len: int, alignment: uint, loc := #caller_location) -> T {
	runtime.make_slice_error_loc(loc, len)
	data := _arena_push_aligned(a, size_of(E)*uint(len), alignment)
	if data == nil && size_of(E) != 0 {
		return nil
	}
	s := ([^]E)(raw_data(data))[:len]
	return T(s)
}

// `make_multi_pointer` allocates and initializes a dynamic array. Like `new`, the second argument is a type, not a value.
// Unlike `new`, `make`'s return value is the same as the type of its argument, not a pointer to it.
//
// This is "similar" to doing `raw_data(make([]E, len, allocator))`.
//
// Note: Prefer using the procedure group `make`.
arena_push_multi_pointer :: proc(a: ^Arena, $T: typeid/[^]$E, #any_int len: int, loc := #caller_location) -> T {
	runtime.make_slice_error_loc(loc, len)
	data := _arena_push_aligned(a, size_of(E)*uint(len), align_of(E), loc)
	if data == nil && size_of(E) != 0 {
		return nil
	}
	return (T)(raw_data(data))
}

arena_push_make :: proc{
	arena_push_slice,
	arena_push_slice_aligned,
	arena_push_multi_pointer,
}

arena_push :: proc{
	arena_push_new,
	arena_push_new_aligned,
	arena_push_clone,
}

arena_bootstrap_new_member :: proc($T: typeid, $member: string, commited: uint = 0, reserved: uint = runtime.Gigabyte * 2, flags: Arena_Flags = {}) -> ^T
	where intrinsics.type_has_field(T, member), intrinsics.type_field_type(T, member) == ^Arena
{
	return arena_bootstrap_new_offset(T, offset_of_by_string(T, member), commited, reserved, flags)
}

arena_bootstrap_new_offset :: proc($T: typeid, offset: uintptr, commited: uint = 0, reserved: uint = runtime.Gigabyte * 2, flags: Arena_Flags = {}) -> (ptr: ^T) {
	arena := arena_alloc()

	ptr = arena_push(arena, T)

	data := uintptr(ptr)
	arena_field := data + offset
	(^^Arena)(arena_field)^ = arena

	return
}

arena_bootstrap_new :: proc{
	arena_bootstrap_new_member,
	arena_bootstrap_new_offset,
}

// Tests

import "core:testing"

@test
arena_bootstrap_test :: proc(t: ^testing.T) {
	Test :: struct {
		data:  []byte,
		arena: ^Arena,
	}

	test := arena_bootstrap_new_member(Test, "arena")
	test.data = {}
	testing.expect(t, test.arena != nil)
	arena_destroy(test.arena)
}

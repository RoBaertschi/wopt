#+vet explicit-allocators
package wopt

import "core:container/xar"
import "core:mem"
import "core:sync"

import B "base"

Compile_Value :: struct {
	using value: Value,

	// Intrusive linked list, next value in the current block or VALUE_NONE
	block_next:  Value_Id,
}

Compile_Block :: struct {
	first, last: Value_Id,

	id:      Block_Id,
	kind:    Block_Kind,
	control: Value_Id,
}

// internal
Thread_Compile_Context :: struct {
	module:          ^Module,
	permanent_arena: ^B.Arena,
	allocator:       mem.Allocator,
	build_arena:     ^B.Arena,

	function: ^Function,

	current_blocks: xar.Array(Compile_Block, 4),
	current_values: xar.Array(Compile_Value, 4),
}

_tcc_block_add_value :: proc(tcc: ^Thread_Compile_Context, block: ^Compile_Block, value: ^Compile_Value) {
	if block.last != VALUE_NONE {
		last_value            := xar.get_ptr(&tcc.current_values, block.last)
		last_value.block_next  = last_value.id
	}

	block.last       = value.id
	value.block_next = VALUE_NONE
}

compile :: proc(m: ^Module, function_id: Function_Id, loc := #caller_location) {
	function := function_get_ptr(m, function_id)
	old_flags := sync.atomic_or_explicit(&function.flags, Function_Flags { ._In_Progress }, .Acquire)
	assert(._In_Progress not_in old_flags, "function_id is marked as in progress, this is invalid API usage, only one thread can compile a function at a time", loc = loc)
	assert(._Build_Done in old_flags, "function_id is not marked as build, this is invalid API usage, a function can only be compiled after building it", loc = loc)
	assert(._Compile_Done not_in old_flags, "function_id is marked as compiled, this is invalid API usage, a function can be compiled only once", loc = loc)



	// Done
	function.flags += {._Compile_Done}
	sync.atomic_and_explicit(&function.flags, ~Function_Flags{._In_Progress}, .Release)
}

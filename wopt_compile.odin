#+vet explicit-allocators
package wopt

import "core:mem"
import "core:sync"

// internal
Thread_Compile_Context :: struct {
	module:    ^Module,
	allocator: mem.Allocator,
}

compile :: proc(tbctx: ^Thread_Build_Context, function_id: Function_Id, loc := #caller_location) {
	m := tbctx.module
	function := function_get_ptr(m, function_id)
	old_flags := sync.atomic_or_explicit(&function.flags, Function_Flags { ._In_Progress }, .Acquire)
	assert(._In_Progress not_in old_flags, "function_id is marked as in progress, this is invalid API usage, only one thread can compile a function at a time", loc = loc)
	assert(._Build_Done in old_flags, "function_id is not marked as build, this is invalid API usage, a function can only be compiled after building it", loc = loc)
	assert(._Compile_Done not_in old_flags, "function_id is marked as compiled, this is invalid API usage, a function can be compiled only once", loc = loc)



	// Done
	function.flags += {._Compile_Done}
	sync.atomic_and_explicit(&function.flags, ~Function_Flags{._In_Progress}, .Release)
}

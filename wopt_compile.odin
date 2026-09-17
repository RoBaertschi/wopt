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
	value_count: int,

	id:      Block_Id,
	kind:    Block_Kind,
	control: Value_Id,
}

// internal
Thread_Compile_Context :: struct {
	module:          ^Module,
	permanent_arena: ^B.Arena,
	allocator:       mem.Allocator,
	temp_arena:     ^B.Arena,

	function: ^Function,

	current_blocks: xar.Array(Compile_Block, 4),
	current_values: xar.Array(Compile_Value, 4),
}

_tcc_block_add_value :: proc(tcc: ^Thread_Compile_Context, block: ^Compile_Block, value: ^Compile_Value) {
	if block.last != VALUE_NONE {
		last_value            := xar.get_ptr(&tcc.current_values, block.last)
		last_value.block_next  = value.id
	} else {
		block.first = value.id
	}

	block.last       = value.id
	value.block_next = VALUE_NONE

	block.value_count += 1
}

_tcc_add_block :: proc(tcc: ^Thread_Compile_Context, block: Compile_Block) -> (block_ptr: ^Compile_Block) {
	block := block

	if block.id == 0 {
		block.id = Block_Id(xar.len(tcc.current_blocks))
	} else {
		assert(block.id == Block_Id(xar.len(tcc.current_blocks)))
	}
	block_ptr, _ = xar.push_back_elem_and_get_ptr(&tcc.current_blocks, block)
	return
}

_tcc_value_replace_op_immediate :: proc(
	tcc: ^Thread_Compile_Context,
	value_id: Value_Id,
	operator: Operator,
	immediate: u64,
) {
	old_value := xar.array_get_ptr(&tcc.current_values, value_id)
	old_value^ = {
		{
			old_value.id,
			operator,
			old_value.type,
			{},
			immediate,
			&operator_information[operator].register_information,
		},
		old_value.block_next,
	}
}

// _tcc_value_replace :: proc(tcc: ^Thread_Compile_Context, new_value: Compile_Value, value_id: Value_Id) {
// 	old_value := xar.array_get_ptr(&tcc.current_values, value_id)
// 	old_value^ = {
// 		{
// 			old_value.id,
// 			new_value.operator,
// 			new_value.type,
// 			new_value.arguments,
// 			new_value.immediate,
// 			new_value.register_information if new_value.register_information != nil else &operator_information[new_value.operator].register_information,
// 		},
// 		new_value.block_next,
// 	}
// }

// TODO(robin, 20260917-180827): do major cleanup to remove this weird roundtrip
compile :: proc(m: ^Module, function_id: Function_Id, loc := #caller_location) {
	function := function_get_ptr(m, function_id)
	old_flags := sync.atomic_or_explicit(&function.flags, Function_Flags { ._In_Progress }, .Acquire)
	assert(._In_Progress not_in old_flags, "function_id is marked as in progress, this is invalid API usage, only one thread can compile a function at a time", loc = loc)
	assert(._Build_Done in old_flags, "function_id is not marked as build, this is invalid API usage, a function can only be compiled after building it", loc = loc)
	assert(._Compile_Done not_in old_flags, "function_id is marked as compiled, this is invalid API usage, a function can be compiled only once", loc = loc)

	tcc := B.arena_bootstrap_new(Thread_Compile_Context, "permanent_arena")
	tcc.temp_arena = B.arena_alloc()

	tcc.module = m

	tcc.allocator = B.arena_allocator(tcc.temp_arena)
	xar.init(&tcc.current_blocks, tcc.allocator)
	B.xar_reserve(&tcc.current_blocks, len(function.build_body.blocks))
	xar.init(&tcc.current_values, tcc.allocator)
	B.xar_reserve(&tcc.current_values, len(function.build_body.values))

	tcc.function = function

	for value in function.build_body.values {
		compile_value := Compile_Value {
			value = value,
		}

		assert(value.id == Value_Id(xar.len(tcc.current_values))) // TODO(robin): remove
		xar.push_back(&tcc.current_values, compile_value)
	}

	for block in function.build_body.blocks {
		compile_block := Compile_Block {
			id      = block.id,
			kind    = block.kind,
			control = block.control,
		}

		compile_block_ptr := _tcc_add_block(
			tcc,
			compile_block,
		)

		for value in block.values {
			_tcc_block_add_value(
				tcc,
				compile_block_ptr,
				xar.get_ptr(&tcc.current_values, value),
			)
		}
	}

	_compile_abi_lower(tcc)


	compile_body := &tcc.function.compile_body

	compile_body.start = tcc.function.build_body.start
	compile_body.blocks = B.arena_push_make(tcc.permanent_arena, []Block, xar.len(tcc.current_blocks))
	compile_body.values = B.arena_push_make(tcc.permanent_arena, []Value, xar.len(tcc.current_values))

	for it := xar.iterator(&tcc.current_blocks); compile_block, i in xar.iterate_by_ptr(&it) {
		block := &compile_body.blocks[i]

		block.values = B.arena_push_make(tcc.permanent_arena, []Value_Id, compile_block.value_count)

		for value_id, j := compile_block.first, 0; value_id != VALUE_NONE; j += 1 {
			value := xar.get_ptr(&tcc.current_values, value_id)

			block.values[j] = value_id

			value_id = value.block_next
		}

		block.id      = compile_block.id
		block.kind    = compile_block.kind
		block.control = compile_block.control
	}

	for it := xar.iterator(&tcc.current_values); compile_value, i in xar.iterate_by_ptr(&it) {
		compile_body.values[i] = compile_value.value
	}

	// Done
	function.flags += {._Compile_Done}
	sync.atomic_and_explicit(&function.flags, ~Function_Flags{._In_Progress}, .Release)
}

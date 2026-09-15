#+vet explicit-allocators
package wopt

import "core:container/xar"

import B "base"

_compile_abi_lower :: proc(tcc: ^Thread_Compile_Context) {
	result := B.arena_push(tcc.permanent_arena, ABI_Result)

	parameters := B.arena_push_make(tcc.permanent_arena, []ABI_Value, len(tcc.function.parameters))
	for param, i in tcc.function.parameters {
		parameters[i] = _abi_value_from_type_id(tcc.permanent_arena, tcc.module, param)
	}

	result.parameters = parameters
	result.result     = _abi_value_from_type_id(tcc.permanent_arena, tcc.module, tcc.function.result)

	abi := _abi_get(tcc.module, tcc.function.abi)

	result.config = abi.procedure(abi.user_data, result.parameters, result.result)

	tcc.function.abi_result = result

	// TODO(robin): validate abi result

	for it := xar.iterator(&tcc.current_blocks); block, i in xar.iterate_by_ptr(&it) {
		if i == 0 {
			continue
		}

		for value_id := block.first; value_id != VALUE_NONE; {
			value : Compile_Value = xar.get(&tcc.current_values, value_id)

			#partial switch value.operator {
			case .Argument:
				abi_value := result.parameters[int(value.immediate)]
				// TODO(robin, 20260915-121028): support more types
				assert(abi_value.type.kind == .I32)
				location := abi_value.location
				// TODO(robin, 20260915-121028): support more location
				assert(location.register != REGISTER_INVALID)
				assert(.Indirect not_in location.flags)


			case .Return:
			}

			value_id = value.block_next
		}
	}
}

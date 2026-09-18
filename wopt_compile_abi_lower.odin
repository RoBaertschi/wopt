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
	tcc.function.register_info = _register_information_from_abi_result(tcc.permanent_arena, result^)

	// TODO(robin, 20260915-170105): validate abi result, remember, untrusted input

	for it := xar.iterator(&tcc.current_blocks); block, i in xar.iterate_by_ptr(&it) {
		if i == 0 {
			continue
		}

		for value_id := block.first; value_id != VALUE_NONE; {
			value : ^Compile_Value = xar.get_ptr(&tcc.current_values, value_id)

			#partial switch value.operator {
			case .Argument:
				abi_value := result.parameters[int(value.immediate)]
				// TODO(robin, 20260915-121028): support more types
				assert(abi_value.type.kind == .I32)
				location := abi_value.location
				// TODO(robin, 20260915-121028): support more location
				assert(location.register != REGISTER_INVALID)
				assert(.Indirect not_in location.flags)

				_tcc_value_replace_op_immediate(
					tcc,
					value_id,
					.Copy_From_Reg,
					u64(location.register),
				)
			case .Return:
				if 0 < len(value.arguments) {
					abi_value := result.result
					// TODO(robin, 20260915-121028): support more types
					assert(abi_value.type.kind == .I32)
					location := abi_value.location
					// TODO(robin, 20260915-121028): support more location
					assert(location.register != REGISTER_INVALID)
					assert(.Indirect not_in location.flags)

					inputs := B.arena_push_soa_slice(tcc.permanent_arena, #soa[]Register_Constraint, 1)

					inputs[0].allowed = { int(location.register) }

					value.register_information  = B.arena_push(tcc.permanent_arena, Register_Information)
					value.register_information^ = {
						inputs = inputs,
					}
				}
			}

			value_id = value.block_next
		}
	}
}

#+vet explicit-allocators
package wopt

import B "base"

Architecture :: enum {
	Amd64,
}

Target :: struct {
	architecture: Architecture,
	default_abi:  ABI_Id,
}

// Infers the target based on the target that the library was compiled for
target_infer :: proc(m: ^Module) -> (target: Target) {
	target.architecture = .Amd64           // TODO(robin, 20260912-105812): add support for more architectures
	target.default_abi  = m.abi_amd64_sysv // TODO(robin, 20260912-120319): detect default abi based on OS

	return
}

Register     :: distinct u8
Register_Set :: bit_set[0..=63; u64]

REGISTER_INVALID :: Register(0xFF)

Register_Constraint :: struct {
	allowed: Register_Set,
	pin:     u8,           // only valid for inputs, only used if not zero, index into outputs + 1
}

Register_Information :: struct {
	inputs:   #soa[]Register_Constraint,
	outputs:  #soa[]Register_Constraint,
	clobbers: Register_Set,
}

_register_information_from_abi_result :: proc(arena: ^B.Arena, result: ABI_Result) -> (info: ^Register_Information) {
	info = B.arena_push(arena, Register_Information)

	abi_value_register_location_count :: proc(value: ABI_Value) -> (n: int) {
		if value.location == nil {
			for child in value.children {
				n += abi_value_register_location_count(child)
			}
		} else if value.location.register != REGISTER_INVALID {
			ensure(.Indirect not_in value.location.flags, "TODO(robin, 20260915-121028): Indirect flag support")
			n = 1
		}

		return
	}

	abi_value_push_register :: proc(value: ABI_Value, i: ^int, constraints: #soa[]Register_Constraint) {
		if value.location == nil {
			for child in value.children {
				abi_value_push_register(child, i, constraints)
			}
		} else if value.location.register != REGISTER_INVALID {
			constraint := Register_Constraint {
				allowed = {int(value.location.register)},
			}
			constraints[i^] = constraint
			i^ += 1
		}
	}

	input_register_count := 0
	for param in result.parameters {
		input_register_count += abi_value_register_location_count(param)
	}
	inputs := B.arena_push_soa_slice(arena, #soa[]Register_Constraint, input_register_count)

	output_register_count := abi_value_register_location_count(result.result)
	outputs := B.arena_push_soa_slice(arena, #soa[]Register_Constraint, output_register_count)

	i := 0
	for param in result.parameters {
		abi_value_push_register(param, &i, inputs)
	}

	i = 0
	abi_value_push_register(result.result, &i, outputs)

	info.inputs  = inputs
	info.outputs = outputs

	info.clobbers = result.config.callee_saved

	return
}

Operator_Information :: struct {
	register_information: Register_Information,
}

@rodata
operator_information: [Operator]Operator_Information

arch_init :: proc() {
	amd64_init()
}

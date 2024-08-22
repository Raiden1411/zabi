## ConditionalJumpInstruction
Runs the jumpi instruction opcode for the interpreter.\
0x57 -> JUMPI

## ProgramCounterInstruction
Runs the pc instruction opcode for the interpreter.\
0x58 -> PC

## JumpInstruction
Runs the jump instruction opcode for the interpreter.\
0x56 -> JUMP

## JumpDestInstruction
Runs the jumpdest instruction opcode for the interpreter.\
0x5B -> JUMPDEST

## InvalidInstruction
Runs the invalid instruction opcode for the interpreter.\
0xFE -> INVALID

## StopInstruction
Runs the stop instruction opcode for the interpreter.\
0x00 -> STOP

## ReturnInstruction
Runs the return instruction opcode for the interpreter.\
0xF3 -> RETURN

## RevertInstruction
Runs the rever instruction opcode for the interpreter.\
0xFD -> REVERT

## UnknownInstruction
Instructions that gets ran if there is no associated opcode.


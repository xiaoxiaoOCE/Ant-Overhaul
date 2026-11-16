.intel_syntax noprefix
.text

# The original call supplies (FunctionHookData vector, UFunction*).
# UE4SS already holds its registry lock. Read the live vector in place.
# Only a possible name match needs the full outer-chain comparison.
.globl blueprint_name_prefilter
blueprint_name_prefilter:
    cmp dword ptr [rip + name_private_offset], 0x18
    jne fallback

    mov eax, dword ptr [rdx + 0x18]
    mov r8, qword ptr [rcx]
    mov r9, qword ptr [rcx + 8]
check_row:
    cmp r8, r9
    je missing
    mov r10, qword ptr [r8]
    cmp r10, qword ptr [r8 + 8]
    je next_row
    cmp eax, dword ptr [r10]
    je fallback
next_row:
    add r8, 0x48
    jmp check_row

missing:
    xor eax, eax
    ret

fallback:
    jmp original_lookup

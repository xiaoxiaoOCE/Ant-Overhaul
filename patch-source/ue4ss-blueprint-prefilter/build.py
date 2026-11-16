"""Build the local prefilter for the pinned UE4SS shipping DLL.

Inputs were checked against LuaMod.cpp at cdbc0b66 and the matching x64
disassembly. The only call changed is the precise script dispatch lookup in
script_hook. Registration and lookup on a possible match still use that same
original function. The leaf prefilter has no stack frame, imports or stored
registry state. A different runtime NamePrivate layout falls through.
"""

import argparse
import ctypes
import hashlib
import json
import struct
import subprocess
import tempfile
from pathlib import Path

import pefile


SOURCE = Path(__file__).with_name('prefilter.s')
OFFICIAL_SHA = 'c273e7228687b647226fd63d7ca65888d313ece6be18996ec1320d00a5efe1f8'
LOOKUP_CALL = 0x3074EF
ORIGINAL_LOOKUP = 0x2ECAF0
NAME_PRIVATE_OFFSET = 0x134C6B8


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def assemble(clang):
    with tempfile.TemporaryDirectory(prefix='eotu-blueprint-prefilter-') as temp:
        obj_path = Path(temp) / 'prefilter.obj'
        subprocess.run([str(clang), '-target', 'x86_64-pc-windows-msvc',
                        '-c', str(SOURCE), '-o', str(obj_path)], check=True)
        obj = obj_path.read_bytes()
    machine, sections, _, symbols, count, optional_size, _ = struct.unpack_from('<HHIIIHH', obj)
    require(machine == 0x8664 and optional_size == 0, 'Expected an AMD64 COFF object')
    strings = symbols + 18 * count
    for section_index in range(sections):
        start = 20 + 40 * section_index
        section, _, _, size, raw, relocs, _, reloc_count, _, _ = struct.unpack_from('<8s6I2HI', obj, start)
        if section.rstrip(b'\0') == b'.text':
            break
    else:
        raise ValueError('Assembler output lacks a text section')
    fixups = {}
    for index in range(reloc_count):
        offset, symbol_index, kind = struct.unpack_from('<IIH', obj, relocs + 10 * index)
        first, second = struct.unpack_from('<II', obj, symbols + 18 * symbol_index)
        require(first == 0, 'Expected a named external relocation')
        name = obj[strings + second:obj.index(b'\0', strings + second)].decode('ascii')
        require(4 <= kind <= 9 and 0 <= offset <= size - 4 and name not in fixups,
                'Unexpected COFF fixup')
        fixups[name] = (offset, kind - 4)
    require(set(fixups) == {'name_private_offset', 'original_lookup'}, 'Unexpected fixup targets')
    return obj[raw:raw + size], fixups


def relocate(code, fixups, address, name_private_offset, original_lookup):
    result = bytearray(code)
    for name, target in {'name_private_offset': name_private_offset,
                         'original_lookup': original_lookup}.items():
        offset, trailing_bytes = fixups[name]
        addend, = struct.unpack_from('<i', result, offset)
        end = address + offset + 4 + trailing_bytes
        struct.pack_into('<i', result, offset, target + addend - end)
    return bytes(result)


def test_leaf(code, fixups):
    """Exercise the emitted instructions in this process with synthetic rows."""
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.VirtualAlloc.argtypes = (ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong, ctypes.c_ulong)
    kernel.VirtualAlloc.restype = ctypes.c_void_p
    kernel.VirtualProtect.argtypes = (ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong,
                                      ctypes.POINTER(ctypes.c_ulong))
    kernel.VirtualFree.argtypes = (ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong)
    kernel.FlushInstructionCache.argtypes = (ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    address = kernel.VirtualAlloc(None, 4096, 0x3000, 0x04)
    require(address, 'Could not allocate the native test page')

    class Row(ctypes.Structure):
        _fields_ = [('begin', ctypes.c_void_p), ('end', ctypes.c_void_p),
                    ('callback_metadata', ctypes.c_ubyte * 56)]

    try:
        require(ctypes.sizeof(Row) == 0x48, 'Unexpected test ABI')
        valid_layout, different_layout, fallback = 0x200, 0x208, 0x210
        ctypes.memmove(address, relocate(code, fixups, 0, valid_layout, fallback), len(code))
        ctypes.memmove(address + 0x100, relocate(code, fixups, 0x100, different_layout, fallback), len(code))
        ctypes.memmove(address + valid_layout, struct.pack('<i', 0x18), 4)
        ctypes.memmove(address + different_layout, struct.pack('<i', 0x20), 4)
        # Returning the vector argument lets the test verify the tail call.
        ctypes.memmove(address + fallback, b'\x48\x89\xc8\xc3', 4)
        previous = ctypes.c_ulong()
        require(kernel.VirtualProtect(address, 4096, 0x20, ctypes.byref(previous)),
                'Could not make the native test page executable')
        require(kernel.FlushInstructionCache(kernel.GetCurrentProcess(), address, 4096),
                'Could not flush the native test page')
        abi = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
        run, unknown_layout = abi(address), abi(address + 0x100)
        names = (ctypes.c_uint32 * 4)(42, 1, 999, 0)
        ptr = ctypes.addressof(names)
        rows = (Row * 3)(Row(), Row(ptr, ptr + 16), Row(ptr + 8, ptr + 16))
        begin = ctypes.addressof(rows)
        registry = (ctypes.c_void_p * 2)(begin, begin + ctypes.sizeof(rows))
        registry_addr = ctypes.addressof(registry)
        node = (ctypes.c_uint32 * 10)()
        node_addr = ctypes.addressof(node)
        for index, expected in ((42, registry_addr), (999, registry_addr), (12, None)):
            node[6] = index
            require(run(registry_addr, node_addr) == expected, 'Name filter returned the wrong branch')
        names[0] = 12
        require(run(registry_addr, node_addr) == registry_addr, 'Registry mutation was not observed')
        registry[1] = begin
        require(run(registry_addr, node_addr) is None, 'Empty registry did not return a miss')
        require(unknown_layout(registry_addr, node_addr) == registry_addr, 'Unexpected layout did not fall through')
    finally:
        kernel.VirtualFree(address, 0, 0x8000)


def patch(original, code, fixups):
    require(sha(original) == OFFICIAL_SHA, 'Input is not the pinned official shipping DLL')
    pe = pefile.PE(data=original)
    require(pe.FILE_HEADER.Machine == 0x8664 and not pe.OPTIONAL_HEADER.DATA_DIRECTORY[4].Size,
            'Expected the original unsigned AMD64 DLL')
    text, next_section = pe.sections[:2]
    require(text.Name.rstrip(b'\0') == b'.text' and text.Characteristics == 0x60000020,
            'Unexpected code section')
    call_offset = pe.get_offset_from_rva(LOOKUP_CALL)
    old_call = b'\xe8' + struct.pack('<i', ORIGINAL_LOOKUP - LOOKUP_CALL - 5)
    require(original[call_offset:call_offset + 5] == old_call, 'Precise lookup call did not match')
    stub_start = (text.Misc_VirtualSize + 15) & ~15
    stub_end = stub_start + len(code)
    stub_rva = text.VirtualAddress + stub_start
    stub_offset = text.PointerToRawData + stub_start
    require(stub_end <= text.SizeOfRawData and text.VirtualAddress + stub_end < next_section.VirtualAddress
            and not any(original[stub_offset:stub_offset + len(code)]), 'Code padding does not fit')
    payload = relocate(code, fixups, stub_rva, NAME_PRIVATE_OFFSET, ORIGINAL_LOOKUP)

    result = bytearray(original)
    size_offset = text.get_field_absolute_offset('Misc_VirtualSize')
    struct.pack_into('<I', result, size_offset, stub_end)
    result[call_offset:call_offset + 5] = b'\xe8' + struct.pack('<i', stub_rva - LOOKUP_CALL - 5)
    result[stub_offset:stub_offset + len(payload)] = payload
    parsed = pefile.PE(data=bytes(result))
    require(parsed.sections[0].Misc_VirtualSize == stub_end
            and parsed.get_data(stub_rva, len(payload)) == payload
            and parsed.OPTIONAL_HEADER.SizeOfImage == pe.OPTIONAL_HEADER.SizeOfImage,
            'Patched PE validation failed')
    return bytes(result), {'callRva': hex(LOOKUP_CALL), 'stubRva': hex(stub_rva),
                           'originalLookupRva': hex(ORIGINAL_LOOKUP), 'stubLength': len(payload)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('official_dll', type=Path)
    parser.add_argument('output_dll', type=Path)
    parser.add_argument('--clang', type=Path, required=True)
    args = parser.parse_args()
    original = args.official_dll.read_bytes()
    code, fixups = assemble(args.clang)
    test_leaf(code, fixups)
    candidate, details = patch(original, code, fixups)
    with args.output_dll.open('xb') as stream:
        stream.write(candidate)
    print(json.dumps(dict(details, officialSha256=sha(original), candidateSha256=sha(candidate),
                          leafAbiTestsPassed=True), indent=2))


if __name__ == '__main__':
    main()

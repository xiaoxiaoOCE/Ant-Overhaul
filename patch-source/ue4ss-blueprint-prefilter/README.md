# Exact UE4SS dependency and local prefilter patch

Ant Overhaul 0.2.0 uses a **locally patched** UE4SS binary. Do not describe it as an unchanged upstream dependency.

## Upstream input

- Project: https://github.com/UE4SS-RE/RE-UE4SS
- Commit: `cdbc0b66cb2bb5b4a3d2f69b6e61a8460961e54c`
- Release identity: `v3.0.1-1183-gcdbc0b66`
- Official archive: https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/zDEV-UE4SS_v3.0.1-1183-gcdbc0b66.zip
- Archive SHA256: `2b634e7e1446b360599c01419d8ca14823a5138fa7fdf8f7fc28a50a13054908`
- Input `ue4ss/UE4SS.dll` SHA256: `c273e7228687b647226fd63d7ca65888d313ece6be18996ec1320d00a5efe1f8`
- Patched output SHA256: `46c90c1a89a778da039f397681c4f6b34cb046d6e8c81f5881c09f5515685c9d`

The upstream developer archive and its DLL/LICENSE/proxy members were independently rechecked during this audit. Both DLLs are20,641,280 bytes; the official and patched DLL differ at56 bytes. `dwmapi.dll` remains byte-identical to the same official archive (`f8bec398fcbb2e3e8d1ef2875cafcc15d09f82073402fc9879a9cbf78b8d9514`).

## Patch source and regular build

Include `patch-source/ue4ss-blueprint-prefilter/build.py` and `prefilter.s` in the source-review archive. They are the actual authored patch inputs, not a replacement explanation of the binary.

Requirements: Python3, `pefile`, and LLVM `clang` capable of AMD64 MSVC COFF assembly. Example from the source-review root:

```powershell
python -m pip install pefile
python patch-source/ue4ss-blueprint-prefilter/build.py path/to/original/UE4SS.dll build/UE4SS.dll --clang path/to/clang.exe
```

The output directory must exist and the output file must not already exist. The script pins the official input hash, assembles `prefilter.s`, validates the COFF relocations, runs synthetic leaf ABI checks, then changes only a precise script-hook lookup call and uses existing code padding for the52-byte prefilter. Unsupported NamePrivate layout takes the original lookup. Possible name matches still use the original full lookup. It does not cache hook results or patch game/DLC ownership.

## What this audit reproduced

The existing authored `patch()` function was executed on the exact official input with the52-byte canonical leaf instruction encoding and two COFF-style fixups; its in-memory result was **byte-identical** to the installed patched output. `patch-source/ue4ss-blueprint-prefilter/provenance.json` records the exact input/output, source hashes, leaf bytes and fixups. No DLL was copied to a runtime or formal install.

The final release audit located the existing Unity-bundled LLVM14 compiler and ran the **actual authored build.py and prefilter.s** against the exact official DLL. The script freshly assembled the AMD64 COFF object, ran its original synthetic leaf ABI tests, applied the patch, and produced SHA256 `46c90c1a89a778da039f397681c4f6b34cb046d6e8c81f5881c09f5515685c9d`, byte-identical to both the current formal DLL and the frozen0.2.0 payload. The release freeze manifest remained unchanged. See `patch-source/ue4ss-blueprint-prefilter/provenance.json` for the full command, compiler hash and build evidence. This reproduces the local binary patch; it is **not** a full UE4SS C++ source compilation.

MIT copyright/license notices remain included verbatim at `ue4ss/LICENSE`. The added Ant Overhaul patch should be identified as a local modification when distributing this dependency.

## Verified compiler

The release verification used an existing Unity-bundled LLVM14 assembler targeting AMD64 MSVC COFF. Its version and SHA256 are in provenance.json. Use your own installed LLVM clang path in the command above; no machine-specific installation path is required.

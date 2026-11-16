# Ant Overhaul 0.2.0 — source review and reproducibility package

This archive is for code review and rebuilding. It is **not** the playable/manual installation package. It contains no EXE, DLL, nested ZIP, player saves, local preferences or game logs. The 14 cooked animation/particle files are intentional binary asset inputs, not executable programs.

## Contents

- `mod-source/AllAttributes/Scripts/`: all 56 Lua modules, byte-identical to the0.2.0 runtime payload.
- `release-manifest.json`: portable public file/version/hash metadata. Local install records and backup locations are removed; payload paths are relative.
- `assets/cooked/` and `assets/manifest.json`: only the 14 modified cooked resource files from AntOverhaul_P.pak. No whole base-game archive is included.
- `tools/build-assets-pak.py`: standard-library Python builder for the exact merged resource PAK.
- `patch-source/ue4ss-blueprint-prefilter/`: the actual Python/assembly patch source, sanitized provenance and rebuild instructions for the locally modified UE4SS dependency.
- `third-party/UE4SS-LICENSE.txt` and `ThirdPartyNotices.txt`: upstream license and truthful modification notices.
- `installer/`: the source-only C#/PowerShell/Python installer build inputs, branding resources and exact source inventory.

## Verify the source inventory

```powershell
python tools/verify-source-package.py
```

This reads the supplied source hashes and makes no game/system changes. It does not treat later build outputs as source inputs.

## Verify/rebuild the resource PAK

Python3.9+ is sufficient; no Unreal Engine SDK is needed because the included inputs are already cooked for the game. From this archive root:

```powershell
python tools/build-assets-pak.py --verify-only
python tools/build-assets-pak.py
```

The second command creates `build/AntOverhaul_P.pak` and refuses to overwrite an existing output. Its SHA256 must be `8a16803ad152c46c0b2c213c708beff59c0a5223800e2821d84d8ca00b5d3e62`. Paths, mount point and exact input hashes are in assets/manifest.json. The release audit also inspected this PAK using upstream repak 0.2.3 and loaded all 7 asset objects in an isolated game. Loading proves the asset paths/types; it is not a new exhaustive playback test of every gameplay mechanic.

## Reproduce the patched UE4SS dependency

Follow `patch-source/ue4ss-blueprint-prefilter/README.md`. Obtain the pinned official upstream DLL separately, verify its hash, then run the supplied patch builder with Python, pefile and an LLVM clang assembler. The original build script and assembly were actually run during release verification, including synthetic ABI tests; the output matched the runtime payload byte for byte. This is a reproducible local patch of the official binary, not a fresh full C++ compilation of UE4SS.

UE4SS remains a third-party runtime dependency and the included binary in the playable distribution is locally modified. The64-bit proxy, UE4SS DLL, media and other runtime assets are supplied by the separate manual package and intentionally omitted here. Putting the Lua files into a PAK would not make the present UE4SS scripts execute automatically.

## Rebuild the installer

Requirements: Windows, Python 3.10+, Microsoft .NET Framework 4.8 C# compiler/reference assemblies, and the separate matching manual package. No installer EXE/DLL/payload ZIP is hidden in this source archive.

Extract the matching Ant Overhaul 0.2.0 manual package separately. Its top level may include a manager and documentation; the builder requires a clean directory containing **only the 67 pinned runtime files**. Stage that directory with the supplied helper, which verifies every input before copying and refuses an existing destination:

```powershell
python tools/stage-runtime-input.py --manual path/to/extracted-manual-package
```

This creates `build/runtime-payload/`. It writes only the new output directory; it does not install into the game or alter the separately extracted manual package. `release-manifest.json` points at this relative directory.

From the source-review root, use the exported installer project and explicit helper inputs:

```powershell
$source = (Get-Location).Path
$freeze = Join-Path $source 'release-manifest.json'
$freezeSha = (Get-FileHash -LiteralPath $freeze -Algorithm SHA256).Hash.ToLowerInvariant()
& (Join-Path $source 'installer/release-builder/Build-Installer-0.2.0.ps1') `
  -FreezeManifest $freeze -ExpectedFreezeSha256 $freezeSha `
  -ProjectRoot (Join-Path $source 'installer') `
  -PayloadRoot (Join-Path $source 'build/runtime-payload') `
  -OutputRoot (Join-Path $source 'build/installer-output') `
  -HealthReference (Join-Path $source 'installer/installer-src/uninstall/health-reference-0.1.18.json') `
  -AutoPrepareSource (Join-Path $source 'installer/installer-src/uninstall/AutoPrepare-0.1.18.cs') `
  -SavePatcherSource (Join-Path $source 'installer/installer-src/uninstall/SavePatcher-0.1.18.cs')
```

The output directory must not already exist. The helper filenames retain `0.1.18` because those reviewed implementations are intentionally reused unchanged; the installer generator targets 0.2.0 and the 67-file release manifest. The selected legacy UI inputs are exported directly into `installer-src/ui`; build transformations are explicit in the supplied builder/generator. See `installer/installer-source-manifest.json` for the full source inventory.

The regular build creates its own temporary build tree, compiles the manager/helper/UI, and embeds the separately supplied verified runtime payload. It does not require a personal game installation as a build input. Matching source and inputs do not by themselves guarantee byte-identical PE timestamps or compiler output across machines. The release's recorded binary hashes identify the audited build; no blanket bit-identical PE rebuild promise is made.

No public 0.1.18 files were overwritten when preparing this package.

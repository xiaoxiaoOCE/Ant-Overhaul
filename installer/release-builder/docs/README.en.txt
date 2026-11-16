Ant Overhaul 0.2.0 — Empires of the Undergrowth
Mod page: https://www.nexusmods.com/empiresoftheundergrowth/mods/29

This release combines a genuine Unreal asset PAK with the UE4SS scripts that implement the mod's gameplay and interface. Both are required. It targets the tested Steam build 26412732 (game 1.2.1.1.0.5).

INSTALL / UPDATE (recommended)
1. Save and close the game. Back up the complete EotU Saved/SaveGames folder, including EAA_ records.
2. Run AntOverhaul-0.2.0-Setup.exe and choose the game folder containing EotU.exe.
3. Install or update, then launch normally from Steam. Supported old installations are backed up and verified before replacement. Only the three verified old Ant Overhaul asset PAKs are replaced by AntOverhaul_P.pak; unrelated PAKs are preserved.
The installer stops if files differ from its known baseline. Keep the error and current files rather than forcing an overwrite.

MANUAL ZIP (new installation)
Extract to a temporary folder first. Copy EotU, AntOverhaul-Manager and the three management CMD files together into the game root. Do not overwrite another loader or an existing mod installation. Run Register-Manual-Install.cmd to verify and register the copy. Use the EXE installer to upgrade an older version.

UNINSTALL
Close the game, then use the installer's Uninstall button or Uninstall-Mod.cmd. The automatic helper checks and backs up affected current formicarium saves before removing matching mod files. Cultivation/skill records and backup saves are retained. No in-game uninstall hotkey is required. Pending purchases, changed saves or unsupported data stop the process safely.
Extra units, captured creatures and their native buildings are not guaranteed to behave fully in an unmodified game. Keep a complete backup; reinstalling after saving without the mod does not guarantee restoration of the previous state.

This package does not claim that all large-battle stutter is fixed. The unfinished performance experiments and deferred story-mission saving work are not included.

REPORT A PROBLEM
Include the mod version, Steam build, steps, a screenshot and EotU/Binaries/Win64/ue4ss/UE4SS.log. If needed, share a private copy of the complete SaveGames folder. Never post your private saves publicly.

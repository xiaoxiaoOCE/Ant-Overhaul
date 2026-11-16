"""Export the exact source-only installer build inputs in portable layout."""
from pathlib import Path
import argparse,hashlib,json,shutil
PROJECT=Path(__file__).resolve().parent.parent;WORK=Path(__file__).parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 global PROJECT
 ap=argparse.ArgumentParser();ap.add_argument('--out',required=True);ap.add_argument('--project',default=str(PROJECT));args=ap.parse_args();PROJECT=Path(args.project).resolve();assert(PROJECT/'installer-src').is_dir(),'Pass --project pointing at the installer source tree';out=Path(args.out).resolve();assert not out.exists();out.mkdir(parents=True)
 pairs=[]
 for n in ['Build-Installer-0.2.0.ps1','prepare_runtime.py','RuntimePolicy.ps1.in','docs/README.en.txt','docs/README.zh-CN.txt','export_sources.py']:
  pairs.append((WORK/n,'release-builder/'+n))
 for n in ['delivery-src/Manage-Mod-0.1.18.ps1','delivery-src/Update-Mod-0.1.18.ps1','installer-src/backend/Backend-0.1.18.ps1','installer-src/uninstall/AutoPrepare-0.1.18.cs','installer-src/uninstall/SavePatcher-0.1.18.cs','installer-src/uninstall/health-reference-0.1.18.json','installer-src/app.manifest','installer-src/ManualManager.ps1','installer-src/assets/EotU-Steam-Logo.png','installer-src/assets/NexusMods-Icon.png']:
  pairs.append((PROJECT/n,n))
 for p in sorted((PROJECT/'installer-src/ui').glob('*.cs')):
  override=PROJECT/'installer-src/ui/0.1.18'/p.name
  pairs.append((override if override.exists()else p,'installer-src/ui/'+p.name))
 records=[]
 for src,relative in pairs:
  assert src.suffix.lower()not in ['.exe','.dll','.zip','.pak','.sav']
  dst=out/relative;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
  assert sha(dst)==sha(src);records.append({'path':relative,'sha256':sha(dst),'length':dst.stat().st_size})
 result={'schema':1,'release':'0.2.0','sourceOnly':True,'files':records,'noPayloadBinaries':True,
 'rebuild':'Use release-builder/Build-Installer-0.2.0.ps1 with -ProjectRoot pointing at this exported directory, explicit final -FreezeManifest and -ExpectedFreezeSha256, -PayloadRoot pointing at a separately obtained directory containing only the 67 frozen payload files, and explicit helper/reference paths under installer-src/uninstall. OutputRoot must be a new directory.',
 'requirements':['Windows','Python3.10+','Microsoft .NET Framework4.8 csc and reference assemblies','Separate complete frozen payload including genuine asset PAK and audited UE4SS DLL; neither is hidden in this source-only export.'],
 'uiSelection':'Selected legacy 0.1.18 overrides are exported into installer-src/ui directly. Builder only changes 0.1.18→0.2.0 and Nexus link to mods/29; original layout, logo pixels and controls preserved.'}
 (out/'installer-source-manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({'files':len(records),'manifest':str(out/'installer-source-manifest.json')}))
if __name__=='__main__':main()

"""Create reviewed release-specific runtime scripts from pinned legacy sources.
Only writes this release's own work/output directories; no formal installation.
"""
from pathlib import Path
import argparse,hashlib,json,re,datetime,shutil
ROOT=Path(__file__).resolve().parent.parent
WORK=Path(__file__).parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def replace_function(s,name,body):
    match=re.search(r'^function '+re.escape(name)+r'(?=[\s(])',s,re.M)
    assert match,name
    following=re.search(r'^function ',s[match.end():],re.M)
    assert following,name+' has no following function'
    end=match.end()+following.start()
    return s[:match.start()]+body.rstrip()+'\n'+s[end:]
def replace_once(s,old,new):
    assert s.count(old)==1,(old[:100],s.count(old))
    return s.replace(old,new)
def fresh(path,text,bom=False):
    assert not path.exists(),path
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text,encoding='utf-8-sig' if bom else 'utf-8',newline='\r\n'if bom else '\n')
def read_legacy(path):return path.read_text(encoding='utf-8-sig')
def normalize(m):
    return {k:m.get(k) for k in ('schema','modId','release','buildId','gameVersion')}|{'files':m['files']}
def main():
 global ROOT
 ap=argparse.ArgumentParser();ap.add_argument('--package',required=True);ap.add_argument('--freeze',required=True);ap.add_argument('--health-reference',required=True);ap.add_argument('--helper',required=True);ap.add_argument('--project',default=str(ROOT))
 args=ap.parse_args();ROOT=Path(args.project).resolve();package=Path(args.package).resolve();freeze_path=Path(args.freeze).resolve();freeze=json.loads(freeze_path.read_text(encoding='utf-8-sig'));release=freeze['release']
 assert release=='0.2.0' and freeze['schema']==1
 manifest_path=package/'manifest.json';manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
 assert manifest['release']==release and manifest['files']==freeze['files']
 baseline_rows=freeze.get('baselines',[]);baselines=[]
 for r in baseline_rows:
  m=r.get('manifest',r)
  if 'path'in m:
   p=Path(m['path']);assert sha(p)==m['sha256'];m=json.loads(p.read_text(encoding='utf-8-sig'))
  baselines.append(normalize(m))
 target=normalize(manifest);allpaths=sorted({f['path']for m in [target]+baselines for f in m['files']})
 for p in allpaths:
  assert not p.startswith(('/','\\')) and ':'not in p and '..'not in p.split('/')
  assert p.startswith('EotU/Binaries/Win64/')or p.startswith('EotU/Content/Movies/EAA_')or p.startswith('EotU/Content/Paks/')
  assert not p.startswith('EotU/Content/Paks/pakchunk')
 policy={'schema':1,'modId':'EotU.AllAttributes.v1','release':release,'manifestSha256':sha(manifest_path),'freezeSha256':sha(freeze_path),'updateSha256':sha(package/'update.json'),'target':target,'baselines':baselines,'allPaths':allpaths,
   'uninstallComponents':{'AutoPrepare.exe':sha(Path(args.helper)),'health-reference.json':sha(Path(args.health_reference))}}
 policy_file=package/'release-policy.json';fresh(policy_file,json.dumps(policy,ensure_ascii=False,indent=2))
 common=(WORK/'RuntimePolicy.ps1.in').read_text().replace('@@POLICY_SHA@@',sha(policy_file)).replace('@@RELEASE@@',release)
 fresh(package/'RuntimePolicy.ps1',common,True)
 old_manager=ROOT/'delivery-src/Manage-Mod-0.1.18.ps1';old_update=ROOT/'delivery-src/Update-Mod-0.1.18.ps1';old_backend=ROOT/'installer-src/backend/Backend-0.1.18.ps1'
 manager=read_legacy(old_manager)
 manager=manager.replace("$modId = 'EotU.AllAttributes.v1'","$modId = 'EotU.AllAttributes.v1'\n. (Join-Path $PSScriptRoot 'RuntimePolicy.ps1')")
 manager=replace_function(manager,'Hash-File',"function Hash-File([string]$Path) {return PolicyHash $Path}")
 manager=replace_function(manager,'Release-Modules',r'''function Release-Modules([string]$Release) {
 $names=@();foreach($m in @($script:ReleasePolicy.target)+@($script:ReleasePolicy.baselines)){if($m.release -ceq $Release){$names+=@($m.files|Where-Object path -like '*/Scripts/*.lua'|ForEach-Object{[IO.Path]::GetFileName($_.path)})}}
 if(-not $names.Count){throw 'Unsupported frozen release'};return @($names|Sort-Object -Unique)
}''')
 manager=replace_function(manager,'Assert-AllowedPayload',r'''function Assert-AllowedPayload([string]$Relative,[string]$Release) {PolicyAllowed $Relative $Release}''')
 manager=replace_function(manager,'Read-Manifest',r'''function Read-Manifest {
 $manifest=PolicyReadTarget
 foreach($f in @($manifest.files)){$source=Resolve-Child (Resolve-Child $script:PackageRoot 'payload') $f.path;Assert-NoReparse $source;if(-not(Test-Path -LiteralPath $source -PathType Leaf) -or (Hash-File $source) -cne $f.sha256 -or (Get-Item -LiteralPath $source).Length -ne $f.length){throw ('Payload integrity failed: '+$f.path)}}
 return $manifest
}''')
 manager=replace_once(manager,"    if (@($record.files).Count -ne (5+@(Release-Modules $record.release).Count)) { throw 'Incomplete installation record; refusing to change files.' }","    [void](PolicyMap $record)")
 manager=replace_once(manager,"        if ($p -notmatch '^EotU/Binaries/Win64/ue4ss(?:/Mods(?:/AllAttributes(?:/Scripts)?)?)?$') { throw 'Invalid created-directory record.' }","        if ($p -cnotin @(PolicyDirectories @($script:ReleasePolicy.target.files)+@($script:ReleasePolicy.baselines|ForEach-Object files))) { throw 'Invalid created-directory record.' }")
 manager=replace_once(manager,"    $plannedDirs = @('EotU/Binaries/Win64/ue4ss','EotU/Binaries/Win64/ue4ss/Mods','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts')","    $plannedDirs = @(PolicyNewDirectories $manifest.files)")
 manager=replace_once(manager,"    $script:SaveGamesRoot = [IO.Path]::GetFullPath($SaveGamesRoot).TrimEnd('\\','/')","    $script:SaveGamesRoot = [IO.Path]::GetFullPath($SaveGamesRoot).TrimEnd('\\','/')\n    $script:ReleasePolicy=ReadReleasePolicy")
 fresh(package/'Manage-Mod.ps1',manager,True)
 update=read_legacy(old_update).replace("$toRelease='0.1.18'","$toRelease='0.2.0'\n. (Join-Path $PSScriptRoot 'RuntimePolicy.ps1')")
 update,count=re.subn(r'(?ms)^\$baseModules=.*?^\$permittedModules=\$baseModules\n','',update,count=1);assert count==1
 update=update.replace(' 个模块',' 个文件')
 update=replace_function(update,'Sha',"function Sha([string]$Path){return PolicyHash $Path}")
 update=replace_function(update,'File-Map',"function File-Map($Manifest) {return PolicyMap $Manifest}")
 update=replace_function(update,'Verify-Freeze',r'''function Verify-Freeze($ToMap) {
 if((Sha $script:FreezeManifest) -cne $script:ReleasePolicy.freezeSha256){throw 'Release freeze integrity mismatch'}
 $freeze=Json $script:FreezeManifest
 if($freeze.schema -ne 1 -or $freeze.release -cne $toRelease -or $freeze.state -cne 'frozen'){throw 'Release is not frozen'}
 [void](PolicyMap $freeze)
}''')
 update=replace_function(update,'Read-Spec',r'''function Read-Spec {
 $bundlePath=Child $script:PackageRoot 'update.json'
 if((Sha $bundlePath) -cne $script:ReleasePolicy.updateSha256){throw 'Update catalog integrity mismatch'}
 $bundle=Json $bundlePath
 if($bundle.schema -ne 2 -or $bundle.modId -cne $modId -or $bundle.toRelease -cne $toRelease){throw 'Wrong update catalog'}
 $target=PolicyReadTarget;$to=File-Map $target;Verify-Freeze $to
 [void](PolicyMap $bundle.toManifest)
 if(($target.files|ConvertTo-Json -Depth 20 -Compress) -cne ($bundle.toManifest.files|ConvertTo-Json -Depth 20 -Compress)){throw 'Update target differs'}
 $record=Json (Child $script:GameRoot $recordName)
 if($Action -eq 'Rollback'){$ref=Json (Child $script:GameRoot $pendingName);$record=Json (Child (Backup-Path $ref.backup) 'record-before.json')}
 $matched=@()
 foreach($r in @($bundle.routes)) {
  [void](File-Map $r.fromManifest)
  if($record.release -cne $r.fromRelease -or [string]$record.buildId -cne [string]$r.fromManifest.buildId -or @($record.files).Count -ne @($r.fromManifest.files).Count){continue}
  $from=File-Map $r.fromManifest;$same=$true;$seen=@{}
  foreach($f in @($record.files)){if(-not $from.ContainsKey($f.path) -or $seen.ContainsKey($f.path) -or $f.sha256 -cne $from[$f.path].sha256 -or $f.length -ne $from[$f.path].length){$same=$false;break};$seen[$f.path]=$true}
  if($same){$matched+=@($r)}
 }
 if($matched.Count -ne 1){throw 'No unique exact update baseline matches'}
 $route=$matched[0];$from=File-Map $route.fromManifest;$expected=@{}
 foreach($p in $from.Keys){if(-not $to.ContainsKey($p)){$expected[$p]='remove'}}
 foreach($p in $to.Keys){if(-not $from.ContainsKey($p)){$expected[$p]='add'}elseif($from[$p].sha256 -cne $to[$p].sha256){$expected[$p]='replace'}elseif($from[$p].length -ne $to[$p].length){throw 'Unchanged file length differs'}}
 $seen=@{}
 foreach($e in @($route.changes)){
  $p=[string]$e.path
  if(-not $expected.ContainsKey($p) -or $seen.ContainsKey($p) -or $e.operation -cne $expected[$p]){throw 'Update delta mismatch'}
  if($from.ContainsKey($p)){if($e.oldSha256 -cne $from[$p].sha256){throw 'Wrong preimage'}}elseif($null -ne $e.oldSha256){throw 'Unexpected old hash'}
  if($to.ContainsKey($p)){if($e.newSha256 -cne $to[$p].sha256){throw 'Wrong new hash'}}elseif($null -ne $e.newSha256){throw 'Unexpected replacement hash'}
  if($e.operation -eq 'remove' -and $p -cnotin @('EotU/Content/Paks/EAA_DriverExecution_P.pak','EotU/Content/Paks/EAA_RendBlood_P.pak','EotU/Content/Paks/EAA_TrapjawSting_P.pak')){throw 'Only the three owned legacy asset PAKs may be removed'}
  $seen[$p]=$true
 }
 if($seen.Count -ne $expected.Count){throw 'Incomplete update delta'}
 foreach($p in $to.Keys){$source=Child (Child $script:PackageRoot 'payload') $p;if((Sha $source) -cne $to[$p].sha256 -or (Get-Item -LiteralPath $source).Length -ne $to[$p].length){throw 'Target payload changed'}}
 return [pscustomobject]@{schema=1;modId=$modId;fromRelease=$route.fromRelease;toRelease=$toRelease;fromManifest=$route.fromManifest;toManifest=$target;changes=$route.changes;routeId=$route.id}
}''')
 update=replace_function(update,'Backup-Module',r'''function Backup-Module([string]$Backup,[string]$Area,[string]$Relative){
 if($Area -cnotin @('old','new') -or $Relative -cnotin @($script:ReleasePolicy.allPaths)){throw 'Unknown backup identity'}
 $index=[Array]::IndexOf([object[]]$script:ReleasePolicy.allPaths,$Relative);if($index-lt0){throw 'Unknown indexed backup path'}
 return Child (Child $Backup $Area) ('file-'+$index.ToString('D4'))
}''')
 update=replace_function(update,'Addition-Receipt',r'''function Addition-Receipt([string]$Backup,[string]$Relative){
 if($Relative -cnotin @($script:ReleasePolicy.allPaths)){throw 'Unknown ownership receipt'}
 $index=[Array]::IndexOf([object[]]$script:ReleasePolicy.allPaths,$Relative);if($index-lt0){throw 'Unknown indexed receipt path'}
 return Child $Backup ('created-'+$index.ToString('D4')+'.json')
}''')
 update=replace_once(update,"    No-Link $script:GameRoot;No-Link $script:PackageRoot;Stopped","    No-Link $script:GameRoot;No-Link $script:PackageRoot;Stopped\n    $script:ReleasePolicy=ReadReleasePolicy")
 update=replace_once(update,"        $actual=Sha (Child $script:GameRoot $path)","        $targetPath=Child $script:GameRoot $path;$actual=$null;if(Test-Path -LiteralPath $targetPath){$actual=Sha $targetPath}")
 update=replace_once(update,"            if($actual -notin @($entry.oldSha256,$entry.newSha256)){throw \"Changed update target must be preserved: $path\"}","            if($entry.operation -eq 'remove'){if($null -ne $actual -and $actual -cne $entry.oldSha256){throw \"Changed removed target: $path\"}}elseif($actual -notin @($entry.oldSha256,$entry.newSha256)){throw \"Changed update target must be preserved: $path\"}")
 update=replace_once(update,"        }elseif((Sha $target) -eq $entry.newSha256){Atomic-Replace (Backup-Module $backup 'old' $entry.path) $target $entry.newSha256 $entry.oldSha256}","        }elseif($entry.operation -eq 'remove'){if(-not(Test-Path -LiteralPath $target)){Atomic-Create (Backup-Module $backup 'old' $entry.path) $target $entry.oldSha256 (Addition-Receipt $backup $entry.path) $entry.path}}elseif((Sha $target) -eq $entry.newSha256){Atomic-Replace (Backup-Module $backup 'old' $entry.path) $target $entry.newSha256 $entry.oldSha256}")
 update=replace_once(update,"    Verify-Installation (Json $recordPath) $Spec.fromManifest","    foreach($dir in @($after.createdDirectories|Where-Object {$_ -cnotin @($old.createdDirectories)}|Sort-Object Length -Descending)){$path=Child $script:GameRoot $dir;No-Link $path;if((Test-Path -LiteralPath $path -PathType Container) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0){[IO.Directory]::Delete($path,$false)}}\n    Verify-Installation (Json $recordPath) $Spec.fromManifest")
 update=replace_once(update,"        if($entry.operation -eq 'replace'){Copy-Exact (Child $script:GameRoot $entry.path) (Backup-Module $backup 'old' $entry.path) $entry.oldSha256}\n        Copy-Exact (Child (Child $script:PackageRoot 'payload') $entry.path) (Backup-Module $backup 'new' $entry.path) $entry.newSha256","        if($entry.operation -in @('replace','remove')){Copy-Exact (Child $script:GameRoot $entry.path) (Backup-Module $backup 'old' $entry.path) $entry.oldSha256}\n        if($entry.operation -ne 'remove'){Copy-Exact (Child (Child $script:PackageRoot 'payload') $entry.path) (Backup-Module $backup 'new' $entry.path) $entry.newSha256}")
 update=replace_once(update,"    $record.release=$spec.toRelease;$record.files=$spec.toManifest.files;$record.buildId=$spec.toManifest.buildId","    $newDirs=@(PolicyNewDirectories $spec.toManifest.files)\n    $record.createdDirectories=@(@($record.createdDirectories)+$newDirs|Sort-Object -Unique)\n    $record.release=$spec.toRelease;$record.files=$spec.toManifest.files;$record.buildId=$spec.toManifest.buildId")
 update=replace_once(update,"    try{\n        foreach($entry in @($spec.changes)){","    try{\n        foreach($dir in @($newDirs|Sort-Object Length)){$path=Child $script:GameRoot $dir;No-Link $path;if(Test-Path -LiteralPath $path){throw 'New directory appeared'};[void][IO.Directory]::CreateDirectory($path)}\n        foreach($entry in @($spec.changes)){")
 update=replace_once(update,"            else{Atomic-Replace (Backup-Module $backup 'new' $entry.path) (Child $script:GameRoot $entry.path) $entry.oldSha256 $entry.newSha256}","            elseif($entry.operation -eq 'remove'){$target=Child $script:GameRoot $entry.path;Stopped;No-Link $target;if((Sha $target) -cne $entry.oldSha256){throw 'Legacy PAK changed before removal'};[IO.File]::Delete($target)}\n            else{Atomic-Replace (Backup-Module $backup 'new' $entry.path) (Child $script:GameRoot $entry.path) $entry.oldSha256 $entry.newSha256}")
 fresh(package/'Update-Mod.ps1',update,True)
 backend=read_legacy(old_backend).replace("$release='0.1.18'","$release='0.2.0'\n. (Join-Path $PSScriptRoot 'RuntimePolicy.ps1')").replace('0.1.18','0.2.0')
 backend=replace_function(backend,'ExpectedPaths',"function ExpectedPaths {return @($script:ReleasePolicy.target.files|ForEach-Object path)}")
 backend=replace_function(backend,'ReadManifest',"function ReadManifest {return PolicyReadTarget}")
 backend=replace_once(backend,"    $dirs=@('EotU/Binaries/Win64/ue4ss','EotU/Binaries/Win64/ue4ss/Mods','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts')","    $dirs=@(PolicyDirectories $Manifest.files)")
 backend=replace_once(backend,"$pending.Push((Child $script:GameRoot $dirs[0]))","$pending.Push((Child $script:GameRoot 'EotU/Binaries/Win64/ue4ss'))")
 backend=replace_once(backend,"createdDirectories=@('EotU/Binaries/Win64/ue4ss','EotU/Binaries/Win64/ue4ss/Mods','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts')","createdDirectories=@(PolicyDirectories $Manifest.files|Where-Object {$_.StartsWith('EotU/Binaries/Win64/ue4ss',[StringComparison]::Ordinal)})")
 backend=backend.replace('36 个模组文件','冻结清单中的全部模组文件')
 backend=replace_once(backend,"    $result.gameRoot=$GameRoot","    $result.gameRoot=$GameRoot\n    $script:ReleasePolicy=ReadReleasePolicy")
 backend=replace_once(backend,"    foreach($path in @($helper,$reference)){NoLink $path;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '安装器缺少自动卸载组件，请重新下载完整安装器。'}}","    foreach($path in @($helper,$reference)){NoLink $path;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '安装器缺少自动卸载组件，请重新下载完整安装器。'};if((Sha $path) -cne $script:ReleasePolicy.uninstallComponents.PSObject.Properties[[IO.Path]::GetFileName($path)].Value){throw '自动卸载组件校验失败。'}}")
 fresh(package/'Backend.ps1',backend,True)
 source_meta={(p.relative_to(ROOT).as_posix()if p.is_relative_to(ROOT)else'installer/'+p.name):sha(p)for p in (old_manager,old_update,old_backend,WORK/'RuntimePolicy.ps1.in',Path(__file__))}
 fresh(package/'installer-runtime-provenance.json',json.dumps({'release':release,'sources':source_meta,'generated':[{'name':n,'sha256':sha(package/n)}for n in ('RuntimePolicy.ps1','Manage-Mod.ps1','Update-Mod.ps1','Backend.ps1')],'formalFilesWritten':False,'createdUtc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2))
 print(json.dumps({'runtimePrepared':True,'release':release,'targetFiles':len(manifest['files']),'baselines':len(baselines),'policySha256':sha(policy_file)}))
if __name__=='__main__':main()

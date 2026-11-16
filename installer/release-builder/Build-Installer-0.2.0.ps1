[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$FreezeManifest,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedFreezeSha256,
 [string]$ProjectRoot='',
 [string]$PayloadRoot='',
 [string]$OutputRoot=(Join-Path $PSScriptRoot 'artifacts'),
 [string]$HealthReference='',
 [string]$AutoPrepareSource='',
 [string]$SavePatcherSource=''
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectRoot)){$ProjectRoot=Split-Path -Parent $PSScriptRoot}
$antProject=[IO.Path]::GetFullPath($ProjectRoot)
$antSrc=Join-Path $antProject 'installer-src'
if(-not(Test-Path -LiteralPath $antSrc -PathType Container)){throw 'Pass -ProjectRoot pointing at the source tree containing installer-src and delivery-src'}
if([string]::IsNullOrWhiteSpace($HealthReference)){$HealthReference=Join-Path $antSrc 'uninstall\health-reference-0.1.18.json'}
if([string]::IsNullOrWhiteSpace($AutoPrepareSource)){$AutoPrepareSource=Join-Path $antSrc 'uninstall\AutoPrepare-0.1.18.cs'}
if([string]::IsNullOrWhiteSpace($SavePatcherSource)){$SavePatcherSource=Join-Path $antSrc 'uninstall\SavePatcher-0.1.18.cs'}
$antWork=[IO.Path]::GetFullPath($PSScriptRoot)
$utf8=New-Object Text.UTF8Encoding($false);$bom=New-Object Text.UTF8Encoding($true)
function NoLink([string]$p){$p=[IO.Path]::GetFullPath($p);while($p){if((Test-Path -LiteralPath $p)-and((Get-Item -LiteralPath $p -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Reparse point refused'};$n=Split-Path -Parent $p;if($n-eq$p){break};$p=$n}}
function Child([string]$r,[string]$p){if([IO.Path]::IsPathRooted($p)-or$p-match'(^|[\\/])\.\.?([\\/]|$)|:|[\x00-\x1f]'){throw 'Unsafe relative path'};$b=[IO.Path]::GetFullPath($r).TrimEnd('\','/');$x=[IO.Path]::GetFullPath((Join-Path $b $p));if(-not$x.StartsWith($b+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped root'};NoLink $x;return $x}
function Sha([string]$p){NoLink $p;return(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Fresh([string]$p,[string]$s,[bool]$WithBom=$false){NoLink $p;if(Test-Path -LiteralPath $p){throw ('Preserving existing output '+$p)};[void][IO.Directory]::CreateDirectory((Split-Path -Parent $p));$enc=$utf8;if($WithBom){$enc=$bom};[IO.File]::WriteAllText($p,$s,$enc)}
function CopyExact([string]$s,[string]$d,[string]$hash){if((Sha $s)-cne$hash){throw 'Source drift'};NoLink $d;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $d));[IO.File]::Copy($s,$d,$false);if((Sha $d)-cne$hash){throw 'Copy integrity failure'}}
NoLink $FreezeManifest
if((Sha $FreezeManifest)-cne$ExpectedFreezeSha256){throw 'Freeze SHA differs from explicit approved input'}
$freeze=Get-Content -LiteralPath $FreezeManifest -Raw -Encoding UTF8|ConvertFrom-Json
if($freeze.schema-ne1-or$freeze.state-cne'frozen'-or$freeze.release-cne'0.2.0'-or$freeze.modId-cne'EotU.AllAttributes.v1'-or[string]$freeze.appId-cne'463530'){throw 'A final frozen 0.2.0 payload is required'}
$payloadValue=[string]$freeze.payloadRoot;if(-not[IO.Path]::IsPathRooted($payloadValue)){$payloadValue=Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($FreezeManifest))) $payloadValue};$payload=[IO.Path]::GetFullPath($payloadValue);if(-not[string]::IsNullOrWhiteSpace($PayloadRoot)){$payload=[IO.Path]::GetFullPath($PayloadRoot)};NoLink $payload
$expected=@{};foreach($f in @($freeze.files)){if($expected.ContainsKey($f.path)-or$f.sha256-cnotmatch'^[0-9a-f]{64}$'-or$f.length-lt0){throw 'Invalid/duplicate freeze file'};$p=Child $payload $f.path;if((Sha $p)-cne$f.sha256-or(Get-Item -LiteralPath $p).Length-ne$f.length){throw ('Frozen payload changed '+$f.path)};$expected[$f.path]=$true}
$actual=@(Get-ChildItem -LiteralPath $payload -Recurse -File|ForEach-Object{$_.FullName.Substring($payload.Length+1).Replace('\','/')})
if($actual.Count-ne$expected.Count-or@($actual|Where-Object{$_-cnotin@($expected.Keys)}).Count){throw 'Payload contains extra/missing files'}
if(@($freeze.files|Where-Object path -like '*/Scripts/*.lua').Count-ne56-or$expected.Count-ne67){throw 'This release requires the reviewed 56 Lua / 67 payload file set'}
if(-not$expected.ContainsKey('EotU/Content/Paks/AntOverhaul_P.pak')){throw 'Genuine merged asset PAK missing'}
foreach($legacy in @('EAA_DriverExecution_P.pak','EAA_RendBlood_P.pak','EAA_TrapjawSting_P.pak')){if($expected.ContainsKey('EotU/Content/Paks/'+$legacy)){throw 'Legacy asset PAK must not remain in new payload'}}
if((Sha $AutoPrepareSource)-cne'04ee7df4fb798e95f51b49048c97e0244915aea2660ae79c7f29d3d48b359b9f'-or(Sha $SavePatcherSource)-cne'bbedf09cbcbc4723295397f06c7c160463c8023d033ac915ca37d12fdae7c2d0'-or(Sha $HealthReference)-cne'4ac47d356007430932d0f7760d47842b87f8b180552d185de53ab300e0968ebb'){throw 'Automatic-uninstall input differs from reviewed bytes'}
$health=Get-Content -LiteralPath $HealthReference -Raw -Encoding UTF8|ConvertFrom-Json
if($health.status-cne'validated'){throw 'Unvalidated health reference'}
$build=Join-Path $antWork ('build-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
$package=Join-Path $build 'package';$embedded=Join-Path $build 'embedded';$manual=Join-Path $build 'manual';$manager=Join-Path $manual 'AntOverhaul-Manager'
$out=[IO.Path]::GetFullPath($OutputRoot);NoLink $out;if(Test-Path -LiteralPath $out){throw 'Refusing to replace existing installer output'}
foreach($d in @($package,$embedded,$manager,$out)){[void][IO.Directory]::CreateDirectory($d)}
$manifest=[ordered]@{schema=1;modId=$freeze.modId;release=$freeze.release;appId=[string]$freeze.appId;buildId=[string]$freeze.buildId;gameVersion=$freeze.gameVersion;gameChecks=$freeze.gameChecks;loaderVersion=$freeze.loaderVersion;files=@($freeze.files)}
Fresh (Join-Path $package 'manifest.json') ($manifest|ConvertTo-Json -Depth 30)
$shippingFreeze=$freeze|ConvertTo-Json -Depth 35|ConvertFrom-Json
$shippingFreeze.payloadRoot='payload'
$shippingJson=$shippingFreeze|ConvertTo-Json -Depth 35
if($shippingJson-match'(?i)(?<![a-z])[a-z]:[\\/]'){throw 'Shipping freeze contains an absolute machine path'}
Fresh (Join-Path $package 'source-freeze.json') $shippingJson
$shippingFreezeSha256=Sha (Join-Path $package 'source-freeze.json')
$routes=@();$baseIds=@{}
foreach($row in @($freeze.baselines)){
 $old=$row;$id='baseline-'+$routes.Count
 if($row.PSObject.Properties['id']){$id=[string]$row.id}
 if($baseIds.ContainsKey($id)-or$id-cnotmatch'^[A-Za-z0-9_.-]{1,80}$'){throw 'Invalid baseline identity'};$baseIds[$id]=$true
 if($row.PSObject.Properties['manifest']){$old=$row.manifest}
 if($old.PSObject.Properties['path']){if((Sha $old.path)-cne$old.sha256){throw 'Baseline drift'};$old=Get-Content -LiteralPath $old.path -Raw -Encoding UTF8|ConvertFrom-Json}
 if($old.schema-ne1-or$old.modId-cne$manifest.modId){throw 'Invalid historical baseline'}
 $from=[ordered]@{schema=1;modId=$old.modId;release=$old.release;appId='463530';buildId=[string]$old.buildId;gameVersion=$old.gameVersion;files=@($old.files)}
 $oldMap=@{};foreach($f in @($from.files)){if($oldMap.ContainsKey($f.path)){throw 'Duplicate baseline file'};$oldMap[$f.path]=$f}
 $newMap=@{};foreach($f in @($manifest.files)){$newMap[$f.path]=$f}
 $changes=@()
 foreach($p in @($oldMap.Keys|Sort-Object)){if(-not$newMap.ContainsKey($p)){$changes+=@([ordered]@{path=$p;operation='remove';oldSha256=$oldMap[$p].sha256;newSha256=$null})}}
 foreach($p in @($newMap.Keys|Sort-Object)){
  $f=$newMap[$p]
  if(-not$oldMap.ContainsKey($p)){$changes+=@([ordered]@{path=$p;operation='add';oldSha256=$null;newSha256=$f.sha256})}
  elseif($oldMap[$p].sha256-cne$f.sha256){$changes+=@([ordered]@{path=$p;operation='replace';oldSha256=$oldMap[$p].sha256;newSha256=$f.sha256})}
  elseif($oldMap[$p].length-ne$f.length){throw 'Equal hash with different length'}
 }
 $routes+=@([ordered]@{id=$id;fromRelease=$old.release;fromManifest=$from;changes=$changes})
}
$bundle=[ordered]@{schema=2;modId=$manifest.modId;toRelease=$manifest.release;toManifest=$manifest;routes=$routes}
Fresh (Join-Path $package 'update.json') ($bundle|ConvertTo-Json -Depth 35)
$refsRoot='C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8';$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$helper=Join-Path $package 'AutoPrepare.exe';$helperRefs=@('mscorlib.dll','System.dll','System.Core.dll','System.IO.Compression.dll','System.Web.Extensions.dll')|ForEach-Object{'/reference:'+(Join-Path $refsRoot $_)}
& $csc /nologo /noconfig /nostdlib+ /target:exe /platform:x64 /optimize+ /debug- /langversion:5 ('/out:'+$helper) @helperRefs $SavePatcherSource $AutoPrepareSource
if($LASTEXITCODE-ne0){throw 'Automatic uninstall helper compile failed'}
CopyExact $HealthReference (Join-Path $package 'health-reference.json') (Sha $HealthReference)
python (Join-Path $antWork 'prepare_runtime.py') --package $package --freeze (Join-Path $package 'source-freeze.json') --health-reference $HealthReference --helper $helper --project $antProject
if($LASTEXITCODE-ne0){throw 'Frozen runtime preparation failed'}
foreach($f in @($freeze.files)){
 CopyExact (Child $payload $f.path) (Child (Join-Path $embedded 'payload') $f.path) $f.sha256
 CopyExact (Child $payload $f.path) (Child $manual $f.path) $f.sha256
}
$components=@('manifest.json','source-freeze.json','update.json','release-policy.json','RuntimePolicy.ps1','Manage-Mod.ps1','Update-Mod.ps1','Backend.ps1','AutoPrepare.exe','health-reference.json','installer-runtime-provenance.json')
foreach($name in $components){foreach($destination in @($embedded,$manager)){CopyExact (Join-Path $package $name) (Join-Path $destination $name) (Sha (Join-Path $package $name))}}
$manualLauncher=Join-Path $antSrc 'ManualManager.ps1';CopyExact $manualLauncher (Join-Path $manager 'ManualManager.ps1') (Sha $manualLauncher)
foreach($entry in @(@('Register-Manual-Install.cmd','AdoptManual'),@('Check-Installation.cmd','Inspect'),@('Uninstall-Mod.cmd','Uninstall'))){$body="@echo off`r`nchcp 65001 >nul`r`nsetlocal DisableDelayedExpansion`r`n`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0AntOverhaul-Manager\ManualManager.ps1`" -Action "+$entry[1]+"`r`nset result=%errorlevel%`r`npause`r`nexit /b %result%`r`n";Fresh (Join-Path $manual $entry[0]) $body}
$logo=Join-Path $antSrc 'assets\EotU-Steam-Logo.png';$nexus=Join-Path $antSrc 'assets\NexusMods-Icon.png'
if((Sha $logo)-cne'ad5d7e8993476b29aa50d3348810abf407e17f6e3f135303aa6e3e5b09021462'-or(Sha $nexus)-cne'c03d6fd060e08be9855ac8a68f105feb41344d0370d40c28d6ba7e6db1cb21be'){throw 'Brand artwork changed'}
$ui=Join-Path $build 'ui';[void][IO.Directory]::CreateDirectory($ui)
foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $antSrc 'ui') -Filter '*.cs' -File)){
 $source=$file.FullName;$versioned=Join-Path $antSrc ('ui\0.1.18\'+$file.Name);if(Test-Path -LiteralPath $versioned){$source=$versioned}
 $text=[IO.File]::ReadAllText($source).Replace('0.1.18','0.2.0').Replace('https://www.nexusmods.com/profile/Miossstry','https://www.nexusmods.com/empiresoftheundergrowth/mods/29').Replace('nexusmods.com/profile/Miossstry','nexusmods.com/empiresoftheundergrowth/mods/29').Replace('Miossstry 的 Nexus Mods 主页','蚂蚁大修的 Nexus Mods 页面').Replace('Nexus Mods 主页','Nexus Mods 页面')
 if($file.Name -ceq 'MainWindow.cs'){$anchor='Background = Brushes.Transparent; WindowStartupLocation = WindowStartupLocation.CenterScreen;';if(-not$text.Contains($anchor)){throw 'UI preview positioning anchor changed'};$text=$text.Replace($anchor,$anchor+"`r`n            if (preview) { WindowStartupLocation = WindowStartupLocation.Manual; Left = Math.Max(0, SystemParameters.WorkArea.Right - Width - 16); Top = 16; }")}
 Fresh (Join-Path $ui $file.Name) $text
}
foreach($name in @('README.en.txt','README.zh-CN.txt')){foreach($destination in @($embedded,$manual,$out)){CopyExact (Join-Path $antWork ('docs\'+$name)) (Join-Path $destination $name) (Sha (Join-Path $antWork ('docs\'+$name)))}}
$notice="Ant Overhaul 0.2.0 is an unofficial mod.`r`nUE4SS: v3.0.1-1183-gcdbc0b66. Packaged DLL SHA256: "+(@($freeze.files|Where-Object path -ceq 'EotU/Binaries/Win64/ue4ss/UE4SS.dll')[0].sha256)+"`r`nThe exact loader and mod provenance is recorded in source-freeze.json; no claim of an unchanged upstream DLL is made.`r`nUE4SS source and license: https://github.com/UE4SS-RE/RE-UE4SS`r`nSteam game-logo artwork and Nexus Mods identification icon remain owned by their respective owners.`r`nMod page: https://www.nexusmods.com/empiresoftheundergrowth/mods/29`r`n`r`n"+[IO.File]::ReadAllText((Child $payload 'EotU/Binaries/Win64/ue4ss/LICENSE'))
foreach($destination in @($embedded,$manual,$out)){Fresh (Join-Path $destination 'ThirdPartyNotices.txt') $notice}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$payloadZip=Join-Path $build 'installer-payload.zip';[IO.Compression.ZipFile]::CreateFromDirectory($embedded,$payloadZip,[IO.Compression.CompressionLevel]::Optimal,$false)
$references=@('mscorlib.dll','System.dll','System.Core.dll','System.Xaml.dll','System.Drawing.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll','System.Windows.Forms.dll','System.Web.Extensions.dll','WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll')|ForEach-Object{'/reference:'+(Join-Path $refsRoot $_)}
$exe=Join-Path $out 'AntOverhaul-0.2.0-Setup.exe';$options=@('/nologo','/noconfig','/nostdlib+','/target:winexe','/platform:x64','/optimize+','/debug-','/langversion:5',('/win32manifest:'+(Join-Path $antSrc 'app.manifest')),('/resource:'+$payloadZip+',AntOverhaul.Payload.zip'),('/resource:'+$logo+',AntOverhaul.EotUSteamLogo.png'),('/resource:'+$nexus+',AntOverhaul.NexusModsIcon.png'),('/out:'+$exe))+$references
$sources=@(Get-ChildItem -LiteralPath $ui -Filter '*.cs' -File|Sort-Object Name|ForEach-Object FullName)
& $csc @options @sources
if($LASTEXITCODE-ne0){throw 'Installer compile failed'}
$manualZip=Join-Path $out 'AntOverhaul-0.2.0-Manual.zip';[IO.Compression.ZipFile]::CreateFromDirectory($manual,$manualZip,[IO.Compression.CompressionLevel]::Optimal,$false)
if((Sha $FreezeManifest)-cne$ExpectedFreezeSha256){throw 'Freeze drifted during build'}
foreach($f in @($freeze.files)){if((Sha (Child $payload $f.path))-cne$f.sha256){throw 'Payload drifted during build'}}
$artifacts=@($exe,$manualZip)|ForEach-Object{[ordered]@{path=$_;sha256=(Sha $_);length=(Get-Item -LiteralPath $_).Length}}
Fresh (Join-Path $out 'SHA256SUMS.txt') (($artifacts|ForEach-Object{$_.sha256+' *'+[IO.Path]::GetFileName($_.path)})-join"`r`n")
$result=[ordered]@{schema=1;release='0.2.0';build=$build;package=$package;embedded=$embedded;manual=$manual;output=$out;freezeSha256=$ExpectedFreezeSha256;shippingFreezeSha256=$shippingFreezeSha256;payloadFiles=$expected.Count;luaFiles=56;nexusLink='https://www.nexusmods.com/empiresoftheundergrowth/mods/29';artifacts=$artifacts;formalFilesWritten=$false;publicUpload=$false;createdUtc=[DateTime]::UtcNow.ToString('o')}
Fresh (Join-Path $out 'installer-build.json') ($result|ConvertTo-Json -Depth 10)
$result|ConvertTo-Json -Depth 6

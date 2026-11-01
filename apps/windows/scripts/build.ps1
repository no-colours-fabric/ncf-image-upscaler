param(
    [Parameter(Mandatory=$true)][string]$Cache,
    [Parameter(Mandatory=$true)][string]$BuildRoot,
    [Parameter(Mandatory=$true)][string]$ISCC,
    [string]$Python='python'
)
# Offline build: no downloads, no installed model cache or research bundle input.
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$repo=Split-Path -Parent (Split-Path -Parent $app)
$stage=Join-Path $BuildRoot 'app'
$artifact=Join-Path $BuildRoot 'installer'
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
& $Python (Join-Path $PSScriptRoot 'stage.py') --cache $Cache --stage $stage
if($LASTEXITCODE -ne 0){throw 'Payload staging failed'}
& $Python (Join-Path $PSScriptRoot 'native-imports.py') --bundle $stage --output (Join-Path $BuildRoot 'native-dependencies.json')
if($LASTEXITCODE -ne 0){throw 'Pinned native import/prerequisite manifest check failed'}
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$references=@('System.dll','System.Core.dll','System.Xaml.dll','System.Web.Extensions.dll','Microsoft.VisualBasic.dll','System.Xml.dll') | ForEach-Object {Join-Path $framework $_}
$references+=@('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll') | ForEach-Object {Join-Path $framework ('WPF/'+$_)}
$compiler=Join-Path $framework 'csc.exe'
$resourceExe=Join-Path $BuildRoot 'ResourceCompiler.exe'
$utf8=New-Object System.Text.UTF8Encoding($false,$true)
Get-ChildItem -LiteralPath (Join-Path $app 'src') -Filter '*.cs' | ForEach-Object {
    $null=$utf8.GetString([System.IO.File]::ReadAllBytes($_.FullName))
}
$arguments=@('/nologo','/codepage:65001','/target:exe','/platform:x64','/langversion:5',('/out:'+$resourceExe))
$arguments+=$references | ForEach-Object {'/reference:'+$_}
$arguments+=(Join-Path $app 'packaging/ResourceCompiler.cs')
& $compiler @arguments
if($LASTEXITCODE -ne 0){throw 'Artwork compiler failed'}
& $resourceExe (Join-Path $repo 'native/Tools/MakeIcon.swift') (Join-Path $stage 'resources')
if($LASTEXITCODE -ne 0){throw 'Artwork conversion failed'}
$arguments=@('/nologo','/codepage:65001','/target:winexe','/platform:x64','/optimize+','/langversion:5',('/out:'+(Join-Path $stage 'NCF Image Upscaler.exe')),('/win32icon:'+(Join-Path $stage 'resources/App.ico')))
$arguments+=$references | ForEach-Object {'/reference:'+$_}
$arguments+=Get-ChildItem -LiteralPath (Join-Path $app 'src') -Filter '*.cs' | ForEach-Object {$_.FullName}
Get-ChildItem -LiteralPath (Join-Path $app 'resources/icons') -Filter '*.svg' | ForEach-Object {$arguments+=('/resource:'+$_.FullName+',NCF.Icons.'+$_.Name)}
& $compiler @arguments
if($LASTEXITCODE -ne 0){throw 'Windows application compilation failed'}
$probeArgs=@('/nologo','/codepage:65001','/target:exe','/platform:x64','/langversion:5','/main:NCF.PrerequisiteProbe',('/out:'+(Join-Path $stage 'resources/NativePrerequisiteCheck.exe')),('/reference:'+(Join-Path $framework 'System.dll')))
$probeArgs+=@('src/NativePrerequisites.cs','src/RequiredMsvcExports.cs','packaging/PrerequisiteProbe.cs') | ForEach-Object {Join-Path $app $_}
& $compiler @probeArgs
if($LASTEXITCODE -ne 0){throw 'Native prerequisite helper compilation failed'}
@'
<?xml version="1.0" encoding="utf-8" ?>
<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup></configuration>
'@ | Set-Content -Encoding utf8 -LiteralPath (Join-Path $stage 'NCF Image Upscaler.exe.config')
& $Python (Join-Path $PSScriptRoot 'build-metadata.py') $stage
if($LASTEXITCODE -ne 0){throw 'Build provenance generation failed'}
& $Python (Join-Path $PSScriptRoot 'audit-payload.py') $stage
if($LASTEXITCODE -ne 0){throw 'Payload audit failed'}
& $ISCC /Qp ('/DPayload='+$stage) ('/DArtifactRoot='+$artifact) (Join-Path $app 'packaging/setup.iss')
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed'}
$setup=Join-Path $artifact 'NCFImageUpscaler-0.1.0-preview.1-windows-x64-setup.exe'
((Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant()+'  '+(Split-Path -Leaf $setup)) | Set-Content -Encoding ascii -LiteralPath (Join-Path $artifact 'SHA256SUMS.txt')
Write-Output $setup

param([Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Path (Join-Path $TestRoot 'resources') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $app 'models.json') -Destination (Join-Path $TestRoot 'resources/models.json')
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$references=@('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Xaml.dll') | ForEach-Object {Join-Path $framework $_}
$references+=@('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll') | ForEach-Object {Join-Path $framework ('WPF/'+$_)}
$exe=Join-Path $TestRoot 'ModelsRegression.exe'
$arguments=@('/nologo','/codepage:65001','/target:exe','/platform:x64','/define:MODELS_REGRESSION','/langversion:5',('/out:'+$exe))
$arguments+=$references | ForEach-Object {'/reference:'+$_}
$arguments+=Join-Path $app 'src/Models.cs'
$arguments+=Join-Path $app 'tests/ModelsRegression.cs'
& (Join-Path $framework 'csc.exe') @arguments
if($LASTEXITCODE -ne 0){throw 'Downloader regression compilation failed'}
# Explicit network test, small Fast artifact only; never runs during inference.
& $exe (Join-Path $TestRoot 'cache') | Tee-Object -FilePath (Join-Path $TestRoot 'model-download-report.txt')
if($LASTEXITCODE -ne 0){throw 'Downloader regression failed'}

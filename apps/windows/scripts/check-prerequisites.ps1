param([Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$exe=Join-Path $TestRoot 'PrerequisiteRegression.exe'
$arguments=@('/nologo','/codepage:65001','/target:exe','/platform:x64','/langversion:5','/main:PrerequisiteRegression',('/out:'+$exe),('/reference:'+(Join-Path $framework 'System.dll')))
$arguments+=@('src/NativePrerequisites.cs','src/RequiredMsvcExports.cs','tests/PrerequisiteRegression.cs') | ForEach-Object {Join-Path $app $_}
& (Join-Path $framework 'csc.exe') @arguments
if($LASTEXITCODE -ne 0){throw 'Prerequisite test compilation failed'}
& $exe | Tee-Object -FilePath (Join-Path $TestRoot 'prerequisite-report.txt')
if($LASTEXITCODE -ne 0){throw 'Prerequisite test failed'}

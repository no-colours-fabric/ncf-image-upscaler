param([Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$references=@('System.dll','System.Core.dll','System.Xaml.dll','System.Web.Extensions.dll','Microsoft.VisualBasic.dll','System.Xml.dll') | ForEach-Object {Join-Path $framework $_}
$references+=@('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll') | ForEach-Object {Join-Path $framework ('WPF/'+$_)}
foreach($test in @('DialogAppearanceRegression','AppearancePreferencesRegression','MaximizeRegression')) {
    $directory=Join-Path $TestRoot $test
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $exe=Join-Path $directory ($test+'.exe')
    $arguments=@('/nologo','/codepage:65001','/target:exe','/platform:x64','/define:CLOSE_REGRESSION',('/main:'+$test),'/langversion:5',('/out:'+$exe))
    $arguments+=$references | ForEach-Object {'/reference:'+$_}
    $arguments+=Get-ChildItem -LiteralPath (Join-Path $app 'src') -Filter '*.cs' | ForEach-Object {$_.FullName}
    $arguments+=Join-Path $app ('tests/'+$test+'.cs')
    Get-ChildItem -LiteralPath (Join-Path $app 'resources/icons') -Filter '*.svg' | ForEach-Object {$arguments+=('/resource:'+$_.FullName+',NCF.Icons.'+$_.Name)}
    & (Join-Path $framework 'csc.exe') @arguments
    if($LASTEXITCODE -ne 0){throw ($test+' compilation failed')}
    & $exe $directory
    if($LASTEXITCODE -ne 0){throw ($test+' failed')}
}

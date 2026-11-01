param([Parameter(Mandatory=$true)][string]$Cache)
# Explicit developer network preparation. No host package installation.
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Path $Cache -Force | Out-Null
function Get-Pinned($Url,$Name,$Hash) {
    $path=Join-Path $Cache $Name
    if((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -eq $Hash){return}
    $temporary=$path+'.partial'
    Invoke-WebRequest -Uri $Url -OutFile $temporary
    if((Get-FileHash -LiteralPath $temporary).Hash.ToLowerInvariant() -ne $Hash){throw "Integrity failure: $Name"}
    Move-Item -LiteralPath $temporary -Destination $path -Force
}
$tools=Get-Content (Join-Path $app 'toolchain.json') -Raw | ConvertFrom-Json
Get-Pinned $tools.python.url $tools.python.file $tools.python.sha256
Get-Pinned $tools.inno.url $tools.inno.file $tools.inno.sha256
foreach($wheel in (Get-Content (Join-Path $app 'wheels.json') -Raw | ConvertFrom-Json)) {
    Get-Pinned $wheel.url $wheel.filename $wheel.sha256
}
Write-Output 'Verified build dependencies are ready. No models downloaded.'

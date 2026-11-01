param([Parameter(Mandatory=$true)][string]$Assets,[switch]$ValidateOnly)
# Invoked only by a reviewed Windows-tag job. Never publishes/replaces a release.
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$version=(Get-Content (Join-Path $app 'VERSION') -Raw).Trim()
$tag='windows-v'+$version
$setup='NCFImageUpscaler-'+$version+'-windows-x64-setup.exe'
if($env:GITHUB_EVENT_NAME -ne 'push' -or $env:GITHUB_REF -ne ('refs/tags/'+$tag) -or $env:GITHUB_REPOSITORY -ne 'no-colours-fabric/ncf-image-upscaler'){throw 'Draft creation is restricted to this repository and an exact Windows version tag push'}
$head=(& git rev-parse HEAD).Trim()
if($head -ne $env:GITHUB_SHA -or $head -ne $env:EXPECTED_SOURCE_COMMIT){throw 'Release source differs from the verified installer source'}
if($env:EXPECTED_SETUP_SHA256 -notmatch '^[0-9a-f]{64}$'){throw 'Missing verified build checksum'}
$allowed=@($setup,'SHA256SUMS.txt') | Sort-Object
$files=@(Get-ChildItem -LiteralPath $Assets -Recurse -File)
if($files.Count -ne 2 -or (Compare-Object $allowed ($files.Name | Sort-Object))){throw 'Only setup EXE and SHA256SUMS.txt may be transferred'}
foreach($file in $files){if($file.Directory.FullName -ne (Resolve-Path -LiteralPath $Assets).ProviderPath -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unexpected nested or linked release asset'}}
$setupPath=Join-Path $Assets $setup
$hash=(Get-FileHash -LiteralPath $setupPath).Hash.ToLowerInvariant()
if($hash -ne $env:EXPECTED_SETUP_SHA256 -or (Get-Content (Join-Path $Assets 'SHA256SUMS.txt') -Raw).Trim() -ne ($hash+'  '+$setup)){throw 'Release asset checksum mismatch'}
if($ValidateOnly){Write-Output 'Tag/source/two-file allowlist/checksums validated; no network or release mutation';return}
if(-not $env:GITHUB_TOKEN){throw 'The tag job must provide its scoped built-in token'}
$api='https://api.github.com/repos/'+$env:GITHUB_REPOSITORY
$headers=@{Authorization=('Bearer '+$env:GITHUB_TOKEN);Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
$existing=$null
try{$existing=Invoke-RestMethod -Uri ($api+'/releases/tags/'+$tag) -Headers $headers}
catch{if([int]$_.Exception.Response.StatusCode -ne 404){throw}}
if($existing){throw 'A release already exists for this tag. Nothing was changed; inspect it manually. Published assets are never replaced and existing drafts are not silently overwritten.'}
$notes=Get-Content (Join-Path $app 'packaging/RELEASE_NOTES.md') -Raw
if($version -notmatch '^(\d+\.\d+\.\d+)-preview\.(\d+)$'){throw 'This workflow publishes only versioned Windows previews'}
$title='NCF Image Upscaler for Windows '+$Matches[1]+' Preview '+$Matches[2]
$body=@{tag_name=$tag;target_commitish=$head;name=$title;body=$notes;draft=$true;prerelease=$true;make_latest='false'} | ConvertTo-Json
$release=Invoke-RestMethod -Method Post -Uri ($api+'/releases') -Headers $headers -ContentType 'application/json' -Body $body
if(-not $release.draft -or -not $release.prerelease -or $release.tag_name -ne $tag){throw 'Unexpected release flags; leave draft for inspection'}
$uploadBase=$release.upload_url -replace '\{.*$',''
if(([Uri]$uploadBase).Scheme -ne 'https' -or ([Uri]$uploadBase).Host -ne 'uploads.github.com'){throw 'Unexpected asset upload endpoint'}
foreach($name in @($setup,'SHA256SUMS.txt')){
    $path=Join-Path $Assets $name
    $uploaded=Invoke-RestMethod -Method Post -Uri ($uploadBase+'?name='+[Uri]::EscapeDataString($name)) -Headers $headers -ContentType 'application/octet-stream' -InFile $path
    if($uploaded.name -ne $name -or $uploaded.size -ne (Get-Item -LiteralPath $path).Length){throw 'Uploaded asset identity/size mismatch; inspect draft'}
    $expected=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
    if($uploaded.digest -and $uploaded.digest -ne ('sha256:'+$expected)){throw 'Server asset digest mismatch; inspect draft'}
    $downloadHeaders=$headers.Clone();$downloadHeaders.Accept='application/octet-stream'
    $copy=Join-Path $Assets ('verify-'+$name)
    try{
        Invoke-WebRequest -Uri $uploaded.url -Headers $downloadHeaders -OutFile $copy
        if((Get-FileHash -LiteralPath $copy).Hash.ToLowerInvariant() -ne $expected){throw 'Downloaded draft asset differs from uploaded file'}
    }finally{if(Test-Path -LiteralPath $copy){Remove-Item -LiteralPath $copy}}
}
$checked=Invoke-RestMethod -Uri ($api+'/releases/'+$release.id) -Headers $headers
if(-not $checked.draft -or -not $checked.prerelease -or (Compare-Object $allowed ($checked.assets.name | Sort-Object))){throw 'Final draft flags/assets mismatch'}
$latest=Invoke-RestMethod -Uri ($api+'/releases/latest') -Headers $headers
if($latest.tag_name -eq $tag){throw 'Windows preview must not replace latest stable release'}
Write-Output ('Verified DRAFT only: '+$checked.html_url)
Write-Output ('Windows installer SHA256: '+$hash)

param ($pool_name, $site_name, $packagepath,$github_token,$org,$repo,$tag)
$base64_token = [System.Convert]:: ToBase64String([char[]]$github_token)
$headers=@{ 'Authorization' = 'Basic {0}' -f $base64_token}
$headers.Add('Accept','application/json')
$headers.Add('mode','no-cors')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$wr = Invoke-WebRequest -Headers $headers -Uri $("https://api.github.com/repos/$org/$repo/releases/tags/$tag")
$objects = $wr.Content | ConvertFrom-Json
# Write-Output $objects

$download = $objects.assets.url;
$zip_file = "$download_path/$tag.zip"
If(!(test-path $download_path))
{
      New-Item -ItemType Directory -Force -Path $download_path
}

Write-Host "Dowloading release $tag"
Write-Host "Asset Url: $download"
$headers.Remove('Accept')
$headers.Add('Accept','application/octet-stream')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Headers $headers $download -UseBasicParsing -OutFile $zip_file

if (Get-Module -ListAvailable -Name webadministration) {
    Write-Host "WebAdministration is already Installed"
} 
else {
    try {
        Install-Module -Name webadministration -Force  
    }
    catch [Exception] {
        $_.message 
        exit
    }
}
import-module webadministration

#check if the app pool exists
if(!(Test-Path IIS:\AppPools\$pool_name ))
{
    #create the app pool
    New-WebAppPool -Name $pool_name -Force
    Write-Output "Pool: '$pool_name' created"
}
else {
    Write-Output "Pool: '$pool_name' exists"
}

#check if the site exists
if(!(Test-Path IIS:\Sites\$site_name  ))
{
   New-Website -Name $site_name -ApplicationPool $pool_name -Force -PhysicalPath $packagepath
   Write-Output "Site: '$site_name' created"
}
else {
    Write-Output "Site: '$site_name' exists"
}

Write-Output "Deleting folder items of $packagepath" 
Remove-Item $packagepath\* -Recurse -Force

Write-Output "Extracting release to $packagepath"
Add-Type -Assembly "System.IO.Compression.Filesystem"
[io.compression.zipfile]::ExtractToDirectory($zip_file, $packagepath)

Write-Output "Restarting site: $site_name"
Stop-WebSite $site_name
Start-WebSite $site_name
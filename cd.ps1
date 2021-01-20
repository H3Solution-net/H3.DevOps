param ($pool_name, $site_name, $packagepath,$github_token,$org,$repo,$tag)
$devops_path = "C:\Devops"
$download_path = "C:\Devops\Download"
$extract_path = "C:\Devops\Extract"
$releases_path = "C:\Devops\Releases"
$backup_path = "C:\Devops\Backup"

Invoke-Check-Devops-Paths $devops_path -paths $download_path,$extract_path,$releases_path,$backup_path
$zip_file = Get-Release-Asset $download_path $github_token $org $repo $tag
$release_extract_path = ExtractFile($zip_file,$extract_path,$tag)
Invoke-Check-IIS-Site $pool_name $packagepath $site_name
Invoke-Backup-And-Replace $packagepath $extract_path $backup_path $tag
RestartSite($site_name)

function RestartSite ($site_name) {
    Write-Output "Restarting site: $site_name"
    Stop-WebSite $site_name
    Start-WebSite $site_name
}
function ExtractFile ($zip_file,$extract_path,$tag) {
    $release_extract_path = "$extract_path\$tag"
    Write-Output "Extracting release to $release_extract_path"
    Add-Type -Assembly "System.IO.Compression.Filesystem"
    [io.compression.zipfile]::ExtractToDirectory($zip_file, $release_extract_path)
    return $release_extract_path
}
function ZipFile( $zipfilename, $sourcedir )
{
   Add-Type -Assembly System.IO.Compression.FileSystem
   $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
   [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir,
        $zipfilename, $compressionLevel, $false)
}
function Invoke-Backup-And-Replace
{
    param([string]$packagepath,[string]$release_extract_path,[string]$backup_path,[string]$tag)

    $release_backup_path = "$backup_path\$tag"
    Clear-Path -path $release_backup_path

    $rfc = get-ChildItem -File -Recurse -Path $release_extract_path
    $source = get-ChildItem -File -Recurse -Path $packagepath
    # check for new files that need to be copied
    compare-Object -DifferenceObject $rfc -ReferenceObject $source -Property Name -PassThru | foreach-Object {
        #copy source to destination
        $rfc_path = $_.DirectoryName -replace [regex]::Escape($release_extract_path),$packagepath
        if ((test-Path -Path $rfc_path) -eq $false) { new-Item -ItemType Directory -Path $rfc_path | out-Null}
        copy-Item -Force -Path $_.FullName -Destination $rfc_path
    }
    # check for same files that need to be replaced
    compare-Object -DifferenceObject $rfc -ReferenceObject $source -ExcludeDifferent -IncludeEqual -Property Name -PassThru | foreach-Object {
        # copy destination to BACKUP
        $backup_dest = $_.DirectoryName -replace [regex]::Escape($packagepath),$release_backup_path
        # create directory, including intermediate paths, if necessary
        if ((test-Path -Path $backup_dest) -eq $false) { new-Item -ItemType Directory -Path $backup_dest | out-Null}
        copy-Item -Force -Path $_.FullName -Destination $backup_dest

        #copy source to destination
        $rfc_path = $_.fullname -replace [regex]::Escape($packagepath),$release_extract_path
        copy-Item -Force -Path $rfc_path -Destination $_.FullName
    }
    ZipFile("$release_backup_path.zip",$backup_path)
    Remove-Item -Recurse -Force $release_backup_path 
}
function Get-Release-Asset
{
    param([string]$download_path,[string]$github_token,[string]$org,[string]$repo,[string]$tag)
    $base64_token = [System.Convert]:: ToBase64String([char[]]$github_token)
    $headers=@{ 'Authorization' = 'Basic {0}' -f $base64_token}
    $headers.Add('Accept','application/json')
    $headers.Add('mode','no-cors')
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wr = Invoke-WebRequest -Headers $headers -Uri $("https://api.github.com/repos/$org/$repo/releases/tags/$tag")
    $objects = $wr.Content | ConvertFrom-Json
    # Write-Output $objects

    $download_url = $objects.assets.url;
    $zip_file = "$download_path\$tag.zip"
    If(!(Test-path $download_path))
    {
        New-Item -ItemType Directory -Force -Path $download_path
    }

    Write-Host "Dowloading release $tag"
    Write-Host "Asset Url: $download_url"
    $headers.Remove('Accept')
    $headers.Add('Accept','application/octet-stream')
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Headers $headers $download_url -UseBasicParsing -OutFile $zip_file
    return $zip_file
}
function Invoke-Check-IIS-Site
{
    param([string]$pool_name,[string]$packagepath, [string]$site_name)
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
       New-Website -Name $site_name -ApplicationPool $pool_name -Force -PhysicalPath $packagepath -HostHeader $site_name
       Write-Output "Site: '$site_name' created"
    }
    else {
        Write-Output "Site: '$site_name' exists"
    }
 
}
function Clear-Path
{
    param([string]$path)
    if ((test-Path -Path $releases_extract_path) -eq $true) 
    {
        Write-Output "Deleting folder items of $releases_extract_path" 
        Remove-Item $releases_extract_path\* -Recurse -Force
    }else {
        new-Item -ItemType Directory -Path $releases_extract_path | out-Null  
    }
 
}
function Invoke-Check-Devops-Paths
{
    param([string]$devops_path,[string[]]$paths)
    if ((test-Path -Path $devops_path) -eq $false) 
    { 
        new-Item -ItemType Directory -Path $devops_path | out-Null
        foreach ($path in $paths)
        {
            Invoke-Check-Path $path
        }
    }
 
}
function Invoke-Check-Path
{
    param([string]$path)
    Write-Output "Creating directory $releases_extract_path"
    if ((test-Path -Path $releases_extract_path) -eq $false) { new-Item -ItemType Directory -Path $releases_extract_path | out-Null }
 
}

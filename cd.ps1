
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$pool_name,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$site_name,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$packagepath,

    [Parameter(Mandatory = $true, Position = 3)]
    [string]$github_token,

    [Parameter(Mandatory = $true, Position = 4)]
    [string]$org,

    [Parameter(Mandatory = $true, Position = 5)]
    [string]$repo,

    [Parameter(Mandatory = $true, Position = 6)]
    [string]$tag

)
function RestartSite ($site_name) {
    Write-Output "Restarting site: $site_name"
    Stop-WebSite $site_name
    Start-WebSite $site_name
}
function ExtractFile {
    param([string]$zip_file,[string]$extract_path, [string]$tag)
    $dest = "$extract_path"
    Write-Host "Extracting file $zip_file at destination: $dest"
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # get an array of FileInfo objects for zip files in the $zip_file directory and loop through
    Get-ChildItem $zip_file -Filter *.zip -File | ForEach-Object {
        # unpacks each zip in directory to destination folder
        # the automatic variable '$_' here represents a single FileInfo object, each file at a time

        # Get the destination folder for the zip file. Create the folder if it does not exist.
        $destination = Join-Path -Path $dest -ChildPath $_.BaseName  # $_.BaseName does not include the extension

        # Check if the folder already exists
        if ((Test-Path $destination -PathType Container)) {
            Delete-Dir -path $destination
        }
            # create the destination folder
            New-Item -Path $destination -ItemType Directory -Force | Out-Null

            # unzip the file
            Write-Host "UnZipping - $($_.FullName)"
            [System.IO.Compression.ZipFile]::ExtractToDirectory($_.FullName, $destination)
    }
}
function ZipFile($zipfilename, $sourcedir)
{
   Add-Type -Assembly System.IO.Compression.FileSystem
   $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
   [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir,
        $zipfilename, $compressionLevel, $false)
}
function Invoke-Backup-And-Replace
{
    param([string]$packagepath,[string]$release_extract_path,[string]$backup_path,[string]$tag)
    Write-Host "Starting taking backup & replacing release"
    # packagepath path must contain atleast single file
    CreateEmptyFile -path $packagepath

    $release_backup_path = "$backup_path\$tag"
    Clear-Path -path $release_backup_path
    $rfc = get-ChildItem -File -Recurse -Path $release_extract_path
    $source = get-ChildItem -File -Recurse -Path $packagepath
    
    # Write-Host $rfc  
    Write-Host $source
    # check for new files that need to be copied
    compare-Object -DifferenceObject $rfc -ReferenceObject $source -Property Name -PassThru | foreach-Object {
        #copy source to destination
        $rfc_path = $_.DirectoryName -replace [regex]::Escape($release_extract_path),$packagepath
        Write-Host "Adding $rfc_path"
        if ((test-Path -Path $rfc_path) -eq $false) { new-Item -ItemType Directory -Path $rfc_path | out-Null}
        copy-Item -Force -Path $_.FullName -Destination $rfc_path
    }
    # check for same files that need to be replaced
    compare-Object -DifferenceObject $rfc -ReferenceObject $source -ExcludeDifferent -IncludeEqual -Property Name -PassThru | foreach-Object {
        # copy destination to BACKUP
        Write-Host "Relacing $_"
        $backup_dest = $_.DirectoryName -replace [regex]::Escape($packagepath),$release_backup_path
        # create directory, including intermediate paths, if necessary
        if ((test-Path -Path $backup_dest) -eq $false) { new-Item -ItemType Directory -Path $backup_dest | out-Null}
        copy-Item -Force -Path $_.FullName -Destination $backup_dest

        #copy source to destination
        $rfc_path = $_.fullname -replace [regex]::Escape($packagepath),$release_extract_path
        copy-Item -Force -Path $rfc_path -Destination $_.FullName
    }
    Write-Host "zipping backup folder: $backup_path"
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
    If(!(Test-path $download_path))
    {
        New-Item -ItemType Directory -Force -Path $download_path
    }
    $zip_file = "$download_path\$tag.zip"
    Write-Host $zip_file
    Write-Host "Dowloading release at $zip_file"
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
    if ((test-Path -Path $path) -eq $true) 
    {
        Write-Output "Deleting folder items of $path" 
        Remove-Item $path\* -Recurse -Force
    }else {
        new-Item -ItemType Directory -Path $path | out-Null  
    }
 
}
function CreateEmptyFile {
    param (
        [string]$path
    )
    $fileToCheck = "$path\empty.txt"
    Write-Host $fileToCheck
    if (!(Test-Path $fileToCheck -PathType leaf))
    {
        Write-Host "Creating empty file"
        New-Item -Path $fileToCheck -ItemType File -Force
    }
    
}
function Delete-Dir([string]$path){
    if ((test-Path -Path $path) -eq $true) 
    {
        Write-Output "Deleting folder items of $path" 
        Remove-Item $path -Recurse -Force
    }
}
function Invoke-Check-Devops-Paths
{
    param([string]$devops_path,[string[]]$paths)
    Write-Host "Checking Devops Paths"
    if ((test-Path -Path $devops_path) -eq $false) 
    { 
        Write-Host "DevOps path didnt exist, creating now...."
        new-Item -ItemType Directory -Path $devops_path | out-Null
        foreach ($path in $paths)
        {
            Write-Host $path
            Invoke-Check-Path($path)
        }
    }
 
}
function Invoke-Check-Path($path)
{
    Write-Output "Creating directory $path"
    if ((test-Path -Path $path) -eq $false) { new-Item -ItemType Directory -Path $path | out-Null }
 
}

$devops_path = "c:\Devops"
$download_path = "C:\Devops\Download"
$extract_path = "c:\Devops\Extract"
$releases_path = "c:\Devops\Releases"
$backup_path = "c:\Devops\Backup"
Write-Host $packagepath

Invoke-Check-Devops-Paths $devops_path -paths $download_path,$extract_path,$releases_path,$backup_path
$zip_file = Get-Release-Asset $download_path $github_token $org $repo $tag
ExtractFile $zip_file -extract_path $extract_path -tag $tag
Invoke-Check-IIS-Site $pool_name $packagepath $site_name
Stop-WebSite $site_name
Invoke-Backup-And-Replace -packagepath $packagepath -release_extract_path "$extract_path\$tag" -backup_path $backup_path -tag $tag
Start-WebSite $site_name
# RestartSite($site_name)
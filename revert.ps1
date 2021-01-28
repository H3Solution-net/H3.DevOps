param(
    [Parameter(Mandatory = $true, Position = 2)]
    [string]$packagepath,

    [Parameter(Mandatory = $true, Position = 4)]
    [string]$org,

    [Parameter(Mandatory = $true, Position = 5)]
    [string]$repo,

    [Parameter(Mandatory = $true, Position = 6)]
    [string]$tag

)
function Delete-Dir([string]$path) {
    if ((test-Path -Path $path) -eq $true) {
        Write-Output "Deleting folder items of $path" 
        Remove-Item $path -Recurse -Force
    }
}
function ExtractFile {
    param([string]$zip_file, [string]$extract_path)
    $dest = "$extract_path"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Write-Output $dest 
    # get an array of FileInfo objects for zip files in the $zip_file directory and loop through
    Get-ChildItem $zip_file -Filter *.zip -File | ForEach-Object {
        # unpacks each zip in directory to destination folder
        # the automatic variable '$_' here represents a single FileInfo object, each file at a time

        # Get the destination folder for the zip file. Create the folder if it does not exist.
        $dest_release = Join-Path -Path $dest -ChildPath $_.BaseName  # $_.BaseName does not include the extension

        # Check if the folder already exists
        if ((Test-Path $dest_release -PathType Container)) {
            Delete-Dir -path $dest_release
        }
        # create the destination folder
        New-Item -Path $dest_release -ItemType Directory -Force | Out-Null

        # unzip the file
        Write-Host "UnZipping - $($_.FullName) to Destination - $dest"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($_.FullName, $dest)
    }
}
function Clear-Path {
    param([string]$path)
    if ((test-Path -Path $path) -eq $true) {
        Write-Output "Deleting folder items of $path" 
        Remove-Item $path\* -Recurse -Force
    }
    else {
        new-Item -ItemType Directory -Path $path | out-Null  
    }
 
}
function Invoke-Backup-And-Replace {
    param([string]$packagepath, [string]$release_extract_path)
    Write-Host "Starting taking backup & replacing release"
    # packagepath path must contain atleast single file
    CreateEmptyFile -path $release_extract_path
    $extract_files = get-ChildItem -File -Recurse -Path $release_extract_path
    $prod_files = get-ChildItem -File -Recurse -Path $packagepath
    
    Write-Host "Replacing Common Files......"
    # check for same files that need to be replaced
    compare-Object -DifferenceObject $extract_files -ReferenceObject $prod_files -ExcludeDifferent -IncludeEqual -Property Name -PassThru | foreach-Object {
        # copy destination to BACKUP
        Write-Host "Relacing" $_.FullName

        #copy prod_files to destination
        $rfc_path = $_.fullname -replace [regex]::Escape($packagepath), $release_extract_path
        copy-Item -Force -Path $rfc_path -Destination $_.FullName
    }
}
function Delete-Dir([string]$path) {
    if ((test-Path -Path $path) -eq $true) {
        Write-Output "Deleting folder items of $path" 
        Remove-Item $path -Recurse -Force
    }
}
$backup_path = "c:\Devops\$org\$repo\Backup"
$backup_extract = "c:\Devops\$org\$repo\Backup_Extract"
ExtractFile "$backup_path\$tag.zip" -extract_path "$backup_extract"
$backup_extract_release = "$backup_extract\$tag"
Invoke-Backup-And-Replace -packagepath $packagepath -release_extract_path $backup_extract_release
Delete-Dir -path $backup_extract_release
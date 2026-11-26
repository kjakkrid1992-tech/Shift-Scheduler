# Partial logical export of public schema only. NOT a complete Supabase backup.
param([Parameter(Mandatory=$true)][string]$BackupDir)
$ErrorActionPreference='Stop'
if (-not $env:PGHOST -or -not $env:PGUSER -or -not $env:PGDATABASE) { throw 'Set PGHOST, PGUSER and PGDATABASE in the current shell; use a protected PGPASSFILE or password prompt.' }
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$dest=[IO.Path]::GetFullPath($BackupDir).TrimEnd('\','/')
if ($dest.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $dest.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Backup destination must be outside the repository.' }
if ($env:PGSSLMODE -notin @('require','verify-ca','verify-full')) { throw 'Set PGSSLMODE=require or verified TLS per provider instructions.' }
Get-Command pg_dump,pg_restore -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$stamp=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$file=Join-Path $dest "public-$stamp.dump"
if(Test-Path -LiteralPath $file){throw 'Backup file already exists.'}
try {
 & pg_dump --format=custom --schema=public --file=$file
 if($LASTEXITCODE -ne 0){throw 'pg_dump failed; incomplete file is not a backup.'}
 & pg_restore --list $file | Out-Null
 if($LASTEXITCODE -ne 0){throw 'pg_restore list failed.'}
 $hash=Get-FileHash -LiteralPath $file -Algorithm SHA256
 "$($hash.Hash)  $([IO.Path]::GetFileName($file))" | Set-Content -LiteralPath "$file.sha256" -Encoding ascii
 Write-Host "Public schema export created: $file"
 Write-Warning 'Archive list verified, not restored. Contains private payroll data. Protect/encrypt it. Does not include auth, staff_private schema, platform configuration or storage.'
} catch {
 if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}
 throw
}

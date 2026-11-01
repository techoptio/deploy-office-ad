$Paths = @{
  ShareRoot   = $PSScriptRoot
  SetupName   = 'setup.exe'
  ConfigName  = 'config.xml'
  DesiredName = 'desired_version.txt'

  StateDir    = 'C:\ProgramData\OfficeODT'
  StateFile   = 'state.json'
  LogFile     = 'deploy.log'

  StagingDir  = 'C:\ProgramData\OfficeODT\staging'
}

$Share = @{
  Setup   = Join-Path $Paths.ShareRoot $Paths.SetupName
  Config  = Join-Path $Paths.ShareRoot $Paths.ConfigName
  Desired = Join-Path $Paths.ShareRoot $Paths.DesiredName
}

$Local = @{
  Root     = $Paths.StateDir
  State    = Join-Path $Paths.StateDir $Paths.StateFile
  Log      = Join-Path $Paths.StateDir $Paths.LogFile

  Staging  = $Paths.StagingDir
  Setup    = Join-Path $Paths.StagingDir $Paths.SetupName
  Config   = Join-Path $Paths.StagingDir $Paths.ConfigName
}

New-Item -ItemType Directory -Path $Local.Root -Force | Out-Null

function Log($msg) {
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -Path $Local.Log -Value "$ts $msg"
}

function Write-State($obj) {
  $obj | ConvertTo-Json | Set-Content -Path $Local.State -Encoding UTF8
}

function Read-State {
  if (!(Test-Path $Local.State)) { return $null }
  try { return (Get-Content $Local.State -Raw | ConvertFrom-Json) } catch { return $null }
}

function Cleanup-OldLogs {
  param([string]$Dir, [int]$Days = 30)
  $cutoff = (Get-Date).AddDays(-$Days)

  $deployLog = Join-Path $Dir 'deploy.log'
  if (Test-Path $deployLog) {
    try {
      $lines = Get-Content $deployLog -ErrorAction Stop
      $kept = @()
      foreach ($line in $lines) {
        # Each line starts with 'yyyy-MM-dd HH:mm:ss' — parse that timestamp
        if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') {
          $parsed = [datetime]::MinValue
          if ([datetime]::TryParseExact($Matches[0], 'yyyy-MM-dd HH:mm:ss', $null, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            if ($parsed -ge $cutoff) { $kept += $line }
            continue
          }
        }
        # Keep lines that don't start with a recognisable timestamp (shouldn't happen, but safe)
        $kept += $line
      }
      if ($kept.Count -lt $lines.Count) {
        Set-Content -Path $deployLog -Value $kept -Encoding UTF8
      }
    } catch {}
  }
}

function Remove-Staging {
  if (Test-Path $Local.Staging) {
    try {
      Log "Removing staging dir: $($Local.Staging)"
      Remove-Item -Path $Local.Staging -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
  }
}

# Prevent concurrent runs
$mutex = New-Object System.Threading.Mutex($false, 'Global\OfficeODTDeploy')
if (-not $mutex.WaitOne(0)) { exit 0 }

$desiredVersion = $null
$lastApplied    = $null
$lastStatus     = $null
$finalStatus    = $null
$finalExitCode  = $null

try {
  Log 'Starting run.'
  Remove-Staging

  Log 'Checking SYSVOL paths...'
  for ($i=0; $i -lt 30; $i++) {
    if ((Test-Path $Share.Setup) -and (Test-Path $Share.Config) -and (Test-Path $Share.Desired)) { break }
    Start-Sleep -Seconds 5
  }

  if (!(Test-Path $Share.Desired)) {
    Log 'Share not reachable. Exiting.'
    $finalStatus = 'share_unreachable'
    return
  }

  $desiredVersion = (Get-Content $Share.Desired -ErrorAction Stop | Select-Object -First 1).Trim()
  if ([string]::IsNullOrWhiteSpace($desiredVersion)) {
    Log 'desired_version.txt empty. Exiting.'
    $finalStatus = 'desired_empty'
    return
  }

  $state = Read-State
  $lastApplied = $state.LastAppliedVersion
  $lastStatus  = $state.LastStatus

  Log "Desired=$desiredVersion LastApplied=$lastApplied LastStatus=$lastStatus"

  if (($lastApplied -eq $desiredVersion) -and ($lastStatus -eq 'success')) {
    Log 'Already applied desired version (state-based). Done.'
    $finalStatus = 'already_compliant'
    return
  }

  Log "Creating staging folder: $($Local.Staging)"
  New-Item -ItemType Directory -Path $Local.Staging -Force | Out-Null

  Log "Copying setup.exe: $($Share.Setup) -> $($Local.Setup)"
  Copy-Item -Path $Share.Setup -Destination $Local.Setup -Force

  Log "Copying config.xml: $($Share.Config) -> $($Local.Config)"
  Copy-Item -Path $Share.Config -Destination $Local.Config -Force

  Write-State @{
    LastAppliedVersion = $lastApplied
    TargetVersion      = $desiredVersion
    LastStatus         = 'in_progress'
    Timestamp          = (Get-Date).ToString('o')
  }

  Log "Running: $($Local.Setup) /download $($Local.Config)"
  $p1 = Start-Process -FilePath $Local.Setup -ArgumentList "/download `"$($Local.Config)`"" -Wait -PassThru
  Log "ODT /download exit code: $($p1.ExitCode)"
  if ($p1.ExitCode -ne 0) {
    $finalStatus = 'download_failed'
    $finalExitCode = $p1.ExitCode
    return
  }

  Log "Running: $($Local.Setup) /configure $($Local.Config)"
  $p2 = Start-Process -FilePath $Local.Setup -ArgumentList "/configure `"$($Local.Config)`"" -Wait -PassThru
  Log "ODT /configure exit code: $($p2.ExitCode)"
  if ($p2.ExitCode -ne 0) {
    $finalStatus = 'configure_failed'
    $finalExitCode = $p2.ExitCode
    return
  }

  $finalStatus = 'success'
  $finalExitCode = 0
}
catch {
  Log ('Unhandled error: ' + $_.Exception.Message)
  $finalStatus = 'exception'
}
finally {
  if ($desiredVersion) {
    if ($finalStatus -eq 'success') {
      Write-State @{
        LastAppliedVersion = $desiredVersion
        LastStatus         = 'success'
        Timestamp          = (Get-Date).ToString('o')
      }
      Log 'Install/update successful.'
    }
    elseif ($finalStatus -and ($finalStatus -notin @('already_compliant','share_unreachable','desired_empty'))) {
      Write-State @{
        LastAppliedVersion = $lastApplied
        TargetVersion      = $desiredVersion
        LastStatus         = $finalStatus
        ExitCode           = $finalExitCode
        Timestamp          = (Get-Date).ToString('o')
      }
      Log "Run finished with status: $finalStatus"
    }
  }

  Remove-Staging

  try {
    Log 'Cleaning up logs older than 30 days...'
    Cleanup-OldLogs -Dir $Local.Root -Days 30
  } catch {}

  try {
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
  } catch {}

  Log 'Done.'
}

exit 0

param(
  [string]$ConfigFile = "/etc/net-resilience.conf"
)

# Load config
if (-not (Test-Path $ConfigFile)) {
  throw "Config file $ConfigFile not found"
}
$config = Get-Content $ConfigFile | ConvertFrom-Json

$LogDir          = $config.LogDir
$PingIntervalSec = $config.PingIntervalSec
$HttpIntervalSec = $config.HttpIntervalSec
$icmpHosts       = $config.ICMPHosts
$httpHosts       = $config.HTTPHosts

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
  New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Detect region and zone from IMDS
$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$headers = @{ Metadata = "true" }

try {
  $instance = Invoke-RestMethod -Headers $headers -Uri "http://169.254.169.254/metadata/instance?api-version=2025-04-07"
  $env:AZ_LOCATION = $instance.compute.location
  $env:AZ_ZONE     = $instance.compute.zone
} catch {
  $env:AZ_LOCATION = "unknown"
  $env:AZ_ZONE     = "unknown"
  Write-Error "IMDS query failed: $($_.Exception.Message)"
}

$instanceId = (hostname)

$init = {
  function Write-EventJson([hashtable]$h, [string]$LogDir) {
    $line = ($h | ConvertTo-Json -Compress)
    $date = (Get-Date -Format 'yyyy-MM-dd')
    $file = Join-Path $LogDir "net-$date.jsonl"
    Add-Content -Path $file -Value $line
  }

  function Test-NetworkTarget {
    param (
      [Parameter(Mandatory)][ValidateSet("ICMP", "HTTP")][string]$Protocol,
      [Parameter(Mandatory)][string]$Target,
      [string]$AzLocation,
      [string]$AzZone,
      [string]$VmInstance,
      [string]$TestType = "OnPrem",
      [string]$CorrelationId
    )

    $ts = (Get-Date).ToString("o")
    $tsUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $statusCode = 99999
    $statusName = "Exception"
    $latencyMs = $null
    $success = $false
    $errorMsg = $null

    if ($Protocol -eq "ICMP") {
      try {
        $pingResult = Test-Connection -ComputerName $Target -Count 1 -TimeoutSeconds 1 -ErrorAction Stop
        $statusEnum = $pingResult.Status
        $statusCode = [int]$statusEnum
        $statusName = $statusEnum.ToString()
        $success = ($statusEnum -eq [System.Net.NetworkInformation.IPStatus]::Success)
        $latencyMs = $pingResult.Latency
      } catch {
        $errorMsg = $_.Exception.Message
      }
    }
    elseif ($Protocol -eq "HTTP") {
      $httpStatusNames = @{
        200 = "OK"; 301 = "MovedPermanently"; 302 = "Found"; 400 = "BadRequest"; 401 = "Unauthorized"
        403 = "Forbidden"; 404 = "NotFound"; 500 = "InternalServerError"; 503 = "ServiceUnavailable"
      }
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $Target -TimeoutSec 5 -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
        $sw.Stop()
        $latencyMs = $sw.ElapsedMilliseconds
        $statusCode = [int]$resp.StatusCode
        $statusName = $httpStatusNames[$statusCode] ?? "HTTP_$statusCode"
        $success = ($statusCode -ge 200 -and $statusCode -lt 400)
      } catch {
        $errorMsg = $_.Exception.Message
      }
    }

    return @{
      TimeGenerated = $tsUtc
      LocalTime     = $ts
      AzLocation    = $AzLocation
      AzZone        = $AzZone
      VmInstance    = $VmInstance
      TestType      = $TestType
      Target        = $Target
      Protocol      = $Protocol
      LatencyMs     = $latencyMs
      Success       = $success
      StatusCode    = $statusCode
      StatusName    = $statusName
      Error         = $errorMsg
      CorrelationId = $CorrelationId
    }
  }
}

# --- Graceful shutdown flag ---
$global:StopRequested = $false

# Trap Ctrl+C
Register-EngineEvent PowerShell.Exiting -Action { $global:StopRequested = $true }
Register-EngineEvent ConsoleCancelEventHandler -Action { $global:StopRequested = $true }

$jobs = @()

foreach ($eachHost in $icmpHosts) {
  $jobs += Start-ThreadJob -InitializationScript $init -ScriptBlock {
    param($TargetHost,$IntervalSec,$LogDir,$AzLocation,$AzZone,$VmInstance)

    while (-not $global:StopRequested) {
    $cid = [guid]::NewGuid()
    $logEntry = Test-NetworkTarget -Protocol "ICMP" -Target $TargetHost `
        -AzLocation $AzLocation -AzZone $AzZone -VmInstance $VmInstance -CorrelationId $cid
    Write-EventJson $logEntry $LogDir
    Start-Sleep -Seconds $IntervalSec
    }
  } -ArgumentList $eachHost,$PingIntervalSec,$LogDir,$env:AZ_LOCATION,$env:AZ_ZONE,$instanceId
}

foreach ($url in $httpHosts) {
  $jobs += Start-ThreadJob -InitializationScript $init -ScriptBlock {
    param($TargetUrl,$IntervalSec,$LogDir,$AzLocation,$AzZone,$VmInstance)
    
    while (-not $global:StopRequested) {
    $cid = [guid]::NewGuid()
    $logEntry = Test-NetworkTarget -Protocol "HTTP" -Target $TargetUrl `
        -AzLocation $AzLocation -AzZone $AzZone -VmInstance $VmInstance -CorrelationId $cid
    Write-EventJson $logEntry $LogDir
    Start-Sleep -Seconds $IntervalSec
    }
  } -ArgumentList $url,$HttpIntervalSec,$LogDir,$env:AZ_LOCATION,$env:AZ_ZONE,$instanceId
}

Write-Output "Started $($icmpHosts.Count) ICMP jobs and $($httpHosts.Count) HTTP jobs."

# --- Wait for jobs until stop requested ---
while (-not $global:StopRequested) {
  Start-Sleep -Seconds 1
}

# Cleanup
Stop-Job $pingJob,$httpJob -Force
Remove-Job $pingJob,$httpJob
Write-Output "Shutdown requested. Jobs stopped cleanly."
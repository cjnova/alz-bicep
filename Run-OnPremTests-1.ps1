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
}

# --- Graceful shutdown flag ---
$global:StopRequested = $false

# Trap Ctrl+C
Register-EngineEvent PowerShell.Exiting -Action { $global:StopRequested = $true }
Register-EngineEvent ConsoleCancelEventHandler -Action { $global:StopRequested = $true }

$jobs = @()

foreach ($targetHost in $icmpHosts) {
  $jobs += Start-ThreadJob -InitializationScript $init -ScriptBlock {
    param($TargetHost,$IntervalSec,$LogDir,$AzLocation,$AzZone,$VmInstance)

    while (-not $global:StopRequested) {
      $ts = (Get-Date).ToString("o")
      $cid = [guid]::NewGuid()
      try {
        $pingResult = Test-Connection -ComputerName $TargetHost -Count 1 -ErrorAction Stop
        $latency = $pingResult.ResponseTime
        Write-EventJson @{
          TimeGenerated=$ts; AzLocation=$AzLocation; AzZone=$AzZone; VmInstance=$VmInstance
          TestType='OnPrem'; Target=$TargetHost; Protocol='ICMP'; LatencyMs=$latency
          Success=$true; StatusCode='Reply'; Error=$null; CorrelationId=$cid
        } $LogDir
      } catch {
        Write-EventJson @{
          TimeGenerated=$ts; AzLocation=$AzLocation; AzZone=$AzZone; VmInstance=$VmInstance
          TestType='OnPrem'; Target=$TargetHost; Protocol='ICMP'; LatencyMs=$null
          Success=$false; StatusCode='Timeout'; Error=$_.Exception.Message; CorrelationId=$cid
        } $LogDir
      }
      Start-Sleep -Seconds $IntervalSec
    }
  } -ArgumentList $host,$PingIntervalSec,$LogDir,$env:AZ_LOCATION,$env:AZ_ZONE,$instanceId
}

foreach ($url in $httpHosts) {
  $jobs += Start-ThreadJob -InitializationScript $init -ScriptBlock {
    param($TargetUrl,$IntervalSec,$LogDir,$AzLocation,$AzZone,$VmInstance)
    
    while (-not $global:StopRequested) {
      $ts = (Get-Date).ToString("o")
      $cid = [guid]::NewGuid()
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $TargetUrl -TimeoutSec 10 -UseBasicParsing
        $sw.Stop()
        Write-EventJson @{
          TimeGenerated=$ts; AzLocation=$AzLocation; AzZone=$AzZone; VmInstance=$VmInstance
          TestType='OnPrem'; Target=$TargetUrl; Protocol='HTTP'; LatencyMs=$sw.ElapsedMilliseconds
          Success=($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
          StatusCode="$($resp.StatusCode)"; Error=$null; CorrelationId=$cid
        } $LogDir
      } catch {
        Write-EventJson @{
          TimeGenerated=$ts; AzLocation=$AzLocation; AzZone=$AzZone; VmInstance=$VmInstance
          TestType='OnPrem'; Target=$TargetUrl; Protocol='HTTP'; LatencyMs=$null
          Success=$false; StatusCode='ERROR'; Error=$_.Exception.Message; CorrelationId=$cid
        } $LogDir
      }
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

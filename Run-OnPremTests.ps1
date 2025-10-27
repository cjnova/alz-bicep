param(
  [int]$IntervalSec = 60,
  [string]$LogDir = "/var/log/net-resilience"
)

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
  New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Detect region and zone from IMDS
try {
  $headers = @{ Metadata = "true" }
  $location = Invoke-RestMethod -Headers $headers -Uri "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01"
  $zone     = Invoke-RestMethod -Headers $headers -Uri "http://169.254.169.254/metadata/instance/compute/zone?api-version=2021-02-01"
  $env:AZ_LOCATION = $location
  $env:AZ_ZONE     = $zone
} catch {
  $env:AZ_LOCATION = "unknown"
  $env:AZ_ZONE     = "unknown"
}

$instanceId = (hostname)

function Write-EventJson([hashtable]$h) {
  $line = ($h | ConvertTo-Json -Compress)
  $date = (Get-Date -Format 'yyyy-MM-dd')
  $file = Join-Path $LogDir "net-$date.jsonl"
  Add-Content -Path $file -Value $line
}

# Define on-prem targets
$targets = @(
  @{ Host = "10.0.0.10"; Protocol = "ICMP" },
  @{ Host = "10.0.0.20"; Protocol = "HTTP"; Url = "https://10.0.0.20/health" }
)

while ($true) {
  $ts = (Get-Date).ToString("o")

  foreach ($target in $targets) {
    $cid = [guid]::NewGuid()

    if ($target.Protocol -eq "ICMP") {
      try {
        $pingResult = Test-Connection -ComputerName $target.Host -Count 1 -ErrorAction Stop
        $latency = $pingResult.ResponseTime
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; AzZone = $env:AZ_ZONE; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Host; Protocol = 'ICMP'; LatencyMs = $latency
          Success = $true; StatusCode = 'Reply'; Error = $null; CorrelationId = $cid
        }
      } catch {
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; AzZone = $env:AZ_ZONE; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Host; Protocol = 'ICMP'; LatencyMs = $null
          Success = $false; StatusCode = 'Timeout'; Error = $_.Exception.Message; CorrelationId = $cid
        }
      }
    }

    if ($target.Protocol -eq "HTTP") {
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $target.Url -TimeoutSec 10 -UseBasicParsing
        $sw.Stop()
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; AzZone = $env:AZ_ZONE; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Url; Protocol = 'HTTP'; LatencyMs = $sw.ElapsedMilliseconds
          Success = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
          StatusCode = "$($resp.StatusCode)"; Error = $null; CorrelationId = $cid
        }
      } catch {
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; AzZone = $env:AZ_ZONE; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Url; Protocol = 'HTTP'; LatencyMs = $null
          Success = $false; StatusCode = 'ERROR'; Error = $_.Exception.Message; CorrelationId = $cid
        }
      }
    }
  }

  Start-Sleep -Seconds $IntervalSec
}

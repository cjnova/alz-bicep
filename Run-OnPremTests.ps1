param(
  [int]$IntervalSec = 60,
  [string]$LogDir = "/var/log/net-resilience"
)

$env:AZ_LOCATION = (Test-Path '/etc/az_location') ? (Get-Content '/etc/az_location') : $env:AZ_LOCATION
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
  @{ Host = "10.0.0.20"; Protocol = "HTTP"; Port = 443; Url = "https://10.0.0.20/health" }
)

while ($true) {
  $ts = (Get-Date).ToString("o")

  foreach ($target in $targets) {
    $cid = [guid]::NewGuid()

    if ($target.Protocol -eq "ICMP") {
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ping = Test-Connection -ComputerName $target.Host -Count 1 -ErrorAction Stop
        $sw.Stop()
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Host; Protocol = 'ICMP'; LatencyMs = $sw.ElapsedMilliseconds
          Success = $true; StatusCode = 'Reply'; Error = $null; CorrelationId = $cid
        }
      } catch {
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Host; Protocol = 'ICMP'; LatencyMs = $null
          Success = $false; StatusCode = 'Timeout'; Error = $_.Exception.Message; CorrelationId = $cid
        }
      }
    }

    if ($target.Protocol -eq "HTTP") {
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $target.Url -TimeoutSec 10
        $sw.Stop()
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Url; Protocol = 'HTTP'; LatencyMs = $sw.ElapsedMilliseconds
          Success = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
          StatusCode = "$($resp.StatusCode)"; Error = $null; CorrelationId = $cid
        }
      } catch {
        Write-EventJson @{
          TimeGenerated = $ts; AzLocation = $env:AZ_LOCATION; VmInstance = $instanceId
          TestType = 'OnPrem'; Target = $target.Url; Protocol = 'HTTP'; LatencyMs = $null
          Success = $false; StatusCode = 'ERROR'; Error = $_.Exception.Message; CorrelationId = $cid
        }
      }
    }
  }

  Start-Sleep -Seconds $IntervalSec
}

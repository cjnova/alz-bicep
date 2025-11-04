<#
.SYNOPSIS
    Automatically configures Azure Monitor data source in Grafana.

.DESCRIPTION
    This script uses the Grafana HTTP API to automatically add Log Analytics Workspace
    as a data source in Azure Managed Grafana with managed identity authentication.
    
    This eliminates the need for manual UI configuration after deployment.

.PARAMETER ResourceGroupName
    The name of the Azure resource group containing Grafana and LAW.

.PARAMETER GrafanaName
    The name of the Azure Managed Grafana instance.

.PARAMETER WorkspaceName
    The name of the Log Analytics Workspace to add as a data source.

.PARAMETER SubscriptionId
    The Azure subscription ID. Defaults to current subscription.

.EXAMPLE
    .\Configure-Grafana-DataSource.ps1 `
        -ResourceGroupName "rg-fileshare-alias" `
        -GrafanaName "grafana-netres-prod" `
        -WorkspaceName "law-net-resilience"
    
    Configures the LAW as a data source in Grafana using default subscription.

.NOTES
    Prerequisites:
    - Azure CLI installed and authenticated (az login)
    - Grafana must have Monitoring Reader role on LAW (configured via Bicep RBAC)
    - User must have Grafana Admin role on the Grafana instance
    
    Author: Azure Monitoring Team
    Date: November 2025
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-fileshare-alias",
    
    [Parameter(Mandatory=$false)]
    [string]$GrafanaName = "grafana-netres-prod",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = "law-net-resilience",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = (az account show --query id -o tsv)
)

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Section {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# ============================================================================
# Get Grafana Endpoint
# ============================================================================
Write-Section "Retrieving Grafana Configuration"

Write-Host "Checking if Grafana resource exists..." -ForegroundColor White

# First check if resource exists using generic resource command (faster and more reliable)
$grafanaResourceExists = az resource show `
    --resource-group $ResourceGroupName `
    --name $GrafanaName `
    --resource-type "Microsoft.Dashboard/grafana" `
    --query id -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not $grafanaResourceExists) {
    Write-Error-Custom "Grafana resource '$GrafanaName' not found in resource group '$ResourceGroupName'"
    Write-Host "`nPossible issues:" -ForegroundColor Yellow
    Write-Host "  1. Grafana not deployed (check enableGrafana parameter)" -ForegroundColor Gray
    Write-Host "  2. Wrong resource group or Grafana name" -ForegroundColor Gray
    Write-Host "  3. Deployment still in progress" -ForegroundColor Gray
    Write-Host "`nVerify with:" -ForegroundColor Yellow
    Write-Host "  az resource list --resource-group $ResourceGroupName --resource-type 'Microsoft.Dashboard/grafana' -o table" -ForegroundColor Gray
    exit 1
}

Write-Host "Getting Grafana endpoint..." -ForegroundColor White
$grafanaEndpoint = az grafana show `
    --name $GrafanaName `
    --resource-group $ResourceGroupName `
    --query properties.endpoint -o tsv

if ($LASTEXITCODE -ne 0 -or -not $grafanaEndpoint) {
    Write-Error-Custom "Failed to get Grafana endpoint"
    Write-Host "`nThis might indicate:" -ForegroundColor Yellow
    Write-Host "  1. Azure CLI Grafana extension not installed: az extension add --name amg" -ForegroundColor Gray
    Write-Host "  2. Grafana resource in bad state" -ForegroundColor Gray
    exit 1
}

Write-Success "Grafana endpoint: $grafanaEndpoint"

# ============================================================================
# Get Log Analytics Workspace Details
# ============================================================================
Write-Section "Retrieving Log Analytics Workspace"

Write-Host "Getting LAW resource ID..." -ForegroundColor White
$lawResourceId = az monitor log-analytics workspace show `
    --name $WorkspaceName `
    --resource-group $ResourceGroupName `
    --query id -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not $lawResourceId) {
    Write-Error-Custom "Failed to get LAW resource ID"
    Write-Host "`nVerify LAW exists:" -ForegroundColor Yellow
    Write-Host "  az monitor log-analytics workspace show --name $WorkspaceName --resource-group $ResourceGroupName" -ForegroundColor Gray
    exit 1
}

Write-Success "LAW Resource ID: $lawResourceId"

# ============================================================================
# Get Access Token for Grafana API
# ============================================================================
Write-Section "Authenticating to Grafana API"

Write-Host "Obtaining access token..." -ForegroundColor White
$token = az account get-access-token --resource https://grafana.azure.com --query accessToken -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not $token) {
    Write-Error-Custom "Failed to get access token"
    Write-Host "`nMake sure you're logged in:" -ForegroundColor Yellow
    Write-Host "  az login" -ForegroundColor Gray
    exit 1
}

Write-Success "Access token obtained"

# ============================================================================
# Configure Data Source
# ============================================================================
Write-Section "Adding Data Source to Grafana"

# Prepare data source configuration
$dataSourceName = "Azure Monitor - $WorkspaceName"
$dataSourceConfig = @{
    name = $dataSourceName
    type = "grafana-azure-monitor-datasource"
    access = "proxy"
    isDefault = $true
    jsonData = @{
        azureAuthType = "msi"
        subscriptionId = $SubscriptionId
        azureLogAnalyticsSameAs = $false
        logAnalyticsDefaultWorkspace = $lawResourceId
        logAnalyticsSubscriptionId = $SubscriptionId
    }
} | ConvertTo-Json -Depth 10

# Prepare headers
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

Write-Host "Adding data source '$dataSourceName'..." -ForegroundColor White

try {
    $response = Invoke-RestMethod `
        -Uri "$grafanaEndpoint/api/datasources" `
        -Method Post `
        -Headers $headers `
        -Body $dataSourceConfig `
        -ErrorAction Stop
    
    Write-Success "Data source added successfully!"
    Write-Host "  Data source ID: $($response.id)" -ForegroundColor Gray
    Write-Host "  Data source UID: $($response.uid)" -ForegroundColor Gray
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Warning-Custom "Data source '$dataSourceName' already exists"
        
        # Try to update instead
        Write-Host "`nAttempting to update existing data source..." -ForegroundColor White
        
        try {
            # Get existing data source ID
            $existingDs = Invoke-RestMethod `
                -Uri "$grafanaEndpoint/api/datasources/name/$([uri]::EscapeDataString($dataSourceName))" `
                -Method Get `
                -Headers $headers `
                -ErrorAction Stop
            
            # Prepare update configuration
            $updateConfig = @{
                id = $existingDs.id
                uid = $existingDs.uid
                name = $dataSourceName
                type = "grafana-azure-monitor-datasource"
                access = "proxy"
                isDefault = $true
                jsonData = @{
                    azureAuthType = "msi"
                    subscriptionId = $SubscriptionId
                    azureLogAnalyticsSameAs = $false
                    logAnalyticsDefaultWorkspace = $lawResourceId
                    logAnalyticsSubscriptionId = $SubscriptionId
                }
            } | ConvertTo-Json -Depth 10
            
            $updateResponse = Invoke-RestMethod `
                -Uri "$grafanaEndpoint/api/datasources/$($existingDs.id)" `
                -Method Put `
                -Headers $headers `
                -Body $updateConfig `
                -ErrorAction Stop
            
            Write-Success "Data source updated successfully!"
            Write-Host "  Data source ID: $($updateResponse.datasource.id)" -ForegroundColor Gray
            
        } catch {
            Write-Error-Custom "Failed to update existing data source"
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
        
    } else {
        Write-Error-Custom "Failed to add data source"
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Host "  Status Code: $statusCode" -ForegroundColor Red
            
            if ($statusCode -eq 403) {
                Write-Host "`nPermission issue detected:" -ForegroundColor Yellow
                Write-Host "  1. Verify you have Grafana Admin role on the Grafana instance" -ForegroundColor Gray
                Write-Host "  2. Check in Azure Portal > Grafana > Access control (IAM)" -ForegroundColor Gray
                Write-Host "  3. Add yourself as 'Grafana Admin' if missing" -ForegroundColor Gray
            }
        }
        exit 1
    }
}

# ============================================================================
# Verify Configuration
# ============================================================================
Write-Section "Verification"

try {
    $dataSources = Invoke-RestMethod `
        -Uri "$grafanaEndpoint/api/datasources" `
        -Method Get `
        -Headers $headers `
        -ErrorAction Stop
    
    $azureMonitorDs = $dataSources | Where-Object { $_.name -eq $dataSourceName }
    
    if ($azureMonitorDs) {
        Write-Success "Data source verified in Grafana"
        Write-Host "  Name: $($azureMonitorDs.name)" -ForegroundColor Gray
        Write-Host "  Type: $($azureMonitorDs.type)" -ForegroundColor Gray
        Write-Host "  Default: $($azureMonitorDs.isDefault)" -ForegroundColor Gray
        Write-Host "  UID: $($azureMonitorDs.uid)" -ForegroundColor Gray
    } else {
        Write-Warning-Custom "Could not verify data source in list"
    }
    
} catch {
    Write-Warning-Custom "Could not retrieve data sources list for verification"
}

# ============================================================================
# Summary
# ============================================================================
Write-Section "Configuration Complete!"

Write-Host "✓ Azure Monitor data source configured successfully" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

Write-Host "`n1. " -NoNewline -ForegroundColor Yellow
Write-Host "Open Grafana in your browser:"
Write-Host "   $grafanaEndpoint" -ForegroundColor Gray

Write-Host "`n2. " -NoNewline -ForegroundColor Yellow
Write-Host "Navigate to: Connections > Data sources"

Write-Host "`n3. " -NoNewline -ForegroundColor Yellow
Write-Host "Verify '$dataSourceName' is listed and working"

Write-Host "`n4. " -NoNewline -ForegroundColor Yellow
Write-Host "Create a dashboard with KQL queries:"
Write-Host "   - Click 'Dashboards' > 'New' > 'New Dashboard'" -ForegroundColor Gray
Write-Host "   - Add a panel and select '$dataSourceName'" -ForegroundColor Gray
Write-Host "   - Use KQL to query NetResilience_CL table:" -ForegroundColor Gray
Write-Host "" -ForegroundColor Gray
Write-Host "   NetResilience_CL" -ForegroundColor DarkGray
Write-Host "   | where TimeGenerated > ago(1h)" -ForegroundColor DarkGray
Write-Host "   | summarize " -ForegroundColor DarkGray
Write-Host "       AvgLatency = avg(LatencyMs)," -ForegroundColor DarkGray
Write-Host "       FailureRate = countif(Success == false) * 100.0 / count()" -ForegroundColor DarkGray
Write-Host "       by bin(TimeGenerated, 5m), Target" -ForegroundColor DarkGray

Write-Host "`n5. " -NoNewline -ForegroundColor Yellow
Write-Host "Example queries to try:"
Write-Host "   - Latency trends: Chart AvgLatency over time" -ForegroundColor Gray
Write-Host "   - Failure rates: Chart FailureRate by Target" -ForegroundColor Gray
Write-Host "   - Zone comparison: Compare metrics across AzZone" -ForegroundColor Gray

Write-Host ""

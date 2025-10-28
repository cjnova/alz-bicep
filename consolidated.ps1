# ================================
# Net Resilience Deployment Script
# ================================

# --- Variables ---
$SubscriptionId  = "<your-subscription-id>"
$RG              = "slz-pro-zb1-ResiliencyTesting"
$Location        = "brazilsouth"
$LawName         = "netresilience-law"
$DcrName         = "netresilience-dcr"
$GrafanaName     = "netresilience-grafana"
$AutomationAcct  = "netresilience-automation"
$RunbookName     = "Control-OnPremTests"
$CredName        = "VmLocalAdmin"
$VmNames         = @("vmtest001","vmtest002","vmtest003")

# --- Step 0: Connect ---
Connect-AzAccount -Tenant "<tenant-id>"
Select-AzSubscription -SubscriptionId $SubscriptionId

# --- Step 1: Create Log Analytics Workspace ---
New-AzOperationalInsightsWorkspace `
  -ResourceGroupName $RG `
  -Name $LawName `
  -Location $Location `
  -Sku PerGB2018

# --- Step 2: Create Custom Table ---
# Note: As of today, custom table creation is only exposed via REST/ARM/Bicep.
# In PowerShell, you can call the REST API directly:
$token = (Get-AzAccessToken).Token
$uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/$LawName/tables/NetworkResilience_CL?api-version=2022-10-01"
$body = @{
  properties = @{
    schema = @{
      name = "NetworkResilience_CL"
      columns = @(
        @{ name="TimeGenerated"; type="DateTime" },
        @{ name="AzLocation"; type="String" },
        @{ name="AzZone"; type="String" },
        @{ name="VmInstance"; type="String" },
        @{ name="TestType"; type="String" },
        @{ name="Target"; type="String" },
        @{ name="Protocol"; type="String" },
        @{ name="LatencyMs"; type="Int64" },
        @{ name="Success"; type="Boolean" },
        @{ name="StatusCode"; type="String" },
        @{ name="Error"; type="String" },
        @{ name="CorrelationId"; type="String" }
      )
    }
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Method Put -Uri $uri -Headers @{Authorization="Bearer $token"} -Body $body -ContentType "application/json"

# --- Step 3: Create Data Collection Rule ---
New-AzDataCollectionRule `
  -ResourceGroupName $RG `
  -Name $DcrName `
  -Location $Location `
  -RuleFilePath "./netresilience-dcr.json"

# --- Step 4: Associate DCR with VMs ---
foreach ($vm in $VmNames) {
    New-AzDataCollectionRuleAssociation `
      -ResourceGroupName $RG `
      -AssociationName "$DcrName-assoc-$vm" `
      -ResourceId "/subscriptions/$SubscriptionId/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachines/$vm" `
      -RuleId "/subscriptions/$SubscriptionId/resourceGroups/$RG/providers/Microsoft.Insights/dataCollectionRules/$DcrName"
}

# --- Step 5: Create Managed Grafana ---
New-AzGrafana `
  -ResourceGroupName $RG `
  -Name $GrafanaName `
  -Location $Location `
  -Sku Standard

# --- Step 6: Import Grafana Dashboard ---
Import-AzGrafanaDashboard `
  -ResourceGroupName $RG `
  -Name $GrafanaName `
  -InputFile "./netresilience-dashboard.json"

# --- Step 7: Create Automation Account ---
New-AzAutomationAccount `
  -ResourceGroupName $RG `
  -Name $AutomationAcct `
  -Location $Location `
  -Plan Free

# --- Step 8: Import Required Modules ---
Import-AzAutomationModule `
  -ResourceGroupName $RG `
  -AutomationAccountName $AutomationAcct `
  -Name "Az.Accounts"

Import-AzAutomationModule `
  -ResourceGroupName $RG `
  -AutomationAccountName $AutomationAcct `
  -Name "Az.Compute"

# --- Step 9: Create Credential Asset ---
New-AzAutomationCredential `
  -ResourceGroupName $RG `
  -AutomationAccountName $AutomationAcct `
  -Name $CredName `
  -Value (New-Object System.Management.Automation.PSCredential("<local-admin-username>", (ConvertTo-SecureString "<local-admin-password>" -AsPlainText -Force)))

# --- Step 10: Create Runbook ---
New-AzAutomationRunbook `
  -ResourceGroupName $RG `
  -AutomationAccountName $AutomationAcct `
  -Name $RunbookName `
  -Type PowerShell `
  -Location $Location

# --- Step 11: Upload Runbook Script ---
$runbookScript = @'
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("start","stop","restart","status")]
    [string]$Action
)

$ResourceGroup = "slz-pro-zb1-ResiliencyTesting"
$VmNames = @("vmtest001","vmtest002","vmtest003")
$cred = Get-AutomationPSCredential -Name "VmLocalAdmin"

$inlineScript = @"
param([string]`$Action)
if (`$Action -eq "start") {
    sudo systemctl start onprem-tests.service
    sudo systemctl status onprem-tests.service --no-pager -l
} elseif (`$Action -eq "stop") {
    sudo systemctl stop onprem-tests.service
    sudo systemctl status onprem-tests.service --no-pager -l
} elseif (`$Action -eq "restart") {
    sudo systemctl restart onprem-tests.service
    sudo systemctl status onprem-tests.service --no-pager -l
} elseif (`$Action -eq "status") {
    sudo systemctl status onprem-tests.service --no-pager -l
}
"@

foreach ($vm in $VmNames) {
    Write-Output "Running $Action on $vm..."
    Invoke-AzVMRunCommand `
        -ResourceGroupName $ResourceGroup `
        -Name $vm `
        -CommandId 'RunShellScript' `
        -ScriptString $inlineScript `
        -Parameters @{ "Action" = $Action } `
        -Credential $cred
}
'@

Set-AzAutomationRunbookContent `
  -ResourceGroupName $RG `
  -AutomationAccountName $AutomationAcct `
  -Name $RunbookName `
  -Content $runbookScript

Publish-AzAutomationRunbook `
  -ResourceGroupName $RG `
  -AutomationAccountName $AutomationAcct `
  -Name $RunbookName

Write-Host "✅ Deployment complete."

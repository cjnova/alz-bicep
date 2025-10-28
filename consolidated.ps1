# ================================
# Net Resilience Deployment Script
# ================================

# --- Variables ---
$RG              = "slz-pro-zb1-ResiliencyTesting"
$Location        = "brazilsouth"
$LawName         = "netresilience-law"
$DcrName         = "netresilience-dcr"
$GrafanaName     = "netresilience-grafana"
$AutomationAcct  = "netresilience-automation"
$RunbookName     = "Control-OnPremTests"
$CredName        = "VmLocalAdmin"
$VmNames         = @("vmtest001","vmtest002","vmtest003")

# --- Step 1: Create Log Analytics Workspace ---
Write-Host "Creating Log Analytics Workspace..."
az monitor log-analytics workspace create `
  --resource-group $RG `
  --workspace-name $LawName `
  --location $Location

# --- Step 2: Create Custom Table ---
Write-Host "Creating custom table NetworkResilience_CL..."
az monitor log-analytics workspace table create `
  --resource-group $RG `
  --workspace-name $LawName `
  --name NetworkResilience_CL `
  --columns TimeGenerated=datetime,AzLocation=string,AzZone=string,VmInstance=string,TestType=string,Target=string,Protocol=string,LatencyMs=long,Success=bool,StatusCode=string,Error=string,CorrelationId=string

# --- Step 3: Create DCR ---
Write-Host "Creating Data Collection Rule..."
az monitor data-collection rule create `
  --resource-group $RG `
  --name $DcrName `
  --location $Location `
  --rule-file ./netresilience-dcr.json

# --- Step 4: Associate DCR with VMs ---
foreach ($vm in $VmNames) {
    Write-Host "Associating DCR with VM: $vm"
    az monitor data-collection rule association create `
      --resource-group $RG `
      --name "$DcrName-assoc-$vm" `
      --resource "/subscriptions/<your-subscription-id>/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachines/$vm" `
      --rule-id "/subscriptions/<your-subscription-id>/resourceGroups/$RG/providers/Microsoft.Insights/dataCollectionRules/$DcrName"
}

# --- Step 5: Create Managed Grafana ---
Write-Host "Creating Managed Grafana..."
az grafana create `
  --resource-group $RG `
  --name $GrafanaName `
  --location $Location `
  --sku Standard

# --- Step 6: Import Grafana Dashboard ---
Write-Host "Importing Grafana dashboard..."
az grafana dashboard import `
  --resource-group $RG `
  --name $GrafanaName `
  --definition ./netresilience-dashboard.json

# --- Step 7: Create Automation Account ---
Write-Host "Creating Automation Account..."
az automation account create `
  --resource-group $RG `
  --name $AutomationAcct `
  --location $Location `
  --sku Free

# --- Step 8: Import Required Modules ---
az automation module import `
  --resource-group $RG `
  --automation-account-name $AutomationAcct `
  --name Az.Accounts

az automation module import `
  --resource-group $RG `
  --automation-account-name $AutomationAcct `
  --name Az.Compute

# --- Step 9: Create Credential Asset ---
Write-Host "Creating credential asset (replace placeholders)..."
az automation credential create `
  --resource-group $RG `
  --automation-account-name $AutomationAcct `
  --name $CredName `
  --username "<local-admin-username>" `
  --password "<local-admin-password>"

# --- Step 10: Create Runbook ---
Write-Host "Creating Runbook..."
az automation runbook create `
  --resource-group $RG `
  --automation-account-name $AutomationAcct `
  --name $RunbookName `
  --type PowerShell `
  --location $Location

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

$runbookScript | Out-File -FilePath runbook-script.ps1 -Encoding utf8

az automation runbook replace-content `
  --resource-group $RG `
  --automation-account-name $AutomationAcct `
  --name $RunbookName `
  --content @runbook-script.ps1

az automation runbook publish `
  --resource-group $RG `
  --automation-account-name $AutomationAcct `
  --name $RunbookName

Write-Host "✅ Deployment complete."

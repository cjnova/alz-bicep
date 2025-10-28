# === Variables ===
RG="slz-pro-zb1-ResiliencyTesting"
LOCATION="brazilsouth"
LAW_NAME="netresilience-law"
DCR_NAME="netresilience-dcr"
GRAFANA_NAME="netresilience-grafana"
AUTOMATION_ACCOUNT="netresilience-automation"
RUNBOOK_NAME="Control-OnPremTests"
CRED_NAME="VmLocalAdmin"

# === Step 1: Create Log Analytics Workspace ===
az monitor log-analytics workspace create \
  --resource-group $RG \
  --workspace-name $LAW_NAME \
  --location $LOCATION

# === Step 2: Create Custom Table ===
az monitor log-analytics workspace table create \
  --resource-group $RG \
  --workspace-name $LAW_NAME \
  --name NetworkResilience_CL \
  --columns TimeGenerated=datetime,AzLocation=string,AzZone=string,VmInstance=string,TestType=string,Target=string,Protocol=string,LatencyMs=long,Success=bool,StatusCode=string,Error=string,CorrelationId=string

# === Step 3: Create DCR ===
az monitor data-collection rule create \
  --resource-group $RG \
  --name $DCR_NAME \
  --location $LOCATION \
  --rule-file ./netresilience-dcr.json

# === Step 4: Associate DCR with VMs ===
for VM in vmtest001 vmtest002 vmtest003; do
  az monitor data-collection rule association create \
    --resource-group $RG \
    --name "${DCR_NAME}-assoc-$VM" \
    --resource "/subscriptions/<your-subscription-id>/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachines/$VM" \
    --rule-id "/subscriptions/<your-subscription-id>/resourceGroups/$RG/providers/Microsoft.Insights/dataCollectionRules/$DCR_NAME"
done

# === Step 5: Create Managed Grafana ===
az grafana create \
  --resource-group $RG \
  --name $GRAFANA_NAME \
  --location $LOCATION \
  --sku Standard

# === Step 6: Import Grafana Dashboard ===
az grafana dashboard import \
  --resource-group $RG \
  --name $GRAFANA_NAME \
  --definition ./netresilience-dashboard.json

# === Step 7: Create Automation Account ===
az automation account create \
  --resource-group $RG \
  --name $AUTOMATION_ACCOUNT \
  --location $LOCATION \
  --sku Free

# === Step 8: Import Required Modules ===
az automation module import \
  --resource-group $RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name Az.Accounts

az automation module import \
  --resource-group $RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name Az.Compute

# === Step 9: Create Credential Asset (replace with real values) ===
az automation credential create \
  --resource-group $RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name $CRED_NAME \
  --username "<local-admin-username>" \
  --password "<local-admin-password>"

# === Step 10: Create Runbook ===
az automation runbook create \
  --resource-group $RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name $RUNBOOK_NAME \
  --type PowerShell \
  --location $LOCATION

# === Step 11: Upload Runbook Script ===
cat > runbook-script.ps1 <<'EOF'
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
EOF

az automation runbook replace-content \
  --resource-group $RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name $RUNBOOK_NAME \
  --content @runbook-script.ps1

az automation runbook publish \
  --resource-group $RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name $RUNBOOK_NAME

echo "✅ Net Resilience stack deployed at resource group scope."

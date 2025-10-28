#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
SUBSCRIPTION="slz01-pro-zb1-regionalplatform001"
RG="slz-pro-zb1-ResiliencyTesting"
LOCATION="brazilsouth"
AUTOMATION_ACCOUNT="netresilience-automation"
RUNBOOK_NAME="Control-OnPremTests"
CRED_NAME="VmLocalAdmin"

# === Step 1: Set subscription ===
az account set --subscription "$SUBSCRIPTION"

# === Step 2: Create Automation Account ===
az automation account create \
  --resource-group "$RG" \
  --name "$AUTOMATION_ACCOUNT" \
  --location "$LOCATION" \
  --sku Free

# === Step 3: Import required modules ===
az automation module import \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name Az.Accounts

az automation module import \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name Az.Compute

# === Step 4: Create Credential Asset ===
# NOTE: Replace <username> and <password> with your VM local admin credentials
az automation credential create \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$CRED_NAME" \
  --username "<username>" \
  --password "<password>"

# === Step 5: Create Runbook ===
az automation runbook create \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK_NAME" \
  --type PowerShell \
  --location "$LOCATION"

# === Step 6: Upload Runbook Script ===
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
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK_NAME" \
  --content @runbook-script.ps1

# === Step 7: Publish Runbook ===
az automation runbook publish \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK_NAME"

echo "✅ Runbook $RUNBOOK_NAME created and published in Automation Account $AUTOMATION_ACCOUNT"

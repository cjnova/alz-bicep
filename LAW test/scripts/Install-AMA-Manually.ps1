<#
.SYNOPSIS
    Manually installs Azure Monitor Agent (AMA) on VMs with user-assigned managed identity.

.DESCRIPTION
    This script manually installs the Azure Monitor Agent extension on virtual machines
    when DCR associations don't automatically trigger the installation. This can happen
    due to timing issues or Azure service delays.
    
    The script:
    - Retrieves the user-assigned managed identity resource ID
    - Installs AMA extension on each VM with proper authentication settings
    - Configures auto-upgrade for the extension
    
.PARAMETER ResourceGroup
    The name of the Azure resource group containing the VMs.
    Default: rg-fileshare-alias

.PARAMETER SubscriptionId
    The Azure subscription ID.
    Default: a1099149-0cc6-4bfb-a427-562663c96a2a

.PARAMETER VmNamePrefix
    The prefix used for VM names (e.g., 'vmnetres' creates vmnetres-1, vmnetres-2, etc.).
    Default: vmnetres

.PARAMETER VmCount
    The number of VMs to install AMA on.
    Default: 1

.PARAMETER ManagedIdentityName
    The name of the user-assigned managed identity used for AMA authentication.
    Default: id-ama-net-resilience

.EXAMPLE
    .\Install-AMA-Manually.ps1
    
    Installs AMA on all VMs using default parameters.

.EXAMPLE
    .\Install-AMA-Manually.ps1 -VmCount 3 -ResourceGroup "my-rg"
    
    Installs AMA on 3 VMs in the specified resource group.

.NOTES
    Prerequisites:
    - Azure CLI installed and authenticated (az login)
    - Appropriate permissions on the resource group and VMs
    - User-assigned managed identity must exist
    - User-assigned identity must have Monitoring Metrics Publisher role on DCR
    
    Author: Azure Monitoring Team
    Date: November 2025
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-fileshare-alias",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "a1099149-0cc6-4bfb-a427-562663c96a2a",
    
    [Parameter(Mandatory=$false)]
    [string]$VmNamePrefix = "vmnetres",
    
    [Parameter(Mandatory=$false)]
    [int]$VmCount = 1,
    
    [Parameter(Mandatory=$false)]
    [string]$ManagedIdentityName = "id-ama-net-resilience"
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
# Set Azure Context
# ============================================================================
Write-Section "Setting Azure Context"

try {
    az account set --subscription $SubscriptionId 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set subscription"
    }
    $currentSub = az account show --query name -o tsv
    Write-Success "Using subscription: $currentSub"
} catch {
    Write-Error-Custom "Failed to set subscription. Make sure you're logged in with 'az login'"
    exit 1
}

# ============================================================================
# Get User-Assigned Managed Identity
# ============================================================================
Write-Section "Retrieving User-Assigned Managed Identity"

$identityResourceId = az identity show `
    --name $ManagedIdentityName `
    --resource-group $ResourceGroup `
    --query id -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not $identityResourceId) {
    Write-Error-Custom "Could not find managed identity '$ManagedIdentityName' in resource group '$ResourceGroup'"
    Write-Host "`nMake sure the managed identity exists:" -ForegroundColor Yellow
    Write-Host "  az identity show --name $ManagedIdentityName --resource-group $ResourceGroup" -ForegroundColor Gray
    exit 1
}

Write-Success "Found managed identity: $ManagedIdentityName"
Write-Host "  Resource ID: $identityResourceId" -ForegroundColor Gray

# ============================================================================
# Install AMA on Each VM
# ============================================================================
Write-Section "Installing Azure Monitor Agent"

$successCount = 0
$failedVMs = @()

for ($i = 1; $i -le $VmCount; $i++) {
    $vmName = "${VmNamePrefix}-${i}"
    
    Write-Host "`nProcessing VM: $vmName" -ForegroundColor White
    
    # Check if VM exists
    $vmExists = az vm show --name $vmName --resource-group $ResourceGroup --query id -o tsv 2>$null
    
    if ($LASTEXITCODE -ne 0 -or -not $vmExists) {
        Write-Error-Custom "VM '$vmName' not found in resource group '$ResourceGroup'"
        $failedVMs += $vmName
        continue
    }
    
    # Check if AMA is already installed
    $existingAma = az vm extension show `
        --vm-name $vmName `
        --resource-group $ResourceGroup `
        --name AzureMonitorLinuxAgent `
        --query "provisioningState" -o tsv 2>$null
    
    if ($existingAma -eq "Succeeded") {
        Write-Warning-Custom "AMA already installed on $vmName (State: Succeeded)"
        Write-Host "  Skipping installation. Use --force to reinstall." -ForegroundColor Gray
        $successCount++
        continue
    } elseif ($existingAma) {
        Write-Warning-Custom "AMA exists on $vmName but state is: $existingAma"
        Write-Host "  Attempting to reinstall..." -ForegroundColor Gray
    }
    
    # Install AMA extension
    Write-Host "  Installing AMA extension..." -ForegroundColor Cyan
    
    # Create settings JSON file (more reliable than inline JSON in PowerShell)
    $settingsFile = Join-Path $env:TEMP "ama-settings-$vmName.json"
    $settingsContent = @{
        authentication = @{
            managedIdentity = @{
                "identifier-name" = "mi_res_id"
                "identifier-value" = $identityResourceId
            }
        }
    }
    $settingsContent | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsFile -Encoding utf8
    
    # Capture both stdout and stderr to show detailed errors
    $output = az vm extension set `
        --name AzureMonitorLinuxAgent `
        --publisher Microsoft.Azure.Monitor `
        --vm-name $vmName `
        --resource-group $ResourceGroup `
        --enable-auto-upgrade true `
        --settings "@$settingsFile" `
        --no-wait 2>&1
    
    # Clean up temp file
    Remove-Item -Path $settingsFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "AMA installation started for $vmName"
        $successCount++
    } else {
        Write-Error-Custom "Failed to install AMA on $vmName"
        Write-Host "  Error details:" -ForegroundColor Red
        $output | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
        $failedVMs += $vmName
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Section "Installation Summary"

Write-Host "Successfully started AMA installation on: $successCount / $VmCount VMs" -ForegroundColor $(if ($successCount -eq $VmCount) { "Green" } else { "Yellow" })

if ($failedVMs.Count -gt 0) {
    Write-Host "`nFailed VMs:" -ForegroundColor Red
    $failedVMs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host "`n" -NoNewline
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

Write-Host "`n1. " -NoNewline -ForegroundColor Yellow
Write-Host "Wait 5-10 minutes for AMA to install and initialize"

Write-Host "`n2. " -NoNewline -ForegroundColor Yellow
Write-Host "Verify AMA extension status:"
Write-Host "   az vm extension list --vm-name ${VmNamePrefix}-1 --resource-group $ResourceGroup --query `"[?name=='AzureMonitorLinuxAgent'].{Name:name,State:provisioningState,Version:typeHandlerVersion}`" -o table" -ForegroundColor Gray

Write-Host "`n3. " -NoNewline -ForegroundColor Yellow
Write-Host "Check AMA logs on the VM (via SSH):"
Write-Host "   sudo cat /var/opt/microsoft/azuremonitoragent/log/mdsd.err" -ForegroundColor Gray
Write-Host "   sudo systemctl status azuremonitoragent" -ForegroundColor Gray

Write-Host "`n4. " -NoNewline -ForegroundColor Yellow
Write-Host "Verify DCR association exists:"
Write-Host "   az monitor data-collection rule association list --resource `"/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/${VmNamePrefix}-1`" -o table" -ForegroundColor Gray

Write-Host "`n5. " -NoNewline -ForegroundColor Yellow
Write-Host "Wait 15-20 minutes, then query Log Analytics for data:"
Write-Host "   NetResilience_CL | take 10" -ForegroundColor Gray

Write-Host "`n6. " -NoNewline -ForegroundColor Yellow
Write-Host "Verify cloud-init setup on VM:"
Write-Host "   ls -la /opt/net-resilience/" -ForegroundColor Gray
Write-Host "   systemctl status net-resilience" -ForegroundColor Gray
Write-Host "   ls -la /var/log/net-resilience/" -ForegroundColor Gray

Write-Host ""

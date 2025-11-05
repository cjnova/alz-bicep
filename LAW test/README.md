# Network Resilience Monitoring - Azure Infrastructure

Automated network resilience testing infrastructure that deploys Azure Monitor Agent on Linux VMs to collect custom network performance metrics into Log Analytics Workspace.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Monitoring & Dashboards](#monitoring--dashboards)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

This solution deploys and configures:

- **Log Analytics Workspace** with custom table for network metrics
- **Data Collection Rule (DCR)** for JSON log ingestion (no DCE - public endpoint)
- **Ubuntu 24.04 VMs** (3x across availability zones 1/2/3) with automated network testing
- **User-Assigned Managed Identity** for AMA authentication
- **Azure Monitor Linux Agent (AMA)** for log collection
- **PowerShell-based network tests** (ICMP + HTTP) running as systemd service

### Key Features

- ✅ **No Data Collection Endpoint (DCE)** - Uses public ingestion endpoint for simplicity
- ✅ **Type-Safe JSON Logging** - PowerShell explicit type casting ensures proper data types
- ✅ **Multi-Zone Deployment** - VMs distributed across availability zones for resilience testing
- ✅ **Automated Testing** - Cloud-init configures PowerShell scripts and systemd service
- ✅ **Entra ID SSH** - AADSSHLoginForLinux extension for secure access
- ✅ **Cross-RG VNet Support** - Deploy VMs into VNets in different resource groups
- ✅ **Optional RBAC** - Deploy without User Access Administrator role

### Estimated Monthly Cost

- **Log Analytics**: ~$10/month (150 MB/day from 3 VMs)
- **Virtual Machines**: ~$180/month (3x Standard_B2als_v2)
- **Total**: ~$190/month

---

## 🏗️ Architecture

### Component Diagram

```text
┌─────────────────────────────────────────────────────────────────────┐
│                   Log Analytics Workspace                           │
│                   (NetResilience_CL custom table)                   │
│                                                                     │
│  - Retention: 30 days                                               │
│  - SKU: PerGB2018                                                   │
│  - Schema: 14 columns (TimeGenerated, LatencyMs, Success, etc.)     │
└────────────▲────────────────────────────────────────────────────────┘
             │
             │ Public Ingestion Endpoint (no DCE)
             │
┌────────────┴────────────────────────────────────────────────────────┐
│              Data Collection Rule (DCR)                             │
│                                                                     │
│  - Stream: Custom-NetResilience_CL                                  │
│  - Data Source: logFiles (JSON format)                              │
│  - File Pattern: /var/log/net-resilience/net-*.jsonl                │
│  - No transformation (pass-through)                                 │
└────────────▲────────────────────────────────────────────────────────┘
             │
             │ DCR Association + RBAC (Monitoring Metrics Publisher)
             │
┌────────────┴────────────────────────────────────────────────────────┐
│           User-Assigned Managed Identity                            │
│           (id-ama-net-resilience)                                   │
│                                                                     │
│  - Shared across all 3 VMs                                          │
│  - Used by AMA for authentication to DCR/LAW                        │
└────────────▲────────────────────────────────────────────────────────┘
             │
    ┌────────┼────────┬────────────────┐
    │        │        │                │
    ▼        ▼        ▼                ▼
┌─────────┬─────────┬─────────┐   ┌──────────────┐
│ VM Zone1│ VM Zone2│ VM Zone3│   │   Dashboards │
│         │         │         │   │   (Portal)   │
│ AMA Ext │ AMA Ext │ AMA Ext │   │              │
│ AAD SSH │ AAD SSH │ AAD SSH │   │ 7 KQL Queries│
└─────────┴─────────┴─────────┘   └──────────────┘
     │         │         │
     └─────────┴─────────┘
             │
  PowerShell Tests (cloud-init)
  /var/log/net-resilience/*.jsonl
```

### Data Flow

1. **Test Execution**: PowerShell script runs continuously (systemd service)
   - ICMP tests: `Test-Connection` to configured hosts
   - HTTP tests: `Invoke-WebRequest` to configured URLs
   - Collects: Latency, Success/Fail, Status Codes

2. **Local Logging**: Test results written to JSON Lines format
   - File: `/var/log/net-resilience/net-YYYY-MM-DD.jsonl`
   - Format: One JSON object per line
   - Type-safe: Explicit casts ensure correct JSON types

3. **AMA Collection**: Azure Monitor Agent monitors log files
   - Authenticates via user-assigned managed identity
   - Reads files matching `/var/log/net-resilience/net-*.jsonl`
   - Streams data to DCR

4. **Ingestion**: Data Collection Rule processes and routes data
   - Validates against stream schema
   - No transformation (pass-through)
   - Sends to Log Analytics Workspace

5. **Storage**: Log Analytics stores in custom table
   - Table: `NetResilience_CL`
   - Indexed by TimeGenerated
   - 30-day retention

6. **Visualization**: Azure Portal Dashboards query and display data
   - KQL queries from `docs/Dashboard-KQL-Queries.md`
   - Real-time monitoring of network performance

---

## 📁 Repository Structure

```text
LAW test/
├── main.bicep                      # Main orchestration template
├── README.md                       # This file - deployment guide
│
├── modules/
│   └── vms.bicep                  # VM deployment module (cross-RG VNet support)
│
├── parameters/
│   └── main.bicepparam            # Deployment parameters + cloud-init script
│
├── scripts/
│   └── Install-AMA-Manually.ps1   # Manual extension installation (if RBAC disabled)
│
├── cfg/
│   └── cloud-config.yml           # Cloud-init configuration reference
│
└── docs/
    ├── README.md                  # Technical reference documentation
    └── Dashboard-KQL-Queries.md   # 7 pre-built dashboard queries
```

### Key Files

| File | Purpose |
|------|---------|
| `main.bicep` | Main orchestration - deploys LAW, DCR, managed identity, VMs |
| `parameters/main.bicepparam` | Deployment parameters + embedded cloud-init script |
| `modules/vms.bicep` | VM deployment module with cross-RG VNet support + AADSSHLoginForLinux extension |
| `scripts/Install-AMA-Manually.ps1` | Manual AMA installation script (for when RBAC not auto-assigned) |
| `docs/README.md` | Technical documentation (schema, RBAC, cloud-init details) |
| `docs/Dashboard-KQL-Queries.md` | 7 KQL queries for Azure Portal dashboards |

---

## 📋 Prerequisites

### 1. Azure Permissions

**During Deployment:**

- **Contributor** role on target resource group
- **Managed Identity Contributor** role on target resource group (to create user-assigned identity)

**For Automatic RBAC Assignment (Optional):**

- **User Access Administrator** role on target resource group
- If you don't have this role, set `enableRbacAssignments=false` and assign RBAC manually after deployment

### 2. PIM Role Activation (CRITICAL for Windows/PowerShell users)

⚠️ **IMPORTANT**: If using Privileged Identity Management (PIM), you MUST activate roles before running `az login`:

**Step-by-Step PIM Activation:**

1. **Azure Portal** → **Privileged Identity Management**
2. **My roles** → **Azure resources**
3. Find and **Activate** required roles:
   - Contributor (on target resource group or subscription)
   - Managed Identity Contributor (if needed)
   - User Access Administrator (if enableRbacAssignments=true)
4. **Wait 5 minutes** for activation to propagate
5. **PowerShell**: Run `az logout` to clear cached tokens
6. **PowerShell**: Run `az login` to get fresh token with PIM roles
7. **Verify**: Run `az role assignment list --assignee <your-upn> --all`

**Why this matters**: Azure CLI caches authentication tokens. If you activate PIM roles AFTER running `az login`, the cached token won't include the newly activated roles, causing "permission denied" errors during deployment.

### 3. Existing Azure Resources

| Resource | Requirement |
|----------|-------------|
| **Virtual Network** | Must exist before deployment |
| **Subnet** | Must exist in the VNet |
| **Resource Group** | Can be created or use existing |

**Note**: VNet and subnet can be in a different resource group - use the `vnetResourceGroup` parameter.

### 4. Local Tools

**Windows PowerShell (Recommended):**

- Azure CLI 2.50+: Install from [docs.microsoft.com/cli/azure/install-azure-cli](https://docs.microsoft.com/cli/azure/install-azure-cli)
- PowerShell 5.1+ or PowerShell 7+

**Verification:**

```powershell
# Check Azure CLI version
az --version

# Check you're logged in
az account show

# List resource groups
az group list -o table
```

### 5. Network Requirements

VMs need outbound internet access to:

- Azure Monitor endpoints (for AMA)
- ICMP/HTTP test targets (e.g., microsoft.com, google.com)
- Package repositories (for cloud-init)

---

## 🚀 Deployment Guide

### Step 1: Activate PIM Roles (if applicable)

⚠️ **CRITICAL**: If using PIM, activate roles FIRST (see Prerequisites section above), then proceed to Step 2.

### Step 2: Authenticate to Azure

```powershell
# Logout to clear cached tokens (if you activated PIM roles)
az logout

# Login to Azure
az login

# Set subscription
az account set --subscription "<subscription-id-or-name>"

# Verify roles
az role assignment list --assignee <your-upn> --all -o table
```

### Step 3: Configure Parameters

Edit `parameters/main.bicepparam` and update these values:

```bicep
// ========== Resource Naming ==========
param workspaceName = 'law-net-resilience'        // Log Analytics Workspace name
param dcrName = 'dcr-net-resilience-prod'         // Data Collection Rule name
param managedIdentityName = 'id-ama-net-resilience'  // User-assigned identity name

// ========== Deployment Settings ==========
param location = 'swedencentral'                  // Azure region
param enableRbacAssignments = true                // Set to false if no User Access Administrator

// ========== VNet Configuration ==========
param vnetName = 'vnet-prod'                      // Existing VNet name
param subnetName = 'snet-vms'                     // Existing subnet name
param vnetResourceGroup = ''                      // Leave empty if VNet in same RG, else specify RG name

// ========== VM Configuration ==========
param vmCount = 3                                 // Number of VMs (one per zone)
param vmNamePrefix = 'vmnetres'                   // VM name prefix (results in vmnetres-1, vmnetres-2, vmnetres-3)
param adminUsername = 'azureuser'                 // VM admin username
param adminPassword = '<secure-password>'         // VM admin password (use Key Vault reference in production)
```

**Security Note**: For production, use Key Vault references instead of plain-text passwords:

```bicep
param adminPassword = getSecret('<keyvault-id>', '<secret-name>')
```

### Step 4: Validate Deployment

```powershell
# Validate template
az deployment group validate `
  --resource-group <your-rg-name> `
  --template-file main.bicep `
  --parameters parameters/main.bicepparam
```

### Step 5: Preview Changes (What-If)

```powershell
# See what resources will be created
az deployment group what-if `
  --resource-group <your-rg-name> `
  --template-file main.bicep `
  --parameters parameters/main.bicepparam
```

**Expected Resources:**

- User-Assigned Managed Identity (1)
- Log Analytics Workspace (1)
- Custom Table (1)
- Data Collection Rule (1)
- Virtual Machines (3)
- Network Interfaces (3)
- Managed Disks (3)
- DCR Associations (3)
- RBAC Role Assignment (1) ← only if enableRbacAssignments=true

### Step 6: Deploy

```powershell
# Deploy infrastructure
az deployment group create `
  --resource-group <your-rg-name> `
  --template-file main.bicep `
  --parameters parameters/main.bicepparam `
  --name "net-resilience-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
```

**Expected Duration**: 10-15 minutes

### Step 7: Verify Deployment

```powershell
# Check deployment status
az deployment group list -g <your-rg-name> -o table

# List deployed resources
az resource list -g <your-rg-name> -o table

# Verify VMs are running
az vm list -g <your-rg-name> --query "[].{Name:name, PowerState:powerState}" -o table

# Check VM extensions
az vm extension list -g <your-rg-name> --vm-name vmnetres-1 -o table
```

---

## ⚙️ Post-Deployment Configuration

### Option A: Automatic (if enableRbacAssignments=true)

If you deployed with `enableRbacAssignments=true`, RBAC and extensions are configured automatically. Skip to **Verify Data Collection** below.

### Option B: Manual (if enableRbacAssignments=false)

If you deployed with `enableRbacAssignments=false` (e.g., you only have Contributor role), follow these steps:

#### Step 1: Assign RBAC Permissions

The user-assigned managed identity needs **Monitoring Metrics Publisher** role on the Data Collection Rule:

```powershell
# Get managed identity principal ID
$identityId = az identity show `
    --name id-ama-net-resilience `
    --resource-group <your-rg-name> `
    --query principalId -o tsv

# Get DCR resource ID
$dcrId = az monitor data-collection rule show `
    --name dcr-net-resilience-prod `
    --resource-group <your-rg-name> `
    --query id -o tsv

# Assign Monitoring Metrics Publisher role
az role assignment create `
    --assignee $identityId `
    --role "Monitoring Metrics Publisher" `
    --scope $dcrId

# Verify assignment
az role assignment list --scope $dcrId -o table
```

#### Step 2: Install VM Extensions

Run the provided PowerShell script to install **Azure Monitor Agent (AMA)**:

**Important**: The **AADSSHLoginForLinux** extension is already installed during VM provisioning via the Bicep template. This script only installs the AMA extension.

```powershell
# Navigate to scripts directory
cd "c:\repos\Santander\tests\LAW test\scripts"

# Install AMA on all VMs
.\Install-AMA-Manually.ps1

# Or with custom parameters
.\Install-AMA-Manually.ps1 `
    -ResourceGroup "your-rg-name" `
    -VmCount 3 `
    -ManagedIdentityName "id-ama-net-resilience"

# Optional: Install Guest Configuration agent (for Azure Policy compliance)
.\Install-AMA-Manually.ps1 -InstallGuestConfiguration
```

**What this script installs:**

- **AzureMonitorLinuxAgent (AMA)** extension
  - Collects custom logs from `/var/log/net-resilience/` directory
  - Sends data to Log Analytics Workspace via Data Collection Rule
  - Uses managed identity for authentication
  - Publisher: Microsoft.Azure.Monitor

**Optional: Guest Configuration Agent**

- **ConfigurationforLinux** extension (if `-InstallGuestConfiguration` flag used)
  - Enables Azure Policy guest configuration compliance
  - Automatically installed by Azure when policy configurations are assigned
  - Only install manually if you have specific Azure Policy requirements
  - Publisher: Microsoft.GuestConfiguration

**Already installed during VM provisioning:**

- **AADSSHLoginForLinux** extension
  - Enables Entra ID (Azure AD) authentication for SSH access
  - Required for `az ssh vm` command to work
  - Deployed automatically by Bicep template (`extensionAadJoinConfig`)
  - Publisher: Microsoft.Azure.ActiveDirectory

**Also on every Azure VM:**

- **Azure Linux Guest Agent (waagent)** 
  - Pre-installed on all Azure marketplace images
  - Manages VM extensions and communicates with Azure fabric
  - Cannot be installed as a VM extension

### Verify AMA Installation

```powershell
# Check extension status
az vm extension list `
    -g <your-rg-name> `
    --vm-name vmnetres-1 `
    --query "[].{Name:name, State:provisioningState, Publisher:publisher}" -o table
```

**Expected Output:**

| Name | State | Publisher |
|------|-------|-----------|
| AADSSHLoginForLinux | Succeeded | Microsoft.Azure.ActiveDirectory |
| AzureMonitorLinuxAgent | Succeeded | Microsoft.Azure.Monitor |

### Verify Data Collection

Wait 10-15 minutes after extension installation, then query Log Analytics:

```kql
NetResilience_CL
| take 10
| project TimeGenerated, VmInstance, Target, Protocol, LatencyMs, Success
```

**Expected**: Rows showing ICMP and HTTP test results from all 3 VMs.

### SSH into VM (Entra ID Login)

```bash
# SSH using Entra ID authentication
az ssh vm --name vmnetres-1 --resource-group <your-rg-name>

# Once logged in, check cloud-init completion
cloud-init status

# Check network testing service
systemctl status net-resilience

# View recent test results
tail -f /var/log/net-resilience/net-$(date +%Y-%m-%d).jsonl
```

---

## 📊 Monitoring & Dashboards

After deployment, create Azure Portal dashboards to visualize the data:

1. **Azure Portal** → **Dashboards** → **Create** → **New dashboard**
2. **Add tile** → **Markdown** (for title)
3. **Add tile** → **Logs** (for each query)
4. Paste KQL queries from `docs/Dashboard-KQL-Queries.md`

**Available Queries** (7 pre-built):

1. **Latency Trend** - Time chart showing average latency over time
2. **Failure Rate** - Table of failure percentages by target
3. **Latency Statistics** - Min/Avg/Max/P95 latency by target
4. **Zone Comparison** - Latency comparison across availability zones
5. **Protocol Breakdown** - Pie chart of ICMP vs HTTP tests
6. **Recent Failures** - Table of failed tests in last hour
7. **Success Rate by VM** - Bar chart comparing VMs

**Dashboard Layout Suggestion:**

```text
┌─────────────────────────────────────────────────────┐
│ Network Resilience Monitoring Dashboard             │
├──────────────────────┬──────────────────────────────┤
│ Latency Trend (Line) │ Failure Rate (Table)         │
├──────────────────────┼──────────────────────────────┤
│ Zone Comparison      │ Protocol Breakdown (Pie)     │
├──────────────────────┴──────────────────────────────┤
│ Recent Failures (Table - full width)                │
└─────────────────────────────────────────────────────┘
```

**Auto-Refresh**: Set dashboard to auto-refresh every 5 minutes.

---

## 🔧 Troubleshooting

### Issue 1: "Permission Denied" During Deployment

**Symptom**: Deployment fails with `AuthorizationFailed` or `Insufficient privileges`

**Cause**: PIM-activated roles not in current Azure CLI token

**Solution**:

```powershell
# 1. Logout and clear cached tokens
az logout

# 2. Login again to get fresh token with PIM roles
az login

# 3. Verify roles are present
az role assignment list --assignee <your-upn> --all -o table

# 4. Retry deployment
az deployment group create ...
```

### Issue 2: No Data in Log Analytics

**Symptom**: Query `NetResilience_CL | take 10` returns no results after 20+ minutes

**Possible Causes & Solutions:**

#### A. AMA Extension Not Installed

```powershell
# Check extension status
az vm extension list -g <your-rg-name> --vm-name vmnetres-1 -o table

# If AMA not installed, use manual installation script
.\scripts\Install-AMA-Manually.ps1
```

#### B. RBAC Not Assigned

```powershell
# Check if managed identity has Monitoring Metrics Publisher role
$identityId = az identity show --name id-ama-net-resilience -g <your-rg-name> --query principalId -o tsv
az role assignment list --assignee $identityId --all -o table

# If missing, assign role (see Post-Deployment Configuration)
```

#### C. DCR Association Missing

```powershell
# List DCR associations
az monitor data-collection rule association list `
    --resource "subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/vmnetres-1" `
    -o table

# If missing, check deployment logs
az deployment group show -g <your-rg-name> -n <deployment-name>
```

#### D. Cloud-Init Failed

```bash
# SSH to VM
az ssh vm --name vmnetres-1 -g <your-rg-name>

# Check cloud-init status
cloud-init status --long

# Check service status
systemctl status net-resilience

# View service logs
journalctl -u net-resilience -n 50

# Check if log files are being created
ls -la /var/log/net-resilience/
```

### Issue 3: "Workspace name already exists"

**Symptom**: Deployment fails with "The resource name already exists in deleted state"

**Cause**: Log Analytics Workspace was deleted but is in 14-day soft-delete period

**Solutions:**

#### Solution 1: Purge the Deleted Workspace (Immediate)

```powershell
# List deleted workspaces
az monitor log-analytics workspace list-deleted --resource-group <your-rg-name>

# Purge specific workspace
az monitor log-analytics workspace delete `
    --resource-group <your-rg-name> `
    --workspace-name law-net-resilience `
    --force true `
    --yes
```

#### Solution 2: Use a Different Name

Edit `parameters/main.bicepparam`:

```bicep
param workspaceName = 'law-net-resilience-v2'  // Change to unique name
```

#### Solution 3: Wait 14 Days

Workspace will be automatically purged after 14 days of soft-delete period.

### Issue 4: VNet Not Found

**Symptom**: Deployment fails with "VNet 'vnet-prod' not found"

**Cause**: VNet is in a different resource group

**Solution**:

Edit `parameters/main.bicepparam`:

```bicep
param vnetName = 'vnet-prod'
param vnetResourceGroup = 'rg-network'  // Specify the VNet's resource group
```

### Issue 5: Extension Installation Conflicts

**Symptom**: Extension installation fails with "A previous installation is in progress"

**Solution**:

```powershell
# Delete conflicting extension
az vm extension delete `
    --vm-name vmnetres-1 `
    -g <your-rg-name> `
    --name AzureMonitorLinuxAgent

# Wait 2 minutes, then retry installation
.\scripts\Install-AMA-Manually.ps1
```

### Issue 6: Type Mismatch in KQL Queries

**Symptom**: Queries fail with "Type mismatch" or filters don't work

**Cause**: Data ingested with wrong types (e.g., `Success="True"` instead of `Success=true`)

**Solution**: This should not occur with the fixed PowerShell script, but if it does:

```kql
// Use type conversion in queries
NetResilience_CL
| extend SuccessBool = tobool(Success)
| extend LatencyInt = toint(LatencyMs)
| where SuccessBool == true
```

**Prevention**: The PowerShell script in `parameters/main.bicepparam` uses explicit type casts (`[int]`, `[bool]`) to ensure correct JSON typing.

---

## 📚 Additional Resources

- **Technical Documentation**: [docs/README.md](docs/README.md)
- **Dashboard Queries**: [docs/Dashboard-KQL-Queries.md](docs/Dashboard-KQL-Queries.md)
- **Azure Monitor Documentation**: [docs.microsoft.com/azure/azure-monitor/](https://docs.microsoft.com/azure/azure-monitor/)
- **AMA Troubleshooting**: [docs.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-troubleshoot-linux-vm](https://docs.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-troubleshoot-linux-vm)

---

**Last Updated**: November 2025  
**Version**: 1.0  
**Maintained By**: SDS Public Cloud Azure Architecture Team

# Azure Monitoring Infrastructure - Net Resilience

Complete Azure monitoring solution with Log Analytics Workspace, Data Collection Rules, and Virtual Machines.

## 📁 Project Structure

```
LAW test/
├── main.bicep                      # Main orchestration template
├── README.md                       # This file - quick start guide
│
├── modules/                        # Reusable Bicep modules
│   └── vms.bicep                  # Virtual Machine deployment module
│
├── parameters/                     # Parameter files
│   ├── main.bicepparam            # Production deployment parameters (USE THIS)
│   └── vms.bicepparam             # VM module unit testing parameters
│
└── docs/                          # Detailed documentation
    └── README.md                  # Complete documentation & troubleshooting
```

## 🚀 Quick Start

### Prerequisites

- **Azure Subscription** with **Owner** or **User Access Administrator** role
  - If you only have **Contributor** role, see [Manual RBAC Assignment](docs/README.md#manual-rbac-assignment-for-contributor-role)
- Existing **Virtual Network** with subnet
- **Azure CLI** or **PowerShell** installed

### 0. Azure Connection

Before deploying, authenticate to Azure and set your subscription context:

```bash
# Azure CLI - Login to Azure
az login

# Set the subscription you want to use
az account set --subscription "<subscription-id-or-name>"

# Verify you're connected to the correct subscription
az account show --output table

# Create or select your resource group
az group create --name <your-rg-name> --location eastus
```

```powershell
# PowerShell - Login to Azure
Connect-AzAccount

# Set the subscription you want to use
Set-AzContext -Subscription "<subscription-id-or-name>"

# Verify you're connected to the correct subscription
Get-AzContext

# Create or select your resource group
New-AzResourceGroup -Name <your-rg-name> -Location eastus
```

### 1. Configure Parameters

Edit `parameters/main.bicepparam`:

```bicep
param vnetName = 'your-vnet-name'          // Update with your VNet
param subnetName = 'your-subnet-name'      // Update with your subnet
param adminPassword = ''                   // Leave empty for PowerShell (prompts securely); required for Azure CLI
param location = 'eastus'                  // Your preferred region
param enableRbacAssignments = true         // Set false if you only have Contributor role
```

### 2. Validate Template

Validate that the template is syntactically correct.

**Azure CLI** - requires password on command line:
```bash
az deployment group validate `
  --resource-group <your-rg-name> `
  --template-file main.bicep `
  --parameters parameters/main.bicepparam `
  --parameters adminPassword='YourSecureP@ssw0rd'
```

**PowerShell** - prompts securely for password:
```powershell
Test-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam
```

**Password Requirements:** Min 12 chars, uppercase, lowercase, number, special char

### 3. Preview Changes (What-If)

Preview what resources will be created/modified.

**Azure CLI** - provide password on command line:

```bash
az deployment group what-if `
  --resource-group <your-rg-name> `
  --template-file main.bicep `
  --parameters parameters/main.bicepparam `
  --parameters adminPassword='YourSecureP@ssw0rd'
```

**PowerShell** - will prompt for password securely:

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam `
  -WhatIf
```

### 4. Deploy

**Azure CLI** - provide password on command line:

```bash
az deployment group create `
  --resource-group <your-rg-name> `
  --template-file main.bicep `
  --parameters parameters/main.bicepparam `
  --parameters adminPassword='YourSecureP@ssw0rd' `
  --name "monitoring-deployment"
```

**PowerShell** - prompts for SecureString password:

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam `
  -Name "monitoring-deployment"
```

**Deployment takes ~10-15 minutes.**

## 📦 What Gets Deployed

- **User-Assigned Managed Identity** - Required for Azure Monitor Agent authentication
  - Shared across all 3 VMs (scalable approach)
  - Used by AMA to authenticate to DCR and LAW
- **Log Analytics Workspace** - Central log repository (30-day retention)
  - Custom table: `NetResilience_CL` with 14-field schema
- **Data Collection Rule** - Custom JSON log collection from `/var/log/net-resilience/`
  - Stream declarations define 14-field JSON schema (TimeGenerated, LocalTime, AzLocation, etc.)
  - No transformation applied - JSONL data flows through unchanged
  - No DCE required - AMA uses public endpoint for logFiles data source
- **Azure Dashboards** - Visualization with KQL queries (created manually via Azure Portal)
  - 7 pre-built dashboard queries provided
  - Native integration with Log Analytics Workspace
- **3 Virtual Machines** - Ubuntu 24.04, Standard_B2als_v2, across availability zones
  - **System-assigned identity**: For Entra ID login
  - **User-assigned identity**: For Azure Monitor Agent
  - Cloud-init with PowerShell 7 installation
  - Network monitoring scripts pre-configured
  - Log rotation configured for Azure Monitor Agent
- **DCR Associations** - Automatic Azure Monitor Agent installation on VMs
- **RBAC Permissions** - Automated role assignments:
  - User-assigned identity → DCR: Monitoring Metrics Publisher (AMA authentication)

## 🔍 Verify Deployment

```bash
# Check VMs
az vm list -g <your-rg-name> -o table

# Check AMA installation (wait 5-10 minutes)
az vm extension list -g <your-rg-name> --vm-name vmnetres1 -o table

# If AMA not installed, use manual installation script
# See scripts/Install-AMA-Manually.ps1

# Query logs
az monitor log-analytics query `
  -w <law-workspace-id> `
  --analytics-query "NetResilience_CL | take 10"
```

## 📊 Visualization with Azure Dashboards

After deployment, create Azure Portal dashboards to visualize the data:

1. **Navigate to**: Azure Portal → Dashboards → + New dashboard
2. **Use KQL queries from**: `docs/Dashboard-KQL-Queries.md`
3. **Key visualizations**:
   - Latency trends over time
   - Failure rates by target
   - VM performance comparison
   - Zone-level analysis
   - Real-time failure monitoring

**See complete dashboard setup guide**: [`docs/Dashboard-KQL-Queries.md`](docs/Dashboard-KQL-Queries.md)

## 🔧 Scripts

### Install-AMA-Manually.ps1

**Purpose**: Manually install Azure Monitor Agent (AMA) on VMs when DCR associations don't trigger automatic installation.

**Location**: `scripts/Install-AMA-Manually.ps1`

**Why needed**: While DCR associations _should_ automatically install AMA, this doesn't always happen reliably. This script provides a fallback to manually install the AMA extension with proper user-assigned managed identity authentication.

**Usage**:
```powershell
# Edit the script to set your values:
# - $resourceGroupName
# - $subscriptionId
# - $vmBaseName
# - $vmCount

# Run the script
.\scripts\Install-AMA-Manually.ps1
```

**What it does**:
1. Retrieves the user-assigned managed identity resource ID
2. Loops through all VMs
3. Installs the AMA extension with proper authentication settings
4. Provides verification commands

**After running**: Wait 5-10 minutes for logs to start flowing to Log Analytics Workspace.

## 📈 Querying Data

Once logs are flowing, you can query the `NetResilience_CL` table:

```kql
// Last 10 records
NetResilience_CL
| take 10

// Failures in last hour
NetResilience_CL
| where TimeGenerated > ago(1h)
| where Success == false
| project TimeGenerated, VmInstance, Target, Protocol, Error

// Average latency by target
NetResilience_CL
| where TimeGenerated > ago(1h)
| where Success == true
| summarize AvgLatency = avg(LatencyMs) by Target
| order by AvgLatency desc
```

**Full dashboard queries**: See `docs/Dashboard-KQL-Queries.md`

## ⚠️ If You Deployed with Contributor Role

If you set `enableRbacAssignments = false`:

1. **Resources are deployed** ✅ but RBAC is missing ❌
2. **Request an admin** with Owner/User Access Administrator role
3. **Have them run** the RBAC assignment template:
   ```bash
   az deployment group create `
     --resource-group <your-rg-name> `
     --template-file modules/rbac-assignments.bicep `
     --parameters parameters/rbac-assignments.bicepparam
   ```
4. See [Manual RBAC Assignment](docs/README.md#manual-rbac-assignment-for-contributor-role) for detailed instructions

## 📚 Full Documentation

See [docs/README.md](docs/README.md) for:
- Detailed architecture
- Complete parameter reference
- Post-deployment configuration
- Troubleshooting guide
- Cost optimization tips

## ⚠️ Common Issues

### Workspace Name Conflict (Soft-Delete)

If deployment fails with `WorkspaceInDeletingState` error, the LAW is in soft-delete (14-day retention):

**Quick Fix - Purge the workspace:**

```powershell
az monitor log-analytics workspace delete `
    --resource-group rg-fileshare-alias `
    --workspace-name law-net-resilience `
    --force true `
    --yes
```

**Or use a different name** in `parameters/main.bicepparam`:

```bicep
param workspaceName = 'law-net-resilience-v2'
```

**See full troubleshooting guide**: [docs/README.md#troubleshooting](docs/README.md#troubleshooting)

---

## 🧪 Module Testing

To test the VM module independently:

**1. Update VM parameters** in `parameters/vms.bicepparam`:
- Set `adminPassword`
- Set `vnetName` and `subnetName`

**2. Validate the module:**

```bash
az deployment group validate `
  --resource-group <your-rg-name> `
  --template-file modules/vms.bicep `
  --parameters parameters/vms.bicepparam
```

**3. Preview changes (What-If):**

```bash
az deployment group what-if `
  --resource-group <your-rg-name> `
  --template-file modules/vms.bicep `
  --parameters parameters/vms.bicepparam
```

**4. Deploy the module:**

```bash
az deployment group create `
  --resource-group <your-rg-name> `
  --template-file modules/vms.bicep `
  --parameters parameters/vms.bicepparam `
  --name "vm-test-deployment"
```

## 💡 Key Features

- ✅ **Security**: Encryption at host, Entra ID login, managed identities
- ✅ **Automatic RBAC**:
  - VMs auto-assigned Monitoring Metrics Publisher on DCR
- ✅ **Automatic AMA**: Azure Monitor Agent installed via DCR associations
- ✅ **Visualization**: Azure Portal Dashboards with pre-built KQL queries
- ✅ **Latest APIs**: 2024-10-01 for Network resources
- ✅ **Best Practices**: Azure Verified Modules (AVM) from public registry
- ✅ **Custom JSON Logs**: Structured JSONL collection from `/var/log/net-resilience/`
  - Stream declarations for schema definition
  - 14 fields: TimeGenerated, LocalTime, AzLocation, AzZone, VmInstance, TestType, Target, Protocol, LatencyMs, Success, StatusCode, StatusName, Error, CorrelationId
- ✅ **Cloud-Init**: Automated VM configuration with PowerShell 7
  - Line-ending normalization (CRLF → LF)
  - No double base64 encoding (Azure handles encoding automatically)
- ✅ **Flexible**: Configurable VM count
- ✅ **Cost-Effective**: B2als_v2 VMs (2 vCPU, 1 GB), 30-day retention

## 🛠️ Requirements

- Azure subscription
- Existing VNet with subnet
- Azure CLI or PowerShell
- Bicep CLI v0.30.x+

## 📄 License

Provided as-is for demonstration purposes.

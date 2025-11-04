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
az deployment group validate \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
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
az deployment group what-if \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
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
az deployment group create \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --parameters adminPassword='YourSecureP@ssw0rd' \
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
- **Azure Managed Grafana** - Monitoring dashboards (Standard tier, Grafana v11)
  - Integrates with LAW via RBAC (Monitoring Reader role)
- **3 Virtual Machines** - Ubuntu 24.04, Standard_B2ts_v2, across availability zones
  - **System-assigned identity**: For Entra ID login
  - **User-assigned identity**: For Azure Monitor Agent
  - Cloud-init with PowerShell 7 installation
  - Network monitoring scripts pre-configured
  - Log rotation configured for Azure Monitor Agent
- **DCR Associations** - Automatic Azure Monitor Agent installation on VMs
- **RBAC Permissions** - Automated role assignments:
  - User-assigned identity → DCR: Monitoring Metrics Publisher (AMA authentication)
  - Grafana → LAW: Monitoring Reader (query data)

## 🔍 Verify Deployment

```bash
# Check VMs
az vm list -g <your-rg-name> -o table

# Check AMA installation (wait 5-10 minutes)
az vm extension list -g <your-rg-name> --vm-name vm-netres-1 -o table

# If AMA not installed, use manual installation script
# See scripts/Install-AMA-Manually.ps1

# Get Grafana endpoint
az deployment group show \
  -g <your-rg-name> \
  -n "monitoring-deployment" \
  --query properties.outputs.grafanaEndpoint.value
```

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

### Configure-Grafana-DataSource.ps1

**Purpose**: Automatically configure Azure Monitor data source in Grafana with Log Analytics Workspace integration.

**Location**: `scripts/Configure-Grafana-DataSource.ps1`

**Why needed**: Azure Managed Grafana doesn't automatically add LAW as a data source during deployment. While RBAC is configured via Bicep, the data source must be added via Grafana HTTP API or manually in the UI.

**Usage**:
```powershell
# Simple - uses default values from parameters/main.bicepparam
.\scripts\Configure-Grafana-DataSource.ps1

# Or specify custom values
.\scripts\Configure-Grafana-DataSource.ps1 `
    -ResourceGroupName "rg-fileshare-alias" `
    -GrafanaName "grafana-netres-prod" `
    -WorkspaceName "law-net-resilience-v2"

# Override specific parameters only
.\scripts\Configure-Grafana-DataSource.ps1 -WorkspaceName "law-net-resilience-v2"
```

**Default values** (from `parameters/main.bicepparam`):
- ResourceGroupName: `"rg-fileshare-alias"`
- GrafanaName: `"grafana-netres-prod"`
- WorkspaceName: `"law-net-resilience"`
- SubscriptionId: Current subscription (auto-detected)

**What it does**:
1. Retrieves Grafana endpoint and LAW resource ID
2. Obtains access token for Grafana HTTP API
3. Adds/updates Azure Monitor data source with managed identity authentication
4. Verifies the configuration

**Prerequisites**:
- Grafana must have Monitoring Reader role on LAW (configured automatically via Bicep RBAC)
- You must have Grafana Admin role on the Grafana instance

**After running**: Open Grafana and create dashboards using KQL queries against `NetResilience_CL` table.

## ⚠️ If You Deployed with Contributor Role

If you set `enableRbacAssignments = false`:

1. **Resources are deployed** ✅ but RBAC is missing ❌
2. **Request an admin** with Owner/User Access Administrator role
3. **Have them run** the RBAC assignment template:
   ```bash
   az deployment group create \
     --resource-group <your-rg-name> \
     --template-file modules/rbac-assignments.bicep \
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

## 🧪 Module Testing

To test the VM module independently:

**1. Update VM parameters** in `parameters/vms.bicepparam`:
- Set `adminPassword`
- Set `vnetName` and `subnetName`

**2. Validate the module:**

```bash
az deployment group validate \
  --resource-group <your-rg-name> \
  --template-file modules/vms.bicep \
  --parameters parameters/vms.bicepparam
```

**3. Preview changes (What-If):**

```bash
az deployment group what-if \
  --resource-group <your-rg-name> \
  --template-file modules/vms.bicep \
  --parameters parameters/vms.bicepparam
```

**4. Deploy the module:**

```bash
az deployment group create \
  --resource-group <your-rg-name> \
  --template-file modules/vms.bicep \
  --parameters parameters/vms.bicepparam \
  --name "vm-test-deployment"
```

## 💡 Key Features

- ✅ **Security**: Encryption at host, Entra ID login, managed identities
- ✅ **Automatic RBAC**:
  - VMs auto-assigned Monitoring Metrics Publisher on DCR
  - Grafana auto-assigned Monitoring Reader on LAW
- ✅ **Automatic AMA**: Azure Monitor Agent installed via DCR associations
- ✅ **Visualization**: Managed Grafana Standard tier with LAW integration
- ✅ **Latest APIs**: 2024-10-01 for Network & Grafana resources
- ✅ **Best Practices**: Azure Verified Modules (AVM) from public registry
- ✅ **Custom JSON Logs**: Structured JSONL collection from `/var/log/net-resilience/`
  - Stream declarations for schema definition
  - 14 fields: TimeGenerated, LocalTime, AzLocation, AzZone, VmInstance, TestType, Target, Protocol, LatencyMs, Success, StatusCode, StatusName, Error, CorrelationId
- ✅ **Cloud-Init**: Automated VM configuration with PowerShell 7
  - Line-ending normalization (CRLF → LF)
  - No double base64 encoding (Azure handles encoding automatically)
- ✅ **Flexible**: Conditional Grafana deployment, configurable VM count
- ✅ **Cost-Effective**: B2ts_v2 VMs (2 vCPU, 1 GB), 30-day retention

## 🛠️ Requirements

- Azure subscription
- Existing VNet with subnet
- Azure CLI or PowerShell
- Bicep CLI v0.30.x+

## 📄 License

Provided as-is for demonstration purposes.

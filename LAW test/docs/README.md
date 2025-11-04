# Azure Monitoring Infrastructure with VM Deployment

This Bicep template orchestrates the deployment of a complete Azure monitoring solution with Virtual Machines configured for custom log collection.

## ⚠️ Recent Updates (November 2025)

- ✅ **LocalTime Field Type Updated**: Changed from `datetime` to `string` to preserve timezone information (ISO8601 format)
- ✅ **Grafana Data Source Automation**: Created script to auto-configure LAW as data source (`scripts/Configure-Grafana-DataSource.ps1`)
- ✅ **Manual AMA Installation Script**: Created fallback script for unreliable DCR-triggered auto-install (`scripts/Install-AMA-Manually.ps1`)
- ✅ **User-Assigned Managed Identity Added**: Required for Azure Monitor Agent authentication to DCR/LAW
- ✅ **RBAC Optimized**: Single role assignment to user-assigned identity (not per-VM system-assigned)
- ✅ **Dual Identity Configuration**: VMs now have both system-assigned (Entra ID) and user-assigned (AMA) identities
- ✅ **DCE Removed**: Not required for public ingestion with logFiles data source (simplified architecture)
- ✅ **DCR Configuration Fixed**: Added required `streamDeclarations` for JSON log schema definition (14 fields)
- ✅ **Grafana Updated**: Version 11 (Standard SKU requirement), name shortened to 23 chars max
- ✅ **Grafana Integration Fixed**: LAW integration via RBAC only (removed azureMonitorWorkspaceIntegrations)
- ✅ **Custom Table Creation**: Using AVM workspace module's tables parameter (not separate module)
- ✅ **Stream Naming Fixed**: DCR uses `Custom-NetResilience_CL`, table is `NetResilience_CL`
- ✅ **Transform KQL Removed**: Optional for JSONL pass-through scenarios
- ✅ **Cloud-Init Fixed**: Removed double base64 encoding issue - Azure ARM API handles encoding automatically
- ✅ **Line Endings Fixed**: CRLF → LF normalization applied to prevent cloud-init parsing errors
- ✅ **JSON Config Fixed**: Removed trailing commas from configuration files
- ✅ **Ubuntu Image Corrected**: Updated to `Canonical/ubuntu-24_04-lts/server` (was incorrect noble reference)

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                      main.bicep                             │
│                   (Orchestration Layer)                     │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┬──────────────┬──────────────┐
        │                   │                   │              │              │
        ▼                   ▼                   ▼              ▼              ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐  ┌─────────┐  ┌─────────────┐
│     LAW      │◄───│   Grafana    │    │ Managed ID   │  │   DCR   │  │ Custom Table│
│  (Workspace) │    │ (Standard v11│    │ (User-Assigned│ │  (Rule) │  │NetResilience│
└──────────────┘    └──────────────┘    └──────┬───────┘  └─────┬───┘  └─────────────┘
                                               │                 │
                                               │                 │ DCRA + RBAC
                                               ▼                 ▼
                                        ┌──────────────────────────────┐
                                        │        vms.bicep             │
                                        │  (3 VMs with dual identity)  │
                                        │  - System: Entra ID          │
                                        │  - User-assigned: AMA        │
                                        └──────────────────────────────┘
```

## Components

### 0. User-Assigned Managed Identity

- **Purpose**: Required for Azure Monitor Agent authentication
- **Name**: `id-ama-net-resilience`
- **Shared**: Assigned to all 3 VMs (scalable approach)
- **Usage**: AMA uses this identity to authenticate to DCR and LAW
- **Benefits**: 
  - More scalable than system-assigned for AMA
  - Less churn in Entra ID (persists across VM lifecycle)
  - Easier management at scale
  - Recommended by Microsoft for production deployments

### 1. Log Analytics Workspace (LAW)

- **Purpose**: Central log repository
- **Retention**: 30 days
- **SKU**: PerGB2018 (pay-as-you-go)
- **Managed Identity**: System-assigned enabled
- **Custom Table**: `NetResilience_CL` with 14-field schema created via AVM

### 2. Data Collection Endpoint (DCE)

**⚠️ REMOVED - Not Required for Public Ingestion**

DCE is **NOT needed** when using:
- Azure Monitor Agent (AMA) with public ingestion
- `logFiles` data source
- Data Collection Rules created after March 31, 2024 (have embedded endpoints)

AMA uses the DCR's public configuration endpoint directly.

### 3. Data Collection Rule (DCR)

- **Kind**: Linux
- **Data Sources**: JSON log files from `/var/log/net-resilience/net-*.jsonl`
- **Stream**: `Custom-NetResilience_CL` (custom stream name with required Custom- prefix)
- **Format**: JSON Lines (JSONL)
- **Destination**: Log Analytics Workspace
- **No DCE**: Uses public endpoint by default for logFiles data source
- **Stream Declarations**: Required for JSON format logs - defines schema with 14 columns:
  - `TimeGenerated` (datetime) - UTC timestamp
  - `LocalTime` (string) - Local timestamp with timezone (ISO8601 format, e.g., "2025-11-04T14:30:45.123+01:00")
  - `AzLocation` (string) - Azure region from IMDS
  - `AzZone` (string) - Availability zone from IMDS
  - `VmInstance` (string) - Hostname
  - `TestType` (string) - Test category (e.g., "OnPrem")
  - `Target` (string) - Test target (IP or URL)
  - `Protocol` (string) - "ICMP" or "HTTP"
  - `LatencyMs` (int) - Response time in milliseconds
  - `Success` (boolean) - Test success/failure
  - `StatusCode` (int) - ICMP status or HTTP status code
  - `StatusName` (string) - Human-readable status
  - `Error` (string) - Error message if failed
  - `CorrelationId` (string) - GUID for request tracing
- **Transform KQL**: REMOVED (optional for JSONL pass-through scenarios)
- **Output Stream**: `Custom-NetResilience_CL` (matches table name in LAW)

### 4. Virtual Machines (via vms.bicep)

- **Count**: 3 VMs across availability zones 1, 2, 3
- **OS**: Ubuntu 24.04 LTS (Canonical/ubuntu-24_04-lts/server)
- **Size**: Standard_B2ts_v2 (2 vCPU, 1 GB RAM)
- **Disk**: 30 GB Premium SSD
- **Managed Identities**:
  - **System-assigned**: Enabled for Entra ID login (AADLogin extension)
  - **User-assigned**: Required for Azure Monitor Agent authentication
- **Features**:
  - Encryption at Host enabled
  - Entra ID login enabled (AADLogin extension)
  - Guest Configuration extension enabled
  - Azure Monitor Agent (auto-installed via DCRA)
- **Cloud-Init Configuration**:
  - Package updates enabled, upgrades disabled initially
  - PowerShell 7 installation from Microsoft repositories
  - Timezone: Europe/Madrid
  - Network monitoring scripts deployed to `/opt/net-resilience/`
  - Configuration file: `/etc/net-resilience.conf` (JSON format, no trailing commas)
  - Systemd service configured (disabled by default for testing)
  - Log rotation: 14-day retention with copytruncate (AMA-safe)
  - **Critical**: Line ending normalization (CRLF → LF) for cloud-init compatibility
  - **Critical**: No manual base64 encoding (Azure ARM API handles automatically)

### 5. Data Collection Rule Associations (DCRA)
- **Purpose**: Associate DCR with each VM
- **Scope**: Each VM resource
- **Effect**: Automatically installs Azure Monitor Agent (AMA)
- **API Version**: 2023-03-11

### 6. RBAC Permissions

#### 6.1 User-Assigned Identity to DCR Permissions

- **Purpose**: Grant user-assigned managed identity permission to send data to DCR
- **Role**: Monitoring Metrics Publisher (`3913510d-42f4-4e42-8a64-420c390055eb`)
- **Scope**: Data Collection Rule
- **Principal**: User-assigned managed identity (`id-ama-net-resilience`)
- **Why User-Assigned**: AMA uses the user-assigned identity for authentication (shared across all 3 VMs)
- **Automatic**: Single role assignment created during deployment
- **Benefits**:
  - One role assignment instead of 3 (more efficient)
  - Aligned with Microsoft best practices for AMA at scale

**Note:** System-assigned identities on VMs are used ONLY for Entra ID login, NOT for DCR permissions.

#### 6.2 Grafana to LAW Permissions

- **Purpose**: Grant Grafana permission to query data from LAW
- **Role**: Monitoring Reader (`43d0d8ad-25c7-4714-9337-8ba259a9fe05`)
- **Scope**: Log Analytics Workspace
- **Principal**: Grafana's system-assigned managed identity
- **Automatic**: Role assignment created during deployment (if Grafana enabled)

**Complete Permission Flow:**

```text
User-Assigned Managed Identity (id-ama-net-resilience)
    ↓ [Monitoring Metrics Publisher on DCR]
    ↓
Data Collection Rule
    ↓ [Built-in permissions]
    ↓
Log Analytics Workspace ←─────────────┐
                                       │
                      [Monitoring Reader]
                                       │
                        Grafana Managed Identity
```

### 7. Azure Managed Grafana (Optional)

- **SKU**: Standard (non-Enterprise)
- **Version**: Grafana 11 (Standard SKU requirement, v10 not supported)
- **Integration**: LAW via RBAC (Monitoring Reader role) - NOT azureMonitorWorkspaceIntegrations
- **Authentication**: Microsoft Entra ID (Azure AD)
- **API Version**: 2024-10-01
- **Managed Identity**: System-assigned (auto-granted Monitoring Reader on LAW)
- **Name Limit**: Maximum 23 characters for Standard SKU
- **Features**:
  - Automatic RBAC for LAW data access
  - API key authentication enabled
  - Public network access (configurable)
  - Optional zone redundancy for HA

## Managed Identity Requirements

**⚠️ CRITICAL: Azure Monitor Agent Requires Managed Identity**

According to [Microsoft documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-requirements#permissions), **managed identity must be enabled** on Azure virtual machines for AMA to function.

### Identity Configuration

This template configures **dual managed identities** on each VM:

1. **System-Assigned Identity**
   - **Purpose**: Entra ID (Azure AD) login
   - **Created**: Automatically per VM
   - **Lifecycle**: Tied to VM (deleted when VM is deleted)
   - **Usage**: AADLogin VM extension

2. **User-Assigned Identity** (Recommended for AMA)
   - **Purpose**: Azure Monitor Agent authentication to DCR/LAW
   - **Created**: Once, shared across all VMs
   - **Name**: `id-ama-net-resilience`
   - **Lifecycle**: Independent of VMs (persists when VMs are deleted/recreated)
   - **Benefits**:
     - ✅ More scalable than system-assigned for AMA
     - ✅ Less churn in Entra ID
     - ✅ Easier to manage at scale
     - ✅ Microsoft-recommended for production deployments

### Why User-Assigned for AMA?

From Microsoft docs:
> "User-assigned managed identity is **strongly recommended** over system-assigned managed identities due to their ease of management at scale."

**System-assigned issues at scale:**
- Creates/deletes identity per VM = churn in Entra ID
- Not suitable for large deployments
- More complex to manage

**User-assigned benefits:**
- One identity shared across all VMs
- Persists across VM lifecycle
- Better for Azure Policy deployments
- Recommended pattern for production

### Authentication Flow

```text
┌─────────────────────────────────────────────────────┐
│ User-Assigned Managed Identity                      │
│ (id-ama-net-resilience)                            │
│ - Created once                                      │
│ - Assigned to all 3 VMs                            │
│ - Granted Monitoring Metrics Publisher on DCR      │
└──────────────┬──────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│ Virtual Machines                                     │
│ - System-assigned: Entra ID login ONLY             │
│ - User-assigned: AMA authentication                 │
└──────────────┬──────────────────────────────────────┘
               │
               ▼ (DCR Association triggers AMA install)
               │
┌──────────────┴──────────────────────────────────────┐
│ Azure Monitor Agent (AMA)                           │
│ - Reads user-assigned identity from VM config       │
│ - Uses it to authenticate to DCR                    │
│ - Sends logs using Monitoring Metrics Publisher role│
│ - NO permissions needed on system-assigned identity │
└─────────────────────────────────────────────────────┘
```

## File Structure

```
LAW test/
├── main.bicep                         # Main orchestration template
├── README.md                          # Quick start guide
├── .gitignore                         # Git ignore rules
│
├── modules/                           # Reusable Bicep modules
│   ├── vms.bicep                     # VM deployment module
│   ├── grafana.bicep                 # Managed Grafana module
│   └── rbac-assignments.bicep        # RBAC role assignments module
│
├── parameters/                        # All parameter files
│   ├── main.bicepparam               # Production deployment parameters
│   ├── rbac-assignments.bicepparam   # RBAC-only deployment parameters
│   └── vms.bicepparam                # VM unit testing parameters
│
├── scripts/                           # Operational scripts
│   ├── Install-AMA-Manually.ps1      # Manual AMA installation (fallback for unreliable auto-install)
│   └── Configure-Grafana-DataSource.ps1  # Automated Grafana data source configuration
│
└── docs/                             # Documentation
    └── README.md                     # Complete detailed documentation (this file)
```

## Prerequisites

1. **Azure Subscription** with appropriate permissions
2. **Existing Virtual Network** with subnet
3. **Resource Group** created
4. **Azure CLI** or **Azure PowerShell** installed
5. **Bicep CLI** v0.30.x or later

## Azure Connection & Setup

Before deploying resources, authenticate to Azure and prepare your environment:

### Using Azure CLI

```bash
# 1. Login to Azure
az login

# 2. List available subscriptions
az account list --output table

# 3. Set the subscription you want to use
az account set --subscription "<subscription-id-or-name>"

# 4. Verify you're connected to the correct subscription
az account show --output table

# 5. Create a resource group (if it doesn't exist)
az group create --name <your-rg-name> --location eastus

# 6. Verify the resource group was created
az group show --name <your-rg-name> --output table
```

### Using Azure PowerShell

```powershell
# 1. Login to Azure
Connect-AzAccount

# 2. List available subscriptions
Get-AzSubscription | Format-Table

# 3. Set the subscription you want to use
Set-AzContext -Subscription "<subscription-id-or-name>"

# 4. Verify you're connected to the correct subscription
Get-AzContext | Select-Object Name, Account, Environment, Subscription

# 5. Create a resource group (if it doesn't exist)
New-AzResourceGroup -Name <your-rg-name> -Location eastus

# 6. Verify the resource group was created
Get-AzResourceGroup -Name <your-rg-name>
```

### Verify Network Prerequisites

Ensure your VNet and subnet exist before deploying:

```bash
# Azure CLI - List VNets
az network vnet list --output table

# Azure CLI - Show subnet details
az network vnet subnet show \
  --resource-group <vnet-rg-name> \
  --vnet-name <your-vnet-name> \
  --name <your-subnet-name>
```

```powershell
# PowerShell - List VNets
Get-AzVirtualNetwork | Format-Table Name, ResourceGroupName, Location

# PowerShell - Show subnet details
Get-AzVirtualNetworkSubnetConfig `
  -ResourceGroupName <vnet-rg-name> `
  -VirtualNetworkName <your-vnet-name> `
  -Name <your-subnet-name>
```

## Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `location` | Azure region | `eastus` |
| `workspaceName` | Log Analytics Workspace name | `law-net-resilience-prod` |
| `dceName` | Data Collection Endpoint name | `dce-net-resilience-prod` |
| `dcrName` | Data Collection Rule name | `dcr-net-resilience-prod` |
| `vmNamePrefix` | Prefix for VM names | `vm-netres` |
| `adminUsername` | VM admin username | `azureuser` |
| `adminPassword` | VM admin password (secure) | (provide securely) |
| `vnetName` | Existing VNet name | `vnet-prod` |
| `subnetName` | Existing subnet name | `subnet-vms` |
| `grafanaName` | Grafana instance name | `grafana-net-resilience-prod` |

### Optional Parameters (with defaults)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `vmCount` | `3` | Number of VMs to deploy |
| `vmSize` | `Standard_B2s` | VM size |
| `osType` | `Linux` | Operating system type |
| `enableEntraIdLogin` | `true` | Enable Microsoft Entra ID authentication |
| `encryptionAtHost` | `true` | Enable encryption at host |
| `disablePasswordAuthentication` | `false` | Disable password auth (use SSH keys) |
| `enableGrafana` | `true` | Deploy Managed Grafana instance |
| `grafanaZoneRedundancy` | `false` | Enable zone redundancy for Grafana |
| `enableRbacAssignments` | `true` | Automatically create RBAC role assignments (requires Owner/UAA role) |

## Deployment

### Deployment Scenarios

#### Scenario A: You Have Owner or User Access Administrator Role ✅ (Recommended)

Follow the standard deployment process below. RBAC assignments will be created automatically.

#### Scenario B: You Have Only Contributor Role ⚠️

If you only have **Contributor** role, you cannot create RBAC role assignments. You have two options:

**Option 1: Skip RBAC during deployment, add later**
1. Set `enableRbacAssignments = false` in `parameters/main.bicepparam`
2. Deploy the infrastructure (resources will be created)
3. Request an admin with Owner/UAA role to run the RBAC assignment template (see [Manual RBAC Assignment](#manual-rbac-assignment-for-contributor-role))

**Option 2: Request elevated permissions**
- Ask your Azure admin to grant you **User Access Administrator** role on the resource group
- Then deploy with `enableRbacAssignments = true` (default)

### Step 1: Update Parameters

Edit `parameters/main.bicepparam` and provide:
- Your existing **VNet name** and **subnet name**
- A secure **admin password**
- Desired **Azure region** (location)
- Grafana name (or disable with `enableGrafana = false`)
- **Leave `adminPassword` empty** - you'll provide it interactively during deployment

```bicep
param location = 'eastus'
param vnetName = 'your-vnet-name'
param subnetName = 'your-subnet-name'
param adminPassword = ''  // Leave empty for PowerShell (prompts securely); required for Azure CLI
param grafanaName = 'grafana-net-resilience-prod'
param enableGrafana = true
```

### Step 2: Validate the Template

Validate that the Bicep template is syntactically correct and all parameters are valid.

**Azure CLI** - does NOT prompt for secure parameters; provide on command line:

```bash
az deployment group validate \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --parameters adminPassword='YourSecureP@ssw0rd'
```

**Azure PowerShell** - prompts securely for SecureString parameters:

```powershell
Test-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam
```

**Password Requirements:**

- Minimum 12 characters
- Contains uppercase, lowercase, number, and special character
- Not a common password

**What validation checks:**

- ✅ Template syntax is correct
- ✅ All required parameters are provided
- ✅ Parameter values are valid
- ✅ Resources can be created with current permissions
- ❌ Does NOT check quota or subscription limits

### Step 3: Preview Changes (What-If)

See exactly what resources will be created, modified, or deleted before deploying.

**Azure CLI** - provide password on command line:

```bash
az deployment group what-if \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --parameters adminPassword='YourSecureP@ssw0rd'
```

**Azure PowerShell** - will prompt for password:

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam `
  -WhatIf
```

**What-If Output shows:**

- 🟢 **Create** - Resources that will be created
- 🟡 **Modify** - Resources that will be updated
- 🔴 **Delete** - Resources that will be removed
- ⚪ **No Change** - Resources that already exist and match

**Example output:**
```
Resource changes: 10 to create, 0 to modify, 0 to delete.

+ Microsoft.Compute/virtualMachines/vm-netres-1
+ Microsoft.Compute/virtualMachines/vm-netres-2
+ Microsoft.Compute/virtualMachines/vm-netres-3
+ Microsoft.Dashboard/grafana/grafana-net-resilience-prod
+ Microsoft.Insights/dataCollectionEndpoints/dce-net-resilience-prod
+ Microsoft.Insights/dataCollectionRules/dcr-net-resilience-prod
...
```

### Step 4: Deploy

After reviewing the what-if output and confirming the changes, deploy the infrastructure.

**Azure CLI** - provide password on command line:

```bash
az deployment group create \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --parameters adminPassword='YourSecureP@ssw0rd' \
  --name "netres-monitoring-deployment"
```

**Azure PowerShell** - will prompt for password as SecureString:

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam `
  -Name "netres-monitoring-deployment"
```

**PowerShell Password Prompt:**

1. Type your password (characters won't be displayed)
2. Press Enter
3. Deployment will proceed

**Deployment takes approximately 10-15 minutes.**

### Step 5: Verify Deployment

After deployment completes, verify:

1. **VMs are running**:
   ```bash
   az vm list -g <your-rg-name> -o table
   ```

2. **Azure Monitor Agent installed** (may take several minutes):
   ```bash
   az vm extension list -g <your-rg-name> --vm-name vm-netres-1 -o table
   ```

3. **DCR Associations created**:
   ```bash
   az monitor data-collection rule association list \
     --resource /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/vm-netres-1
   ```

4. **Logs flowing to Log Analytics** (after generating sample logs):
   ```kql
   NetResilience_CL
   | take 10
   ```

5. **Grafana endpoint**:
   ```bash
   az deployment group show \
     -g <your-rg-name> \
     -n "netres-monitoring-deployment" \
     --query properties.outputs.grafanaEndpoint.value
   ```

## Manual RBAC Assignment (for Contributor Role)

If you deployed with `enableRbacAssignments = false` because you only have Contributor role, follow these steps to add RBAC permissions. **This requires an admin with Owner or User Access Administrator role.**

### Why RBAC is Required

Without RBAC role assignments:
- ❌ VMs cannot send logs to Log Analytics (no data collection)
- ❌ Grafana cannot query data from Log Analytics (dashboards won't work)

### Steps for Admin to Grant RBAC

#### Option 1: Using the Provided Bicep Template (Recommended)

**Admin runs this deployment:**

1. **Update parameters** in `parameters/rbac-assignments.bicepparam`:
   ```bicep
   param dcrName = 'dcr-net-resilience-prod'  // Match your DCR name
   param lawName = 'law-net-resilience-prod'  // Match your LAW name
   param grafanaName = 'grafana-net-resilience-prod'  // Match your Grafana name
   param enableGrafana = true
   
   param vmNames = [
     'vm-netres-1'  // Match your deployed VM names
     'vm-netres-2'
     'vm-netres-3'
   ]
   ```

2. **Deploy RBAC assignments**:
   ```bash
   # Azure CLI
   az deployment group create \
     --resource-group <your-rg-name> \
     --template-file modules/rbac-assignments.bicep \
     --parameters parameters/rbac-assignments.bicepparam \
     --name "rbac-assignment-$(date +%Y%m%d-%H%M%S)"
   
   # PowerShell
   New-AzResourceGroupDeployment `
     -ResourceGroupName <your-rg-name> `
     -TemplateFile modules/rbac-assignments.bicep `
     -TemplateParameterFile parameters/rbac-assignments.bicepparam `
     -Name "rbac-assignment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
   ```

3. **Verify assignments**:
   ```bash
   # Check VM permissions on DCR
   az role assignment list \
     --scope $(az monitor data-collection rule show -g <rg> -n dcr-net-resilience-prod --query id -o tsv) \
     -o table
   
   # Check Grafana permissions on LAW
   az role assignment list \
     --scope $(az monitor log-analytics workspace show -g <rg> -n law-net-resilience-prod --query id -o tsv) \
     -o table
   ```

#### Option 2: Using Azure CLI Commands

**Admin runs these commands for each VM:**

```bash
# Get resource IDs
DCR_ID=$(az monitor data-collection rule show -g <rg> -n dcr-net-resilience-prod --query id -o tsv)
LAW_ID=$(az monitor log-analytics workspace show -g <rg> -n law-net-resilience-prod --query id -o tsv)

# Grant VM permissions (repeat for each VM)
for VM_NAME in vm-netres-1 vm-netres-2 vm-netres-3; do
  VM_IDENTITY=$(az vm show -g <rg> -n $VM_NAME --query identity.principalId -o tsv)
  
  az role assignment create \
    --assignee $VM_IDENTITY \
    --role "Monitoring Metrics Publisher" \
    --scope $DCR_ID
  
  echo "Assigned Monitoring Metrics Publisher to $VM_NAME"
done

# Grant Grafana permission
GRAFANA_IDENTITY=$(az grafana show -g <rg> -n grafana-net-resilience-prod --query identity.principalId -o tsv)

az role assignment create \
  --assignee $GRAFANA_IDENTITY \
  --role "Monitoring Reader" \
  --scope $LAW_ID

echo "Assigned Monitoring Reader to Grafana"
```

#### Option 3: Using Azure Portal (Manual)

**For VM Permissions:**
1. Navigate to your **Data Collection Rule** in Azure Portal
2. Go to **Access control (IAM)** → **Add role assignment**
3. Select role: **Monitoring Metrics Publisher**
4. Assign access to: **Managed identity**
5. Select members: Choose each VM (vm-netres-1, vm-netres-2, vm-netres-3)
6. Click **Review + assign**

**For Grafana Permission:**
1. Navigate to your **Log Analytics Workspace** in Azure Portal
2. Go to **Access control (IAM)** → **Add role assignment**
3. Select role: **Monitoring Reader**
4. Assign access to: **Managed identity**
5. Select members: Choose your Grafana instance
6. Click **Review + assign**

### Verify RBAC After Assignment

After admin completes RBAC assignment, verify:

```bash
# Test log ingestion (create a test log file on VM)
ssh azureuser@<vm-ip>
sudo mkdir -p /var/log/net-resilience
echo '{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","level":"INFO","message":"RBAC test"}' | sudo tee /var/log/net-resilience/net-test.jsonl

# Wait 5-10 minutes, then query LAW
az monitor log-analytics query \
  -w <workspace-id> \
  --analytics-query "NetResilience_CL | where message_s contains 'RBAC test' | take 10"
```

Expected: You should see the test log entry, confirming VMs can send logs.

## Post-Deployment Configuration

### Configure Grafana Data Source (Automated)

While Grafana has the necessary RBAC permissions (Monitoring Reader on LAW), the data source itself must be configured. You can do this **automatically with a script** or manually via the UI.

**Automated Configuration (Recommended):**

```powershell
# Option 1: Simple usage with default values
.\scripts\Configure-Grafana-DataSource.ps1

# Option 2: Specify all parameters explicitly
.\scripts\Configure-Grafana-DataSource.ps1 `
    -ResourceGroupName "rg-fileshare-alias" `
    -GrafanaName "grafana-netres-prod" `
    -WorkspaceName "law-net-resilience"

# Option 3: Override only specific parameters
.\scripts\Configure-Grafana-DataSource.ps1 -WorkspaceName "law-net-resilience-v2"
```

**Default parameter values:**
The script uses defaults from `parameters/main.bicepparam`:
- **ResourceGroupName**: `"rg-fileshare-alias"`
- **GrafanaName**: `"grafana-netres-prod"`
- **WorkspaceName**: `"law-net-resilience"`
- **SubscriptionId**: Current subscription (auto-detected)

You can override any parameter as needed. This makes the script easy to run after deployment without remembering all the resource names.

**What the script does:**
1. Retrieves Grafana endpoint and LAW resource ID
2. Obtains access token for Grafana HTTP API
3. Adds Azure Monitor data source with managed identity authentication
4. Verifies the configuration
5. Provides next steps for creating dashboards

**Prerequisites for the script:**
- You must have **Grafana Admin** role on the Grafana instance
- Azure CLI must be authenticated (`az login`)
- RBAC must be enabled in deployment (`enableRbacAssignments = true`)

**Manual Configuration Alternative:**

If you prefer to configure manually or the script fails:

### Access Azure Managed Grafana

1. **Get the Grafana URL** from deployment outputs (see above)
2. **Navigate to the URL** in your browser
3. **Authenticate** using Microsoft Entra ID (your Azure AD account)
4. **Grant permissions** when prompted
5. **Add data source** (use script above or manually add Azure Monitor)

**After configuring the data source:**
- ✅ Log Analytics workspace accessible via Azure Monitor data source
- ✅ Managed identity authentication (no credentials needed)
- ✅ Ready to query NetResilience_CL table

**Create your first dashboard:**
1. Click **Dashboards** → **New Dashboard**
2. Add a panel with this query:
   ```kql
   NetResilience_CL
   | summarize count() by bin(TimeGenerated, 5m)
   | render timechart
   ```

### Azure Monitor Agent Installation

**Good news!** The Azure Monitor Agent (AMA) is **automatically installed** when you create the Data Collection Rule Association (DCRA). You don't need to manually install it.

**How it works:**
1. When the DCRA is created (linking VM to DCR), Azure automatically deploys the AMA extension
2. The agent installs in the background (takes 5-10 minutes)
3. Agent automatically configures itself based on the associated DCR

**To verify AMA installation:**

```bash
# Check if AMA extension is installed
az vm extension show \
  -g <your-rg-name> \
  --vm-name vm-netres-1 \
  -n AzureMonitorLinuxAgent

# Or list all extensions
az vm extension list \
  -g <your-rg-name> \
  --vm-name vm-netres-1 \
  -o table
```

**On the VM itself:**

```bash
# SSH to VM
ssh azureuser@<vm-ip>

# Check AMA service status
systemctl status azuremonitoragent

# View AMA logs
sudo journalctl -u azuremonitoragent -f
```

> **Note:** The cloud-init script in this template references the Dependency Agent (for VM Insights), not AMA. The AMA is installed automatically via the DCRA extension mechanism.

### Generate Sample Logs

Create test log entries to verify the collection pipeline:

```bash
# SSH to a VM
sudo bash -c 'cat > /var/log/net-resilience/net-test.jsonl << EOF
{"timestamp":"$(date -Iseconds)","level":"INFO","message":"Test log entry","source":"manual"}
{"timestamp":"$(date -Iseconds)","level":"DEBUG","message":"Connection established","latency_ms":42}
{"timestamp":"$(date -Iseconds)","level":"WARN","message":"High latency detected","latency_ms":250}
EOF'
```

Wait 5-10 minutes for ingestion, then query in Log Analytics:

```kql
NetResilience_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, level, message, latency_ms
| order by TimeGenerated desc
```

## Outputs

The deployment provides these outputs:

| Output | Description |
|--------|-------------|
| `lawResourceId` | Log Analytics Workspace resource ID |
| `lawWorkspaceId` | Log Analytics Workspace ID (GUID) |
| `dceResourceId` | Data Collection Endpoint resource ID |
| `dcrResourceId` | Data Collection Rule resource ID |
| `vmResourceIds` | Array of VM resource IDs |
| `vmNames` | Array of VM names |
| `grafanaResourceId` | Grafana instance resource ID (if enabled) |
| `grafanaEndpoint` | Grafana dashboard URL (if enabled) |
| `grafanaPrincipalId` | Grafana managed identity principal ID (if enabled) |

Access outputs:

```bash
# Azure CLI
az deployment group show \
  -g <your-rg-name> \
  -n "netres-monitoring-deployment" \
  --query properties.outputs

# Azure PowerShell
(Get-AzResourceGroupDeployment -ResourceGroupName <your-rg-name> -Name "netres-monitoring-deployment").Outputs
```

## Troubleshooting

### Azure Monitor Agent (AMA) not installing

**Symptom**: VMs are deployed but AMA extension not installed, even though DCR associations exist.

**Root Cause**: DCR associations should automatically trigger AMA installation, but this doesn't always happen reliably.

**Solution**: Use the manual installation script.

#### Manual AMA Installation Script

**Location**: `scripts/Install-AMA-Manually.ps1`

**Usage**:
```powershell
# 1. Edit the script to configure your environment:
#    - $resourceGroupName = "rg-fileshare-alias"
#    - $subscriptionId = "your-subscription-id"
#    - $vmBaseName = "vmnetres"
#    - $vmCount = 3

# 2. Run the script
.\scripts\Install-AMA-Manually.ps1
```

**What it does**:
1. Retrieves the user-assigned managed identity resource ID (required for AMA authentication)
2. Loops through all VMs in the deployment
3. Installs AzureMonitorLinuxAgent extension with proper authentication settings
4. Provides verification commands

**Expected output**:
- Green: Successful AMA installation
- Yellow: AMA already installed
- Red: Installation errors

**Verification**:
```powershell
# Check AMA extension status
az vm extension list --resource-group rg-fileshare-alias --vm-name vmnetres-1 -o table

# Expected: AzureMonitorLinuxAgent with ProvisioningState: Succeeded

# Wait 5-10 minutes, then query logs
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "NetResilience_CL | take 10"
```

**Troubleshooting the script**:
- **Identity not found**: Verify user-assigned identity `id-ama-net-resilience` exists in resource group
- **Permission denied**: Ensure you have Contributor role on the resource group
- **Extension conflict**: If AMA already installed incorrectly, remove it first:
  ```powershell
  az vm extension delete --resource-group <rg> --vm-name <vm> --name AzureMonitorLinuxAgent
  ```

### VMs not receiving DCR configuration

1. Check DCR Association:
   ```bash
   az monitor data-collection rule association list \
     --resource <vm-resource-id>
   ```

2. Verify Azure Monitor Agent is running:
   ```bash
   az vm extension show \
     -g <rg> \
     --vm-name vm-netres-1 \
     -n AzureMonitorLinuxAgent
   ```

3. Check agent logs on VM:
   ```bash
   sudo journalctl -u azuremonitoragent
   ```

### Logs not appearing in Log Analytics

1. **Wait time**: Initial ingestion can take 10-20 minutes
2. **Check DCR configuration**: Ensure file pattern matches your log files
3. **Verify log file permissions**: AMA needs read access
4. **Check log format**: Must be valid JSON for JSON format type
5. **Verify RBAC permissions**: Check VM managed identity has Monitoring Metrics Publisher on DCR
   ```bash
   # Get VM's managed identity principal ID
   VM_IDENTITY=$(az vm show -g <rg> -n vm-netres-1 --query identity.principalId -o tsv)
   
   # Get DCR resource ID
   DCR_ID=$(az monitor data-collection rule show -g <rg> -n dcr-net-resilience-prod --query id -o tsv)
   
   # Check role assignment exists
   az role assignment list --assignee $VM_IDENTITY --scope $DCR_ID -o table
   ```

6. **Test log file creation**: Create a test log file to verify AMA is reading
   ```bash
   sudo mkdir -p /var/log/net-resilience
   echo '{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","level":"INFO","message":"Test log"}' | sudo tee /var/log/net-resilience/net-test.jsonl
   ```

### Cannot access Grafana

1. **Verify deployment**: Check `grafanaEndpoint` output is not empty
   ```bash
   az deployment group show \
     -g <rg> \
     -n "netres-monitoring-deployment" \
     --query properties.outputs.grafanaEndpoint.value
   ```

2. **Check user permissions**: Your Azure AD account needs access
   - Navigate to Grafana resource in Azure Portal
   - Go to **Access control (IAM)**
   - Add yourself as **Grafana Admin** or **Grafana Editor**

3. **Verify Grafana has LAW access**: Check Monitoring Reader role is assigned
   ```bash
   # Get Grafana's managed identity
   GRAFANA_IDENTITY=$(az grafana show -g <rg> -n grafana-net-resilience-prod --query identity.principalId -o tsv)
   
   # Get LAW resource ID
   LAW_ID=$(az monitor log-analytics workspace show -g <rg> -n law-net-resilience-prod --query id -o tsv)
   
   # Check role assignment
   az role assignment list --assignee $GRAFANA_IDENTITY --scope $LAW_ID -o table
   ```
   Expected: Should show "Monitoring Reader" role

4. **Configure data source**: Run the automated script
   ```powershell
   # Simple - uses default values
   .\scripts\Configure-Grafana-DataSource.ps1
   
   # Or specify custom values
   .\scripts\Configure-Grafana-DataSource.ps1 `
       -ResourceGroupName "rg-fileshare-alias" `
       -GrafanaName "grafana-netres-prod" `
       -WorkspaceName "law-net-resilience-v2"
   ```
   Or manually add Azure Monitor data source in Grafana UI (Connections → Data sources)

5. **Disable Grafana**: Set `enableGrafana = false` in parameters if not needed

### Grafana Data Source Configuration Fails

If the `Configure-Grafana-DataSource.ps1` script fails:

1. **Permission denied (403 error)**:
   - Ensure you have **Grafana Admin** role on the Grafana instance
   - Check in Azure Portal → Grafana → Access control (IAM)
   - Add yourself with "Grafana Admin" role if missing

2. **Cannot authenticate**:
   - Verify you're logged in: `az login`
   - Check subscription context: `az account show`

3. **Data source already exists (409 conflict)**:
   - Script will automatically update the existing data source
   - If update fails, manually delete old data source in Grafana UI first

4. **RBAC not configured**:
   - Verify Grafana has Monitoring Reader on LAW (see "Cannot access Grafana" #3 above)
   - If missing, ensure `enableRbacAssignments = true` in parameters and redeploy

### Cloud-Init Issues

If VMs are deployed but cloud-init scripts didn't execute properly:

1. **Check cloud-init status**:
   ```bash
   sudo cloud-init status --long
   ```
   Expected: `status: done` (not `degraded`)

2. **Common issues**:
   
   **Issue: "Unhandled non-multipart (text/x-not-multipart)" error**
   - **Cause**: Double base64 encoding in customData
   - **Fix**: Verify `vms.bicep` does NOT call `base64()` - Azure ARM API encodes automatically
   - **Correct code**: `customData: replace(replace(cloudInitData, '\r\n', '\n'), '\r', '\n')`
   - **Incorrect code**: ❌ `customData: base64(replace(...))`
   
   **Issue: Cloud-init files not created**
   - **Cause**: Windows CRLF line endings in cloud-init YAML
   - **Fix**: Line ending normalization is applied in `vms.bicep`
   - **Verify**: `od -c /var/lib/cloud/instance/user-data.txt | head -20` should show decoded YAML
   
   **Issue: JSON parsing errors in config files**
   - **Cause**: Trailing commas in JSON (invalid JSON syntax)
   - **Fix**: Remove trailing commas from arrays in `/etc/net-resilience.conf`
   - **Example**: `"ICMPHosts": ["8.8.8.8"]` (no comma after last element)

3. **View cloud-init logs**:
   ```bash
   sudo cat /var/log/cloud-init.log
   sudo cat /var/log/cloud-init-output.log
   ```

4. **Verify files were created**:
   ```bash
   ls -la /etc/net-resilience.conf
   ls -la /opt/net-resilience/Run-OnPremTests.ps1
   ls -la /etc/systemd/system/net-resilience.service
   pwsh --version  # Should show PowerShell 7.x
   ```

5. **Test cloud-init configuration manually**:
   ```bash
   sudo cloud-init schema --system
   sudo cloud-init clean --logs --reboot  # ⚠️ Only for testing - will rerun cloud-init
   ```

### Deployment errors

Common issues:
- **Subnet not found**: Verify VNet and subnet names in parameters
- **Invalid admin password**: Must meet complexity requirements
- **Quota exceeded**: Check VM quota in your subscription/region
- **Ubuntu image not found**: Verify image reference is `Canonical/ubuntu-24_04-lts/server`

## Security Considerations

1. **Admin Password**: Use Azure Key Vault reference instead of plain text
   ```bicep
   param adminPassword string = getSecret('<vault-id>', '<secret-name>')
   ```

2. **SSH Keys**: Consider disabling password auth and using SSH keys
   ```bicep
   param disablePasswordAuthentication = true
   // Add SSH key configuration
   ```

3. **Private Endpoints**: Restrict DCE to private endpoint access
   ```bicep
   publicNetworkAccess: 'Disabled'
   ```

4. **Managed Identities**: VMs use system-assigned managed identity for authentication
   - AMA uses VM's managed identity to authenticate to DCR
   - Monitoring Metrics Publisher role automatically assigned during deployment
   - No credentials stored on VM - secure by default

## Maintenance

### Update API Versions

To update to newer API versions:

1. Check latest versions:
   ```bash
   az provider show -n Microsoft.Insights --query "resourceTypes[?resourceType=='dataCollectionRules'].apiVersions[0]"
   ```

2. Update in Bicep files:
   ```bicep
   resource dcrAssociations 'Microsoft.Insights/dataCollectionRuleAssociations@<new-version>'
   ```

### Scale VMs

To add/remove VMs, update `vmCount` parameter and redeploy:

```bicep
param vmCount = 5  // Scale to 5 VMs
```

The deployment is idempotent and will add new VMs or remove excess ones.

## Cost Optimization

Estimated monthly costs (East US region):

- **3x Standard_B2s VMs**: ~$60 ($20 each)
- **3x 30 GB Premium SSD**: ~$15 ($5 each)
- **Log Analytics**: Variable, depends on ingestion volume
  - First 5 GB/month: Free
  - Additional data: $2.30/GB
- **Data Collection**: No additional cost
- **Managed Grafana (Standard)**: ~$120/month
  - Includes: Unlimited dashboards, unlimited users
  - 10 active users included

**Total**: ~$195-220/month (excluding log ingestion)

To reduce costs:
- Use **Standard_B1s** for non-production: ~$10/month each
- Use **Standard HDD** instead of Premium SSD: ~$1.50/month
- Reduce data retention to 7 days (minimum)
- **Disable Grafana** if not needed: Set `enableGrafana = false` (saves $120/month)
- Use **Grafana OSS** on a VM instead (self-managed, $0 license cost)

## Additional Resources

- [Azure Monitor Agent Overview](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-overview)
- [Data Collection Rules](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Custom Logs in Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-text-log)
- [Azure Managed Grafana](https://learn.microsoft.com/azure/managed-grafana/overview)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Azure Verified Modules](https://aka.ms/avm)

## License

This template is provided as-is for demonstration purposes.

## Support

For issues or questions:
1. Check Azure Monitor Agent troubleshooting guide
2. Review deployment logs in Azure Portal
3. Verify resource health in Azure Resource Health

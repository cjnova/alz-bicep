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

### 1. Configure Parameters

Edit `parameters/main.bicepparam`:

```bicep
param vnetName = 'your-vnet-name'          // Update with your VNet
param subnetName = 'your-subnet-name'      // Update with your subnet
param adminPassword = ''                   // Leave empty - you'll be prompted during deployment
param location = 'eastus'                  // Your preferred region
param enableRbacAssignments = true         // Set false if you only have Contributor role
```

### 2. Validate Template

Validate that the template is syntactically correct. **You'll be prompted to enter the admin password securely:**

```bash
# Azure CLI - prompts: "Please provide securestring value for 'adminPassword':"
az deployment group validate \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam

# PowerShell - prompts for SecureString
Test-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam
```

**Password Requirements:** Min 12 chars, uppercase, lowercase, number, special char

### 3. Preview Changes (What-If)

Preview what resources will be created/modified. **You'll be prompted for password again:**

```bash
# Azure CLI - will prompt for password
az deployment group what-if \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam

# PowerShell - will prompt for password
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam `
  -WhatIf
```

### 4. Deploy

**You'll be prompted to enter the admin password securely** (won't be displayed on screen):

```bash
# Azure CLI - prompts: "Please provide securestring value for 'adminPassword':"
az deployment group create \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --name "monitoring-deployment"

# PowerShell - prompts for SecureString password
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam `
  -Name "monitoring-deployment"
```

**Deployment takes ~10-15 minutes.**

## 📦 What Gets Deployed

- **Log Analytics Workspace** - Central log repository (30-day retention)
- **Data Collection Endpoint** - Log ingestion endpoint
- **Data Collection Rule** - Custom JSON log collection from `/var/log/net-resilience/`
- **Azure Managed Grafana** - Monitoring dashboards (Standard tier, Grafana 10)
- **3 Virtual Machines** - Ubuntu 24.04, Standard_B2ts_v2, across availability zones
- **DCR Associations** - Automatic Azure Monitor Agent installation on VMs
- **RBAC Permissions** - Automated role assignments:
  - VMs → DCR: Monitoring Metrics Publisher (send logs)
  - Grafana → LAW: Monitoring Reader (query data)

## 🔍 Verify Deployment

```bash
# Check VMs
az vm list -g <your-rg-name> -o table

# Check AMA installation (wait 5-10 minutes)
az vm extension list -g <your-rg-name> --vm-name vm-netres-1 -o table

# Get Grafana endpoint
az deployment group show \
  -g <your-rg-name> \
  -n "monitoring-deployment" \
  --query properties.outputs.grafanaEndpoint.value
```

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
- ✅ **Custom Logs**: JSON log collection from `/var/log/net-resilience/`
- ✅ **Flexible**: Conditional Grafana deployment, configurable VM count
- ✅ **Cost-Effective**: B2ts_v2 VMs (2 vCPU, 1 GB), 30-day retention

## 🛠️ Requirements

- Azure subscription
- Existing VNet with subnet
- Azure CLI or PowerShell
- Bicep CLI v0.30.x+

## 📄 License

Provided as-is for demonstration purposes.

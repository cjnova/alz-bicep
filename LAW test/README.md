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

### 1. Configure Parameters

Edit `parameters/main.bicepparam`:

```bicep
param vnetName = 'your-vnet-name'          // Update with your VNet
param subnetName = 'your-subnet-name'      // Update with your subnet
param adminPassword = 'YourSecureP@ssw0rd' // Set secure password
param location = 'eastus'                  // Your preferred region
```

### 2. Validate Deployment

```bash
az deployment group validate \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam
```

### 3. Deploy

```bash
az deployment group create \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --name "monitoring-deployment"
```

## 📦 What Gets Deployed

- **Log Analytics Workspace** - Central log repository
- **Data Collection Endpoint** - Log ingestion endpoint
- **Data Collection Rule** - Custom JSON log collection config
- **3 Virtual Machines** - Ubuntu 24.04 across availability zones
- **DCR Associations** - Automatic Azure Monitor Agent installation

## 🔍 Verify Deployment

```bash
# Check VMs
az vm list -g <your-rg-name> -o table

# Check AMA installation (wait 5-10 minutes)
az vm extension list -g <your-rg-name> --vm-name vm-netres-1 -o table
```

## 📚 Full Documentation

See [docs/README.md](docs/README.md) for:
- Detailed architecture
- Complete parameter reference
- Post-deployment configuration
- Troubleshooting guide
- Cost optimization tips

## 🧪 Module Testing

To test the VM module independently:

```bash
az deployment group create \
  --resource-group <your-rg-name> \
  --template-file modules/vms.bicep \
  --parameters parameters/vms.bicepparam
```

## 💡 Key Features

- ✅ Encryption at host enabled
- ✅ Microsoft Entra ID login
- ✅ Automatic Azure Monitor Agent installation
- ✅ Latest API versions (2024-10-01 for Network)
- ✅ Azure Verified Modules (AVM)
- ✅ Custom JSON log collection

## 🛠️ Requirements

- Azure subscription
- Existing VNet with subnet
- Azure CLI or PowerShell
- Bicep CLI v0.30.x+

## 📄 License

Provided as-is for demonstration purposes.

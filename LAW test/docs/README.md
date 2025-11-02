# Azure Monitoring Infrastructure with VM Deployment

This Bicep template orchestrates the deployment of a complete Azure monitoring solution with Virtual Machines configured for custom log collection.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      main.bicep                             │
│                   (Orchestration Layer)                     │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┬──────────────┐
        │                   │                   │              │
        ▼                   ▼                   ▼              ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐  ┌─────────┐
│     LAW      │◄───│   Grafana    │    │     DCE      │  │   DCR   │
│  (Workspace) │    │  (Standard)  │    │  (Endpoint)  │  │  (Rule) │
└──────────────┘    └──────────────┘    └──────────────┘  └─────┬───┘
                                                                 │
                                                                 │ Associated via
                                                                 ▼
                                                          ┌──────────────┐
                                                          │   vms.bicep  │
                                                          │  (3 VMs in   │
                                                          │     AZs)     │
                                                          └──────────────┘
```

## Components

### 1. Log Analytics Workspace (LAW)
- **Purpose**: Central log repository
- **Retention**: 30 days
- **SKU**: PerGB2018 (pay-as-you-go)
- **Managed Identity**: System-assigned enabled

### 2. Data Collection Endpoint (DCE)
- **Purpose**: Network endpoint for log ingestion
- **Public Access**: Enabled (can be restricted to private endpoint)
- **Description**: DCE for net-resilience logs

### 3. Data Collection Rule (DCR)
- **Kind**: Linux
- **Data Sources**: JSON log files from `/var/log/net-resilience/net-*.jsonl`
- **Stream**: `NetResilience_CL` (custom table)
- **Format**: JSON Lines
- **Destination**: Log Analytics Workspace

### 4. Virtual Machines (via vms.bicep)
- **Count**: 3 VMs across availability zones 1, 2, 3
- **OS**: Ubuntu 24.04 LTS (Noble)
- **Size**: Standard_B2s
- **Disk**: 30 GB Premium SSD
- **Features**:
  - Encryption at Host enabled
  - Entra ID login enabled
  - Cloud-init for configuration
  - Azure Monitor Agent installation

### 5. Data Collection Rule Associations (DCRA)
- **Purpose**: Associate DCR with each VM
- **Scope**: Each VM resource
- **API Version**: 2023-03-11

### 6. Azure Managed Grafana (Optional)
- **SKU**: Standard (non-Enterprise)
- **Version**: Grafana 10
- **Integration**: Automatic Log Analytics datasource
- **Authentication**: Microsoft Entra ID (Azure AD)
- **API Version**: 2024-10-01
- **Features**:
  - System-assigned managed identity
  - API key authentication enabled
  - Public network access (configurable)
  - Optional zone redundancy for HA

## File Structure

```
LAW test/
├── main.bicep                    # Orchestration template
├── README.md                     # Quick start guide
├── .gitignore                    # Git ignore rules
│
├── modules/                      # Reusable Bicep modules
│   ├── vms.bicep                # VM deployment module
│   └── grafana.bicep            # Managed Grafana module
│
├── parameters/                   # All parameter files
│   ├── main.bicepparam          # Production parameters (main deployment)
│   └── vms.bicepparam           # VM unit testing parameters
│
└── docs/                        # Documentation
    └── README.md                # Complete detailed documentation (this file)
```

## Prerequisites

1. **Azure Subscription** with appropriate permissions
2. **Existing Virtual Network** with subnet
3. **Resource Group** created
4. **Azure CLI** or **Azure PowerShell** installed
5. **Bicep CLI** v0.30.x or later

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

## Deployment

### Step 1: Update Parameters

Edit `parameters/main.bicepparam` and provide:
- Your existing **VNet name** and **subnet name**
- A secure **admin password**
- Desired **Azure region** (location)
- Grafana name (or disable with `enableGrafana = false`)

```bicep
param location = 'eastus'
param vnetName = 'your-vnet-name'
param subnetName = 'your-subnet-name'
param adminPassword = '...' // Use secure parameter or Key Vault reference
param grafanaName = 'grafana-net-resilience-prod'
param enableGrafana = true
```

### Step 2: Validate the Deployment

```bash
# Azure CLI
az deployment group validate \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam

# Azure PowerShell
Test-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam
```

### Step 3: Deploy

```bash
# Azure CLI
az deployment group create \
  --resource-group <your-rg-name> \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --name "netres-monitoring-deployment"

# Azure PowerShell
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg-name> `
  -TemplateFile main.bicep `
  -TemplateParameterFile parameters/main.bicepparam `
  -Name "netres-monitoring-deployment"
```

### Step 4: Verify Deployment

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

## Post-Deployment Configuration

### Access Azure Managed Grafana

1. **Get the Grafana URL** from deployment outputs (see above)
2. **Navigate to the URL** in your browser
3. **Authenticate** using Microsoft Entra ID (your Azure AD account)
4. **Grant permissions** when prompted

**Grafana is pre-configured with:**
- ✅ Log Analytics workspace as a datasource
- ✅ Azure Monitor integration
- ✅ Managed identity authentication

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

### Cannot access Grafana

1. **Verify deployment**: Check `grafanaEndpoint` output is not empty
   ```bash
   az deployment group show \
     -g <rg> \
     -n "netres-monitoring-deployment" \
     --query properties.outputs.grafanaEndpoint.value
   ```

2. **Check permissions**: Your Azure AD account needs access
   - Navigate to Grafana resource in Azure Portal
   - Go to **Access control (IAM)**
   - Add yourself as **Grafana Admin** or **Grafana Editor**

3. **Disable Grafana**: Set `enableGrafana = false` in parameters if not needed

### Deployment errors

Common issues:
- **Subnet not found**: Verify VNet and subnet names in parameters
- **Invalid admin password**: Must meet complexity requirements
- **Quota exceeded**: Check VM quota in your subscription/region

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

4. **Managed Identities**: VMs use managed identity for Azure Monitor Agent authentication

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

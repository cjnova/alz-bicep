# Network Resilience Monitoring - Technical Documentation

> **Note**: For complete deployment instructions, troubleshooting, and detailed guides, see the [main README.md](../README.md).

This document provides technical reference material for developers and operators working with the network resilience monitoring infrastructure.

## 📋 Quick Reference

### Architecture Overview

**Deployed Resources:**

- User-Assigned Managed Identity (`id-ama-net-resilience`)
- Log Analytics Workspace (`law-net-resilience`) with custom table `NetResilience_CL`
- Data Collection Rule (`dcr-net-resilience-prod`) - No DCE (public ingestion)
- 3 Ubuntu VMs (`vmnetres-1/2/3`) across availability zones 1/2/3
- Azure Monitor Linux Agent (AMA) + AADSSHLoginForLinux extensions

**Data Flow:**

```text
VM (PowerShell tests) → JSON logs (/var/log/net-resilience/)
  ↓
Azure Monitor Agent (AMA) → Managed Identity Auth
  ↓
Data Collection Rule (DCR) → Public Endpoint
  ↓
Log Analytics Workspace → NetResilience_CL table
  ↓
Azure Portal Dashboards → KQL Queries
```

### Key Files

| File | Purpose |
|------|---------|
| `main.bicep` | Main deployment template |
| `parameters/main.bicepparam` | Deployment parameters + cloud-init script |
| `modules/vms.bicep` | VM deployment module with cross-RG VNet support |
| `scripts/Install-AMA-Manually.ps1` | Manual extension installation (if RBAC disabled) |
| `docs/Dashboard-KQL-Queries.md` | 7 pre-built dashboard queries |

### Resource Configuration

#### Log Analytics Workspace

- **SKU**: PerGB2018 (pay-as-you-go)
- **Retention**: 30 days
- **Pricing**: ~$2.30/GB ingested + ~$0.10/GB stored
- **Expected Cost**: ~$10/month (150 MB/day from 3 VMs)

#### Data Collection Rule

- **Kind**: Linux
- **Data Source**: logFiles (JSON format)
- **File Pattern**: `/var/log/net-resilience/net-*.jsonl`
- **Stream**: `Custom-NetResilience_CL`
- **Endpoint**: Public ingestion (no DCE)
- **Transformation**: None (pass-through)

#### Virtual Machines

- **SKU**: Standard_B2als_v2 (2 vCPU, 4 GB RAM, ARM-based)
- **OS**: Ubuntu 24.04 LTS
- **Disk**: 30 GB Premium SSD
- **Identity**: User-assigned (for AMA) + System-assigned (for Entra ID SSH)
- **Zones**: 1, 2, 3 (one VM per zone)
- **Pricing**: ~$60/month per VM = $180/month total

### Custom Table Schema

**Table**: `NetResilience_CL`

| Column | Type | Description |
|--------|------|-------------|
| `TimeGenerated` | `dateTime` | Azure ingestion timestamp (UTC) |
| `LocalTime` | `string` | Test execution timestamp (ISO 8601 with timezone) |
| `AzLocation` | `string` | Azure region (e.g., `swedencentral`) |
| `AzZone` | `string` | Availability zone (`1`, `2`, `3`) |
| `VmInstance` | `string` | VM hostname (e.g., `vmnetres-1`) |
| `TestType` | `string` | Test category (e.g., `OnPrem`) |
| `Target` | `string` | Test target (hostname or URL) |
| `Protocol` | `string` | Test protocol (`ICMP` or `HTTP`) |
| `LatencyMs` | `int` | Round-trip latency in milliseconds |
| `Success` | `boolean` | Test succeeded (`true`/`false`) |
| `StatusCode` | `int` | Protocol status code |
| `StatusName` | `string` | Human-readable status |
| `Error` | `string` | Error message (empty if success) |
| `CorrelationId` | `string` | GUID for tracking related tests |

### RBAC Configuration

**Required Role Assignment:**

- **Role**: Monitoring Metrics Publisher (`3913510d-42f4-4e42-8a64-420c390055eb`)
- **Principal**: User-assigned managed identity (`id-ama-net-resilience`)
- **Scope**: Data Collection Rule (`dcr-net-resilience-prod`)

**Deployment Options:**

1. **Automatic** (if `enableRbacAssignments=true`): Role assigned during deployment (requires User Access Administrator)
2. **Manual** (if `enableRbacAssignments=false`): Assign role post-deployment using PowerShell/Azure CLI

### VM Extensions

**Extensions deployed on each VM:**

1. **AADSSHLoginForLinux**
   - Publisher: `Microsoft.Azure.ActiveDirectory`
   - Purpose: Enable Entra ID SSH authentication
   - Installation: **Automatic during VM provisioning** (via Bicep `extensionAadJoinConfig`)
   - Enables `az ssh vm` command with Azure AD credentials

2. **AzureMonitorLinuxAgent (AMA)**
   - Publisher: `Microsoft.Azure.Monitor`
   - Purpose: Collect custom logs and send to Log Analytics
   - Authentication: User-assigned managed identity
   - Installation Options:
     - **Automatic**: If `enableRbacAssignments=true` (RBAC assigned during deployment)
     - **Manual**: Use `Install-AMA-Manually.ps1` script if RBAC not automatically assigned

3. **ConfigurationforLinux (Optional)**
   - Publisher: `Microsoft.GuestConfiguration`
   - Purpose: Azure Policy guest configuration compliance
   - Installation: **Automatic** when Azure Policy configurations are assigned to VMs
   - Manual installation: Use `Install-AMA-Manually.ps1 -InstallGuestConfiguration` if needed for specific policy requirements

**Base Agent (pre-installed):**
- **Azure Linux Guest Agent (waagent)**: Pre-installed on all Ubuntu marketplace images, manages VM extensions and Azure fabric communication

### Cloud-Init Configuration

**Location**: Embedded in `parameters/main.bicepparam`

**What it does:**

1. Installs PowerShell 7
2. Creates `/opt/net-resilience/Run-OnPremTests.ps1` (network test script)
3. Creates `/etc/net-resilience.conf` (JSON configuration)
4. Creates `/etc/systemd/system/net-resilience.service` (systemd unit)
5. Enables and starts the service

**Service Details:**

- **Name**: `net-resilience`
- **Type**: Simple (foreground process)
- **ExecStart**: `/usr/bin/pwsh -File /opt/net-resilience/Run-OnPremTests.ps1`
- **Restart**: Always (with 10-second delay)

### PowerShell Type Safety

**Critical for proper JSON serialization:**

```powershell
# Initialize with explicit types (not $null or default)
$latencyMs = [int]0          # JSON: 0 (not "" or null)
$success = [bool]$false      # JSON: false (not "False")
$statusCode = [int]99999     # JSON: 99999 (not "99999")
$errorMsg = ""               # JSON: "" (not null)

# Explicit casts when assigning values
$latencyMs = [int]$pingResult.Latency          # JSON: 491 (not "491")
$success = [bool]($statusCode -eq 0)           # JSON: true (not "True")
$statusCode = [int]$resp.StatusCode            # JSON: 200 (not "200")
```

**Why this matters**: Without explicit types, PowerShell may serialize numbers as strings and booleans as "True"/"False", causing KQL query failures.

### Deployment Timeline

| Time | Milestone | Verification |
|------|-----------|--------------|
| T+0 | Deployment started | `az deployment group create` |
| T+5min | LAW + Custom Table ready | Query: `NetResilience_CL \| getschema` |
| T+6min | DCR deployed | `az monitor data-collection rule show` |
| T+15min | VMs running | `az vm list --query "[].powerState"` |
| T+20min | Cloud-init complete | SSH: `systemctl status net-resilience` |
| T+30min | Extensions installed | `az vm extension list` |
| T+40min | Data flowing | Query: `NetResilience_CL \| take 10` |
| T+45min | Dashboard ready | Create dashboard with KQL queries |

### API Versions

| Resource | API Version |
|----------|-------------|
| User-Assigned Identity | `2023-01-31` |
| Log Analytics Workspace | `2022-10-01` |
| Data Collection Rule | `2022-06-01` |
| Virtual Machine | `2024-03-01` |
| Network Interface | `2024-10-01` |
| Role Assignment | `2022-04-01` |

### AVM Modules Used

- `avm/res/managed-identity/user-assigned-identity:0.4.0`
- `avm/res/operational-insights/workspace:0.12.0`
- `avm/res/insights/data-collection-rule:0.8.0`
- `avm/res/compute/virtual-machine:0.20.0`
- `avm/ptn/authorization/resource-role-assignment:0.1.1`

---

## 📚 Additional Resources

- **Main README**: [../README.md](../README.md) - Complete deployment guide, prerequisites, troubleshooting
- **Dashboard Queries**: [Dashboard-KQL-Queries.md](Dashboard-KQL-Queries.md) - 7 pre-built KQL queries for Azure Dashboards
- **Manual AMA Installation**: `scripts/Install-AMA-Manually.ps1` - Extension installation script

---

**Last Updated**: November 2025  
**Version**: 1.0  
**Maintained By**: SDS Public Cloud Azure Architecture Team

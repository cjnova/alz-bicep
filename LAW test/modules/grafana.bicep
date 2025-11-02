// ============================================================================
// Managed Grafana Module
// ============================================================================
// This module deploys an Azure Managed Grafana instance (Standard tier)
// integrated with Log Analytics Workspace for monitoring dashboards

@description('The name of the Managed Grafana instance')
param grafanaName string

@description('Location for the Grafana instance')
param location string

@description('Resource ID of the Log Analytics Workspace to integrate with')
param logAnalyticsWorkspaceId string

@description('Tags to apply to the Grafana resource')
param tags object = {}

@description('Enable zone redundancy for high availability')
param zoneRedundancy bool = false

@description('Enable public network access')
param publicNetworkAccess bool = true

@description('Enable deterministic outbound IPs')
param deterministicOutboundIP bool = false

@description('Enable API key authentication')
param apiKey bool = true

@description('Grafana major version to deploy')
param grafanaMajorVersion string = '10'

// ============================================================================
// Managed Grafana Instance (Standard - non-Enterprise)
// ============================================================================
resource grafana 'Microsoft.Dashboard/grafana@2024-10-01' = {
  name: grafanaName
  location: location
  tags: tags
  
  // Standard SKU (non-Enterprise)
  sku: {
    name: 'Standard'
  }
  
  // System-assigned managed identity for Azure resource access
  identity: {
    type: 'SystemAssigned'
  }
  
  properties: {
    // API key setting
    apiKey: apiKey ? 'Enabled' : 'Disabled'
    
    // Deterministic outbound IPs (useful for firewall rules)
    deterministicOutboundIP: deterministicOutboundIP ? 'Enabled' : 'Disabled'
    
    // Public network access control
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    
    // Zone redundancy for HA
    zoneRedundancy: zoneRedundancy ? 'Enabled' : 'Disabled'
    
    // Grafana version
    grafanaMajorVersion: grafanaMajorVersion
    
    // Integration with Azure Monitor (Log Analytics)
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================
@description('The resource ID of the Grafana instance')
output resourceId string = grafana.id

@description('The name of the Grafana instance')
output name string = grafana.name

@description('The endpoint URL of the Grafana instance')
output endpoint string = grafana.properties.endpoint

@description('The principal ID of the system-assigned managed identity')
output principalId string = grafana.identity.principalId

@description('The Grafana version deployed')
output grafanaVersion string = grafana.properties.grafanaVersion

@description('List of outbound IPs (if deterministic IPs enabled)')
output outboundIPs array = deterministicOutboundIP ? grafana.properties.outboundIPs : []

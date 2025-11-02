param location string
param workspaceName string
param dceName string
param dcrName string
param deploymentTimestamp string = utcNow()

// Grafana parameters
param grafanaName string
param enableGrafana bool = true
param grafanaZoneRedundancy bool = false

// VM deployment parameters
param vmNamePrefix string
param vmCount int = 3
param adminUsername string
@secure()
param adminPassword string
param vnetName string
param subnetName string
param cloudInitData string
param osType string
param vmSize string
param imageReference object
param osDisk object
param disablePasswordAuthentication bool
param enableEntraIdLogin bool
param encryptionAtHost bool

module law 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: '${workspaceName}-${deploymentTimestamp}'
  params: {
    name: workspaceName
    location: location
    dataRetention: 30
    skuName: 'PerGB2018'
    managedIdentities: {
      systemAssigned: true
    }
  }
}

module dce 'br/public:avm/res/insights/data-collection-endpoint:0.5.1' = {
  name: '${dceName}-${deploymentTimestamp}'
  params: {
    name: dceName
    location: location
    description: 'DCE for net-resilience logs'
    publicNetworkAccess: 'Enabled'
  }
}

module dcr 'br/public:avm/res/insights/data-collection-rule:0.8.0' = {
  name: '${dcrName}-${deploymentTimestamp}'
  params: {
    name: dcrName
    location: resourceGroup().location

    dataCollectionRuleProperties: {
      kind: 'Linux'
      description: 'Collect custom JSON logs for Net Resilience'
      dataCollectionEndpointResourceId: dce.outputs.resourceId

      dataSources: {
        logFiles: [
          {
            name: 'netResilienceSource'
            streams: [
              'NetResilience_CL'
            ]
            filePatterns: [
              '/var/log/net-resilience/net-*.jsonl'
            ]
            format: 'json'
          }
        ]
      }

      destinations: {
        logAnalytics: [
          {
            name: 'logAnalyticsDest'
            workspaceResourceId: law.outputs.resourceId
          }
        ]
      }

      dataFlows: [
        {
          streams: [
            'NetResilience_CL'
          ]
          destinations: [
            'logAnalyticsDest'
          ]
        }
      ]
    }
  }
}

// Deploy Managed Grafana (optional)
module grafana './modules/grafana.bicep' = if (enableGrafana) {
  name: 'grafana-${deploymentTimestamp}'
  params: {
    grafanaName: grafanaName
    location: location
    logAnalyticsWorkspaceId: law.outputs.resourceId
    zoneRedundancy: grafanaZoneRedundancy
    publicNetworkAccess: true
    deterministicOutboundIP: false
    apiKey: true
    grafanaMajorVersion: '10'
    tags: {
      Environment: 'Production'
      ManagedBy: 'Bicep'
      Purpose: 'Monitoring-Dashboards'
    }
  }
}

// Deploy VMs
module vmDeployment './modules/vms.bicep' = {
  name: 'vm-deployment-${deploymentTimestamp}'
  params: {
    location: location
    vmNamePrefix: vmNamePrefix
    vmCount: vmCount
    adminUsername: adminUsername
    adminPassword: adminPassword
    vnetName: vnetName
    subnetName: subnetName
    cloudInitData: cloudInitData
    osType: osType
    vmSize: vmSize
    imageReference: imageReference
    osDisk: osDisk
    disablePasswordAuthentication: disablePasswordAuthentication
    enableEntraIdLogin: enableEntraIdLogin
    encryptionAtHost: encryptionAtHost
    deploymentTimestamp: deploymentTimestamp
  }
  dependsOn: [
    dcr
  ]
}

// Associate DCR with VMs using Data Collection Rule Associations
// Reference existing VMs deployed by the module
resource existingVms 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [for i in range(0, vmCount): {
  name: '${vmNamePrefix}-${i + 1}'
}]

// Create DCR associations as extension resources scoped to each VM
resource dcrAssociations 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [for i in range(0, vmCount): {
  name: 'dcra-${vmNamePrefix}-${i + 1}'
  scope: existingVms[i]
  properties: {
    dataCollectionRuleId: dcr.outputs.resourceId
  }
  dependsOn: [
    vmDeployment
  ]
}]

// Outputs
output lawResourceId string = law.outputs.resourceId
output lawWorkspaceId string = law.outputs.logAnalyticsWorkspaceId
output dceResourceId string = dce.outputs.resourceId
output dcrResourceId string = dcr.outputs.resourceId
output vmResourceIds array = vmDeployment.outputs.vmIds
output vmNames array = vmDeployment.outputs.vmNames
output grafanaResourceId string = enableGrafana ? grafana!.outputs.resourceId : ''
output grafanaEndpoint string = enableGrafana ? grafana!.outputs.endpoint : ''
output grafanaPrincipalId string = enableGrafana ? grafana!.outputs.principalId : ''

// ============================================================================
// Azure Monitoring Infrastructure - Main Orchestration Template
// ============================================================================
// Deploys complete monitoring solution:
// - Log Analytics Workspace (LAW) for log storage
// - Data Collection Rule (DCR) with stream declarations for custom JSON logs
// - Virtual Machines (Ubuntu 24.04) with cloud-init configuration
// - Data Collection Rule Associations (DCRA) for automatic AMA deployment
// - RBAC role assignments (user-assigned managed identity → DCR)
//
// Key Features:
// - Custom JSON log collection from /var/log/net-resilience/*.jsonl
// - Stream declarations define 14-field schema (TimeGenerated, LocalTime, etc.)
// - No transformation applied - JSONL data flows through unchanged
// - Cloud-init with line-ending normalization (no manual base64 encoding)
// - User-assigned managed identities for secure authentication
// - No DCE required - AMA uses public endpoint for logFiles data source
// - Azure Dashboards for visualization (created manually via portal)
// ============================================================================

param location string
param workspaceName string
param dcrName string
param deploymentTimestamp string = utcNow()

// RBAC parameters
param enableRbacAssignments bool = true

// Managed Identity parameters
param managedIdentityName string

// VM deployment parameters
param vmNamePrefix string
param vmCount int = 3
param adminUsername string
@secure()
param adminPassword string
param vnetName string
param subnetName string
@description('Optional: Resource group name where VNet is located. Leave empty if VNet is in the same resource group as the deployment.')
param vnetResourceGroup string = ''
param cloudInitData string
param osType string
param vmSize string
param imageReference object
param osDisk object
param disablePasswordAuthentication bool
param enableEntraIdLogin bool
param encryptionAtHost bool

// ============================================================================
// User-Assigned Managed Identity for AMA
// ============================================================================
// Required for Azure Monitor Agent to authenticate and send logs to DCR/LAW
// User-assigned identity is recommended over system-assigned for:
// - Better scalability (shared across multiple VMs)
// - Less churn in Entra ID (identity persists across VM lifecycle)
// - Easier management at scale

module managedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: '${managedIdentityName}-${deploymentTimestamp}'
  params: {
    name: managedIdentityName
    location: location
  }
}

// ============================================================================
// Log Analytics Workspace
// ============================================================================

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
    // Create custom table using AVM
    tables: [
      {
        name: 'NetResilience_CL'
        retentionInDays: 30
        plan: 'Analytics'
        schema: {
          name: 'NetResilience_CL'
          description: 'Network resilience monitoring logs from PowerShell tests'
          columns: [
            { name: 'TimeGenerated', type: 'dateTime', description: 'Timestamp when the record was generated (UTC)' }
            { name: 'LocalTime', type: 'string', description: 'Local timestamp with timezone (ISO8601 format)' }
            { name: 'AzLocation', type: 'string', description: 'Azure region where the VM is located' }
            { name: 'AzZone', type: 'string', description: 'Azure availability zone of the VM' }
            { name: 'VmInstance', type: 'string', description: 'VM instance name' }
            { name: 'TestType', type: 'string', description: 'Type of network test (ICMP, HTTP, etc.)' }
            { name: 'Target', type: 'string', description: 'Target endpoint being tested' }
            { name: 'Protocol', type: 'string', description: 'Protocol used for the test' }
            { name: 'LatencyMs', type: 'int', description: 'Latency in milliseconds' }
            { name: 'Success', type: 'boolean', description: 'Whether the test succeeded' }
            { name: 'StatusCode', type: 'int', description: 'HTTP status code or ICMP response code' }
            { name: 'StatusName', type: 'string', description: 'Human-readable status name' }
            { name: 'Error', type: 'string', description: 'Error message if test failed' }
            { name: 'CorrelationId', type: 'string', description: 'Correlation ID for tracking related tests' }
          ]
        }
      }
    ]
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
      // No DCE needed - AMA uses public endpoint by default for logFiles data source

      dataSources: {
        logFiles: [
          {
            name: 'netResilienceSource'
            streams: [
              'Custom-NetResilience_CL'
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
            'Custom-NetResilience_CL'
          ]
          destinations: [
            'logAnalyticsDest'
          ]
          outputStream: 'Custom-NetResilience_CL'
        }
      ]

      streamDeclarations: {
        'Custom-NetResilience_CL': {
          columns: [
            {
              name: 'TimeGenerated'
              type: 'datetime'
            }
            {
              name: 'LocalTime'
              type: 'string'
            }
            {
              name: 'AzLocation'
              type: 'string'
            }
            {
              name: 'AzZone'
              type: 'string'
            }
            {
              name: 'VmInstance'
              type: 'string'
            }
            {
              name: 'TestType'
              type: 'string'
            }
            {
              name: 'Target'
              type: 'string'
            }
            {
              name: 'Protocol'
              type: 'string'
            }
            {
              name: 'LatencyMs'
              type: 'int'
            }
            {
              name: 'Success'
              type: 'boolean'
            }
            {
              name: 'StatusCode'
              type: 'int'
            }
            {
              name: 'StatusName'
              type: 'string'
            }
            {
              name: 'Error'
              type: 'string'
            }
            {
              name: 'CorrelationId'
              type: 'string'
            }
          ]
        }
      }
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
    vnetResourceGroup: vnetResourceGroup
    cloudInitData: cloudInitData
    osType: osType
    vmSize: vmSize
    imageReference: imageReference
    osDisk: osDisk
    disablePasswordAuthentication: disablePasswordAuthentication
    enableEntraIdLogin: enableEntraIdLogin
    encryptionAtHost: encryptionAtHost
    deploymentTimestamp: deploymentTimestamp
    userAssignedIdentityResourceId: managedIdentity.outputs.resourceId
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

// Reference the deployed DCR for role assignments
resource existingDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: dcrName
}

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

// Grant user-assigned managed identity permission to send data to DCR
// Note: Since AMA uses the user-assigned identity for authentication,
// this role must be granted to the user-assigned identity (not system-assigned)
resource dcrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAssignments) {
  name: guid(existingDcr.id, managedIdentityName, '3913510d-42f4-4e42-8a64-420c390055eb')
  scope: existingDcr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalId: managedIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    dcrAssociations
  ]
}

// Outputs
output lawResourceId string = law.outputs.resourceId
output lawWorkspaceId string = law.outputs.logAnalyticsWorkspaceId
output dcrResourceId string = dcr.outputs.resourceId
output managedIdentityResourceId string = managedIdentity.outputs.resourceId
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId
output managedIdentityClientId string = managedIdentity.outputs.clientId
output vmResourceIds array = vmDeployment.outputs.vmIds
output vmNames array = vmDeployment.outputs.vmNames

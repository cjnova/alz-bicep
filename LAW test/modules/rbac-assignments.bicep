// rbac-assignments.bicep
// Separate template for RBAC role assignments
// Use this when deploying with Contributor role (set enableRbacAssignments=false in main deployment)
// Requires Owner or User Access Administrator role to deploy

param dcrName string
param lawName string
param vmNames array
param grafanaName string
param enableGrafana bool = true

// Reference existing DCR
resource existingDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: dcrName
}

// Reference existing LAW
resource existingLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}

// Reference existing VMs
resource existingVms 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [for vmName in vmNames: {
  name: vmName
}]

// Reference existing Grafana
resource existingGrafana 'Microsoft.Dashboard/grafana@2024-10-01' existing = if (enableGrafana) {
  name: grafanaName
}

// Grant VM managed identities permission to send data to DCR
resource dcrRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (vmName, i) in vmNames: {
  name: guid(existingDcr.id, existingVms[i].id, '3913510d-42f4-4e42-8a64-420c390055eb')
  scope: existingDcr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalId: existingVms[i].identity.principalId
    principalType: 'ServicePrincipal'
  }
}]

// Grant Grafana managed identity permission to read from LAW
resource grafanaLawRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableGrafana) {
  name: guid(existingLaw.id, grafanaName, '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
  scope: existingLaw
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader
    principalId: existingGrafana!.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output dcrRoleAssignmentsCount int = length(vmNames)
output grafanaRoleAssignmentCreated bool = enableGrafana

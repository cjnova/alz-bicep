param location string
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
param deploymentTimestamp string = utcNow()
param userAssignedIdentityResourceId string

// Get existing virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2024-10-01' existing = {
  name: vnetName
}

// Get existing subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-10-01' existing = {
  parent: vnet
  name: subnetName
}

// Deploy VMs in a loop, one per availability zone
module vms 'br/public:avm/res/compute/virtual-machine:0.20.0' = [for i in range(1, vmCount): {
  name: '${vmNamePrefix}-${i}-${deploymentTimestamp}'
  params: {
    name: '${vmNamePrefix}-${i}'
    location: location
    availabilityZone: i
    
    osType: osType
    vmSize: vmSize
    
    imageReference: imageReference
    
    osDisk: osDisk
    
    adminUsername: adminUsername
    disablePasswordAuthentication: disablePasswordAuthentication
    adminPassword: adminPassword
    encryptionAtHost: encryptionAtHost
    
    // Enable VM agent (required for extensions)
    provisionVMAgent: true
    
    // Enable both system-assigned and user-assigned managed identities
    // System-assigned: Required for Entra ID login
    // User-assigned: Required for Azure Monitor Agent to authenticate to DCR/LAW
    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: [
        userAssignedIdentityResourceId
      ]
    }
    
    nicConfigurations: [
      {
        name: '${vmNamePrefix}-${i}-nic'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: subnet.id
          }
        ]
        deleteOption: 'Delete'
      }
    ]
    
    extensionAadJoinConfig: enableEntraIdLogin ? {
      enabled: true
    } : null
    
    // Enable Guest Configuration extension (required for Azure policies and compliance)
    extensionGuestConfigurationExtension: {
      enabled: true
      enableAutomaticUpgrade: true
    }
    
    // Normalize line endings: replace CRLF with LF, then any remaining CR with LF
    // Note: Azure automatically base64-encodes customData, so we don't call base64() here
    customData: replace(replace(cloudInitData, '\r\n', '\n'), '\r', '\n')
  }
}]

output vmNames array = [for i in range(0, vmCount): vms[i].outputs.name]
output vmIds array = [for i in range(0, vmCount): vms[i].outputs.resourceId]
output systemAssignedMIPrincipalIds array = [for i in range(0, vmCount): vms[i].outputs.systemAssignedMIPrincipalId!]

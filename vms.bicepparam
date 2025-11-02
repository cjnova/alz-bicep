using './vms.bicep'

param location = 'eastus'
param vmNamePrefix = 'myvm'
param vmCount = 3
param adminUsername = 'azureuser'
param adminPassword = '' // Set this value or use Key Vault reference
param vnetName = '' // Name of existing virtual network
param subnetName = '' // Name of existing subnet

// VM Configuration Parameters
param osType = 'Linux'
param vmSize = 'Standard_D2s_v3'
param disablePasswordAuthentication = false
param enableEntraIdLogin = true
param encryptionAtHost = true

param imageReference = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-noble'
  sku: '24_04-lts-gen2'
  version: 'latest'
}

param osDisk = {
  createOption: 'FromImage'
  deleteOption: 'Delete'
  diskSizeGB: 30
  managedDisk: {
    storageAccountType: 'Premium_LRS'
  }
}

param cloudInitData = '''
#cloud-config
package_update: true
package_upgrade: true

packages:
  - azure-cli
  - git

runcmd:
  - echo "VM provisioned successfully" > /tmp/cloud-init-complete.txt
'''

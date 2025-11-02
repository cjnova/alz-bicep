using '../main.bicep'

// Monitoring infrastructure parameters
param location = 'eastus'
param workspaceName = 'law-net-resilience-prod'
param dceName = 'dce-net-resilience-prod'
param dcrName = 'dcr-net-resilience-prod'

// Grafana parameters
param grafanaName = 'grafana-net-resilience-prod'
param enableGrafana = true
param grafanaZoneRedundancy = false

// RBAC parameters
// Set to false if deploying with Contributor role (role assignments will need to be done separately)
// Set to true if deploying with Owner or User Access Administrator role
param enableRbacAssignments = true

// VM deployment parameters
param vmNamePrefix = 'vm-netres'
param vmCount = 3
param adminUsername = 'azureuser'
param adminPassword = '' // Leave empty - Azure CLI/PowerShell will prompt securely during deployment
param vnetName = 'vnet-prod'  // Update with your existing VNet name
param subnetName = 'subnet-vms'  // Update with your existing subnet name
param osType = 'Linux'
param vmSize = 'Standard_B2ts_v2'
param disablePasswordAuthentication = false
param enableEntraIdLogin = true
param encryptionAtHost = true

// Ubuntu 24.04 LTS image
param imageReference = {
  publisher: 'canonical'
  offer: '0001-com-ubuntu-server-noble'
  sku: '24_04-lts-gen2'
  version: 'latest'
}

// OS Disk configuration - 30 GB Premium SSD
param osDisk = {
  caching: 'ReadWrite'
  createOption: 'FromImage'
  diskSizeGB: 30
  managedDisk: {
    storageAccountType: 'Premium_LRS'
  }
  deleteOption: 'Delete'
}

// Cloud-init script for VM initialization
param cloudInitData = '''
#cloud-config
package_update: true
package_upgrade: true
packages:
  - curl
  - jq
  - unzip
  - python3
  - python3-pip
  - git

runcmd:
  - mkdir -p /var/log/net-resilience
  - chmod 755 /var/log/net-resilience
  - echo "Net Resilience VM initialized at $(date)" > /var/log/net-resilience/init.log
  - echo "Azure Monitor Agent (AMA) will be automatically installed via Data Collection Rule Association" >> /var/log/net-resilience/init.log
  
write_files:
  - path: /var/log/net-resilience/readme.txt
    content: |
      This directory contains net-resilience application logs.
      Logs are collected by Azure Monitor Agent (AMA) via Data Collection Rule.
      
      AMA is automatically installed when the VM is associated with a DCR.
      No manual installation required.
      
      Log format: JSON Lines (.jsonl)
      Collection pattern: /var/log/net-resilience/net-*.jsonl
      
      Custom table in Log Analytics: NetResilience_CL
      
      For more information, see Azure Monitor documentation.
    owner: root:root
    permissions: '0644'
'''

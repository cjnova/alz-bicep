// rbac-assignments.bicepparam
// Parameter file for separate RBAC role assignments
// Use this when main deployment was done with enableRbacAssignments=false

using '../modules/rbac-assignments.bicep'

// Resource names - must match what was deployed
param dcrName = 'dcr-net-resilience-prod'
param lawName = 'law-net-resilience-prod'
param grafanaName = 'grafana-net-resilience-prod'
param enableGrafana = true

// VM names - must match the deployed VMs
param vmNames = [
  'vm-netres-1'
  'vm-netres-2'
  'vm-netres-3'
]

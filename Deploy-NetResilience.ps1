# ================================
# Net Resilience Deployment Script
# ================================

# --- Variables ---
$Subscription = "slz01-pro-zb1-regionalplatform001"
$ResourceGroup = "slz-pro-zb1-ResiliencyTesting"
$Location = "brazilsouth"
$LawName = "netresilience-law"
$DcrName = "netresilience-dcr"
$GrafanaName = "netresilience-grafana"
$DashboardJson = ".\netresilience-dashboard.json"
$DcrJson = ".\netresilience-dcr.json"

$VmNames = @("vmtest0001","vmtest0002","vmtest0003")

# --- Step 1: Create Log Analytics Workspace ---
Write-Host "Creating Log Analytics Workspace..."
az monitor log-analytics workspace create `
  --subscription $Subscription `
  --resource-group $ResourceGroup `
  --workspace-name $LawName `
  --location $Location

# --- Step 2: Create Custom Table ---
Write-Host "Creating custom table NetworkResilience_CL..."
az monitor log-analytics workspace table create `
  --subscription $Subscription `
  --resource-group $ResourceGroup `
  --workspace-name $LawName `
  --name NetworkResilience_CL `
  --columns TimeGenerated=datetime,AzLocation=string,AzZone=string,VmInstance=string,TestType=string,Target=string,Protocol=string,LatencyMs=long,Success=bool,StatusCode=string,Error=string,CorrelationId=string

# --- Step 3: Create DCR ---
Write-Host "Creating Data Collection Rule..."
az monitor data-collection rule create `
  --subscription $Subscription `
  --resource-group $ResourceGroup `
  --name $DcrName `
  --location $Location `
  --rule-file $DcrJson

# --- Step 4: Associate DCR with VMs ---
foreach ($vm in $VmNames) {
    Write-Host "Associating DCR with VM: $vm"
    az monitor data-collection rule association create `
      --subscription $Subscription `
      --name "$DcrName-assoc-$vm" `
      --resource "/subscriptions/$Subscription/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/$vm" `
      --rule-id "/subscriptions/$Subscription/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/dataCollectionRules/$DcrName"
}

# --- Step 5: Create Managed Grafana ---
Write-Host "Creating Managed Grafana instance..."
az grafana create `
  --subscription $Subscription `
  --name $GrafanaName `
  --resource-group $ResourceGroup `
  --location $Location `
  --sku Standard

# --- Step 6: Import Grafana Dashboard ---
Write-Host "Importing Grafana dashboard..."
az grafana dashboard import `
  --subscription $Subscription `
  --name $GrafanaName `
  --resource-group $ResourceGroup `
  --definition $DashboardJson

Write-Host "✅ Deployment complete."

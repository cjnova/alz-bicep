#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
SUBSCRIPTION="slz01-pro-zb1-regionalplatform001"
RG="slz-pro-zb1-ResiliencyTesting"
LOCATION="brazilsouth"
LAW_NAME="netresilience-law"
DCR_NAME="netresilience-dcr"
GRAFANA_NAME="netresilience-grafana"
DASHBOARD_JSON="./netresilience-dashboard.json"

VM_NAMES=("vmtest0001" "vmtest0002" "vmtest0003")

# === Step 1: Create Log Analytics Workspace ===
echo "Creating Log Analytics Workspace..."
az monitor log-analytics workspace create \
  --subscription "$SUBSCRIPTION" \
  --resource-group "$RG" \
  --workspace-name "$LAW_NAME" \
  --location "$LOCATION" \
  --query id -o tsv

# === Step 2: Create Custom Table ===
echo "Creating custom table NetworkResilience_CL..."
az monitor log-analytics workspace table create \
  --subscription "$SUBSCRIPTION" \
  --resource-group "$RG" \
  --workspace-name "$LAW_NAME" \
  --name NetworkResilience_CL \
  --columns TimeGenerated=datetime,AzLocation=string,AzZone=string,VmInstance=string,TestType=string,Target=string,Protocol=string,LatencyMs=long,Success=bool,StatusCode=string,Error=string,CorrelationId=string

# === Step 3: Create DCR ===
echo "Creating Data Collection Rule..."
az monitor data-collection rule create \
  --subscription "$SUBSCRIPTION" \
  --resource-group "$RG" \
  --name "$DCR_NAME" \
  --location "$LOCATION" \
  --rule-file ./netresilience-dcr.json

# === Step 4: Associate DCR with VMs ===
for VM in "${VM_NAMES[@]}"; do
  echo "Associating DCR with VM: $VM"
  az monitor data-collection rule association create \
    --subscription "$SUBSCRIPTION" \
    --name "${DCR_NAME}-assoc-$VM" \
    --resource "/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachines/$VM" \
    --rule-id "/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.Insights/dataCollectionRules/$DCR_NAME"
done

# === Step 5: Create Managed Grafana ===
echo "Creating Managed Grafana instance..."
az grafana create \
  --subscription "$SUBSCRIPTION" \
  --name "$GRAFANA_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard

# === Step 6: Import Grafana Dashboard ===
echo "Importing Grafana dashboard..."
az grafana dashboard import \
  --subscription "$SUBSCRIPTION" \
  --name "$GRAFANA_NAME" \
  --resource-group "$RG" \
  --definition "$DASHBOARD_JSON"

echo "✅ Deployment complete."

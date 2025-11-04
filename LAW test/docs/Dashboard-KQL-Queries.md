# 📊 Azure Dashboard - Network Resilience KQL Queries

This document provides ready-to-use KQL queries for creating an Azure Portal Dashboard to visualize network resilience test data from the `NetResilience_CL` custom log table.

## ⚠️ Important: Using LocalTime vs TimeGenerated

The queries in this guide use the **`LocalTime`** field (string format: ISO 8601) instead of Azure's system-generated `TimeGenerated` field. 

**Why LocalTime?**
- **LocalTime**: Timestamp when the test was actually executed on the VM (accurate test time)
- **TimeGenerated**: Timestamp when Azure ingested the log (can have delays)

**Note**: Since `LocalTime` is a string, we convert it to datetime using `todatetime(LocalTime)` for time-based operations.

---

## 🎯 Dashboard Overview

The dashboard includes 7 key visualizations:
1. **Latency Trend** - Time series chart showing average and P95 latency
2. **Failure Rate by Target** - Grid showing failure statistics per endpoint
3. **Latency Statistics by VM** - Detailed percentile breakdown per VM instance
4. **Zone Comparison** - Compare performance across availability zones
5. **Protocol Breakdown** - Donut chart showing ICMP vs HTTP distribution
6. **Recent Failures** - Real-time troubleshooting view of failures
7. **Success Rate by VM** - Bar chart showing health overview

---

## 📈 Query 1: Latency Trend (Time Chart)

**Visualization**: Line Chart  
**Time Range**: Last 1 hour  
**Purpose**: Track latency trends over time for each target

```kql
NetResilience_CL
| where todatetime(LocalTime) > ago(1h)
| where Success == true
| summarize 
    AvgLatency = avg(LatencyMs), 
    P95Latency = percentile(LatencyMs, 95) 
  by bin(todatetime(LocalTime), 5m), Target
| render timechart
```

**Dashboard Settings:**
- **Chart Type**: Line chart
- **Title**: "Average Latency Over Time (by Target)"
- **Subtitle**: "Last 1 hour - 5 minute intervals"
- **Y-Axis**: Latency (ms)
- **Legend**: Split by Target

---

## 📊 Query 2: Failure Rate by Target (Grid)

**Visualization**: Grid  
**Time Range**: Last 1 hour  
**Purpose**: Identify problematic endpoints with high failure rates

```kql
NetResilience_CL
| where todatetime(LocalTime) > ago(1h)
| summarize 
    Total = count(),
    Failures = countif(Success == false),
    FailureRate = round(countif(Success == false) * 100.0 / count(), 2)
  by Target, Protocol
| order by FailureRate desc
```

**Dashboard Settings:**
- **Chart Type**: Grid/Table
- **Title**: "Failure Rates by Target (Last Hour)"
- **Subtitle**: "Sorted by failure rate"
- **Columns**: Target, Protocol, Total, Failures, FailureRate

---

## 🖥️ Query 3: Latency Statistics by VM (Grid)

**Visualization**: Grid  
**Time Range**: Last 1 hour  
**Purpose**: Compare performance characteristics across VM instances

```kql
NetResilience_CL
| where todatetime(LocalTime) > ago(1h)
| where Success == true
| summarize 
    AvgLatency = round(avg(LatencyMs), 2),
    MinLatency = min(LatencyMs),
    MaxLatency = max(LatencyMs),
    P50 = round(percentile(LatencyMs, 50), 2),
    P95 = round(percentile(LatencyMs, 95), 2),
    P99 = round(percentile(LatencyMs, 99), 2)
  by VmInstance, AzZone
| order by VmInstance asc
```

**Dashboard Settings:**
- **Chart Type**: Grid/Table
- **Title**: "Latency Statistics by VM Instance"
- **Subtitle**: "Min, Avg, Max, P50, P95, P99 (ms)"
- **Columns**: VmInstance, AzZone, AvgLatency, MinLatency, MaxLatency, P50, P95, P99

---

## 🌍 Query 4: Zone Comparison (Time Chart)

**Visualization**: Line Chart  
**Time Range**: Last 1 hour  
**Purpose**: Compare latency across availability zones

```kql
NetResilience_CL
| where todatetime(LocalTime) > ago(1h)
| summarize 
    AvgLatency = round(avg(LatencyMs), 2),
    FailureRate = round(countif(Success == false) * 100.0 / count(), 2),
    TestCount = count()
  by bin(todatetime(LocalTime), 10m), AzZone
| render timechart
```

**Dashboard Settings:**
- **Chart Type**: Line chart
- **Title**: "Average Latency by Availability Zone"
- **Subtitle**: "Compare performance across zones"
- **Y-Axis**: Latency (ms)
- **Legend**: Split by AzZone

---

## 🔄 Query 5: Protocol Breakdown (Donut Chart)

**Visualization**: Donut Chart  
**Time Range**: Last 1 hour  
**Purpose**: Show distribution of test types

```kql
NetResilience_CL
| where todatetime(LocalTime) > ago(1h)
| summarize 
    Tests = count(),
    AvgLatency = round(avg(LatencyMs), 2),
    SuccessRate = round(countif(Success == true) * 100.0 / count(), 2)
  by Protocol
```

**Dashboard Settings:**
- **Chart Type**: Donut chart
- **Title**: "Tests by Protocol"
- **Subtitle**: "ICMP vs HTTP distribution"
- **Legend**: Protocol names
- **Values**: Test count

---

## 🚨 Query 6: Recent Failures (Grid)

**Visualization**: Grid  
**Time Range**: Last 1 hour  
**Purpose**: Real-time troubleshooting of connectivity issues

```kql
NetResilience_CL
| where todatetime(LocalTime) > ago(1h)
| where Success == false
| project LocalTime, VmInstance, Target, Protocol, StatusCode, StatusName, Error
| order by todatetime(LocalTime) desc
| take 20
```

**Dashboard Settings:**
- **Chart Type**: Grid/Table
- **Title**: "Recent Failures (Last 20)"
- **Subtitle**: "Troubleshoot connectivity issues"
- **Columns**: LocalTime, VmInstance, Target, Protocol, StatusCode, StatusName, Error
- **Auto-refresh**: Enable (1 minute)

---

## ✅ Query 7: Success Rate by VM (Bar Chart)

**Visualization**: Bar Chart  
**Time Range**: Last 1 hour  
**Purpose**: Quick health overview of all VMs

```kql
NetResilience_CL
| where todatetime(LocalTime) > ago(1h)
| summarize 
    SuccessRate = round(countif(Success == true) * 100.0 / count(), 2),
    Total = count(),
    Failures = countif(Success == false)
  by VmInstance
| order by VmInstance asc
```

**Dashboard Settings:**
- **Chart Type**: Bar chart (horizontal)
- **Title**: "Success Rate by VM Instance (%)"
- **Subtitle**: "Health overview across all VMs"
- **X-Axis**: Success Rate (%)
- **Y-Axis**: VM Instance names

---

## 🛠️ How to Create the Dashboard

### Option 1: Manual Creation via Azure Portal

1. **Navigate to Dashboards**:
   - Azure Portal → Dashboards → + New dashboard
   - Name: "Network Resilience Monitoring"

2. **Add Tiles**:
   - Click "Edit" → "+ Add tile"
   - Select "Logs" tile type
   - Configure workspace: `law-net-resilience`
   - Paste query from above
   - Configure visualization settings
   - Set title and subtitle
   - Save tile

3. **Arrange Layout**:
   - Drag tiles to desired positions
   - Resize tiles (recommended: 6x4 for charts, 12x3 for grids)
   - Save dashboard

4. **Configure Auto-refresh**:
   - Dashboard settings → Auto-refresh: 5 minutes

### Option 2: Quick Dashboard from Log Analytics

1. **Navigate to Log Analytics Workspace**:
   - Azure Portal → Log Analytics workspaces → `law-net-resilience`

2. **Run Query and Pin**:
   - Click "Logs" in left menu
   - Paste one of the queries above
   - Click "Run"
   - Click "Pin to dashboard" icon
   - Select "New dashboard" or existing
   - Repeat for all 7 queries

3. **Edit and Arrange**:
   - Navigate to your dashboard
   - Click "Edit" to arrange tiles
   - Resize and position as needed
   - Save dashboard

---

## 🎨 Recommended Dashboard Layout

```
┌─────────────────────────────────────────────────────────┐
│  📊 Network Resilience Monitoring Dashboard (12 columns)│
├─────────────────────────┬───────────────────────────────┤
│                         │                               │
│  Latency Trend          │  Failure Rate by Target       │
│  (6 columns x 4 rows)   │  (6 columns x 4 rows)         │
│                         │                               │
├─────────────────────────┼───────────────────────────────┤
│                         │                               │
│  Latency Stats by VM    │  Zone Comparison              │
│  (6 columns x 4 rows)   │  (6 columns x 4 rows)         │
│                         │                               │
├─────────────┬───────────┴───────────────────────────────┤
│  Protocol   │                                           │
│  Breakdown  │  Recent Failures                          │
│  (4 cols x  │  (8 columns x 3 rows)                     │
│   3 rows)   │                                           │
├─────────────┴───────────────────────────────────────────┤
│                                                         │
│  Success Rate by VM Instance                            │
│  (12 columns x 3 rows)                                  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🔍 Advanced Filtering

### Filter by Specific VM

Add to any query:
```kql
| where VmInstance == "vmnetres1"
```

### Filter by Target

Add to any query:
```kql
| where Target contains "google.com"
```

### Extend Time Range

Change time range:
```kql
| where todatetime(LocalTime) > ago(24h)  // Last 24 hours
| where todatetime(LocalTime) > ago(7d)   // Last 7 days
```

### Filter by Success/Failure

```kql
| where Success == false  // Only failures
| where Success == true   // Only successful tests
```

---

## 📌 Best Practices

1. **Time Range**: Start with 1 hour for real-time monitoring, extend to 24h for trends
2. **Auto-refresh**: Set to 5 minutes for near real-time updates
3. **Tile Sizing**: Use consistent sizes for better visual appeal
4. **Color Coding**: Configure thresholds (e.g., latency > 100ms = yellow, > 500ms = red)
5. **Alerts**: Create alert rules for critical thresholds directly from dashboard tiles

---

## 🚀 Next Steps

After creating the dashboard:

1. **Share Dashboard**: Share → Publish → Get sharing link
2. **Set as Default**: Mark as favorite or set as default dashboard
3. **Create Alerts**: Pin alert rules to dashboard for quick access
4. **Export Data**: Use "Export to Excel" from grid tiles for reports
5. **Mobile Access**: Access dashboard from Azure Mobile App

---

## 📚 Related Documentation

- [Azure Dashboards Documentation](https://learn.microsoft.com/en-us/azure/azure-portal/azure-portal-dashboards)
- [KQL Quick Reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/kql-quick-reference)
- [Log Analytics Tutorial](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-tutorial)

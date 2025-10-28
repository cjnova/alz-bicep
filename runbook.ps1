param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("start","stop","restart","status")]
    [string]$Action
)

$ResourceGroup = "slz-pro-zb1-ResiliencyTesting"
$VmNames = @("vmtest001","vmtest002","vmtest003")
$cred = Get-AutomationPSCredential -Name "VmLocalAdmin"

$inlineScript = @"
param([string]`$Action)
if (`$Action -eq "start") { sudo systemctl start onprem-tests.service }
elseif (`$Action -eq "stop") { sudo systemctl stop onprem-tests.service }
elseif (`$Action -eq "restart") { sudo systemctl restart onprem-tests.service }
elseif (`$Action -eq "status") { sudo systemctl status onprem-tests.service --no-pager -l }
"@

foreach ($vm in $VmNames) {
    Invoke-AzVMRunCommand `
        -ResourceGroupName $ResourceGroup `
        -Name $vm `
        -CommandId 'RunShellScript' `
        -ScriptString $inlineScript `
        -Parameters @{ "Action" = $Action } `
        -Credential $cred
}

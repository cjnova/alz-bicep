# Pester test structure for infoBlox resilience testing
Describe "Test infoBlox resilience" {
    BeforeAll {
        # Setup code for Describe block
        $InfoBlox1 = "ChaosStudio-VM"
        $InfoBlox2 = "ChaosStudio-VM"
        $rg = "exampleRG"
        $location = "swedencentral"
        $testDNSInternet = "www.bancosantander.es"
        $testDNSAzure = "www.bancosantander.es"
        $testDNSOnprem = "www.bancosantander.es"

        function Test-DnsResolution {
            param (
                [string]$DnsName
            )
        
            try {
                $result = Resolve-DnsName -Name $DnsName -ErrorAction Stop
                if ($result) {
                    return $true
                }
            } catch {
                return $false
            }
        }
    }
        Context "Validate Initial scenario" {
            
            BeforeAll {
                # Setup code for initial scenario validation
                $vmConfigInfBlox1 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox1
                $vmStatusInfBlox1 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox1 -Status
                $vmConfigInfBlox2 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox2
                $vmStatusInfBlox2 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox2 -Status
                $Infoblox1Array = $vmConfigInfBlox1.NetworkProfile[0].NetworkInterfaces.Id -split "/"
                $InfoBlox1 = Get-AzNetworkInterface -Name $Infoblox1Array[8] -ResourceGroup $Infoblox1Array[4]
                $Infoblox2Array = $vmConfigInfBlox1.NetworkProfile[0].NetworkInterfaces.Id -split "/"
                $InfoBlox2 = Get-AzNetworkInterface -Name $Infoblox1Array[8] -ResourceGroup $Infoblox1Array[4]
            }

            It "should check InfoBlox1 is online" {
                # Test code to check InfoBlox1 DNS server is online
                $vmStatusInfBlox1.Statuses[1].code -eq "PowerState/running" | Should -Be $true
            }

            It "should check InfoBlox2 is online" {
                # Test code to check InfoBlox2 DNS server is online
                $vmStatusInfBlox2.Statuses[1].code -eq "PowerState/running" | Should -Be $true
            }

            It "InfoBlox1 check deployment region is West Europe" {
                # Test code to check deployment region
                $vmConfigInfBlox1.Location | Should -Be $location
            }
            
            It "InfoBlox2 check deployment region is West Europe" {
                # Test code to check deployment region
                $vmConfigInfBlox2.Location | Should -Be $location
            }


            It "Check AZ are different for DNS Server VMs" {
                # Test code to check AZ is different for DNS Server VMs
                $vmConfigInfBlox1.Zones[0] -ne $vmConfigInfBlox2.Zones[0] | Should -Be $true
            }

            It "InfoBlox1 check static IP assignment" {
                # Test code to check static IP assignment for VM IP
                $InfoBlox1.IpConfigurations.PrivateIpAllocationMethod -eq "Static" | Should -Be $true
            }

            It "InfoBlox2 check static IP assignment" {
                # Test code to check static IP assignment for VM IP
                $InfoBlox2.IpConfigurations.PrivateIpAllocationMethod -eq "Static" | Should -Be $true
            }

            It "InfoBlox1 check accelerated networking enabled" {
                # Test code to check accelerated networking enabled
                $InfoBlox1.EnableAcceleratedNetworking | Should -Be $true
            }

            It "InfoBlox2 check accelerated networking enabled" {
                # Test code to check accelerated networking enabled
                $InfoBlox2.EnableAcceleratedNetworking | Should -Be $true
            }

            It "should check DNS resolution Internet" {
                # Test code to check DNS resolution Internet
                Test-DnsResolution -DnsName $testDNSInternet | Should -Be $true
            }

            It "should check DNS resolution Azure" {
                # Test code to check DNS resolution Azure
                Test-DnsResolution -DnsName $testDNSAzure | Should -Be $true
            }

            It "should check DNS resolution On-Prem" {
                # Test code to check DNS resolution On-Prem
                Test-DnsResolution -DnsName $testDNSOnprem | Should -Be $true
            }

            AfterAll {
                # Cleanup code for initial scenario validation
                Read-Host -Prompt "Press any key to continue..."
                Write-Host "Starting Experiment" -ForegroundColor Yellow
                Write-Host "Shutdown InfoBlox1" -ForegroundColor Yellow
                
            }
        }   

    Context "Execute Experiment and validate service availability" {
        BeforeAll {
            # Setup code for executing the experiment
            $shutdownVMStatus = Stop-AzVM -ResourceGroupName $rg -Name $InfoBlox1 -Force
            $vmStatusInfBlox1 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox1 -Status
            $vmStatusInfBlox2 = Get-AzVM -ResourceGroupName $rg -Name $Infoblox2 -Status
        }

        It "should check InfoBlox1 shutdown was sucessful" {
            # Test code to check InfoBlox1 DNS server is ooffline
            $shutdownVMStatus.Status -eq "Succeeded" | Should -Be $true
        }
        
        It "should check InfoBlox1 is offline" {
            # Test code to check InfoBlox1 DNS server is ooffline
            $vmStatusInfBlox1.Statuses[1].code -ne "PowerState/running" | Should -Be $true
        }

        It "should check DNS resolution Internet in contingency mode" {
            # Test code to check DNS resolution Internet
            Test-DnsResolution -DnsName $testDNSInternet | Should -Be $true
        }

        It "should check DNS resolution Azure in contingency mode" {
            # Test code to check DNS resolution Azure
            Test-DnsResolution -DnsName $testDNSAzure | Should -Be $true
        }

        It "should check DNS resolution On-Prem in contingency mode" {
            # Test code to check DNS resolution On-Prem
            Test-DnsResolution -DnsName $testDNSOnprem | Should -Be $true
        }

        It "should check we recovered from contingency mode" {
            # Test code to check contingency mode is recovered to normal state
            $startVMStatus = Start-AzVM -ResourceGroupName $rg -Name $InfoBlox1
            $startVMStatus.Status -eq "Succeeded" | Should -Be $true
        }

        AfterAll {
            # Cleanup code for executing the experiment
            Read-Host -Prompt "Press any key to continue..."
            Write-Host "Ending Experiment" -ForegroundColor Yellow
            Write-Host "Waiting for 60 seconds for VM to start" -ForegroundColor Yellow
            Start-Sleep -Seconds 60
        }
    }

    Context "Validate final scenario. Check DNS resolution after experiment in normal mode" {
        BeforeAll {
            # Setup code for final scenario validation
            $vmConfigInfBlox1 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox1
            $vmStatusInfBlox1 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox1 -Status
            $vmConfigInfBlox2 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox2
            $vmStatusInfBlox2 = Get-AzVM -ResourceGroupName $rg -Name $InfoBlox2 -Status
        }

        It "should check InfoBlox1 is online" {
            # Test code to check InfoBlox1 DNS server is online
            $vmStatusInfBlox1.Statuses[1].code -eq "PowerState/running" | Should -Be $true
        }

        It "should check InfoBlox2 is online" {
            # Test code to check InfoBlox2 DNS server is online
            $vmStatusInfBlox2.Statuses[1].code -eq "PowerState/running" | Should -Be $true
        }

        It "should check DNS resolution Internet" {
            # Test code to check DNS resolution Internet
            Test-DnsResolution -DnsName $testDNSInternet | Should -Be $true
        }

        It "should check DNS resolution Azure" {
            # Test code to check DNS resolution Azure
            Test-DnsResolution -DnsName $testDNSAzure | Should -Be $true
        }

        It "should check DNS resolution On-Prem" {
            # Test code to check DNS resolution On-Prem
            Test-DnsResolution -DnsName $testDNSOnprem | Should -Be $true
        }

        AfterAll {
            # Cleanup code for final scenario validation
            Write-Host "Santander LZ DNS resilience tests finished" -ForegroundColor Yellow
        }
    }
}

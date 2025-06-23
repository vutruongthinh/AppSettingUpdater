# AppSettingUpdater.Tests.ps1
$ModulePath = "$PSScriptRoot\..\AppSettingUpdater.psd1"
Write-Host $ModulePath
Import-Module -Name $ModulePath -Force

Describe "AppSettingUpdater Module Tests" {

    BeforeAll {
        # Create mocks for Azure commands at module level
        Mock Get-Module { @{ Name = 'Az.Websites' } } -ModuleName AppSettingUpdater
        Mock Get-AzContext { @{ Context = 'FakeContext' } } -ModuleName AppSettingUpdater
        Mock Get-AzWebAppSlot {
            [PSCustomObject]@{
                SiteConfig = [PSCustomObject]@{
                    AppSettings = @(
                        [PSCustomObject]@{ Name = "MY_SETTING"; Value = "oldValue" }
                    )
                }
            }
        } -ModuleName AppSettingUpdater
        Mock Set-AzWebAppSlot { 
            # Mock successful update - return void like the real cmdlet
        } -ModuleName AppSettingUpdater
        Mock Switch-AzWebAppSlot { 
            # Mock successful swap operation - return void like the real cmdlet
        } -ModuleName AppSettingUpdater
    }

    Describe "Test-WebAppContext" {
        It "Should not throw if module and context exist" {
            { Test-WebAppContext } | Should -Not -Throw
        }

        It "Should throw when Az.Websites module is not available" {
            Mock Get-Module { $null } -ModuleName AppSettingUpdater
            { Test-WebAppContext } | Should -Throw "*Az.Websites module is not installed*"
        }

        It "Should throw when not logged into Azure" {
            Mock Get-AzContext { $null } -ModuleName AppSettingUpdater
            { Test-WebAppContext } | Should -Throw "*You are not logged in*"
        }
    }

    Describe "Get-WebAppSlotTarget" {
        BeforeAll {
            Mock Get-AzWebAppSlot {
                [PSCustomObject]@{
                    Name = "TestApp"
                }
            } -ModuleName AppSettingUpdater
        }

        It "Should return web app and slot info for valid slots" {
            $result = Get-WebAppSlotTarget -WebAppNames @('TestApp') -ResourceGroup 'TestRG' -Slot 'staging'
            $result.WebApp | Should -Be 'TestApp'
            $result.Slot | Should -Be 'staging'
            Should -Invoke Get-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater
        }

        It "Should handle multiple web apps" {
            Get-WebAppSlotTarget -WebAppNames @('App1', 'App2') -ResourceGroup 'TestRG' -Slot 'staging'
            Should -Invoke Get-AzWebAppSlot -Exactly 2 -ModuleName AppSettingUpdater
        }

        It "Should write warning when slot is not found" {
            Mock Get-AzWebAppSlot { throw "Slot not found" } -ModuleName AppSettingUpdater
            Mock Write-Warning -ModuleName AppSettingUpdater
            
            Get-WebAppSlotTarget -WebAppNames @('TestApp') -ResourceGroup 'TestRG' -Slot 'staging'
            Should -Invoke Write-Warning -Exactly 1 -ModuleName AppSettingUpdater
        }
    }

    Describe "Set-WebAppSlotAppSetting" {
        Context "When setting already has the desired value" {
            It "Should return Updated = false" {
                Mock Get-AzWebAppSlot {
                    [PSCustomObject]@{
                        SiteConfig = [PSCustomObject]@{
                            AppSettings = @(
                                [PSCustomObject]@{ Name = "MY_SETTING"; Value = "newValue" }
                            )
                        }
                    }
                } -ModuleName AppSettingUpdater

                $result = Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'staging' -ResourceGroup 'TestRG' -SettingName 'MY_SETTING' -SettingValue 'newValue'
                $result.Updated | Should -BeFalse
                $result.Message | Should -Be 'No change'
            }
        }

        Context "When DryRun is enabled" {
            It "Should not call Set-AzWebAppSlot" {
                $result = Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'staging' -ResourceGroup 'TestRG' -SettingName 'MY_SETTING' -SettingValue 'newValue' -DryRun
                Should -Invoke Set-AzWebAppSlot -Exactly 0 -ModuleName AppSettingUpdater
                $result.Message | Should -Match 'DryRun'
            }
        }

        Context "When setting value differs" {
            It "Should update and return Updated = true" {
                $result = Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'staging' -ResourceGroup 'TestRG' -SettingName 'MY_SETTING' -SettingValue 'newValue'
                Should -Invoke Set-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater
                $result.Updated | Should -BeTrue
            }
        }

        Context "When an error occurs" {
            It "Should throw with descriptive error message" {
                Mock Get-AzWebAppSlot { throw "Access denied" } -ModuleName AppSettingUpdater
                
                { Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'staging' -ResourceGroup 'TestRG' -SettingName 'MY_SETTING' -SettingValue 'newValue' -ErrorAction SilentlyContinue } |
                    Should -Throw
            }
        }
    }

    Describe "Start-WebAppSlotSwapPreview" {
        It "Should call Switch-AzWebAppSlot with correct parameters" {
            Start-WebAppSlotSwapPreview -WebApp 'TestApp' -ResourceGroup 'TestRG'
            Should -Invoke Switch-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater -ParameterFilter {
                $Name -eq 'TestApp' -and 
                $ResourceGroupName -eq 'TestRG' -and 
                $SourceSlotName -eq 'staging' -and 
                $DestinationSlotName -eq 'production' -and 
                $SwapWithPreviewAction -eq 'ApplySlotConfig'
            }
        }

        It "Should accept custom source and destination slots" {
            Start-WebAppSlotSwapPreview -WebApp 'TestApp' -ResourceGroup 'TestRG' -SourceSlot 'qa' -DestinationSlot 'staging'
            Should -Invoke Switch-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater -ParameterFilter {
                $SourceSlotName -eq 'qa' -and $DestinationSlotName -eq 'staging'
            }
        }

        It "Should throw when swap initiation fails" {
            Mock Switch-AzWebAppSlot { throw "Swap failed" } -ModuleName AppSettingUpdater
            
            { Start-WebAppSlotSwapPreview -WebApp 'TestApp' -ResourceGroup 'TestRG' -ErrorAction SilentlyContinue } |
                Should -Throw "*Failed to initiate slot swap preview*"
        }
    }

    Describe "Complete-WebAppSlotSwap" {
        It "Should call Switch-AzWebAppSlot with CompleteSlotSwap action" {
            Complete-WebAppSlotSwap -WebApp 'TestApp' -ResourceGroup 'TestRG'
            Should -Invoke Switch-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater -ParameterFilter {
                $Name -eq 'TestApp' -and 
                $ResourceGroupName -eq 'TestRG' -and 
                $SourceSlotName -eq 'staging' -and 
                $SwapWithPreviewAction -eq 'CompleteSlotSwap'
            }
        }

        It "Should accept custom source slot" {
            Complete-WebAppSlotSwap -WebApp 'TestApp' -ResourceGroup 'TestRG' -SourceSlot 'qa'
            Should -Invoke Switch-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater -ParameterFilter {
                $SourceSlotName -eq 'qa'
            }
        }

        It "Should throw when completion fails" {
            Mock Switch-AzWebAppSlot { throw "Complete failed" } -ModuleName AppSettingUpdater
            
            { Complete-WebAppSlotSwap -WebApp 'TestApp' -ResourceGroup 'TestRG' -ErrorAction SilentlyContinue } |
                Should -Throw "*Failed to complete slot swap*"
        }
    }

    Describe "Undo-WebAppSlotSwap" {
        It "Should call Switch-AzWebAppSlot with ResetSlotSwap action" {
            Undo-WebAppSlotSwap -WebApp 'TestApp' -ResourceGroup 'TestRG'
            Should -Invoke Switch-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater -ParameterFilter {
                $Name -eq 'TestApp' -and 
                $ResourceGroupName -eq 'TestRG' -and 
                $SourceSlotName -eq 'staging' -and 
                $SwapWithPreviewAction -eq 'ResetSlotSwap'
            }
        }

        It "Should accept custom source slot" {
            Undo-WebAppSlotSwap -WebApp 'TestApp' -ResourceGroup 'TestRG' -SourceSlot 'qa'
            Should -Invoke Switch-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater -ParameterFilter {
                $SourceSlotName -eq 'qa'
            }
        }

        It "Should throw when cancellation fails" {
            Mock Switch-AzWebAppSlot { throw "Cancel failed" } -ModuleName AppSettingUpdater
            
            { Undo-WebAppSlotSwap -WebApp 'TestApp' -ResourceGroup 'TestRG' -ErrorAction SilentlyContinue } |
                Should -Throw "*Failed to cancel slot swap*"
        }
    }

    # Additional edge case tests for enhanced coverage
    Describe "Parameter Validation Tests" {
        It "Should validate slot parameter values in Set-WebAppSlotAppSetting" {
            { Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'invalid' -ResourceGroup 'TestRG' -SettingName 'TEST' -SettingValue 'value' } |
                Should -Throw "*ValidateSet*"
        }

        It "Should validate empty SettingName in Set-WebAppSlotAppSetting" {
            { Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'staging' -ResourceGroup 'TestRG' -SettingName '' -SettingValue 'value' } |
                Should -Throw "*argument is null or empty*"
        }

        It "Should validate slot parameter in Start-WebAppSlotSwapPreview" {
            { Start-WebAppSlotSwapPreview -WebApp 'TestApp' -ResourceGroup 'TestRG' -SourceSlot 'invalid' } |
                Should -Throw "*ValidateSet*"
        }
    }

    Describe "Integration Scenarios" {
        It "Should handle app settings with special characters" {
            Mock Get-AzWebAppSlot {
                [PSCustomObject]@{
                    SiteConfig = [PSCustomObject]@{
                        AppSettings = @(
                            [PSCustomObject]@{ Name = "SPECIAL_SETTING"; Value = "old=value&with=chars" }
                        )
                    }
                }
            } -ModuleName AppSettingUpdater

            $result = Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'staging' -ResourceGroup 'TestRG' -SettingName 'SPECIAL_SETTING' -SettingValue 'new=value&with=special#chars'
            $result.Updated | Should -BeTrue
            Should -Invoke Set-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater
        }

        It "Should handle empty app settings collection" {
            Mock Get-AzWebAppSlot {
                [PSCustomObject]@{
                    SiteConfig = [PSCustomObject]@{
                        AppSettings = @()
                    }
                }
            } -ModuleName AppSettingUpdater

            $result = Set-WebAppSlotAppSetting -WebApp 'TestApp' -Slot 'staging' -ResourceGroup 'TestRG' -SettingName 'NEW_SETTING' -SettingValue 'newValue'
            $result.Updated | Should -BeTrue
            Should -Invoke Set-AzWebAppSlot -Exactly 1 -ModuleName AppSettingUpdater
        }

        It "Should handle null app settings in Get-WebAppSlotTarget" {
            Mock Get-AzWebAppSlot { $null } -ModuleName AppSettingUpdater
            Mock Write-Warning -ModuleName AppSettingUpdater
            
            $result = Get-WebAppSlotTarget -WebAppNames @('TestApp') -ResourceGroup 'TestRG' -Slot 'staging'
            $result | Should -BeNullOrEmpty
        }
    }
}

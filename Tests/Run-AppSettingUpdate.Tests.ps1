# Run-AppSettingUpdate.Tests.ps1
# Test file specifically for the Run-AppSettingUpdate.ps1 runbook

$RunbookPath = "$PSScriptRoot\..\Run-AppSettingUpdate.ps1"
$ModulePath = "$PSScriptRoot\..\AppSettingUpdater.psd1"

Describe "Run-AppSettingUpdate Runbook Tests" {

    BeforeAll {
        # Import the module to make functions available for mocking
        Import-Module -Name $ModulePath -Force
        
        # Mock all Azure-related functions to avoid authentication requirements
        Mock Test-WebAppContext { } -ModuleName AppSettingUpdater
        Mock Get-WebAppSlotTarget { 
            [PSCustomObject]@{
                WebApp = $WebApp
                Slot = $Slot
            }
        } -ModuleName AppSettingUpdater
        Mock Set-WebAppSlotAppSetting { 
            [PSCustomObject]@{
                Updated = $true
                Message = "Setting updated successfully"
            }
        } -ModuleName AppSettingUpdater        Mock Start-WebAppSlotSwapPreview { } -ModuleName AppSettingUpdater
        Mock Complete-WebAppSlotSwap { } -ModuleName AppSettingUpdater
        Mock Undo-WebAppSlotSwap { } -ModuleName AppSettingUpdater
    }

    Describe "Parameter Validation" {
        It "Should accept valid parameters" {
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -DryRun } | Should -Not -Throw
        }

        It "Should validate slot parameter" {
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -Slot "invalid" -DryRun } | Should -Throw
        }

        It "Should require WebApp parameter" {
            { . $RunbookPath -ResourceGroup "TestRG" -DryRun } | Should -Throw
        }        It "Should require ResourceGroup parameter" {
            { . $RunbookPath -WebApp "TestApp" -DryRun } | Should -Throw
        }
    }

    Describe "Dry Run Mode" {
        It "Should complete successfully in dry run mode with single app" {
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -SettingName "TEST_SETTING" -SettingValue "test_value" -DryRun } | Should -Not -Throw
        }

        It "Should complete successfully in dry run mode with multiple apps" {
            { . $RunbookPath -WebApp @("App1", "App2", "App3") -ResourceGroup "TestRG" -SettingName "TEST_SETTING" -SettingValue "test_value" -DryRun -Force } | Should -Not -Throw
        }

        It "Should handle MaxParallelJobs parameter" {
            { . $RunbookPath -WebApp @("App1", "App2") -ResourceGroup "TestRG" -MaxParallelJobs 2 -DryRun -Force } | Should -Not -Throw
        }    }

    Describe "Error Handling" {
        It "Should handle module import failures gracefully" {
            # This test verifies the runbook can handle missing module scenarios
            Mock Import-Module { throw "Module not found" }
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -DryRun } | Should -Throw
        }    }

    Describe "Logging and Output" {
        It "Should produce proper log output" {
            $output = . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -DryRun 2>&1
            $output | Should -Match "Starting Azure Web App Deployment Workflow"
            $output | Should -Match "DRY RUN MODE"
            $output | Should -Match "DEPLOYMENT SUMMARY"
        }

        It "Should log parallel job execution" {
            $output = . $RunbookPath -WebApp @("App1", "App2") -ResourceGroup "TestRG" -DryRun -Force 2>&1
            $output | Should -Match "Starting parallel deployment jobs"
            $output | Should -Match "Max Parallel Jobs: 5"
        }    }

    Describe "Parallel Execution" {
        It "Should respect MaxParallelJobs limit" {
            $output = . $RunbookPath -WebApp @("App1", "App2", "App3", "App4", "App5", "App6") -ResourceGroup "TestRG" -MaxParallelJobs 3 -DryRun -Force 2>&1
            $output | Should -Match "Max Parallel Jobs: 3"
        }

        It "Should handle single app execution" {
            { . $RunbookPath -WebApp "SingleApp" -ResourceGroup "TestRG" -DryRun } | Should -Not -Throw
        }
    }

    Describe "Force Parameter" {        It "Should skip confirmation when Force is used" {
            { . $RunbookPath -WebApp @("App1", "App2") -ResourceGroup "TestRG" -Force -DryRun } | Should -Not -Throw
        }
    }

    Describe "Different Slot Configurations" {        It "Should work with staging slot" {
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -Slot "staging" -DryRun } | Should -Not -Throw
        }

        It "Should work with qa slot" {
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -Slot "qa" -DryRun } | Should -Not -Throw
        }

        It "Should work with testing slot" {
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -Slot "testing" -DryRun } | Should -Not -Throw
        }

        It "Should work with preprod slot" {
            { . $RunbookPath -WebApp "TestApp" -ResourceGroup "TestRG" -Slot "preprod" -DryRun } | Should -Not -Throw
        }
    }
}

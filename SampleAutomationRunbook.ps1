<#
.SYNOPSIS
    Azure Web App slot-based deployment template with settings update and production swap.

.DESCRIPTION
    This is a template runbook for Azure Web App settings automation that demonstrates:
    - Update app settings in non-production slots first
    - Slot swap with review and validation placeholders
    - Parallel execution across multiple Web Apps
    - Comprehensive logging and error handling
    - Dry-run capabilities for safe testing
    
    WORKFLOW:
    1. Update app settings in non-production slot (staging/qa/testing)
    2. Perform slot swap with preview
    3. Validation checkpoint (placeholder - assumes True for simplicity)
    4. Complete slot swap to production
    
    CUSTOMIZE THIS TEMPLATE:
    1. Modify the validation logic for your specific requirements
    2. Add custom health checks or business validation
    3. Customize error handling and rollback logic
    4. Add additional automation steps as needed

.PARAMETER WebApps
    Array of Azure Web App names to update settings for.

.PARAMETER ResourceGroup
    The Azure Resource Group containing the Web Apps.

.PARAMETER SettingName
    Name of the app setting to update across all Web Apps.

.PARAMETER SettingValue
    Value of the app setting to apply to all Web Apps.

.PARAMETER Slot
    Non-production slot for initial setting update (default: staging). Settings are updated here first, then swapped to production.

.PARAMETER DryRun
    If specified, shows what would be done without making actual changes.

.PARAMETER Force
    Skip confirmation prompts for production operations.

.PARAMETER MaxParallelJobs
    Maximum number of parallel jobs to run simultaneously (default: 5).

.EXAMPLE
    .\SampleAutomationRunbook.ps1 -WebApps "MyApp" -ResourceGroup "MyRG" -SettingName "API_VERSION" -SettingValue "v2.0" -DryRun
    
.EXAMPLE
    .\SampleAutomationRunbook.ps1 -WebApps @("App1", "App2", "App3") -ResourceGroup "MyRG" -SettingName "DATABASE_URL" -SettingValue "new-connection-string" -Slot "staging"

.EXAMPLE
    .\SampleAutomationRunbook.ps1 -WebApps @("App1", "App2") -ResourceGroup "MyRG" -SettingName "FEATURE_FLAG" -SettingValue "enabled" -MaxParallelJobs 3 -Force

.NOTES
    Author: Thinh Vu
    Version: 1.0.0
    Template Purpose: Demonstrates Azure Web App settings automation patterns
    Requires: Az.Websites module, AppSettingUpdater module
    
    TEMPLATE USAGE:
    - This template focuses on safe slot-based deployments
    - Settings are updated in non-production slots first
    - Slot swaps include validation checkpoints
    - Customize validation logic for your specific needs
    - Test thoroughly with -DryRun before production use
#>

# ====================================================================
# AZURE WEB APP SLOT-BASED DEPLOYMENT AUTOMATION TEMPLATE
# ====================================================================
# 
# This template demonstrates safe slot-based deployments with:
# - App settings updates in non-production slots first
# - Slot swap with preview and validation checkpoints
# - Parallel processing across multiple Web Apps
# - Comprehensive error handling and logging
# - Dry-run capabilities for safe testing
#
# DEPLOYMENT WORKFLOW:
# 1. Update app settings in non-production slot (staging/qa/testing)
# 2. Initiate slot swap with preview
# 3. Validation checkpoint (placeholder for custom validation)
# 4. Complete slot swap to production
#
# HOW TO USE THIS TEMPLATE:
# 1. Copy this file to create your own Web App deployment runbook
# 2. Search for "CUSTOMIZE" comments and replace with your logic
# 3. Add your specific validation and health check steps
# 4. Modify parameters for your specific Web App requirements
# 5. Test thoroughly with -DryRun before production use
#
# TEMPLATE FEATURES DEMONSTRATED:
# - Safe slot-based deployment pattern
# - AppSettingUpdater module integration
# - Professional logging and progress tracking
# - Validation checkpoints with rollback capability
# ====================================================================

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Azure Web App names to update")]
    [ValidateNotNullOrEmpty()]
    [string[]]$WebApps,

    [Parameter(Mandatory = $true, HelpMessage = "Azure Resource Group name")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true, HelpMessage = "App setting name to update")]
    [ValidateNotNullOrEmpty()]
    [string]$SettingName,

    [Parameter(Mandatory = $true, HelpMessage = "App setting value to apply")]
    [string]$SettingValue,

    [Parameter(HelpMessage = "Non-production slot for initial setting update")]
    [ValidateSet("staging", "testing", "qa", "preprod")]
    [string]$Slot = 'staging',

    [Parameter(HelpMessage = "Maximum number of parallel jobs")]
    [ValidateRange(1, 10)]
    [int]$MaxParallelJobs = 5,

    [Parameter(HelpMessage = "Show what would be done without making changes")]
    [switch]$DryRun,

    [Parameter(HelpMessage = "Skip confirmation prompts")]
    [switch]$Force
)

# Import required modules and set up logging
# CUSTOMIZE: Add additional module imports if needed for your automation
Import-Module "$PSScriptRoot\AppSettingUpdater.psd1" -Force

# Enhanced logging function - TEMPLATE: Reusable across Web App automation scripts
function Write-WebAppLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Level) {
        "Info"    { "[INFO]" }
        "Warning" { "[WARN]" }
        "Error"   { "[ERROR]" }
        "Success" { "[SUCCESS]" }
    }
    
    $logMessage = "$timestamp $prefix $Message"
    
    switch ($Level) {
        "Info"    { Write-Host $logMessage -ForegroundColor Cyan }
        "Warning" { Write-Warning $logMessage }
        "Error"   { Write-Error $logMessage }
        "Success" { Write-Host $logMessage -ForegroundColor Green }
    }
}

# TEMPLATE: Customize this script block for slot-based deployment automation
$WebAppDeploymentScript = {
    param(
        [string]$WebAppName,
        [string]$ResourceGroup,
        [string]$SettingName,
        [string]$SettingValue,
        [string]$Slot,
        [bool]$DryRun,
        [string]$ModulePath
    )
    
    # Import the module in the job context
    Import-Module $ModulePath -Force
    
    # Job-specific logging function
    function Write-JobLog {
        param([string]$Message, [string]$Level = "Info")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $prefix = "[$Level] [$WebAppName]"
        Write-Output "$timestamp $prefix $Message"
    }
    
    try {
        Write-JobLog "Starting slot-based deployment for $WebAppName"
        
        # Step 1: Validate Azure context and prerequisites
        Write-JobLog "Validating Azure context and prerequisites..."
        Test-WebAppContext
        Write-JobLog "Azure context validation successful" "Success"

        # Step 2: Validate target Web App and non-production slot exists
        Write-JobLog "Validating Web App '$WebAppName' and non-production slot '$Slot'..."
        $slotTarget = Get-WebAppSlotTarget -WebAppNames @($WebAppName) -ResourceGroup $ResourceGroup -Slot $Slot
        if (-not $slotTarget) {
            throw "Non-production slot '$Slot' not found in Web App '$WebAppName'. Please create the slot first."
        }
        Write-JobLog "Web App and slot validation successful" "Success"

        # Step 3: Update app setting in non-production slot
        Write-JobLog "Phase 1: Updating app setting '$SettingName' in non-production slot '$Slot'..."
        if ($DryRun) {
            Write-JobLog "Dry run mode - would update: $SettingName = $SettingValue in slot '$Slot'" "Info"
            Write-JobLog "Dry run mode - would perform slot swap with preview" "Info"
            Write-JobLog "Dry run mode - would validate deployment" "Info"
            Write-JobLog "Dry run mode - would complete slot swap to production" "Info"
            return @{
                WebApp = $WebAppName
                Success = $true
                Message = "Dry run completed successfully - slot-based deployment simulated"
                DryRun = $true
            }
        }

        # Update the app setting in the non-production slot
        $settingResult = Set-WebAppSlotAppSetting -WebApp $WebAppName -Slot $Slot -ResourceGroup $ResourceGroup -SettingName $SettingName -SettingValue $SettingValue
        
        if ($settingResult.Updated) {
            Write-JobLog "App setting updated successfully in slot '$Slot'" "Success"
        } else {
            Write-JobLog "App setting unchanged in slot '$Slot': $($settingResult.Message)" "Info"
        }

        # Step 4: Initiate slot swap with preview
        Write-JobLog "Phase 2: Initiating slot swap with preview from '$Slot' to production..."
        $swapResult = Start-WebAppSlotSwapPreview -WebApp $WebAppName -ResourceGroup $ResourceGroup -SourceSlot $Slot -TargetSlot "production"
        
        if ($swapResult.SwapInitiated) {
            Write-JobLog "Slot swap preview initiated successfully" "Success"
        } else {
            throw "Failed to initiate slot swap preview: $($swapResult.Message)"
        }

        # Step 5: Validation checkpoint (CUSTOMIZE: Add your validation logic here)
        Write-JobLog "Phase 3: Performing deployment validation..."
        
        # CUSTOMIZE: Replace this placeholder with your actual validation logic
        # Examples:
        # - HTTP health checks to the staged production URL
        # - Database connectivity tests
        # - API functionality validation
        # - Performance benchmarks
        
        Start-Sleep -Seconds 5  # Simulate validation time
        $validationPassed = $true  # Placeholder - assumes validation passes
        
        if ($validationPassed) {
            Write-JobLog "Deployment validation passed" "Success"
        } else {
            Write-JobLog "Deployment validation failed - initiating rollback" "Error"
            $rollbackResult = Undo-WebAppSlotSwap -WebApp $WebAppName -ResourceGroup $ResourceGroup
            if ($rollbackResult.SwapUndone) {
                Write-JobLog "Rollback completed successfully" "Warning"
            }
            throw "Deployment validation failed and rollback completed"
        }

        # Step 6: Complete slot swap to production
        Write-JobLog "Phase 4: Completing slot swap to production..."
        $completeResult = Complete-WebAppSlotSwap -WebApp $WebAppName -ResourceGroup $ResourceGroup
        
        if ($completeResult.SwapCompleted) {
            Write-JobLog "Slot swap to production completed successfully" "Success"
        } else {
            throw "Failed to complete slot swap: $($completeResult.Message)"
        }

        # Step 7: Post-deployment verification (CUSTOMIZE: Add your post-deployment steps)
        Write-JobLog "Phase 5: Performing post-deployment verification..."
        # CUSTOMIZE: Add your specific post-deployment verification here
        # Examples:
        # - Verify production URL is responding correctly
        # - Check application logs for errors
        # - Send success notifications
        # - Update monitoring systems
        
        Write-JobLog "SLOT-BASED DEPLOYMENT SUCCESSFUL" "Success"
        
        return @{
            WebApp = $WebAppName
            Success = $true
            Message = "Slot-based deployment completed successfully: $Slot → production"
            DryRun = $false
        }

    } catch {
        Write-JobLog "SLOT-BASED DEPLOYMENT FAILED: $($_.Exception.Message)" "Error"
        
        # CUSTOMIZE: Add your specific error recovery logic here
        try {
            Write-JobLog "Attempting error recovery and cleanup..." "Warning"
            # Add your recovery logic here (e.g., rollback swap, revert settings, notifications)
            # Note: If swap was initiated but not completed, consider rolling back
            Write-JobLog "Error recovery completed" "Warning"
        } catch {
            Write-JobLog "Error recovery failed: $($_.Exception.Message)" "Error"
        }
        
        return @{
            WebApp = $WebAppName
            Success = $false
            Message = "Slot-based deployment failed: $($_.Exception.Message)"
            DryRun = $false
        }
    }
}

# Main slot-based deployment workflow - TEMPLATE: This pattern demonstrates safe production deployments
Write-WebAppLog "=== Starting Azure Web App Slot-Based Deployment Workflow ===" "Info"
Write-WebAppLog "Target Web Apps: $($WebApps -join ', ')" "Info"
Write-WebAppLog "ResourceGroup: $ResourceGroup | Non-Production Slot: $Slot" "Info"
Write-WebAppLog "Setting: $SettingName = $SettingValue" "Info"
Write-WebAppLog "Deployment Flow: Update $Slot → Swap Preview → Validate → Complete Swap → Production" "Info"
Write-WebAppLog "Max Parallel Jobs: $MaxParallelJobs" "Info"

if ($DryRun) {
    Write-WebAppLog "DRY RUN MODE - No actual changes will be made" "Warning"
}

# Confirmation for production impact when dealing with multiple Web Apps
if (-not $Force -and $WebApps.Count -gt 1 -and $PSCmdlet.ShouldProcess("$($WebApps.Count) Web Apps slot-based deployment", "Process")) {
    $confirmation = Read-Host "Do you want to proceed with slot-based deployment for $($WebApps.Count) Web Apps? This will deploy to PRODUCTION. (y/N)"
    if ($confirmation -notmatch '^[Yy]') {
        Write-WebAppLog "Operation cancelled by user" "Warning"
        return
    }
}

try {
    # Get the full path to the module for job execution
    $ModulePath = (Get-Module AppSettingUpdater).Path
    if (-not $ModulePath) {
        $ModulePath = "$PSScriptRoot\AppSettingUpdater.psd1"
    }
    
    Write-WebAppLog "Starting parallel slot-based deployment jobs..." "Info"
    
    # Initialize job tracking
    $jobs = @()
    $jobResults = @()
    $activeJobs = 0
    $completedWebApps = 0
    $totalWebApps = $WebApps.Count
    
    # Start jobs for each Web App with throttling
    foreach ($webApp in $WebApps) {
        # Wait if we've reached the maximum parallel jobs
        while ($activeJobs -ge $MaxParallelJobs) {
            Start-Sleep -Seconds 2
            
            # Check for completed jobs
            $completedJobs = $jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' -or $_.State -eq 'Stopped' }
            foreach ($completedJob in $completedJobs) {
                if ($completedJob.ProcessedResult -ne $true) {
                    $result = Receive-Job -Job $completedJob
                    $jobResults += $result
                    Remove-Job -Job $completedJob
                    $activeJobs--
                    $completedWebApps++
                    $completedJob.ProcessedResult = $true
                    
                    # Log progress
                    Write-WebAppLog "Job completed for $($result.WebApp): $($result.Message) [$completedWebApps/$totalWebApps]" $(if ($result.Success) { "Success" } else { "Warning" })
                }
            }
        }
        
        # Start new job for this Web App
        Write-WebAppLog "Starting deployment job for $webApp..." "Info"
        $job = Start-Job -ScriptBlock $WebAppDeploymentScript -ArgumentList @(
            $webApp,
            $ResourceGroup,
            $SettingName,
            $SettingValue,
            $Slot,
            $DryRun.IsPresent,
            $ModulePath
        )
        
        $job | Add-Member -NotePropertyName ProcessedResult -NotePropertyValue $false
        $jobs += $job
        $activeJobs++
        
        Write-WebAppLog "Job started for $webApp (Job ID: $($job.Id))" "Info"
    }
    
    # Wait for all remaining jobs to complete
    Write-WebAppLog "Waiting for all slot-based deployment jobs to complete..." "Info"
    
    while ($activeJobs -gt 0) {
        Start-Sleep -Seconds 5
        
        # Check for completed jobs
        $completedJobs = $jobs | Where-Object { 
            ($_.State -eq 'Completed' -or $_.State -eq 'Failed' -or $_.State -eq 'Stopped') -and 
            $_.ProcessedResult -ne $true 
        }
        
        foreach ($completedJob in $completedJobs) {
            $result = Receive-Job -Job $completedJob
            $jobResults += $result
            Remove-Job -Job $completedJob
            $activeJobs--
            $completedWebApps++
            $completedJob.ProcessedResult = $true
            
            # Log progress
            Write-WebAppLog "Job completed for $($result.WebApp): $($result.Message) [$completedWebApps/$totalWebApps]" $(if ($result.Success) { "Success" } else { "Warning" })
        }
        
        # Update progress
        if ($completedWebApps -lt $totalWebApps) {
            Write-WebAppLog "Progress: $completedWebApps/$totalWebApps jobs completed, $activeJobs active jobs remaining" "Info"
        }
    }
    
    # Analyze results
    Write-WebAppLog "=== SLOT-BASED DEPLOYMENT SUMMARY ===" "Info"
    $successfulOperations = $jobResults | Where-Object { $_.Success -eq $true }
    $failedOperations = $jobResults | Where-Object { $_.Success -eq $false }
    $dryRunResults = $jobResults | Where-Object { $_.DryRun -eq $true }
    
    if ($DryRun) {
        Write-WebAppLog "DRY RUN COMPLETED" "Success"
        Write-WebAppLog "Web Apps processed: $($dryRunResults.Count)" "Info"
    } else {
        Write-WebAppLog "Successful deployments: $($successfulOperations.Count)/$totalWebApps" "Success"
        Write-WebAppLog "Failed deployments: $($failedOperations.Count)/$totalWebApps" $(if ($failedOperations.Count -gt 0) { "Error" } else { "Info" })
        
        if ($successfulOperations.Count -gt 0) {
            Write-WebAppLog "Successfully deployed Web Apps: $($successfulOperations.WebApp -join ', ')" "Success"
        }
        
        if ($failedOperations.Count -gt 0) {
            Write-WebAppLog "Failed deployments: $($failedOperations.WebApp -join ', ')" "Error"
            foreach ($failure in $failedOperations) {
                Write-WebAppLog "  - $($failure.WebApp): $($failure.Message)" "Error"
            }
        }
    }
    
    # Exit with appropriate code
    if ($failedOperations.Count -gt 0 -and -not $DryRun) {
        Write-WebAppLog "=== SLOT-BASED DEPLOYMENT COMPLETED WITH FAILURES ===" "Warning"
        exit 1
    } else {
        Write-WebAppLog "=== SLOT-BASED DEPLOYMENT COMPLETED SUCCESSFULLY ===" "Success"
    }

} catch {
    Write-WebAppLog "=== SLOT-BASED DEPLOYMENT ORCHESTRATION FAILED ===" "Error"
    Write-WebAppLog "Error: $($_.Exception.Message)" "Error"
    Write-WebAppLog "StackTrace: $($_.ScriptStackTrace)" "Error"
    
    # Clean up any running jobs
    Write-WebAppLog "Cleaning up running jobs..." "Warning"
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job
    Get-Job | Remove-Job -Force
    
    exit 1
} finally {
    # Ensure all jobs are cleaned up
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    Write-WebAppLog "=== Slot-based deployment workflow completed ===" "Info"
}

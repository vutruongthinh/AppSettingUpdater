<#
.SYNOPSIS
    Automated Azure Web App deployment runbook with app setting updates and slot swapping.

.DESCRIPTION
    This runbook can be used both manually (interactive validation) and automatically.
    Refer to RUNBOOK-EXAMPLES.md for detailed usage examples.
    The runbook performs a complete deployment workflow:
    1. Updates app settings in the specified slot
    2. Initiates slot swap with preview
    3. Performs validation checks
    4. Completes or rolls back the swap based on validation results

.PARAMETER WebApp
    The name(s) of the Azure Web App(s) to deploy to. Supports single app or array of multiple apps.

.PARAMETER ResourceGroup
    The Azure Resource Group containing the Web App(s).

.PARAMETER Slot
    The source slot for deployment. Must be one of: staging, testing, qa, preprod.

.PARAMETER SettingName
    The name of the app setting to update.

.PARAMETER SettingValue
    The new value for the app setting.

.PARAMETER ValidationUrl
    Optional URL to test after swap preview for validation.

.PARAMETER ValidationTimeoutSeconds
    Maximum time to wait for validation checks (default: 300 seconds).

.PARAMETER DryRun
    If specified, shows what would be done without making actual changes.

.PARAMETER Force
    Skip confirmation prompts for production deployments.

.PARAMETER MaxParallelJobs
    Maximum number of parallel deployment jobs to run simultaneously (default: 5).

.PARAMETER JobTimeoutMinutes
    Maximum time to wait for each deployment job to complete (default: 30 minutes).

.EXAMPLE
    .\Run-AppSettingUpdate.ps1 -WebApp "MyApp" -ResourceGroup "MyRG" -SettingName "API_VERSION" -SettingValue "v2.0"
    
.EXAMPLE
    .\Run-AppSettingUpdate.ps1 -WebApp @("App1", "App2", "App3") -ResourceGroup "MyRG" -SettingName "VERSION" -SettingValue "2.0" -MaxParallelJobs 3
    
.EXAMPLE
    .\Run-AppSettingUpdate.ps1 -WebApp "MyApp" -ResourceGroup "MyRG" -Slot "qa" -DryRun

.NOTES
    Author: Thinh Vu
    Version: 2.0.0
    Requires: Az.Websites module, AppSettingUpdater module
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Azure Web App name(s)")]
    [ValidateNotNullOrEmpty()]
    [string[]]$WebApp,

    [Parameter(Mandatory = $true, HelpMessage = "Azure Resource Group name")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,

    [Parameter(HelpMessage = "Source slot for deployment")]
    [ValidateSet("staging", "testing", "qa", "preprod")]
    [string]$Slot = 'staging',

    [Parameter(HelpMessage = "App setting name to update")]
    [ValidateNotNullOrEmpty()]
    [string]$SettingName = 'MY_SETTING',

    [Parameter(HelpMessage = "New value for the app setting")]
    [string]$SettingValue = 'newValue',

    [Parameter(HelpMessage = "URL to validate after swap preview for validation")]
    [ValidateScript({
        if ($_ -and -not ([System.Uri]::IsWellFormedUriString($_, [System.UriKind]::Absolute))) {
            throw "ValidationUrl must be a valid absolute URL"
        }
        return $true
    })]
    [string]$ValidationUrl,

    [Parameter(HelpMessage = "Maximum validation timeout in seconds")]
    [ValidateRange(30, 1800)]
    [int]$ValidationTimeoutSeconds = 300,

    [Parameter(HelpMessage = "Maximum number of parallel deployment jobs")]
    [ValidateRange(1, 10)]
    [int]$MaxParallelJobs = 5,

    [Parameter(HelpMessage = "Maximum time to wait for each job to complete (minutes)")]
    [ValidateRange(5, 120)]
    [int]$JobTimeoutMinutes = 30,

    [Parameter(HelpMessage = "Show what would be done without making changes")]
    [switch]$DryRun,

    [Parameter(HelpMessage = "Skip confirmation prompts")]
    [switch]$Force
)

# Import required modules and set up logging
Import-Module "$PSScriptRoot\AppSettingUpdater.psd1" -Force

# Enhanced logging function
function Write-DeploymentLog {
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

# Enhanced validation function
function Test-DeploymentValidation {
    param(
        [string]$ValidationUrl,
        [int]$TimeoutSeconds = 300,
        [string]$WebAppName = "Unknown"
    )
    
    if (-not $ValidationUrl) {
        Write-DeploymentLog "No validation URL provided for $WebAppName. Skipping automated validation." "Warning"
        return $true
    }
    
    Write-DeploymentLog "Starting validation checks for $WebAppName against: $ValidationUrl"
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $maxRetries = 10
    $retryCount = 0
    
    do {
        try {
            $response = Invoke-WebRequest -Uri $ValidationUrl -Method GET -TimeoutSec 30 -UseBasicParsing
            
            if ($response.StatusCode -eq 200) {
                Write-DeploymentLog "Validation successful for $WebAppName - HTTP $($response.StatusCode)" "Success"
                return $true
            } else {
                Write-DeploymentLog "Validation for $WebAppName returned HTTP $($response.StatusCode)" "Warning"
            }
        } catch {
            Write-DeploymentLog "Validation attempt $($retryCount + 1) failed for $WebAppName`: $($_.Exception.Message)" "Warning"
        }
        
        $retryCount++
        if ($retryCount -lt $maxRetries -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            Write-DeploymentLog "Retrying validation for $WebAppName in 30 seconds... ($retryCount/$maxRetries)"
            Start-Sleep -Seconds 30
        }
        
    } while ($retryCount -lt $maxRetries -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    
    Write-DeploymentLog "Validation failed for $WebAppName after $retryCount attempts in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds" "Error"
    return $false
}

# Deployment job script block for parallel execution
$DeploymentJobScript = {
    param(
        [string]$WebAppName,
        [string]$ResourceGroup,
        [string]$Slot,
        [string]$SettingName,
        [string]$SettingValue,
        [string]$ValidationUrl,
        [int]$ValidationTimeoutSeconds,
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
        Write-JobLog "Starting deployment job for $WebAppName"
        
        # Step 1: Validate Azure context and prerequisites
        Write-JobLog "Validating Azure context and prerequisites..."
        Test-WebAppContext
        Write-JobLog "Azure context validation successful" "Success"

        # Step 2: Validate target slot exists
        Write-JobLog "Validating target slot exists..."
        $slotTargets = Get-WebAppSlotTarget -WebAppNames @($WebAppName) -ResourceGroup $ResourceGroup -Slot $Slot
        if (-not $slotTargets) {
            throw "Slot '$Slot' not found in Web App '$WebAppName'"
        }
        Write-JobLog "Target slot validation successful" "Success"

        # Step 3: Update app setting
        Write-JobLog "Updating app setting '$SettingName' in slot '$Slot'..."
        $settingResult = Set-WebAppSlotAppSetting -WebApp $WebAppName -Slot $Slot -ResourceGroup $ResourceGroup -SettingName $SettingName -SettingValue $SettingValue -DryRun:$DryRun

        if ($DryRun) {
            Write-JobLog "Dry run complete. No changes were applied." "Info"
            Write-JobLog "Would have updated: $($settingResult.Message)" "Info"
            return @{
                WebApp = $WebAppName
                Success = $true
                Message = "Dry run completed successfully"
                DryRun = $true
            }
        }

        if ($settingResult.Updated) {
            Write-JobLog "App setting updated successfully" "Success"
        } else {
            Write-JobLog "App setting unchanged: $($settingResult.Message)" "Info"
        }

        # Step 4: Initiate swap with preview
        Write-JobLog "Initiating slot swap with preview from '$Slot' to production..."
        Start-WebAppSlotSwapPreview -WebApp $WebAppName -ResourceGroup $ResourceGroup -SourceSlot $Slot
        Write-JobLog "Swap with preview initiated successfully" "Success"

        # Step 5: Validation phase
        Write-JobLog "Performing deployment validation..."
        $validationPassed = $true
        if ($ValidationUrl) {
            # Build validation URL for this specific app if it's a template
            $appValidationUrl = $ValidationUrl -replace '\{WebApp\}', $WebAppName
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $maxRetries = 10
            $retryCount = 0
            
            do {
                try {
                    $response = Invoke-WebRequest -Uri $appValidationUrl -Method GET -TimeoutSec 30 -UseBasicParsing
                    
                    if ($response.StatusCode -eq 200) {
                        Write-JobLog "Validation successful - HTTP $($response.StatusCode)" "Success"
                        $validationPassed = $true
                        break
                    } else {
                        Write-JobLog "Validation returned HTTP $($response.StatusCode)" "Warning"
                    }
                } catch {
                    Write-JobLog "Validation attempt $($retryCount + 1) failed: $($_.Exception.Message)" "Warning"
                }
                
                $retryCount++
                if ($retryCount -lt $maxRetries -and $stopwatch.Elapsed.TotalSeconds -lt $ValidationTimeoutSeconds) {
                    Write-JobLog "Retrying in 30 seconds... ($retryCount/$maxRetries)"
                    Start-Sleep -Seconds 30
                }
                
            } while ($retryCount -lt $maxRetries -and $stopwatch.Elapsed.TotalSeconds -lt $ValidationTimeoutSeconds)
            
            if ($retryCount -ge $maxRetries -or $stopwatch.Elapsed.TotalSeconds -ge $ValidationTimeoutSeconds) {
                Write-JobLog "Validation failed after $retryCount attempts" "Error"
                $validationPassed = $false
            }
        } else {
            Write-JobLog "No validation URL provided. Skipping automated validation." "Warning"
        }

        # Step 6: Complete or rollback based on validation
        if ($validationPassed) {
            Write-JobLog "Validation passed. Completing slot swap..." "Success"
            Complete-WebAppSlotSwap -WebApp $WebAppName -ResourceGroup $ResourceGroup -SourceSlot $Slot
            Write-JobLog "DEPLOYMENT SUCCESSFUL" "Success"
            Write-JobLog "Application successfully deployed from '$Slot' to production" "Success"
            
            return @{
                WebApp = $WebAppName
                Success = $true
                Message = "Deployment completed successfully"
                DryRun = $false
            }
        } else {
            Write-JobLog "Validation failed. Rolling back slot swap..." "Error"
            Undo-WebAppSlotSwap -WebApp $WebAppName -ResourceGroup $ResourceGroup -SourceSlot $Slot
            Write-JobLog "DEPLOYMENT ROLLED BACK" "Warning"
            Write-JobLog "Slot swap has been cancelled due to validation failure" "Warning"
            
            return @{
                WebApp = $WebAppName
                Success = $false
                Message = "Deployment rolled back due to validation failure"
                DryRun = $false
            }
        }

    } catch {
        Write-JobLog "DEPLOYMENT FAILED: $($_.Exception.Message)" "Error"
        
        # Attempt emergency rollback if swap was initiated
        try {
            Write-JobLog "Attempting emergency rollback..." "Warning"
            Undo-WebAppSlotSwap -WebApp $WebAppName -ResourceGroup $ResourceGroup -SourceSlot $Slot -ErrorAction SilentlyContinue
            Write-JobLog "Emergency rollback completed" "Warning"
        } catch {
            Write-JobLog "Emergency rollback failed: $($_.Exception.Message)" "Error"
        }
        
        return @{
            WebApp = $WebAppName
            Success = $false
            Message = "Deployment failed: $($_.Exception.Message)"
            DryRun = $false
        }
    }
}

# Main deployment workflow
Write-DeploymentLog "=== Starting Azure Web App Deployment Workflow ===" "Info"
Write-DeploymentLog "Target Web Apps: $($WebApp -join ', ')" "Info"
Write-DeploymentLog "ResourceGroup: $ResourceGroup | Slot: $Slot" "Info"
Write-DeploymentLog "Setting: $SettingName = $SettingValue" "Info"
Write-DeploymentLog "Max Parallel Jobs: $MaxParallelJobs" "Info"

if ($DryRun) {
    Write-DeploymentLog "DRY RUN MODE - No actual changes will be made" "Warning"
}

# Confirmation for production impact when dealing with multiple apps
if (-not $Force -and $WebApp.Count -gt 1 -and $PSCmdlet.ShouldProcess("$($WebApp.Count) Web Apps slot swap from $Slot to production", "Initiate")) {
    $confirmation = Read-Host "Do you want to proceed with slot swap to production for $($WebApp.Count) Web Apps? (y/N)"
    if ($confirmation -notmatch '^[Yy]') {
        Write-DeploymentLog "Deployment cancelled by user" "Warning"
        return
    }
}

try {
    # Get the full path to the module for job execution
    $ModulePath = (Get-Module AppSettingUpdater).Path
    if (-not $ModulePath) {
        $ModulePath = "$PSScriptRoot\AppSettingUpdater.psd1"
    }
    
    Write-DeploymentLog "Starting parallel deployment jobs..." "Info"
    
    # Initialize job tracking
    $jobs = @()
    $jobResults = @()
    $activeJobs = 0
    $completedApps = 0
    $totalApps = $WebApp.Count
    
    # Start jobs for each web app with throttling
    foreach ($app in $WebApp) {
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
                    $completedApps++
                    $completedJob.ProcessedResult = $true
                    
                    # Log progress
                    Write-DeploymentLog "Job completed for $($result.WebApp): $($result.Message) [$completedApps/$totalApps]" $(if ($result.Success) { "Success" } else { "Warning" })
                }
            }
        }
        
        # Start new job for this web app
        Write-DeploymentLog "Starting deployment job for $app..." "Info"
        $job = Start-Job -ScriptBlock $DeploymentJobScript -ArgumentList @(
            $app,
            $ResourceGroup,
            $Slot,
            $SettingName,
            $SettingValue,
            $ValidationUrl,
            $ValidationTimeoutSeconds,
            $DryRun.IsPresent,
            $ModulePath
        )
        
        $job | Add-Member -NotePropertyName ProcessedResult -NotePropertyValue $false
        $jobs += $job
        $activeJobs++
        
        Write-DeploymentLog "Job started for $app (Job ID: $($job.Id))" "Info"
    }
    
    # Wait for all remaining jobs to complete with timeout
    Write-DeploymentLog "Waiting for all deployment jobs to complete..." "Info"
    $timeoutTime = (Get-Date).AddMinutes($JobTimeoutMinutes)
    
    while ($activeJobs -gt 0 -and (Get-Date) -lt $timeoutTime) {
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
            $completedApps++
            $completedJob.ProcessedResult = $true
            
            # Log progress
            Write-DeploymentLog "Job completed for $($result.WebApp): $($result.Message) [$completedApps/$totalApps]" $(if ($result.Success) { "Success" } else { "Warning" })
        }
        
        # Update progress
        if ($completedApps -lt $totalApps) {
            Write-DeploymentLog "Progress: $completedApps/$totalApps jobs completed, $activeJobs active jobs remaining" "Info"
        }
    }
    
    # Handle any jobs that didn't complete within timeout
    if ($activeJobs -gt 0) {
        Write-DeploymentLog "Timeout reached. Stopping $activeJobs remaining jobs..." "Warning"
        $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
        foreach ($job in $runningJobs) {
            Stop-Job -Job $job
            $result = @{
                WebApp = "Unknown"
                Success = $false
                Message = "Job timed out after $JobTimeoutMinutes minutes"
                DryRun = $false
            }
            $jobResults += $result
            Remove-Job -Job $job
        }
    }
    
    # Analyze results
    Write-DeploymentLog "=== DEPLOYMENT SUMMARY ===" "Info"
    $successfulDeployments = $jobResults | Where-Object { $_.Success -eq $true }
    $failedDeployments = $jobResults | Where-Object { $_.Success -eq $false }
    $dryRunResults = $jobResults | Where-Object { $_.DryRun -eq $true }
    
    if ($DryRun) {
        Write-DeploymentLog "DRY RUN COMPLETED" "Success"
        Write-DeploymentLog "Apps processed: $($dryRunResults.Count)" "Info"
    } else {
        Write-DeploymentLog "Successful deployments: $($successfulDeployments.Count)/$totalApps" "Success"
        Write-DeploymentLog "Failed deployments: $($failedDeployments.Count)/$totalApps" $(if ($failedDeployments.Count -gt 0) { "Error" } else { "Info" })
        
        if ($successfulDeployments.Count -gt 0) {
            Write-DeploymentLog "Successfully deployed apps: $($successfulDeployments.WebApp -join ', ')" "Success"
        }
        
        if ($failedDeployments.Count -gt 0) {
            Write-DeploymentLog "Failed deployments: $($failedDeployments.WebApp -join ', ')" "Error"
            foreach ($failure in $failedDeployments) {
                Write-DeploymentLog "  - $($failure.WebApp): $($failure.Message)" "Error"
            }
        }
    }
    
    # Exit with appropriate code
    if ($failedDeployments.Count -gt 0 -and -not $DryRun) {
        Write-DeploymentLog "=== DEPLOYMENT COMPLETED WITH FAILURES ===" "Warning"
        exit 1
    } else {
        Write-DeploymentLog "=== DEPLOYMENT COMPLETED SUCCESSFULLY ===" "Success"
    }

} catch {
    Write-DeploymentLog "=== DEPLOYMENT ORCHESTRATION FAILED ===" "Error"
    Write-DeploymentLog "Error: $($_.Exception.Message)" "Error"
    Write-DeploymentLog "StackTrace: $($_.ScriptStackTrace)" "Error"
    
    # Clean up any running jobs
    Write-DeploymentLog "Cleaning up running jobs..." "Warning"
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job
    Get-Job | Remove-Job -Force
    
    exit 1
} finally {
    # Ensure all jobs are cleaned up
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    Write-DeploymentLog "=== Deployment workflow completed ===" "Info"
}

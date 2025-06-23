#Requires -Version 5.1
#Requires -Modules Az.Websites

<#
.SYNOPSIS
    PowerShell module for automated Azure Web App deployment with safe slot swapping and app setting management.

.DESCRIPTION
    AppSettingUpdater provides enterprise-grade automation for Azure Web App deployments using slot swapping with preview.
    Features include intelligent app setting updates, validation workflows, automatic rollback capabilities, and comprehensive
    error handling. Designed for production CI/CD pipelines with safety-first approach.

.AUTHOR
    AppSettingUpdater Team

.VERSION
    2.0.0

.PROJECTURI
    https://github.com/vutruongthinh/AppSettingUpdater

.TAGS
    Azure, WebApp, Deployment, SlotSwap, DevOps, Automation

.NOTES
    Requires Az.Websites module and active Azure authentication context.
    Supports PowerShell 5.1+ and PowerShell 7.x
#>

#region Prerequisites and Context Validation

<#
.SYNOPSIS
    Validates Azure context and required modules for Web App operations.

.DESCRIPTION
    Performs prerequisite checks to ensure the environment is properly configured for Azure Web App operations.
    Validates that the Az.Websites module is available and that the user has an active Azure authentication context.

.EXAMPLE
    Test-WebAppContext
    Validates the current environment for Azure Web App operations.

.NOTES
    This function is called automatically by other module functions to ensure prerequisites are met.
    Throws descriptive errors if prerequisites are not satisfied.

.LINK
    https://docs.microsoft.com/en-us/powershell/azure/install-az-ps
#>
function Test-WebAppContext {
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    # Validate required Azure PowerShell module is available
    if (-not (Get-Module -ListAvailable -Name Az.Websites)) {
        throw "Az.Websites module is not installed. Use 'Install-Module Az.Websites' first."
    }

    # Validate user has active Azure authentication context
    if (-not (Get-AzContext)) {
        throw "You are not logged in. Use 'Connect-AzAccount'."
    }

    Write-Verbose "Azure context validation successful"
}

#endregion

#region Discovery and Validation Functions

<#
.SYNOPSIS
    Discovers and validates Azure Web App deployment slot targets.

.DESCRIPTION
    Queries Azure to verify the existence of specified deployment slots across multiple Web Apps.
    Returns a collection of validated deployment targets, with warnings for any slots that cannot be found.
    Useful for pre-deployment validation and batch operations.

.PARAMETER WebAppNames
    Array of Azure Web App names to validate. Supports multiple apps for batch operations.

.PARAMETER ResourceGroup
    Azure Resource Group containing the Web Apps.

.PARAMETER Slot
    Target deployment slot to validate. Must be one of: staging, testing, qa, preprod.

.EXAMPLE
    Get-WebAppSlotTarget -WebAppNames @("MyApp1", "MyApp2") -ResourceGroup "Production" -Slot "staging"
    Validates that the staging slot exists in both MyApp1 and MyApp2.

.EXAMPLE
    $targets = Get-WebAppSlotTarget -WebAppNames @("MyApp") -ResourceGroup "Dev" -Slot "qa"
    if ($targets) { Write-Host "QA slot is available for deployment" }

.OUTPUTS
    PSCustomObject[]
    Returns array of objects with WebApp and Slot properties for each valid target.

.NOTES
    Non-existent slots are logged as warnings but do not cause the function to fail.
    This allows for graceful handling of partially configured environments.
#>
function Get-WebAppSlotTarget {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory, HelpMessage = "Array of Web App names to validate")]
        [ValidateNotNullOrEmpty()]
        [string[]]$WebAppNames,
        
        [Parameter(Mandatory, HelpMessage = "Azure Resource Group name")]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroup,
        
        [Parameter(Mandatory, HelpMessage = "Target deployment slot to validate")]
        [ValidateSet("staging", "testing", "qa", "preprod")]
        [string]$Slot
    )

    # Ensure Azure context is valid before proceeding
    Test-WebAppContext

    Write-Verbose "Validating slot '$Slot' across $($WebAppNames.Count) Web App(s)"

    # Iterate through each Web App and validate slot existence
    foreach ($name in $WebAppNames) {
        try {
            Write-Verbose "Checking slot '$Slot' in Web App '$name'"
            
            # Query Azure for the specific slot configuration
            $slotInfo = Get-AzWebAppSlot -ResourceGroupName $ResourceGroup -Name $name -Slot $Slot -ErrorAction Stop
            
            if ($slotInfo) {
                Write-Verbose "✓ Slot '$Slot' found in Web App '$name'"
                
                # Return structured object for successful validation
                [PSCustomObject]@{
                    WebApp = $name
                    Slot   = $Slot
                    ResourceGroup = $ResourceGroup
                }
            }
        } catch {
            # Log warning for missing slots but continue processing other apps
            Write-Warning "Slot '$Slot' not found in Web App '$name': $($_.Exception.Message)"
        }
    }
}

#endregion

#region App Settings Management

<#
.SYNOPSIS
    Intelligently updates Azure Web App slot application settings with safety checks.

.DESCRIPTION
    Provides safe, idempotent application setting updates for Azure Web App deployment slots.
    Only updates settings when the value actually differs, preventing unnecessary changes.
    Supports dry-run mode for validation and testing scenarios.

.PARAMETER WebApp
    Name of the target Azure Web App.

.PARAMETER Slot
    Target deployment slot. Must be one of: staging, testing, qa, preprod.

.PARAMETER ResourceGroup
    Azure Resource Group containing the Web App.

.PARAMETER SettingName
    Name of the application setting to update. Cannot be null or empty.

.PARAMETER SettingValue
    New value for the application setting. Can be empty string if needed.

.PARAMETER DryRun
    When specified, simulates the update without making actual changes. Useful for validation.

.EXAMPLE
    Set-WebAppSlotAppSetting -WebApp "MyApp" -Slot "staging" -ResourceGroup "Production" -SettingName "API_VERSION" -SettingValue "v2.0"
    Updates the API_VERSION setting in the staging slot to "v2.0".

.EXAMPLE
    $result = Set-WebAppSlotAppSetting -WebApp "MyApp" -Slot "qa" -ResourceGroup "Test" -SettingName "DEBUG_MODE" -SettingValue "true" -DryRun
    Simulates updating the DEBUG_MODE setting without making actual changes.

.OUTPUTS
    PSCustomObject
    Returns object with WebApp, Slot, SettingName, Updated, and Message properties.

.NOTES
    This function is idempotent - it only makes changes when the setting value actually differs.
    All existing app settings are preserved during updates.
    Supports verbose logging for detailed operation tracking.
#>
function Set-WebAppSlotAppSetting {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, HelpMessage = "Target Azure Web App name")]
        [ValidateNotNullOrEmpty()]
        [string]$WebApp,
        
        [Parameter(Mandatory, HelpMessage = "Target deployment slot")]
        [ValidateSet("staging", "testing", "qa", "preprod")]
        [string]$Slot,
        
        [Parameter(Mandatory, HelpMessage = "Azure Resource Group name")]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroup,
        
        [Parameter(Mandatory, HelpMessage = "Application setting name to update")]
        [ValidateNotNullOrEmpty()]
        [string]$SettingName,
        
        [Parameter(Mandatory, HelpMessage = "New value for the application setting")]
        [AllowEmptyString()]
        [string]$SettingValue,
        
        [Parameter(HelpMessage = "Simulate changes without applying them")]
        [switch]$DryRun
    )

    # Ensure Azure context is valid before proceeding
    Test-WebAppContext

    Write-Verbose "Processing app setting '$SettingName' for '$WebApp/$Slot'"

    try {
        # Retrieve current slot configuration
        Write-Verbose "Retrieving current configuration for slot '$Slot'"
        $slotConfig = Get-AzWebAppSlot -ResourceGroupName $ResourceGroup -Name $WebApp -Slot $Slot -ErrorAction Stop
        
        # Build hashtable of current app settings for efficient lookups
        $settings = @{}
        foreach ($setting in $slotConfig.SiteConfig.AppSettings) {
            $settings[$setting.Name] = $setting.Value
        }
        
        Write-Verbose "Current app settings count: $($settings.Count)"

        # Check if setting value already matches desired value (idempotent behavior)
        if ($settings.ContainsKey($SettingName) -and $settings[$SettingName] -eq $SettingValue) {
            Write-Verbose "No change needed for [$SettingName] - current value matches desired value"
            
            return [PSCustomObject]@{
                WebApp = $WebApp
                Slot = $Slot
                SettingName = $SettingName
                Updated = $false
                Message = "No change"
            }
        }

        # Handle dry-run mode - simulate changes without applying
        if ($DryRun) {
            $currentValue = $settings[$SettingName]
            Write-Verbose "DRY RUN: Would update [$SettingName] from '$currentValue' to '$SettingValue' in slot '$Slot'"
            
            return [PSCustomObject]@{
                WebApp = $WebApp
                Slot = $Slot
                SettingName = $SettingName
                Updated = $false
                Message = "DryRun - would update from '$currentValue' to '$SettingValue'"
            }
        }

        # Apply the setting update
        Write-Verbose "Updating app setting [$SettingName] in slot '$Slot'"
        $settings[$SettingName] = $SettingValue
        
        # Update the slot configuration with modified settings
        Set-AzWebAppSlot -ResourceGroupName $ResourceGroup -Name $WebApp -Slot $Slot -AppSettings $settings -ErrorAction Stop
        
        Write-Verbose "✓ Successfully updated app setting [$SettingName]"

        return [PSCustomObject]@{
            WebApp = $WebApp
            Slot = $Slot
            SettingName = $SettingName
            Updated = $true
            Message = "Updated"
        }

    } catch {
        # Provide detailed error context for debugging
        $errorMessage = "Error updating setting [$SettingName] in '$WebApp/$Slot': $($_.Exception.Message)"
        Write-Error $errorMessage
        throw $errorMessage
    }
}

#endregion

#region Slot Swap Operations

<#
.SYNOPSIS
    Initiates Azure Web App slot swap with preview for safe deployment staging.

.DESCRIPTION
    Starts a slot swap operation using Azure's "Swap with Preview" feature, which allows for validation
    before completing the swap. This enables zero-downtime deployments with the ability to validate
    the staged environment before promoting to production.

.PARAMETER WebApp
    Name of the target Azure Web App.

.PARAMETER ResourceGroup
    Azure Resource Group containing the Web App.

.PARAMETER SourceSlot
    Source deployment slot to swap from. Defaults to "staging".

.PARAMETER DestinationSlot
    Destination slot to swap to. Defaults to "production".

.EXAMPLE
    Start-WebAppSlotSwapPreview -WebApp "MyApp" -ResourceGroup "Production"
    Initiates swap preview from staging to production using default values.

.EXAMPLE
    Start-WebAppSlotSwapPreview -WebApp "MyApp" -ResourceGroup "Test" -SourceSlot "qa" -DestinationSlot "staging"
    Initiates swap preview from qa slot to staging slot.

.NOTES
    After calling this function, use validation logic to test the staged environment,
    then call Complete-WebAppSlotSwap or Undo-WebAppSlotSwap based on validation results.
    The swap is not completed until Complete-WebAppSlotSwap is called.

.LINK
    Complete-WebAppSlotSwap
    Undo-WebAppSlotSwap
#>
function Start-WebAppSlotSwapPreview {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, HelpMessage = "Target Azure Web App name")]
        [ValidateNotNullOrEmpty()]
        [string]$WebApp,
        
        [Parameter(Mandatory, HelpMessage = "Azure Resource Group name")]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroup,
        
        [Parameter(HelpMessage = "Source slot to swap from")]
        [ValidateSet("staging", "testing", "qa", "preprod")]
        [string]$SourceSlot = "staging",
        
        [Parameter(HelpMessage = "Destination slot to swap to")]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationSlot = "production"
    )

    # Ensure Azure context is valid before proceeding
    Test-WebAppContext

    Write-Verbose "Initiating slot swap preview: '$SourceSlot' → '$DestinationSlot' for Web App '$WebApp'"

    try {
        # Initiate the swap with preview operation
        # PreserveVnet maintains network configuration during swap
        Switch-AzWebAppSlot -Name $WebApp -ResourceGroupName $ResourceGroup `
            -SourceSlotName $SourceSlot -DestinationSlotName $DestinationSlot `
            -SwapWithPreviewAction ApplySlotConfig -PreserveVnet $true -ErrorAction Stop
        
        Write-Verbose "✓ Swap with preview initiated successfully"
        Write-Verbose "Next steps: Validate staged environment, then Complete or Undo the swap"
        
    } catch {
        $errorMessage = "Failed to initiate slot swap preview for '$WebApp': $($_.Exception.Message)"
        Write-Error $errorMessage
        throw $errorMessage
    }
}

<#
.SYNOPSIS
    Completes a previously initiated Azure Web App slot swap operation.

.DESCRIPTION
    Finalizes a slot swap that was started with Start-WebAppSlotSwapPreview. This promotes the staged
    environment to production, completing the deployment process. This action is irreversible and
    should only be called after successful validation of the preview environment.

.PARAMETER WebApp
    Name of the target Azure Web App.

.PARAMETER ResourceGroup
    Azure Resource Group containing the Web App.

.PARAMETER SourceSlot
    Source deployment slot that was used in the preview. Defaults to "staging".

.EXAMPLE
    Complete-WebAppSlotSwap -WebApp "MyApp" -ResourceGroup "Production"
    Completes the slot swap from staging to production.

.EXAMPLE
    Complete-WebAppSlotSwap -WebApp "MyApp" -ResourceGroup "Test" -SourceSlot "qa"
    Completes the slot swap from qa slot to production.

.NOTES
    This action completes the swap operation and is irreversible. Ensure validation has passed
    before calling this function. If validation fails, use Undo-WebAppSlotSwap instead.

.LINK
    Start-WebAppSlotSwapPreview
    Undo-WebAppSlotSwap
#>
function Complete-WebAppSlotSwap {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, HelpMessage = "Target Azure Web App name")]
        [ValidateNotNullOrEmpty()]
        [string]$WebApp,
        
        [Parameter(Mandatory, HelpMessage = "Azure Resource Group name")]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroup,
        
        [Parameter(HelpMessage = "Source slot used in the swap preview")]
        [ValidateSet("staging", "testing", "qa", "preprod")]
        [string]$SourceSlot = "staging"
    )

    # Ensure Azure context is valid before proceeding
    Test-WebAppContext

    Write-Verbose "Completing slot swap for Web App '$WebApp' from slot '$SourceSlot'"

    try {
        # Complete the previously initiated swap operation
        Switch-AzWebAppSlot -Name $WebApp -ResourceGroupName $ResourceGroup `
            -SourceSlotName $SourceSlot -SwapWithPreviewAction CompleteSlotSwap -ErrorAction Stop
        
        Write-Verbose "✓ Slot swap completed successfully"
        Write-Verbose "Deployment from '$SourceSlot' to production is now live"
        
    } catch {
        $errorMessage = "Failed to complete slot swap for '$WebApp': $($_.Exception.Message)"
        Write-Error $errorMessage
        throw $errorMessage
    }
}

<#
.SYNOPSIS
    Cancels and rolls back a previously initiated Azure Web App slot swap operation.

.DESCRIPTION
    Undoes a slot swap that was started with Start-WebAppSlotSwapPreview, effectively rolling back
    to the previous state. This is used when validation fails or when an emergency rollback is needed.
    Provides immediate recovery capability for failed deployments.

.PARAMETER WebApp
    Name of the target Azure Web App.

.PARAMETER ResourceGroup
    Azure Resource Group containing the Web App.

.PARAMETER SourceSlot
    Source deployment slot that was used in the preview. Defaults to "staging".

.EXAMPLE
    Undo-WebAppSlotSwap -WebApp "MyApp" -ResourceGroup "Production"
    Cancels the slot swap and rolls back to the previous state.

.EXAMPLE
    Undo-WebAppSlotSwap -WebApp "MyApp" -ResourceGroup "Test" -SourceSlot "qa"
    Cancels the slot swap from qa slot and rolls back.

.NOTES
    This function provides emergency rollback capability and should be used when validation
    fails or immediate recovery is needed. The operation restores the previous environment state.

.LINK
    Start-WebAppSlotSwapPreview
    Complete-WebAppSlotSwap
#>
function Undo-WebAppSlotSwap {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, HelpMessage = "Target Azure Web App name")]
        [ValidateNotNullOrEmpty()]
        [string]$WebApp,
        
        [Parameter(Mandatory, HelpMessage = "Azure Resource Group name")]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroup,
        
        [Parameter(HelpMessage = "Source slot used in the swap preview")]
        [ValidateSet("staging", "testing", "qa", "preprod")]
        [string]$SourceSlot = "staging"
    )

    # Ensure Azure context is valid before proceeding
    Test-WebAppContext

    Write-Verbose "Undoing slot swap for Web App '$WebApp' from slot '$SourceSlot'"

    try {
        # Reset/cancel the previously initiated swap operation
        Switch-AzWebAppSlot -Name $WebApp -ResourceGroupName $ResourceGroup `
            -SourceSlotName $SourceSlot -SwapWithPreviewAction ResetSlotSwap -ErrorAction Stop
        
        Write-Verbose "✓ Slot swap cancelled and rolled back successfully"
        Write-Verbose "Previous environment state has been restored"
        
    } catch {
        $errorMessage = "Failed to cancel slot swap for '$WebApp': $($_.Exception.Message)"
        Write-Error $errorMessage
        throw $errorMessage
    }
}

#endregion

# Module metadata and exports
Export-ModuleMember -Function @(
    'Test-WebAppContext',
    'Get-WebAppSlotTarget', 
    'Set-WebAppSlotAppSetting',
    'Start-WebAppSlotSwapPreview',
    'Complete-WebAppSlotSwap',
    'Undo-WebAppSlotSwap'
)


param (
    [string]$TestPath = "$PSScriptRoot\Tests\AppSettingUpdater.Tests.ps1",
    [string]$ModulePath = "$PSScriptRoot\AppSettingUpdater.psd1",
    [string]$ReportPath = "$PSScriptRoot\Reports\TestReport.xml"
)

Write-Host "=== AppSettingUpdater Test Suite Runner ===" -ForegroundColor Cyan
Write-Host "Test Path: $TestPath" -ForegroundColor Gray
Write-Host "Module Path: $ModulePath" -ForegroundColor Gray
Write-Host "Report Path: $ReportPath" -ForegroundColor Gray
Write-Host ""

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Error "Pester module is not installed. Run 'Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser'."
    return
}

# Check for Pester 5.x
$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if ($pesterModule.Version.Major -lt 5) {
    Write-Error "Pester 5.0 or later is required. Current version: $($pesterModule.Version). Run 'Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser'."
    return
}

Write-Host "Pester $($pesterModule.Version) detected" -ForegroundColor Green

Import-Module -Name $ModulePath -Force

# Import Pester 5.x (use the latest available 5.x version)
Import-Module Pester -MinimumVersion 5.0 -Force

# Pester 5.x configuration
$PesterConfig = New-PesterConfiguration
$PesterConfig.Run.Path = $TestPath
$PesterConfig.TestResult.Enabled = $true
$PesterConfig.TestResult.OutputFormat = 'NUnitXml'
$PesterConfig.TestResult.OutputPath = $ReportPath
$PesterConfig.Output.Verbosity = 'Detailed'
$PesterConfig.Run.PassThru = $true

# Run tests with Pester 5.x syntax
Write-Host "=== Executing Test Suite ===" -ForegroundColor Cyan
$startTime = Get-Date
$testResult = Invoke-Pester -Configuration $PesterConfig 
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "=== Test Execution Summary ===" -ForegroundColor Cyan
Write-Host "Duration: $([math]::Round($duration.TotalSeconds, 2)) seconds" -ForegroundColor Gray
Write-Host "Tests Run: $($testResult.TotalCount)" -ForegroundColor White
Write-Host "Passed: $($testResult.PassedCount)" -ForegroundColor Green
Write-Host "Failed: $($testResult.FailedCount)" -ForegroundColor $(if ($testResult.FailedCount -gt 0) { "Red" } else { "Gray" })
Write-Host "Skipped: $($testResult.SkippedCount)" -ForegroundColor Yellow
if ($testResult.TotalCount -gt 0) {
    Write-Host "Success Rate: $([math]::Round(($testResult.PassedCount / $testResult.TotalCount) * 100, 1))%" -ForegroundColor $(if ($testResult.FailedCount -eq 0) { "Green" } else { "Yellow" })
}

Write-Host ""
if ($testResult.FailedCount -eq 0) {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
} else {
    Write-Host "$($testResult.FailedCount) TEST(S) FAILED" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test run complete. Report generated at: $ReportPath" -ForegroundColor Cyan

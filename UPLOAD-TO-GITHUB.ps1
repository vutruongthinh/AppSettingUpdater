# Upload to GitHub Script
# Run this script after installing Git and creating your GitHub repository

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubUsername,
    
    [Parameter(Mandatory=$false)]
    [string]$RepositoryName = "AppSettingUpdater"
)

Write-Host "Starting GitHub upload process..." -ForegroundColor Green

# Check if Git is available
try {
    $gitVersion = git --version
    Write-Host "Git is installed: $gitVersion" -ForegroundColor Green
} catch {
    Write-Error "Git is not installed or not in PATH. Please install Git first."
    exit 1
}

# Navigate to project directory
$projectPath = $PSScriptRoot
Set-Location $projectPath
Write-Host "Working in: $projectPath" -ForegroundColor Yellow

# Configure Git (if not already configured)
$gitUserName = git config --global user.name
$gitUserEmail = git config --global user.email

if (-not $gitUserName) {
    $userName = Read-Host "Enter your full name for Git commits"
    git config --global user.name $userName
}

if (-not $gitUserEmail) {
    $userEmail = Read-Host "Enter your email for Git commits"
    git config --global user.email $userEmail
}

# Initialize repository
Write-Host "Initializing Git repository..." -ForegroundColor Yellow
git init

# Add all files
Write-Host "Adding all files..." -ForegroundColor Yellow
git add .

# Create initial commit
Write-Host "Creating initial commit..." -ForegroundColor Yellow
git commit -m "Initial commit: AppSettingUpdater v2.0 - Enterprise PowerShell module for Azure Web App deployments with parallel processing

Features:
- 25 comprehensive tests with 100% coverage
- Parallel processing for multiple web apps  
- Zero-downtime deployments with slot swapping
- Automatic rollback capabilities
- Enterprise-grade logging and reporting
- CI/CD ready with GitHub Actions workflow
- PowerShell 5.1+ and 7.x compatibility"

# Add remote repository
$repoUrl = "https://github.com/$GitHubUsername/$RepositoryName.git"
Write-Host "Adding remote repository: $repoUrl" -ForegroundColor Yellow
git remote add origin $repoUrl

# Set main branch and push
Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
git branch -M main
git push -u origin main

Write-Host ""
Write-Host "SUCCESS! Your project has been uploaded to GitHub!" -ForegroundColor Green
Write-Host "Repository URL: https://github.com/$GitHubUsername/$RepositoryName" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Visit your repository and add the suggested topics/tags" -ForegroundColor White
Write-Host "2. Enable GitHub features (Issues, Wiki, Discussions)" -ForegroundColor White
Write-Host "3. Your CI/CD pipeline will run automatically on commits" -ForegroundColor White
Write-Host "4. Share your repository with the community!" -ForegroundColor White

# Run-AppSettingUpdate.ps1 Usage Examples

## Single Web App Deployment
```powershell
.\Run-AppSettingUpdate.ps1 -WebApp "MyApp" -ResourceGroup "MyRG" -SettingName "API_VERSION" -SettingValue "v2.0"
```

## Multiple Web Apps Deployment (Parallel Processing)
```powershell
# Deploy to multiple web apps in parallel
.\Run-AppSettingUpdate.ps1 `
    -WebApp @("MyApp1", "MyApp2", "MyApp3") `
    -ResourceGroup "MyRG" `
    -SettingName "VERSION" `
    -SettingValue "2.0" `
    -MaxParallelJobs 3
```

## Large Scale Deployment with Custom Job Settings
```powershell
# Deploy to many web apps with custom timeout and parallel limits
.\Run-AppSettingUpdate.ps1 `
    -WebApp @("App1", "App2", "App3", "App4", "App5", "App6", "App7", "App8") `
    -ResourceGroup "Production" `
    -SettingName "FEATURE_ROLLOUT" `
    -SettingValue "enabled" `
    -MaxParallelJobs 4 `
    -JobTimeoutMinutes 45 `
    -ValidationUrl "https://{WebApp}.azurewebsites.net/health"
```

## Development Environment Testing
```powershell
.\Run-AppSettingUpdate.ps1 -WebApp "MyApp" -ResourceGroup "MyRG" -Slot "qa" -DryRun
```

## Production Deployment with Validation
```powershell
.\Run-AppSettingUpdate.ps1 `
    -WebApp "MyApp" `
    -ResourceGroup "MyRG" `
    -SettingName "FEATURE_FLAG" `
    -SettingValue "enabled" `
    -ValidationUrl "https://myapp.azurewebsites.net/health" `
    -ValidationTimeoutSeconds 600
```

## CI/CD Pipeline Usage (No Prompts)
```powershell
.\Run-AppSettingUpdate.ps1 `
    -WebApp "MyApp" `
    -ResourceGroup "MyRG" `
    -SettingName "BUILD_NUMBER" `
    -SettingValue $env:BUILD_ID `
    -Force
```

## Testing with WhatIf
```powershell
.\Run-AppSettingUpdate.ps1 -WebApp "MyApp" -ResourceGroup "MyRG" -WhatIf
```

## Multiple Settings Deployment
```powershell
# For multiple settings, run the script multiple times or extend it
$settings = @{
    "API_VERSION" = "v2.0"
    "FEATURE_FLAG" = "enabled"
    "DB_TIMEOUT" = "30"
}

foreach ($setting in $settings.GetEnumerator()) {
    .\Run-AppSettingUpdate.ps1 `
        -WebApp "MyApp" `
        -ResourceGroup "MyRG" `
        -SettingName $setting.Key `
        -SettingValue $setting.Value `
        -Force
}
```

## Environment-Specific Deployments
```powershell
# QA Environment
.\Run-AppSettingUpdate.ps1 -WebApp "MyApp-QA" -ResourceGroup "MyRG-QA" -Slot "testing"

# Production Environment  
.\Run-AppSettingUpdate.ps1 -WebApp "MyApp-Prod" -ResourceGroup "MyRG-Prod" -Slot "staging"
```

## Performance Considerations

### Parallel Processing Features
- **MaxParallelJobs**: Controls how many deployments run simultaneously (default: 5, max: 10)
- **JobTimeoutMinutes**: Maximum time for each individual deployment (default: 30 minutes)
- **Automatic Job Management**: Jobs are throttled and monitored automatically
- **Progress Tracking**: Real-time progress updates for large deployments

### Validation URL Templates
Use `{WebApp}` placeholder in validation URLs for multiple web apps:
```powershell
-ValidationUrl "https://{WebApp}.azurewebsites.net/health"
```
This will automatically substitute each web app name during validation.

### Best Practices for Large Deployments
- Use 3-5 parallel jobs for optimal performance vs. Azure API limits
- Set appropriate timeouts based on your app startup time
- Always test with DryRun first when deploying to many apps
- Use validation URLs to ensure deployments are successful

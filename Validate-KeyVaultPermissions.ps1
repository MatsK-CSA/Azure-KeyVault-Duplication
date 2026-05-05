# Validate-KeyVaultPermissions.ps1
# Validates that the current user has sufficient permissions on source and target Key Vaults

param(
    [switch]$Verbose
)

# ============================================================================
# Configuration (CUSTOMIZE THESE VARIABLES)
# ============================================================================

# Source Key Vault Configuration
$SourceSubscriptionId = "YOUR_SOURCE_SUBSCRIPTION_ID"
$SourceResourceGroup = "YOUR_SOURCE_RESOURCE_GROUP"
$SourceKeyVaultName = "YOUR_SOURCE_KEYVAULT_NAME"

# Target Key Vault Configuration
$TargetSubscriptionId = "YOUR_TARGET_SUBSCRIPTION_ID"
$TargetResourceGroup = "YOUR_TARGET_RESOURCE_GROUP"
$TargetKeyVaultName = "YOUR_TARGET_KEYVAULT_NAME"

# Logging Configuration
$LogDirectory = "$(Get-Location)\Logs"

# ============================================================================
# Initialize
# ============================================================================

# Import helper module
$helperPath = Join-Path (Split-Path -Parent $PSCommandPath) "KeyVaultHelper.ps1"
if (-not (Test-Path $helperPath)) {
    Write-Host "Error: KeyVaultHelper.ps1 not found at $helperPath" -ForegroundColor Red
    exit 1
}

. $helperPath

# Initialize logging
Initialize-Logging -LogDir $LogDirectory -Verbose $Verbose | Out-Null

# ============================================================================
# Main Validation Logic
# ============================================================================

Write-Log "========================================" -Level "INFO"
Write-Log "Key Vault Permissions Validation" -Level "INFO"
Write-Log "========================================" -Level "INFO"

$startTime = Get-Date
$allPermissionsValid = $true

# Test Azure CLI connection
Write-Log "Step 1: Testing Azure CLI connection..." -Level "INFO"
if (-not (Test-AzureCliConnection $SourceSubscriptionId $TargetSubscriptionId)) {
    Write-Log "Failed to connect to Azure. Please run 'az login' first." -Level "ERROR"
    exit 1
}

# Test Source Key Vault Access
Write-Log "Step 2: Testing Source Key Vault access..." -Level "INFO"
if (-not (Test-KeyVaultAccess $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName)) {
    Write-Log "Cannot access source Key Vault. Please verify subscription, resource group, and vault name." -Level "ERROR"
    $allPermissionsValid = $false
}
else {
    Write-Log "Source Key Vault is accessible." -Level "SUCCESS"
    
    # Test Source permissions
    Write-Log "Testing permissions on source Key Vault..." -Level "DEBUG"
    $sourcePermissions = Test-KeyVaultPermissions $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName
    
    foreach ($perm in @("secrets/get", "secrets/list", "certificates/get", "certificates/list")) {
        if ($sourcePermissions[$perm]) {
            Write-Log "  [OK] $perm" -Level "INFO"
        }
        else {
            Write-Log "  x $perm - MISSING" -Level "ERROR"
            $allPermissionsValid = $false
        }
    }
}

# Test Target Key Vault Access
Write-Log "Step 3: Testing Target Key Vault access..." -Level "INFO"
if (-not (Test-KeyVaultAccess $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName)) {
    Write-Log "Cannot access target Key Vault. Please verify subscription, resource group, and vault name." -Level "ERROR"
    $allPermissionsValid = $false
}
else {
    Write-Log "Target Key Vault is accessible." -Level "SUCCESS"
    
    # Test Target permissions
    Write-Log "Testing permissions on target Key Vault..." -Level "DEBUG"
    $targetPermissions = Test-KeyVaultPermissions $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName
    
    foreach ($perm in @("secrets/set", "secrets/list", "certificates/import", "certificates/list")) {
        if ($targetPermissions[$perm]) {
            Write-Log "  [OK] $perm" -Level "INFO"
        }
        else {
            Write-Log "  x $perm - MISSING" -Level "ERROR"
            $allPermissionsValid = $false
        }
    }
}

# Get RBAC information
Write-Log "Step 4: Retrieving RBAC role assignments..." -Level "INFO"
Set-AzureSubscription $SourceSubscriptionId | Out-Null
$sourceRoles = Get-UserRoleAssignments $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName
Set-AzureSubscription $TargetSubscriptionId | Out-Null
$targetRoles = Get-UserRoleAssignments $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName

if ($sourceRoles.Count -gt 0) {
    Write-Log "Source Key Vault RBAC roles:" -Level "INFO"
    $sourceRoles | ForEach-Object {
        Write-Log "  - $($_.roleDefinitionName)" -Level "DEBUG"
    }
}
else {
    Write-Log "No RBAC roles assigned on source Key Vault" -Level "WARN"
}

if ($targetRoles.Count -gt 0) {
    Write-Log "Target Key Vault RBAC roles:" -Level "INFO"
    $targetRoles | ForEach-Object {
        Write-Log "  - $($_.roleDefinitionName)" -Level "DEBUG"
    }
}
else {
    Write-Log "No RBAC roles assigned on target Key Vault" -Level "WARN"
}

# Summary
Write-Log "========================================" -Level "INFO"
$endTime = Get-Date
$duration = $endTime - $startTime

if ($allPermissionsValid) {
    Write-Log "[PASS] All required permissions are available!" -Level "SUCCESS"
    Write-Log "You may proceed with the duplication script." -Level "SUCCESS"
}
else {
    Write-Log "[FAIL] Some required permissions are missing." -Level "ERROR"
    Write-Log "Please contact your Azure administrator to grant necessary permissions." -Level "ERROR"
}

# Report summary
Report-ErrorSummary $LogDirectory | Out-Null
Get-ExecutionSummary -ErrorCount (Get-ErrorSummary).Count -Duration $duration.ToString("hh\:mm\:ss")

# Exit with appropriate code
if ($allPermissionsValid) {
    exit 0
}
else {
    exit 1
}

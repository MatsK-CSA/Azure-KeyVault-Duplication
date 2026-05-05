# Validate-DuplicationComplete.ps1
# Validates that secrets and certificates were successfully duplicated from source to target

param(
    [switch]$Verbose,
    [switch]$CompareMetadata
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
Write-Log "Key Vault Duplication Validation" -Level "INFO"
Write-Log "========================================" -Level "INFO"

$startTime = Get-Date
$validationResults = @{
    Match = $true
    DifferencesFound = 0
    MissingInTarget = @()
    ExtraInTarget = @()
    MetadataMismatches = @()
}

# Validate Azure CLI connection
Write-Log "Step 1: Validating Azure CLI connection..." -Level "INFO"
if (-not (Test-AzureCliConnection $SourceSubscriptionId $TargetSubscriptionId)) {
    Write-Log "Failed to connect to Azure." -Level "ERROR"
    exit 1
}

# Test vault access
Write-Log "Step 2: Testing Key Vault access..." -Level "INFO"
if (-not (Test-KeyVaultAccess $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName)) {
    Write-Log "Cannot access source Key Vault." -Level "ERROR"
    exit 1
}

if (-not (Test-KeyVaultAccess $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName)) {
    Write-Log "Cannot access target Key Vault." -Level "ERROR"
    exit 1
}

# Get secrets from both vaults
Write-Log "Step 3: Retrieving secrets from both Key Vaults..." -Level "INFO"
$sourceSecrets = Get-AllKeyVaultSecrets $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName
$targetSecrets = Get-AllKeyVaultSecrets $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName

$sourceSecretNames = $sourceSecrets | ForEach-Object { $_.name } | Sort-Object
$targetSecretNames = $targetSecrets | ForEach-Object { $_.name } | Sort-Object

Write-Log "Source secrets count: $($sourceSecrets.Count)" -Level "INFO"
Write-Log "Target secrets count: $($targetSecrets.Count)" -Level "INFO"

# Check for missing/extra secrets
foreach ($secretName in $sourceSecretNames) {
    if ($secretName -notin $targetSecretNames) {
        # Check if it's expired (expected to be missing)
        $sourceSecret = $sourceSecrets | Where-Object { $_.name -eq $secretName }
        if (Test-IsExpired $sourceSecret) {
            Write-Log "Secret missing in target (expected - expired): $secretName" -Level "DEBUG"
        }
        else {
            Write-Log "Secret missing in target: $secretName" -Level "WARN"
            $validationResults.MissingInTarget += $secretName
            $validationResults.Match = $false
            $validationResults.DifferencesFound++
        }
    }
}

foreach ($secretName in $targetSecretNames) {
    if ($secretName -notin $sourceSecretNames) {
        Write-Log "Extra secret in target (not in source): $secretName" -Level "WARN"
        $validationResults.ExtraInTarget += $secretName
        $validationResults.DifferencesFound++
    }
}

# Validate metadata if requested
if ($CompareMetadata) {
    Write-Log "Step 4: Comparing secret metadata..." -Level "INFO"
    
    foreach ($secretName in $sourceSecretNames) {
        if ($secretName -notin $targetSecretNames) {
            continue
        }
        
        $sourceSecret = $sourceSecrets | Where-Object { $_.name -eq $secretName }
        $targetSecret = $targetSecrets | Where-Object { $_.name -eq $secretName }
        
        # Compare attributes
        $mismatches = @()
        
        if ($sourceSecret.attributes.enabled -ne $targetSecret.attributes.enabled) {
            $mismatches += "Enabled state differs (source: $($sourceSecret.attributes.enabled), target: $($targetSecret.attributes.enabled))"
        }
        
        if ($sourceSecret.contentType -ne $targetSecret.contentType) {
            $mismatches += "Content type differs (source: $($sourceSecret.contentType), target: $($targetSecret.contentType))"
        }
        
        if ($mismatches.Count -gt 0) {
            Write-Log "Metadata mismatch for secret '$secretName': $($mismatches -join '; ')" -Level "WARN"
            $validationResults.MetadataMismatches += @{
                Name = $secretName
                Mismatches = $mismatches
            }
        }
    }
}

# Get certificates from both vaults
Write-Log "Step 5: Retrieving certificates from both Key Vaults..." -Level "INFO"
$sourceCertificates = Get-AllKeyVaultCertificates $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName
$targetCertificates = Get-AllKeyVaultCertificates $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName

$sourceCertNames = $sourceCertificates | ForEach-Object { $_.name } | Sort-Object
$targetCertNames = $targetCertificates | ForEach-Object { $_.name } | Sort-Object

Write-Log "Source certificates count: $($sourceCertificates.Count)" -Level "INFO"
Write-Log "Target certificates count: $($targetCertificates.Count)" -Level "INFO"

# Check for missing/extra certificates
foreach ($certName in $sourceCertNames) {
    if ($certName -notin $targetCertNames) {
        # Check if it's expired
        $sourceCert = $sourceCertificates | Where-Object { $_.name -eq $certName }
        if (Test-IsExpired $sourceCert) {
            Write-Log "Certificate missing in target (expected - expired): $certName" -Level "DEBUG"
        }
        else {
            Write-Log "Certificate missing in target: $certName" -Level "WARN"
            $validationResults.MissingInTarget += $certName
            $validationResults.Match = $false
            $validationResults.DifferencesFound++
        }
    }
}

foreach ($certName in $targetCertNames) {
    if ($certName -notin $sourceCertNames) {
        Write-Log "Extra certificate in target (not in source): $certName" -Level "WARN"
        $validationResults.ExtraInTarget += $certName
        $validationResults.DifferencesFound++
    }
}

# Validation summary
Write-Log "========================================" -Level "INFO"
Write-Log "Validation Summary" -Level "INFO"
Write-Log "========================================" -Level "INFO"

Write-Log "Total items in source: $($sourceSecrets.Count + $sourceCertificates.Count)" -Level "INFO"
Write-Log "Total items in target: $($targetSecrets.Count + $targetCertificates.Count)" -Level "INFO"
Write-Log "Differences found: $($validationResults.DifferencesFound)" -Level "INFO"

if ($validationResults.MissingInTarget.Count -gt 0) {
    Write-Log "Missing in target:" -Level "WARN"
    $validationResults.MissingInTarget | ForEach-Object {
        Write-Log "  - $_" -Level "WARN"
    }
}

if ($validationResults.ExtraInTarget.Count -gt 0) {
    Write-Log "Extra in target:" -Level "WARN"
    $validationResults.ExtraInTarget | ForEach-Object {
        Write-Log "  - $_" -Level "WARN"
    }
}

if ($validationResults.MetadataMismatches.Count -gt 0) {
    Write-Log "Metadata mismatches:" -Level "WARN"
    $validationResults.MetadataMismatches | ForEach-Object {
        Write-Log "  - $($_.Name): $($_.Mismatches -join '; ')" -Level "WARN"
    }
}

# Export validation report to CSV
$reportFile = Join-Path $LogDirectory "Validation_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$reportData = @()

foreach ($item in $sourceSecretNames) {
    $status = if ($item -in $targetSecretNames) { "OK" } else { "MISSING" }
    $reportData += [PSCustomObject]@{
        Type = "Secret"
        Name = $item
        InSource = "Yes"
        InTarget = if ($item -in $targetSecretNames) { "Yes" } else { "No" }
        Status = $status
    }
}

foreach ($item in $sourceCertNames) {
    $status = if ($item -in $targetCertNames) { "OK" } else { "MISSING" }
    $reportData += [PSCustomObject]@{
        Type = "Certificate"
        Name = $item
        InSource = "Yes"
        InTarget = if ($item -in $targetCertNames) { "Yes" } else { "No" }
        Status = $status
    }
}

foreach ($item in $targetSecretNames) {
    if ($item -notin $sourceSecretNames) {
        $reportData += [PSCustomObject]@{
            Type = "Secret"
            Name = $item
            InSource = "No"
            InTarget = "Yes"
            Status = "EXTRA"
        }
    }
}

foreach ($item in $targetCertNames) {
    if ($item -notin $sourceCertNames) {
        $reportData += [PSCustomObject]@{
            Type = "Certificate"
            Name = $item
            InSource = "No"
            InTarget = "Yes"
            Status = "EXTRA"
        }
    }
}

$reportData | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
Write-Log "Validation report exported to: $reportFile" -Level "INFO"

# Final result
Write-Log "========================================" -Level "INFO"
$endTime = Get-Date
$duration = $endTime - $startTime
Write-Log "Duration: $($duration.ToString('hh\:mm\:ss'))" -Level "INFO"

if ($validationResults.Match) {
    Write-Log "[PASS] Validation PASSED - Duplication is complete!" -Level "SUCCESS"
    Report-ErrorSummary $LogDirectory | Out-Null
    exit 0
}
else {
    Write-Log "[FAIL] Validation FAILED - Differences detected" -Level "ERROR"
    Report-ErrorSummary $LogDirectory | Out-Null
    exit 1
}

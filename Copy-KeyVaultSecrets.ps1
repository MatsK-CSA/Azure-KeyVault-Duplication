# Copy-KeyVaultSecrets.ps1
# Duplicates all secrets and certificates from source to target Key Vault
#
# DISCLAIMER: Sample Code is provided for the purpose of illustration only and is not intended
# to be used in a production environment. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE
# PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR
# PURPOSE. We grant You a nonexclusive, royalty-free right to use and modify the Sample Code
# and to reproduce and distribute the object code form of the Sample Code, provided that You
# agree: (i) to not use Our name, logo, or trademarks to market Your software product in
# which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software
# product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and
# defend Us and Our suppliers from and against any claims or lawsuits, including attorneys'
# fees, that arise or result from the use or distribution of the Sample Code.

param(
    [switch]$DryRun,
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
# Main Duplication Logic
# ============================================================================

Write-Log "========================================" -Level "INFO"
Write-Log "Key Vault Duplication Script" -Level "INFO"
Write-Log "========================================" -Level "INFO"

if ($DryRun) {
    Write-Log "** DRY RUN MODE - No changes will be made **" -Level "WARN"
}

$startTime = Get-Date
$statistics = @{
    SecretsProcessed = 0
    SecretsSkipped = 0
    SecretsExpired = 0
    CertificatesProcessed = 0
    CertificatesSkipped = 0
    CertificatesExpired = 0
    ErrorCount = 0
}

$dryRunReport = @()

# Validate Azure CLI connection
Write-Log "Step 1: Validating Azure CLI connection..." -Level "INFO"
if (-not (Test-AzureCliConnection $SourceSubscriptionId $TargetSubscriptionId)) {
    Write-Log "Failed to connect to Azure. Please run 'az login' first." -Level "ERROR"
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

Write-Log "Both Key Vaults are accessible." -Level "SUCCESS"

# Get all secrets from source
Write-Log "Step 3: Retrieving all secrets from source Key Vault..." -Level "INFO"
$sourceSecrets = Get-AllKeyVaultSecrets $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName

# Get existing secrets from target (to check for duplicates)
Write-Log "Retrieving existing secrets from target Key Vault..." -Level "INFO"
$targetSecrets = Get-AllKeyVaultSecrets $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName
$targetSecretNames = $targetSecrets | ForEach-Object { $_.name }

# Process secrets
Write-Log "Step 4: Processing secrets..." -Level "INFO"
foreach ($secret in $sourceSecrets) {
    $secretName = $secret.name
    Write-Log "Processing secret: $secretName" -Level "DEBUG"
    
    try {
        # Retrieve full secret details
        $fullSecret = Get-KeyVaultSecret $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName $secretName
        
        if (-not $fullSecret) {
            Add-ErrorRecord "Failed to retrieve full secret details" $secretName "Secret"
            $statistics.ErrorCount++
            continue
        }
        
        # Check if secret is expired
        if (Test-IsExpired $fullSecret) {
            Write-Log "Skipping expired secret: $secretName" -Level "WARN"
            $statistics.SecretsExpired++
            $dryRunReport += @{
                Type = "Secret"
                Name = $secretName
                Status = "Skipped (Expired)"
                Reason = "Secret has expired"
            }
            continue
        }
        
        # Check if secret already exists in target
        if ($targetSecretNames -contains $secretName) {
            Write-Log "Secret already exists in target vault, skipping: $secretName" -Level "WARN"
            $statistics.SecretsSkipped++
            $dryRunReport += @{
                Type = "Secret"
                Name = $secretName
                Status = "Skipped (Exists)"
                Reason = "Already exists in target"
            }
            continue
        }
        
        # Prepare metadata
        $metadata = @{
            ContentType = $fullSecret.contentType
            Tags = $fullSecret.tags
        }
        
        if ($DryRun) {
            Write-Log "DRY RUN: Would copy secret: $secretName" -Level "INFO"
            $dryRunReport += @{
                Type = "Secret"
                Name = $secretName
                Status = "Would Copy"
                ContentType = $fullSecret.contentType
                Reason = "Valid, not expired, not duplicate"
            }
        }
        else {
            # Set the secret in target
            if (Set-KeyVaultSecret $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName $secretName $fullSecret.value $metadata) {
                Write-Log "Successfully copied secret: $secretName" -Level "SUCCESS"
                $statistics.SecretsProcessed++
                $dryRunReport += @{
                    Type = "Secret"
                    Name = $secretName
                    Status = "Copied"
                    ContentType = $fullSecret.contentType
                }
            }
            else {
                Write-Log "Failed to copy secret: $secretName" -Level "ERROR"
                $statistics.ErrorCount++
            }
        }
    }
    catch {
        Add-ErrorRecord "Unexpected error processing secret: $_" $secretName "Secret"
        $statistics.ErrorCount++
    }
}

# Get all certificates from source
Write-Log "Step 5: Retrieving all certificates from source Key Vault..." -Level "INFO"
$sourceCertificates = Get-AllKeyVaultCertificates $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName

# Get existing certificates from target
Write-Log "Retrieving existing certificates from target Key Vault..." -Level "INFO"
$targetCertificates = Get-AllKeyVaultCertificates $TargetSubscriptionId $TargetResourceGroup $TargetKeyVaultName
$targetCertNames = $targetCertificates | ForEach-Object { $_.name }

# Process certificates
Write-Log "Step 6: Processing certificates..." -Level "INFO"
foreach ($cert in $sourceCertificates) {
    $certName = $cert.name
    Write-Log "Processing certificate: $certName" -Level "DEBUG"
    
    try {
        # Retrieve full certificate details
        $fullCert = Get-KeyVaultCertificate $SourceSubscriptionId $SourceResourceGroup $SourceKeyVaultName $certName
        
        if (-not $fullCert) {
            Add-ErrorRecord "Failed to retrieve full certificate details" $certName "Certificate"
            $statistics.ErrorCount++
            continue
        }
        
        # Check if certificate is expired
        if (Test-IsExpired $fullCert) {
            Write-Log "Skipping expired certificate: $certName" -Level "WARN"
            $statistics.CertificatesExpired++
            $dryRunReport += @{
                Type = "Certificate"
                Name = $certName
                Status = "Skipped (Expired)"
                Reason = "Certificate has expired"
            }
            continue
        }
        
        # Check if certificate already exists in target
        if ($targetCertNames -contains $certName) {
            Write-Log "Certificate already exists in target vault, skipping: $certName" -Level "WARN"
            $statistics.CertificatesSkipped++
            $dryRunReport += @{
                Type = "Certificate"
                Name = $certName
                Status = "Skipped (Exists)"
                Reason = "Already exists in target"
            }
            continue
        }
        
        # Prepare metadata
        $metadata = @{
            Tags = $fullCert.tags
        }
        
        if ($DryRun) {
            Write-Log "DRY RUN: Would copy certificate: $certName" -Level "INFO"
            $dryRunReport += @{
                Type = "Certificate"
                Name = $certName
                Status = "Would Copy"
                Issuer = $fullCert.issuer
                Reason = "Valid, not expired, not duplicate"
            }
        }
        else {
            # Export certificate with private key via the secret (certificates
            # are stored as secrets in Key Vault with their private key).
            # Using 'certificate download' only gets the public cert.
            Set-AzureSubscription $SourceSubscriptionId | Out-Null
            $certSecret = az keyvault secret show --name $certName --vault-name $SourceKeyVaultName 2>&1 | ConvertFrom-Json
            
            if ($LASTEXITCODE -eq 0 -and $certSecret) {
                $certTempFile = Join-Path $env:TEMP "$certName.pfx"
                
                # Determine encoding and write to temp file
                if ($certSecret.contentType -eq "application/x-pkcs12") {
                    # Base64-encoded PFX
                    [System.IO.File]::WriteAllBytes($certTempFile, [System.Convert]::FromBase64String($certSecret.value))
                }
                else {
                    # PEM format - write as-is
                    $certTempFile = Join-Path $env:TEMP "$certName.pem"
                    Set-Content -Path $certTempFile -Value $certSecret.value -Encoding UTF8
                }
                
                # Import to target vault
                Set-AzureSubscription $TargetSubscriptionId | Out-Null
                $importArgs = @("keyvault", "certificate", "import", "--name", $certName, "--vault-name", $TargetKeyVaultName, "--file", $certTempFile)
                
                if ($metadata.Tags -and $metadata.Tags.Count -gt 0) {
                    $tagPairs = $metadata.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
                    $importArgs += @("--tags")
                    $importArgs += $tagPairs
                }
                
                $importResult = az @importArgs 2>&1
                
                Remove-Item $certTempFile -Force -ErrorAction SilentlyContinue
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Successfully copied certificate: $certName" -Level "SUCCESS"
                    $statistics.CertificatesProcessed++
                    $dryRunReport += @{
                        Type = "Certificate"
                        Name = $certName
                        Status = "Copied"
                        Issuer = $fullCert.issuer
                    }
                }
                else {
                    Add-ErrorRecord "Failed to import certificate: $($importResult -join ' ')" $certName "Certificate"
                    $statistics.ErrorCount++
                }
            }
            else {
                Add-ErrorRecord "Failed to export certificate secret (private key): ensure you have secrets/get permission" $certName "Certificate"
                $statistics.ErrorCount++
            }
        }
    }
    catch {
        Add-ErrorRecord "Unexpected error processing certificate: $_" $certName "Certificate"
        $statistics.ErrorCount++
    }
}

# Export dry-run report to CSV if applicable
if ($DryRun -and $dryRunReport.Count -gt 0) {
    $csvFile = Join-Path $LogDirectory "DryRun_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    $dryRunReport | ForEach-Object {
        [PSCustomObject]@{
            Type = $_.Type
            Name = $_.Name
            Status = $_.Status
            ContentType = $_.ContentType
            Issuer = $_.Issuer
            Reason = $_.Reason
        }
    } | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    
    Write-Log "Dry-run report exported to: $csvFile" -Level "INFO"
}

# Summary
Write-Log "========================================" -Level "INFO"
Write-Log "Duplication Summary" -Level "INFO"
Write-Log "========================================" -Level "INFO"
Write-Log "Secrets Processed:      $($statistics.SecretsProcessed)" -Level "INFO"
Write-Log "Secrets Skipped:        $($statistics.SecretsSkipped)" -Level "INFO"
Write-Log "Secrets Expired:        $($statistics.SecretsExpired)" -Level "INFO"
Write-Log "Certificates Processed: $($statistics.CertificatesProcessed)" -Level "INFO"
Write-Log "Certificates Skipped:   $($statistics.CertificatesSkipped)" -Level "INFO"
Write-Log "Certificates Expired:   $($statistics.CertificatesExpired)" -Level "INFO"

$endTime = Get-Date
$duration = $endTime - $startTime

Report-ErrorSummary $LogDirectory | Out-Null
Get-ExecutionSummary -SecretsProcessed $statistics.SecretsProcessed `
                      -SecretsSkipped $($statistics.SecretsSkipped + $statistics.SecretsExpired) `
                      -CertificatesProcessed $statistics.CertificatesProcessed `
                      -CertificatesSkipped $($statistics.CertificatesSkipped + $statistics.CertificatesExpired) `
                      -ErrorCount $statistics.ErrorCount `
                      -Duration $duration.ToString("hh\:mm\:ss")

exit 0

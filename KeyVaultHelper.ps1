# KeyVaultHelper.ps1
# Shared functions and utilities for Key Vault duplication scripts

$script:LogFile = $null
$script:VerboseLogging = $false
$script:Errors = @()

# ============================================================================
# Configuration Variables (Customize these at the top of calling scripts)
# ============================================================================
# Source Configuration
$script:SourceSubscriptionId = ""
$script:SourceResourceGroup = ""
$script:SourceKeyVaultName = ""

# Target Configuration
$script:TargetSubscriptionId = ""
$script:TargetResourceGroup = ""
$script:TargetKeyVaultName = ""

# Logging Configuration
$script:LogDirectory = "$(Get-Location)\Logs"

# ============================================================================
# Logging Functions
# ============================================================================

<#
.SYNOPSIS
Initializes the logging system
#>
function Initialize-Logging {
    param(
        [string]$LogDir = $script:LogDirectory,
        [bool]$Verbose = $false
    )
    
    $script:VerboseLogging = $Verbose
    $script:LogDirectory = $LogDir
    
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path $LogDir "KeyVault_$timestamp.log"
    
    Write-Log "=== Key Vault Duplication Script Started ===" -Level "INFO"
    Write-Log "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO"
    Write-Log "Verbose Logging: $Verbose" -Level "INFO"
    
    return $script:LogFile
}

<#
.SYNOPSIS
Writes a log message to both console and log file
#>
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Color coding for console
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor White }
        "WARN"    { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "DEBUG"   { 
            if ($script:VerboseLogging) {
                Write-Host $logMessage -ForegroundColor Cyan
            }
        }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Always write to log file
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage
    }
}

<#
.SYNOPSIS
Records an error for later reporting
#>
function Add-ErrorRecord {
    param(
        [string]$Message,
        [string]$ItemName = "",
        [string]$ItemType = ""
    )
    
    $errorRecord = @{
        Timestamp = Get-Date
        Message = $Message
        ItemName = $ItemName
        ItemType = $ItemType
    }
    
    $script:Errors += $errorRecord
    Write-Log "ERROR: $Message" -Level "ERROR"
}

<#
.SYNOPSIS
Gets all recorded errors
#>
function Get-ErrorSummary {
    return $script:Errors
}

<#
.SYNOPSIS
Clears all recorded errors
#>
function Clear-ErrorRecords {
    $script:Errors = @()
}

<#
.SYNOPSIS
Prints error summary and returns count
#>
function Report-ErrorSummary {
    param(
        [string]$LogDir = $script:LogDirectory
    )
    
    if ($script:Errors.Count -eq 0) {
        Write-Log "=== No errors encountered ===" -Level "SUCCESS"
        return 0
    }
    
    Write-Log "=== ERROR SUMMARY ===" -Level "ERROR"
    Write-Log "Total Errors: $($script:Errors.Count)" -Level "ERROR"
    
    $script:Errors | ForEach-Object {
        Write-Log "  [$($_.Timestamp.ToString('HH:mm:ss'))] $($_.ItemType) '$($_.ItemName)': $($_.Message)" -Level "ERROR"
    }
    
    return $script:Errors.Count
}

# ============================================================================
# Azure Authentication Functions
# ============================================================================

<#
.SYNOPSIS
Tests Azure CLI connectivity and validates subscriptions
#>
function Test-AzureCliConnection {
    param(
        [string]$SourceSubscriptionId,
        [string]$TargetSubscriptionId
    )
    
    Write-Log "Testing Azure CLI connection..." -Level "INFO"
    
    try {
        $currentAccount = az account show 2>$null | ConvertFrom-Json
        if (-not $currentAccount) {
            Write-Log "Not logged in to Azure. Please run 'az login' first." -Level "ERROR"
            return $false
        }
        
        Write-Log "Logged in as: $($currentAccount.user.name)" -Level "INFO"
        Write-Log "Current subscription: $($currentAccount.name) ($($currentAccount.id))" -Level "DEBUG"
    }
    catch {
        Add-ErrorRecord "Failed to check Azure CLI connection: $_" "" "Connection"
        return $false
    }
    
    return $true
}

<#
.SYNOPSIS
Sets Azure CLI subscription context
#>
function Set-AzureSubscription {
    param(
        [string]$SubscriptionId
    )
    
    Write-Log "Setting subscription to: $SubscriptionId" -Level "DEBUG"
    
    try {
        az account set --subscription $SubscriptionId 2>&1 | Out-Null
        $current = az account show 2>$null | ConvertFrom-Json
        Write-Log "Subscription set to: $($current.name)" -Level "DEBUG"
        return $true
    }
    catch {
        Add-ErrorRecord "Failed to set subscription: $_" $SubscriptionId "Subscription"
        return $false
    }
}

# ============================================================================
# Key Vault Access Functions
# ============================================================================

<#
.SYNOPSIS
Tests if a Key Vault is accessible
#>
function Test-KeyVaultAccess {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName
    )
    
    Write-Log "Testing access to Key Vault: $VaultName (Sub: $SubscriptionId, RG: $ResourceGroup)" -Level "DEBUG"
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return $false
    }
    
    try {
        az keyvault show --name $VaultName --resource-group $ResourceGroup 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Add-ErrorRecord "Cannot access Key Vault: $VaultName" $VaultName "KeyVault"
            return $false
        }
        
        Write-Log "Successfully accessed Key Vault: $VaultName" -Level "DEBUG"
        return $true
    }
    catch {
        Add-ErrorRecord "Error accessing Key Vault: $_" $VaultName "KeyVault"
        return $false
    }
}

<#
.SYNOPSIS
Gets a secret from Key Vault
#>
function Get-KeyVaultSecret {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName,
        [string]$SecretName
    )
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return $null
    }
    
    try {
        $secret = az keyvault secret show --name $SecretName --vault-name $VaultName 2>&1 | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to retrieve secret: $SecretName" -Level "WARN"
            return $null
        }
        
        Write-Log "Retrieved secret: $SecretName" -Level "DEBUG"
        return $secret
    }
    catch {
        Add-ErrorRecord "Error retrieving secret $SecretName : $_" $SecretName "Secret"
        return $null
    }
}

<#
.SYNOPSIS
Sets a secret in Key Vault
#>
function Set-KeyVaultSecret {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName,
        [string]$SecretName,
        [string]$SecretValue,
        [hashtable]$Metadata = @{}
    )
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return $false
    }
    
    try {
        $cmdArgs = @("keyvault", "secret", "set", "--name", $SecretName, "--vault-name", $VaultName, "--value", $SecretValue)
        
        # Add metadata if provided
        if ($Metadata.ContentType) {
            $cmdArgs += @("--content-type", $Metadata.ContentType)
        }
        
        if ($Metadata.Tags -and $Metadata.Tags.Count -gt 0) {
            $tagPairs = $Metadata.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
            $cmdArgs += @("--tags")
            $cmdArgs += $tagPairs
        }
        
        $result = az @cmdArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Add-ErrorRecord "Failed to set secret: $($result -join ' ')" $SecretName "Secret"
            return $false
        }
        
        Write-Log "Set secret: $SecretName" -Level "DEBUG"
        return $true
    }
    catch {
        Add-ErrorRecord "Error setting secret $SecretName : $_" $SecretName "Secret"
        return $false
    }
}

<#
.SYNOPSIS
Gets a certificate from Key Vault
#>
function Get-KeyVaultCertificate {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName,
        [string]$CertificateName
    )
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return $null
    }
    
    try {
        $cert = az keyvault certificate show --name $CertificateName --vault-name $VaultName 2>&1 | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to retrieve certificate: $CertificateName" -Level "WARN"
            return $null
        }
        
        Write-Log "Retrieved certificate: $CertificateName" -Level "DEBUG"
        return $cert
    }
    catch {
        Add-ErrorRecord "Error retrieving certificate $CertificateName : $_" $CertificateName "Certificate"
        return $null
    }
}

<#
.SYNOPSIS
Imports a certificate to Key Vault from PEM data
#>
function Import-KeyVaultCertificate {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName,
        [string]$CertificateName,
        [string]$CertificateData,
        [hashtable]$Metadata = @{}
    )
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return $false
    }
    
    try {
        # Write certificate to temp file
        $tempFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tempFile -Value $CertificateData -Encoding UTF8
        
        $cmdArgs = @("keyvault", "certificate", "import", "--name", $CertificateName, "--vault-name", $VaultName, "--file", $tempFile)
        
        if ($Metadata.Tags -and $Metadata.Tags.Count -gt 0) {
            $tagPairs = $Metadata.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
            $cmdArgs += @("--tags")
            $cmdArgs += $tagPairs
        }
        
        $result = az @cmdArgs 2>&1
        
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -ne 0) {
            Add-ErrorRecord "Failed to import certificate: $($result -join ' ')" $CertificateName "Certificate"
            return $false
        }
        
        Write-Log "Imported certificate: $CertificateName" -Level "DEBUG"
        return $true
    }
    catch {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Add-ErrorRecord "Error importing certificate $CertificateName : $_" $CertificateName "Certificate"
        return $false
    }
}

<#
.SYNOPSIS
Lists all secrets in a Key Vault
#>
function Get-AllKeyVaultSecrets {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName
    )
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return @()
    }
    
    try {
        $secrets = @(az keyvault secret list --vault-name $VaultName 2>&1 | ConvertFrom-Json)
        Write-Log "Retrieved $($secrets.Count) secrets from $VaultName" -Level "INFO"
        return $secrets
    }
    catch {
        Add-ErrorRecord "Error listing secrets from $VaultName : $_" $VaultName "KeyVault"
        return @()
    }
}

<#
.SYNOPSIS
Lists all certificates in a Key Vault
#>
function Get-AllKeyVaultCertificates {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName
    )
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return @()
    }
    
    try {
        $certs = @(az keyvault certificate list --vault-name $VaultName 2>&1 | ConvertFrom-Json)
        Write-Log "Retrieved $($certs.Count) certificates from $VaultName" -Level "INFO"
        return $certs
    }
    catch {
        Add-ErrorRecord "Error listing certificates from $VaultName : $_" $VaultName "KeyVault"
        return @()
    }
}

# ============================================================================
# RBAC Permission Functions
# ============================================================================

<#
.SYNOPSIS
Gets current user's RBAC role assignments for a Key Vault
#>
function Get-UserRoleAssignments {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName
    )
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return @()
    }
    
    try {
        $vaultId = az keyvault show --name $VaultName --resource-group $ResourceGroup --query "id" -o tsv 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Add-ErrorRecord "Failed to get Key Vault resource ID" $VaultName "KeyVault"
            return @()
        }
        
        $currentUser = az account show --query "user.name" -o tsv 2>&1
        
        # Get role assignments for the current user on this Key Vault
        $roleAssignments = az role assignment list --scope $vaultId --assignee $currentUser 2>&1 | ConvertFrom-Json
        
        return $roleAssignments
    }
    catch {
        Add-ErrorRecord "Error retrieving role assignments: $_" "" "RBAC"
        return @()
    }
}

<#
.SYNOPSIS
Tests specific Key Vault permissions via API calls
#>
function Test-KeyVaultPermissions {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$VaultName,
        [string[]]$PermissionsToTest = @("secrets/get", "secrets/set", "secrets/list", "certificates/get", "certificates/import", "certificates/list")
    )
    
    Write-Log "Testing Key Vault permissions for: $VaultName" -Level "INFO"
    
    if (-not (Set-AzureSubscription $SubscriptionId)) {
        return @{}
    }
    
    $permissionResults = @{}
    
    try {
        # Test by attempting real operations
        $testSecret = "test-permission-check-$(Get-Random -Minimum 1000 -Maximum 9999)"
        
        # Test GET
        $permissionResults["secrets/get"] = $false
        $testSecrets = @(Get-AllKeyVaultSecrets $SubscriptionId $ResourceGroup $VaultName)
        if ($testSecrets.Count -ge 0) {
            $permissionResults["secrets/get"] = $true
        }
        
        # Test LIST
        $permissionResults["secrets/list"] = $permissionResults["secrets/get"]
        
        # Test SET (try to set a test secret, then delete and purge it)
        $permissionResults["secrets/set"] = $false
        az keyvault secret set --vault-name $VaultName --name $testSecret --value "test" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $permissionResults["secrets/set"] = $true
            az keyvault secret delete --vault-name $VaultName --name $testSecret 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            az keyvault secret purge --vault-name $VaultName --name $testSecret 2>&1 | Out-Null
        }
        
        # Test certificates
        $permissionResults["certificates/get"] = $false
        $permissionResults["certificates/list"] = $false
        $testCerts = @(Get-AllKeyVaultCertificates $SubscriptionId $ResourceGroup $VaultName)
        if ($testCerts.Count -ge 0) {
            $permissionResults["certificates/get"] = $true
            $permissionResults["certificates/list"] = $true
        }
        
        $permissionResults["certificates/import"] = $false
        # Attempting import will be tested during the actual copy operation
        
    }
    catch {
        Add-ErrorRecord "Error testing permissions: $_" $VaultName "Permissions"
    }
    
    return $permissionResults
}

# ============================================================================
# CSV Export Functions
# ============================================================================

<#
.SYNOPSIS
Exports an array of objects to CSV
#>
function Export-ToCsv {
    param(
        [array]$Data,
        [string]$FilePath,
        [array]$Properties = @()
    )
    
    try {
        if ($Properties.Count -gt 0) {
            $Data | Select-Object -Property $Properties | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
        }
        else {
            $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
        }
        
        Write-Log "Exported to CSV: $FilePath" -Level "INFO"
        return $true
    }
    catch {
        Add-ErrorRecord "Failed to export CSV: $_" $FilePath "Export"
        return $false
    }
}

# ============================================================================
# Utility Functions
# ============================================================================

<#
.SYNOPSIS
Checks if a secret/certificate is expired
#>
function Test-IsExpired {
    param(
        [object]$Item
    )
    
    if ($Item.attributes.expires) {
        try {
            $expiryTime = [datetime]::Parse($Item.attributes.expires)
            return $expiryTime -lt (Get-Date)
        }
        catch {
            Write-Log "Unable to parse expiry date: $($Item.attributes.expires)" -Level "WARN"
            return $false
        }
    }
    
    return $false
}

<#
.SYNOPSIS
Gets a formatted summary of script execution
#>
function Get-ExecutionSummary {
    param(
        [int]$SecretsProcessed = 0,
        [int]$SecretsSkipped = 0,
        [int]$CertificatesProcessed = 0,
        [int]$CertificatesSkipped = 0,
        [int]$ErrorCount = 0,
        [string]$Duration = ""
    )
    
    $summary = @"
==========================================
         EXECUTION SUMMARY
==========================================
Secrets Processed:      $SecretsProcessed
Secrets Skipped:        $SecretsSkipped
Certificates Processed: $CertificatesProcessed
Certificates Skipped:   $CertificatesSkipped
Errors:                 $ErrorCount
Duration:               $Duration
Log File:               $script:LogFile
==========================================
"@
    
    Write-Host $summary
    Add-Content -Path $script:LogFile -Value $summary
}

# Note: This file is dot-sourced (not imported as a module), so all
# functions above are automatically available in the calling script's scope.

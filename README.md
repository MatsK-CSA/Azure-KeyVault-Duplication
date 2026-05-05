# Azure Key Vault Duplication Scripts

A comprehensive PowerShell solution for duplicating secrets and certificates from a source Azure Key Vault to a target Key Vault with validation and comprehensive logging.

## Overview

This solution consists of four components:

1. **KeyVaultHelper.ps1** - Shared utility module with common functions
2. **Validate-KeyVaultPermissions.ps1** - Validates user has required permissions
3. **Copy-KeyVaultSecrets.ps1** - Performs the actual duplication with dry-run support
4. **Validate-DuplicationComplete.ps1** - Audits and validates the duplication

## Prerequisites

- PowerShell 5.1 or later (Windows) / PowerShell 7+ (Cross-platform)
- Azure CLI installed and in PATH
- Active Azure subscription with at least one Key Vault
- `az login` executed and authenticated

### Installation

```bash
# Install Azure CLI (if not already installed)
# Windows:
choco install azure-cli

# macOS:
brew install azure-cli

# Linux: Follow https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux
```

### Authentication

```powershell
# Login to Azure
az login

# Optionally set your default subscription
az account set --subscription "SUBSCRIPTION_ID"
```

## Quick Start

### 1. Configure Variables

Edit each script and update the configuration section at the top:

```powershell
# Source Key Vault Configuration
$SourceSubscriptionId = "YOUR_SOURCE_SUBSCRIPTION_ID"
$SourceResourceGroup = "YOUR_SOURCE_RESOURCE_GROUP"
$SourceKeyVaultName = "YOUR_SOURCE_KEYVAULT_NAME"

# Target Key Vault Configuration
$TargetSubscriptionId = "YOUR_TARGET_SUBSCRIPTION_ID"
$TargetResourceGroup = "YOUR_TARGET_RESOURCE_GROUP"
$TargetKeyVaultName = "YOUR_TARGET_KEYVAULT_NAME"
```

### 2. Validate Permissions

```powershell
# Check if you have required permissions on both vaults
.\Validate-KeyVaultPermissions.ps1

# With verbose output
.\Validate-KeyVaultPermissions.ps1 -Verbose
```

Expected output:
```
[PASS] All required permissions are available!
```

### 3. Perform Dry Run (Recommended)

```powershell
# Preview what will be copied without making changes
.\Copy-KeyVaultSecrets.ps1 -DryRun

# With verbose output
.\Copy-KeyVaultSecrets.ps1 -DryRun -Verbose
```

This generates a CSV report: `Logs\DryRun_Report_YYYYMMDD_HHMMSS.csv`

Review the report to ensure:
- All expected secrets/certificates are listed as "Would Copy"
- No unexpected items
- Skipped items have valid reasons

### 4. Execute Duplication

```powershell
# Perform actual duplication (after successful dry-run)
.\Copy-KeyVaultSecrets.ps1

# With verbose output
.\Copy-KeyVaultSecrets.ps1 -Verbose
```

### 5. Validate Results

```powershell
# Verify duplication was successful
.\Validate-DuplicationComplete.ps1

# Compare metadata as well
.\Validate-DuplicationComplete.ps1 -CompareMetadata

# With verbose output
.\Validate-DuplicationComplete.ps1 -Verbose
```

Expected output:
```
[PASS] Validation PASSED - Duplication is complete!
```

## Usage Examples

### Example 1: Duplicate within same subscription (different resource groups)

```powershell
# Configure scripts
$SourceSubscriptionId = "12345678-1234-1234-1234-123456789012"
$SourceResourceGroup = "rg-prod"
$SourceKeyVaultName = "kv-prod-source"

$TargetSubscriptionId = "12345678-1234-1234-1234-123456789012"  # Same
$TargetResourceGroup = "rg-backup"
$TargetKeyVaultName = "kv-prod-backup"

# Run workflow
.\Validate-KeyVaultPermissions.ps1 -Verbose
.\Copy-KeyVaultSecrets.ps1 -DryRun -Verbose
# Review CSV report
.\Copy-KeyVaultSecrets.ps1 -Verbose
.\Validate-DuplicationComplete.ps1 -Verbose
```

### Example 2: Cross-subscription duplication

```powershell
# Configure scripts
$SourceSubscriptionId = "prod-sub-guid"      # Production subscription
$SourceResourceGroup = "rg-prod"
$SourceKeyVaultName = "kv-prod"

$TargetSubscriptionId = "dr-sub-guid"        # Disaster recovery subscription
$TargetResourceGroup = "rg-dr"
$TargetKeyVaultName = "kv-dr"

# Login as user with access to both subscriptions
az login

# Run workflow with extra care on validation
.\Validate-KeyVaultPermissions.ps1 -Verbose
# This should pass for BOTH subscriptions
```

## Script Reference

### Validate-KeyVaultPermissions.ps1

**Purpose**: Validate the current user has sufficient permissions on both source and target Key Vaults.

**Parameters**:
- `-Verbose` : Enable detailed logging output

**Output**:
- Console: Permission check results
- Log file: `Logs\KeyVault_YYYYMMDD_HHMMSS.log`

**Exit Codes**:
- `0` : All permissions valid
- `1` : Missing permissions

**Permissions Validated**:
- **Source**: `secrets/get`, `secrets/list`, `certificates/get`, `certificates/list`
- **Target**: `secrets/set`, `secrets/list`, `certificates/import`, `certificates/list`

### Copy-KeyVaultSecrets.ps1

**Purpose**: Duplicate secrets and certificates from source to target Key Vault.

**Parameters**:
- `-DryRun` : Preview without making changes (generates CSV report)
- `-Verbose` : Enable detailed logging output

**Output**:
- Console: Progress updates
- Log file: `Logs\KeyVault_YYYYMMDD_HHMMSS.log`
- CSV report (dry-run only): `Logs\DryRun_Report_YYYYMMDD_HHMMSS.csv`

**Behavior**:
- Skips secrets/certificates that already exist in target (with warning)
- Skips expired secrets/certificates (with report)
- Copies all metadata: tags, content type, enabled/disabled state
- Copies current version only (for certificates)
- Accumulates errors and reports summary at end

**Data Copied**:
- Secret name, value, content type, tags, enabled state
- Certificate name, full certificate with private key (via secret-based export), tags, enabled state

### Validate-DuplicationComplete.ps1

**Purpose**: Audit and validate that secrets/certificates were successfully duplicated.

**Parameters**:
- `-CompareMetadata` : Also validate that metadata matches between source and target
- `-Verbose` : Enable detailed logging output

**Output**:
- Console: Validation results with differences
- Log file: `Logs\KeyVault_YYYYMMDD_HHMMSS.log`
- CSV report: `Logs\Validation_Report_YYYYMMDD_HHMMSS.csv`

**Exit Codes**:
- `0` : Validation passed
- `1` : Differences detected

**Report CSV Columns**:
- Type: Secret or Certificate
- Name: Item name
- InSource: Yes/No
- InTarget: Yes/No
- Status: OK, MISSING, or EXTRA

## Logging

All scripts generate detailed logs in the `Logs` subdirectory:

```
Logs/
├── KeyVault_20260505_143022.log      # Main execution log
├── DryRun_Report_20260505_143022.csv # Dry-run CSV (if -DryRun used)
└── Validation_Report_20260505_143022.csv # Validation CSV (if validation run)
```

Log file format:
```
[2026-05-05 14:30:22] [INFO] Key Vault Duplication Script
[2026-05-05 14:30:22] [DEBUG] Processing secret: my-secret-1
[2026-05-05 14:30:23] [ERROR] Failed to retrieve secret: my-secret-2
```

## Common Issues & Troubleshooting

### "Not logged in to Azure"
```powershell
# Solution: Run az login
az login
```

### "Cannot access Key Vault"
**Causes**:
1. Subscription ID is incorrect
2. Resource group name is incorrect
3. Key Vault name is incorrect (case-sensitive)
4. User lacks RBAC permissions

**Diagnosis**:
```powershell
# Verify vault exists and you can see it
az keyvault list --resource-group "YOUR_RG"

# Verify current subscription
az account show

# Check role assignments
az role assignment list --scope "/subscriptions/YOUR_SUB/resourceGroups/YOUR_RG/providers/Microsoft.KeyVault/vaults/YOUR_KV"
```

### "Missing permissions: secrets/set"
**Cause**: User lacks permission to set secrets in target Key Vault.

**Solution**: Request one of these Azure roles on the target Key Vault:
- `Key Vault Administrator` (full access)
- `Key Vault Secrets Officer` (for secrets only)
- `Key Vault Certificates Officer` (for certificates only)

Assign via Azure Portal or CLI:
```powershell
az role assignment create --role "Key Vault Administrator" --assignee "user@example.com" --scope "/subscriptions/SUB_ID/resourceGroups/RG_NAME/providers/Microsoft.KeyVault/vaults/KV_NAME"
```

### "Certificate is expired"
**Behavior**: Script skips expired certificates and reports them.

**Options**:
1. Renew the certificate in the source vault before running duplication
2. Manually copy the expired certificate if needed
3. Leave it skipped (duplication will not copy it)

### "DryRun CSV is empty"
**Cause**: All secrets/certificates already exist in target or all are expired.

**Check**:
```powershell
# See what's in source
az keyvault secret list --vault-name "SOURCE_KV"
az keyvault certificate list --vault-name "SOURCE_KV"

# See what's in target
az keyvault secret list --vault-name "TARGET_KV"
az keyvault certificate list --vault-name "TARGET_KV"
```

### Scripts slow on large vaults (1000+ items)
**Cause**: Sequential processing of many items.

**Mitigation**:
- Consider splitting scripts across multiple runs with different name filters (advanced)
- Ensure good network connectivity to Azure
- Use `-Verbose` to monitor progress

## Access Policy vs RBAC

Azure Key Vault supports two access models:

1. **RBAC** (Recommended for new vaults) - Role-based access using Azure roles
   - Scripts use Azure CLI commands that respect RBAC
   - Configure via Azure Portal → Access Control (IAM)

2. **Access Policies** (Legacy) - Custom per-key-vault policies
   - Scripts may have limited functionality with Access Policies only
   - If vault uses Access Policies, ensure the policy grants: `Get`, `Set`, `List` on both secrets and certificates

**Check which model your vault uses**:
```powershell
az keyvault show --name "YOUR_KV" --query "properties.enableRbacAuthorization"
```

Output: `true` (RBAC enabled) or `false` (Access Policies)

## Performance & Limits

- Azure Key Vault rate limit: ~2000 requests per 10 seconds
- Scripts process items sequentially to maintain auditability
- Typical duplication rate: 5-10 secrets/certificates per second
- Estimated time for 100 items: ~15-30 seconds

## Security Considerations

1. **Secrets in Logs**: Log files may contain sensitive information (error messages with secret names)
   - Store logs securely
   - Restrict access to `Logs` directory
   - Consider deleting logs after validation

2. **Audit Trail**: All duplication operations are logged
   - Log files include timestamp and user identity
   - Suitable for compliance/audit purposes

3. **Temporary Files**: Scripts create temporary certificate files in `$env:TEMP`
   - Automatically cleaned up after import
   - Consider disk encryption for sensitive environments

4. **Dry-Run CSV**: CSV report contains item names (but not values)
   - Review carefully before sharing

## Advanced Usage

### Resume After Failure

If duplication fails partway through:

1. Check the error log for what failed
2. Manually fix the issue (e.g., grant missing permission)
3. Run the copy script again
   - It will skip items already in target (avoiding duplicates)
   - It will continue with failed items

### Extract Dry-Run Report

```powershell
# Get the latest dry-run CSV
$latestReport = Get-ChildItem -Path "Logs\DryRun_Report*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

# Open in Excel
$latestReport | Invoke-Item

# Or import to PowerShell for analysis
$dryRunData = Import-Csv $latestReport.FullName
$dryRunData | Where-Object Status -eq "Would Copy" | Measure-Object
```

### Custom RBAC Roles

If user has a custom role, ensure it grants:
- `Microsoft.KeyVault/vaults/secrets/read`
- `Microsoft.KeyVault/vaults/secrets/write`
- `Microsoft.KeyVault/vaults/certificates/read`
- `Microsoft.KeyVault/vaults/certificates/import`

## Support & Troubleshooting

If scripts fail:

1. **Enable verbose logging**:
   ```powershell
   .\Copy-KeyVaultSecrets.ps1 -Verbose
   ```

2. **Review the log file**:
   ```powershell
   $latestLog = Get-ChildItem -Path "Logs\KeyVault*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
   Get-Content $latestLog.FullName -Tail 50
   ```

3. **Verify Azure CLI works independently**:
   ```powershell
   az keyvault secret list --vault-name "SOURCE_KV"
   ```

4. **Check permissions directly**:
   ```powershell
   .\Validate-KeyVaultPermissions.ps1 -Verbose
   ```

## Recommended Workflow

1. ✅ **Start with validation** (checks permissions without making changes)
   ```powershell
   .\Validate-KeyVaultPermissions.ps1 -Verbose
   ```

2. ✅ **Run dry-run first** (previews without changes, generates CSV)
   ```powershell
   .\Copy-KeyVaultSecrets.ps1 -DryRun -Verbose
   # Review Logs\DryRun_Report*.csv
   ```

3. ✅ **Execute duplication** (makes actual changes after dry-run verification)
   ```powershell
   .\Copy-KeyVaultSecrets.ps1 -Verbose
   ```

4. ✅ **Validate results** (audits the duplication)
   ```powershell
   .\Validate-DuplicationComplete.ps1 -CompareMetadata -Verbose
   # Review Logs\Validation_Report*.csv
   ```

5. ✅ **Archive logs** (for compliance/audit trail)
   ```powershell
   Compress-Archive -Path "Logs" -DestinationPath "Archive_$(Get-Date -Format 'yyyyMMdd').zip"
   ```

## What This Solution Handles

✅ Validates user permissions before operations  
✅ Skips expired secrets and certificates  
✅ Skips duplicates (items already in target)  
✅ Preserves all metadata (tags, enabled state, content type)  
✅ Handles large vaults (100+, 1000+ items)  
✅ Provides dry-run capability with CSV report  
✅ Accumulates errors and reports summary  
✅ Generates audit-trail logs  
✅ Validates duplication completeness  
✅ Cross-subscription support  
✅ Cross-region support (same subscription)  
✅ Verbose logging for troubleshooting  

## What You Should Consider

⚠️ **Certificate dependencies** - If certificates reference other resources, validate manually  
⚠️ **Cross-tenant scenarios** - Not currently supported; would require separate authentication contexts  
⚠️ **Soft-deleted items** - Script ignores soft-deleted items; recover in Azure Portal if needed  
⚠️ **Access Policies only** - If vault uses legacy Access Policies (not RBAC), additional setup may be needed  
⚠️ **Retention policies** - Target vault may have different retention settings; consider alignment  
⚠️ **Cost implications** - Duplication doesn't incur extra Key Vault costs (read/write operations are metered)  

## Version History

- **v1.0** (2026-05-05)
  - Initial release
  - Support for secrets and certificates (current version only)
  - Dry-run mode with CSV export
  - Comprehensive validation and logging
  - Cross-subscription support

## Disclaimer

Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys' fees, that arise or result from the use or distribution of the Sample Code.

## Questions?

For issues or questions:
1. Review the troubleshooting section above
2. Check log files in `Logs\` directory
3. Verify permissions with `Validate-KeyVaultPermissions.ps1`
4. Run scripts with `-Verbose` flag for detailed diagnostics

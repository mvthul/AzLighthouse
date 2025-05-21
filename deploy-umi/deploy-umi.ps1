<#
.SYNOPSIS
  Deploys a User Managed Identity (UMI) for Sentinel ingestion.
.DESCRIPTION
  This script deploys a User Managed Identity (UMI) for Sentinel ingestion. It creates a resource group,
  registers the required Azure Resource Providers, installs the required PowerShell modules, and assigns
  permissions to the UMI. It also creates a service principal and assigns the required permissions for
  the UMI to manage the service principal.
.PARAMETER CustomerPrefix
  The customer prefix name. This is used to create the resource group name.
.PARAMETER SubscriptionId
  The subscription ID where the UMI will be deployed.
.PARAMETER AzRegion
  The Azure region where the UMI will be deployed. Default is 'eastus'.

#>
[CmdletBinding()]
param (
  [Parameter()]
  [string] $CustomerPrefix,
  [Parameter()]
  [string] $SubscriptionId,
  [Parameter()]
  [string] $AzRegion = 'eastus'
)

do {
  $customerPrefix = Read-Host 'Enter customer prefix name: '
} while ($customerPrefix.Length -lt 3)

do {
  $subscription = Read-Host 'Enter the subscription id: '
} while ($subscription.Length -lt 36)

$umiName = 'MSSP-Sentinel-Ingestion-UMI'
$rg = "$($customerPrefix)-Sentinel-Prod-rg"

# Install the required PowerShell modules
Install-Module Az.Resources -Scope CurrentUser -SkipPublisherCheck -Force -AllowClobber -AcceptLicense
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -SkipPublisherCheck -Force -AllowClobber -AcceptLicense
Install-Module Microsoft.Graph.Applications -Scope CurrentUser -SkipPublisherCheck -Force -AllowClobber -AcceptLicense

# Add required Azure Resource Providers
Register-AzResourceProvider -ProviderNamespace Microsoft.Insights
Register-AzResourceProvider -ProviderNamespace Microsoft.ManagedServices
Register-AzResourceProvider -ProviderNamespace Microsoft.ManagedIdentity

# Default resource group for managed identities
$graphAppId = '00000003-0000-0000-c000-000000000000' # Don't change this.
# Get the context of the current subscription
$subscriptionId = (Get-AzContext).Subscription.Id
$scope = "/subscriptions/$($subscriptionId)"
# Azure RBAC role IDs needed
$azureOwnerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' # This is Owner.
$azureKVAdminRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74483' # This is Key Vault Administrator.
$azureKVUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6' # This is Key Vault Secrets User.
$metricsPubRoleId = '3913510d-42f4-4e42-8a64-420c390055eb' # This is Monitoring Metrics Publisher.

# Create resource group if needed.
if ([string]::IsNullOrEmpty((Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue))) {
  New-AzResourceGroup -Name $rg -Location $azRegion
}

# Create user managed identity
$null = New-AzUserAssignedIdentity -Name $umiName -ResourceGroupName $rg -Location $AzRegion
$umi = Get-AzADServicePrincipal -DisplayName $umiName

Connect-AzureAD -TenantId $context.Tenant.ID
# If Connect-AzureAd does not work, run 'Connect-AzureAD -TenantId <CustomerTenantId>'
Start-Sleep 10

# Assign User Assigned Identity Owner permissions to the subscription
New-AzRoleAssignment -RoleDefinitionId $azureOwnerRoleId -ObjectId $umi.Id -Scope $scope
Start-Sleep 5
New-AzRoleAssignment -RoleDefinitionId $azureKVAdminRoleId -ObjectId $umi.Id -Scope $scope
Start-Sleep 5
New-AzRoleAssignment -RoleDefinitionId $azureKVUserRoleId -ObjectId $umi.Id -Scope $scope
Start-Sleep 5

# Create the service principal/app registration
New-AzADServicePrincipal -DisplayName $AppName
Start-Sleep 20
$adsp = Get-AzADServicePrincipal -DisplayName $AppName

# Assign the UMI Monitoring Metrics Publisher role to the subscription.
# This role is required to allow the UMI to publish data to Azure Sentinel/Azure Monitor.

New-AzRoleAssignment -RoleDefinitionId $metricsPubRoleId -ObjectId $adsp.Id -Scope $Subscription

# Assign UMI permissions to read applications and manage owned applications.
$graphSP = Get-AzADServicePrincipal -appId $graphAppId
# Graph API permissions to set
$addPermissions = @(
  'Application.ReadWrite.OwnedBy',
  'Application.Read.All'
)
$appRoles = $graphSP.AppRole |
  Where-Object { ($_.Value -in $addPermissions) -and ($_.AllowedMemberType -contains 'Application') }
$appRoles | ForEach-Object {
  New-AzureAdServiceAppRoleAssignment -ObjectId $umi.Id -PrincipalId $umi.Id -ResourceId $graphSp.Id -Id $_.Id
}

# Make sure the UMI is set as the owner of the application. This is required to allow
# the UMI to manage the app registration.
$newOwner = @{
  '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/{$($Umi.Id)}"
}

# Connect to Microsoft Graph. You will need to complete the authentication outside the shell.
Connect-MgGraph -Scopes 'Application.ReadWrite.All', 'Directory.Read.All' -NoWelcome

# This adds the UMI as an owner
New-MgApplicationOwnerByRef -ApplicationId $Id -BodyParameter $newOwner
# This will update the name to be in line with our new standard name
Update-MgApplication -ApplicationId $Id -DisplayName 'MSSP-Sentinel-Ingestion'

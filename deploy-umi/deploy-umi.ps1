[CmdletBinding()]
param (
  [Parameter()]
  [string] $CustomerPrefix,
  [Parameter()]
  [string] $SubscriptionId,
  [Parameter()]
  [string] $AzureRegion = "eastus"
)

do {
  $customerPrefix = Read-Host "Enter customer prefix name: "
} while ($customerPrefix.Length -lt 3)

do {
  $subscription = Read-Host "Enter the subscription id: "
} while ($subscription.Length -lt 36)

$umiName = "MSSP-Sentinel-Ingestion-UMI"
$rg = "$($customerPrefix)-Sentinel-Prod-rg"
  
# Add required Azure Resource Providers
Register-AzResourceProvider -ProviderNamespace Microsoft.Insights
Register-AzResourceProvider -ProviderNamespace Microsoft.ManagedServices
Register-AzResourceProvider -ProviderNamespace Microsoft.ManagedIdentity
# Default resource group for managed identities
  
$graphAppId = "00000003-0000-0000-c000-000000000000" # Don't change this.
  
# Graph API permissions to set
$addPermissions = @(
  "Application.ReadWrite.OwnedBy"
)

$subscriptionId = (Get-AzContext).Subscription.Id
$scope = "/subscriptions/$($subscriptionId)"
$azureOwnerRoleId = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635" # This is Owner.
$azureKVAdminRoleId = "00482a5a-887f-4fb3-b363-3b7fe8e74483" # This is Key Vault Administrator.
$azureKVUserRoleId = "4633458b-17de-408a-b874-0445c86b69e6" # This is Key Vault Secrets User.
  
# Create resource group if needed.
if ([string]::IsNullOrEmpty((Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue))) {
  New-AzResourceGroup -Name $rg -Location $azRegion
}
  
# Create user managed identity
$null = New-AzUserAssignedIdentity -Name $umiName -ResourceGroupName $rg -Location $AzRegion
$umi = Get-AzAdServicePrincipal -DisplayName $umiName
# Assign permissions to allow creating service principals.
$graphSP = Get-AzADServicePrincipal -appId $graphAppId
$appRoles = $graphSP.AppRole | Where-Object { ($_.Value -in $addPermissions) -and ($_.AllowedMemberType -contains "Application") }
  
Connect-AzureAD -TenantId $context.Tenant.Id
# If Connect-AzureAd does not work, run 'Connect-AzureAD -TenantId <CustomerTenantId>'
Start-Sleep 10
  
# Assign User Assigned Identity Owner permissions to the subscription 
New-AzRoleAssignment -RoleDefinitionId $azureOwnerRoleId -ObjectId $umi.Id -Scope $scope
Start-Sleep 5
New-AzRoleAssignment -RoleDefinitionId $azureKVAdminRoleId -ObjectId $umi.Id -Scope $scope
Start-Sleep 5
New-AzRoleAssignment -RoleDefinitionId $azureKVUserRoleId -ObjectId $umi.Id -Scope $scope
Start-Sleep 5
  
# This requires permissions to assign app roles so may need to be rerun by an administrator. Have them run the following
#Connect-AzureAD -TenantId $context.Tenant.Id
  
# Graph API permissions to set
$addPermissions = @(
  "Application.ReadWrite.OwnedBy"
)
  
$appRoles | ForEach-Object { New-AzureAdServiceAppRoleAssignment -ObjectId $umi.Id -PrincipalId $umi.Id -ResourceId $graphSp.Id -Id $_.Id }

New-AzAdServicePrincipal -DisplayName $AppName
Start-Sleep 20
$adsp = Get-AzAdServicePrincipal -DisplayName $AppName
New-AzRoleAssignment -RoleDefinitionId '3913510d-42f4-4e42-8a64-420c390055eb' -ObjectId $adsp.Id -Scope $Subscription


# Make sure the UMI is set as the owner of the application. This is required to allow the UMI to manage the app registration.
$NewOwner = @{
  "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$($Umi.Id)}"
}
# This adds the UMI as an owner
New-MgApplicationOwnerByRef -ApplicationId $Id -BodyParameter $NewOwner
# This will update the name to be in line with our new standard name
Update-MgApplication -ApplicationId $Id -DisplayName "MSSP-Sentinel-Ingestion"
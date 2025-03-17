[CmdletBinding()]
param (
    [Parameter()]
    [string] $CustomerPrefix,
    [Parameter()]
    [string] $SubscriptionId,
    [Parameter()]
    [string] $AzureRegion = "eastus",
    [Parameter()]
    [string] $UmiName = "Sentinel-Prod-UMI"
)

  $context = Set-AzContext -Subscription $subscription
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
  # assign permissions to allow creating service principals.
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
  
# MSSP SOC Azure Lighthouse Onboarding

Managing Microsoft Sentinel at scale with Lighthouse for distributed IT teams. This process is specifically meant for organizations that are using Lighthouse to manage tenants where different IT organizations control each tenant. It is also for when the SOC will have a separate subscription for its services that will be billed back to them.

## 1. Create SOC subscription in tenant

Follow the steps to create a subscription in the customer tenant.

## 2. Onboard customer tenant into Lighthouse

A user in the customer tenant with the correct permissions can use the following link to onboard:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2FLighthouse-Offers%2Flighthouse-offer1.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2FLighthouse-Offers%2FcreateUiDefinition.json" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/>

## 3. Customer creates user assigned identity

The following steps will require the customer to create identities to allow SOC to perform automation tasks.

### Create User Managed Identity and assigns permissions

These tasks can be completed in the Azure Portal using Cloud Shell. Open the Cloud Shell verify that PowerShell (not Bash) is the selected shell type.

```PowerShell
# Connect to the right subscription
do {
  $customerPrefix = Read-Host "Enter customer prefix name: "
} while ($customerPrefix.Length -lt 3)

do {
  $subscription = Read-Host "Enter the subscription id: "
} while ($subscription.Length -lt 36)

$context = Set-AzContext -Subscription $subscription

$umiName = "MSSP-Sentinel-Ingestion-UMI"
$azRegion = "eastus"
$rg = "$($customerPrefix)-Sentinel-Prod-rg"
$appName = "MSSP-Sentinel-Ingestion"

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

$output = New-AzAdServicePrincipal -DisplayName $appName
Start-Sleep 20
$adsp = Get-AzAdServicePrincipal -DisplayName $appName
New-AzRoleAssignment -RoleDefinitionId '3913510d-42f4-4e42-8a64-420c390055eb' -ObjectId $adsp.Id -Scope $subscription

```

## 4. MSSP creates Service Principal / App Registration and assigns permissions

The customer should complete the following tasks from their tenant.

### Automated Process (Preferred)

Click the button below to automatically create the service principal using the UMI created earlier.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2FDeploy-ServicePrincipal%2Fdeployment.json" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/>

### Manual process (If the automated process doesn't work)

#### Manual Option 1: Using the Azure portal

Sign in to the Azure portal and complete these high-level steps.

1. Create a Service Principal in customer tenant
2. Assign the Service Principal the Monitoring Metrics Publisher role (3913510d-42f4-4e42-8a64-420c390055eb) for entire subscription.
3. Create credentials for the SP and securely supply to MSSP.

#### Manual Option 2: Using the Azure Cloud Shell

These tasks can also be completed in the Azure Portal using Cloud Shell. Open the Cloud Shell, and verify that PowerShell (not Bash) is selected. Then run the following script:

```PowerShell
# Name of the service principal
$servicePrincipalName = "MsspNameSOC-Sentinel-LogIngest"
$subscriptionId = (Get-AzContext).Subscription.Id
$sp = New-AzAdServicePrincipal -DisplayName $servicePrincipalName
$scope = "/subscriptions/$($subscriptionId)"
New-AzRoleAssignment -RoleDefinitionId "3913510d-42f4-4e42-8a64-420c390055eb" -ObjectId $sp.Id -Scope $scope
New-AzADServicePrincipalCredential -ObjectId $sp.Id
```

## 5. Azure Automation

This rotates the service principal secrets.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2Fazure-automate%2FautomationAccount.json)

> **IMPORTANT**: After a successful deployment, you must manually set the runbook to use the customized runtime environment.

## 6. Deploy Sentinel using template

If you would like the standard connectors to be connected, the customer must be signed in with Global Admin. Otherwise the SOC can complete the basic deployment and the work with the customer to complete the configuration steps.

### Customized Sentinel-All-In-One v2

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw%2Egithubusercontent%2Ecom%2Fmvthul%2FAzLighthouse%2Frefs%2Fheads%2Fmain%2FDeploy%2DSentinel%2Fazuredeploy%2Ejson/createUIDefinitionUri/https%3A%2F%2Fraw%2Egithubusercontent%2Ecom%2Fmvthul%2FAzLighthouse%2Frefs%2Fheads%2Fmain%2FDeploy%2DSentinel%2FcreateUiDefinition%2Ejson)

### Work-In-Progress Customize Sentinel-All-In-One v2

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2FDeploy-Sentinel-Dev%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2FDeploy-Sentinel-Dev%2FcreateUiDefinition.json)

### ORIGINAL Sentinel-All-In-One v2

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2FSentinel-All-In-One%2Fv2%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoelst%2FAzLighthouse%2Fmain%2FSentinel-All-In-One%2Fv2%2FcreateUiDefinition.json)

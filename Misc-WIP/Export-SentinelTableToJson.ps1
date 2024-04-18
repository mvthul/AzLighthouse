[CmdletBinding()]
param (
    $TableName = "DeviceInfo",
    $ExportPath = (Join-Path "C:/" "SentinelTables"),
    [datetime]$StartDate = "1/1/2023",
    [datetime]$EndDate = "1/11/2023",
    # The Azure Tenant ID for the Azure Subscription
    $TenantId,
    # The Azure Subscription ID for Sentinel and the Azure Storage Account
    $SubscriptionId,
    # The Log Analytics Workspace ID for Sentinel
    $WorkspaceId,
    # The name of the Azure Storage Account to upload the data to
    $AzureStorageAccountName,
    # The name of the Azure Storage Container to upload the data to
    $AzureStorageContainer,
    # The resource group for the Azure Storage Account
    $AzureStorageAccountResourceGroup,
    # The number of hours to get data for in each iteration. This should be evenly divisible by 24. The default is 12 hours.
    $HourIncrements = 12
)
[System.Net.ServicePointManager]::MaxServicePointIdleTime = 600000

# Validate all parameters have been provided, if not prompt for them.
if (-not $TableName) {
    $TableName = Read-Host "Enter the table name:"
}

if (-not $ExportPath) {
    $ExportPath = Read-Host "Enter the local export path:"
}

if (-not $StartDate) {
    $StartDate = Read-Host "Enter the start date (MM/dd/yyyy):"
}

if (-not $EndDate) {
    $EndDate = Read-Host "Enter the end date (MM/dd/yyyy):"
}

if (-not $TenantId) {
    $TenantId = Read-Host "Enter the Azure Tenant ID:"
}

if (-not $SubscriptionId) {
    $SubscriptionId = Read-Host "Enter the Azure Subscription ID:"
}

if (-not $WorkspaceId) {
    $WorkspaceId = Read-Host "Enter the Log Analytics Workspace ID:"
}

if (-not $AzureStorageAccountName) {
    $AzureStorageAccountName = Read-Host "Enter the Azure Storage Account name:"
}

if (-not $AzureStorageContainer) {
    $AzureStorageContainer = Read-Host "Enter the Azure Storage Container name:"
}

if (-not $AzureStorageAccountResourceGroup) {
    $AzureStorageAccountResourceGroup = Read-Host "Enter the Azure Storage Account resource group:"
}

if (-not $HourIncrements) {
    $HourIncrements = Read-Host "Enter the number of hours to get data for in each iteration (must be divisable by 24):"
}

# Authenticate to Azure
Connect-AzAccount -TenantId $TenantId -Subscription $SubscriptionId
$context = (Get-AzStorageAccount -ResourceGroupName $AzureStorageAccountResourceGroup -Name $AzureStorageAccountName).Context

if (!(Test-Path $ExportPath)) { 
    $null = New-Item -ItemType Directory -Path $ExportPath
} 

# Create a loop to get data for one day at a time but for the entire range specified by $StartDate and $EndDate and $EndDate
$EndDate = $EndDate.AddDays(1)
# Calculate the number of hours between the start and end dates
$hours = ($EndDate - $StartDate).TotalHours

# Loop through each timespan in the range
for ($i = 0; $i -lt $hours; $i = $i + $HourIncrements) {
    # Calculate the current date based on the start date and the loop index
    $currentDate = $StartDate.AddHours($i)
    $nextDate = $currentDate.AddHours($HourIncrements)
    
    # Construct the query for the current date
    $currentQuery = $TableName
    $currentTimeSpan = New-TimeSpan -Start $currentDate -End $nextDate
    Write-Output "Getting data from $currentQuery for $currentDate to $nextDate"
    # Get the Table data from Log Analytics for the current date
    $currentTableResult = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $currentQuery -wait 600 -Timespan $currentTimeSpan | Select-Object Results -ExpandProperty Results -ExcludeProperty Results
    $currentTableResultCount = ($currentTableResult | Measure-Object).Count

    $fileName = "$TableName-$($currentDate.ToString('yyyy-MM-dd-mmHHss'))-$($nextDate.ToString('yyyy-MM-dd-mmHHss')).json"
    $OutputFile = Join-Path $ExportPath $fileName

    # Write file for the current date
    if ($currentTableResultCount -ge 1) {
        
        $currentTableResult | ConvertTo-json -Depth 100 | Out-File $OutputFile -Force 
        if (Test-Path $OutputFile) {
            
            $result = Set-AzStorageBlobContent -Context $context -Container $AzureStorageContainer -File $OutputFile -Blob $fileName -Force -ErrorAction SilentlyContinue
            if ($result) {
                #Write-Verbose "File $OutputFile uploaded to Azure Storage"
            }
            else {
                Write-Verbose "Failed to upload file $OutputFile to Azure Storage"
            }
        }
        else {
            Write-Verbose "Failed to create file $OutputFile"
        }
       
    }
    else {
        Write-Verbose "No data returned for $currentDate to $nextDate"
    }

}

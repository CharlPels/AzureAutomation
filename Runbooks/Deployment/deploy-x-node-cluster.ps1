<#
    .DESCRIPTION
        Deployment of a multinode Windows cluster

    .NOTES
        AUTHOR: Charl Pels
        LASTEDIT: 06-2-2017
#>
param(
    [Parameter(Mandatory=$true)]
    [String] $AzureResourceGroupName,

    [Parameter(Mandatory=$true)]
    [String] $ServerbaseName,

    #Storage account name must be between 3 and 24 characters in length and use numbers and lower-case letters only.
    [Parameter(Mandatory=$true)]
    [String] $StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string] $NetworkparametersnetworkSubnetName,

    [Parameter(Mandatory=$False)]
    [String] $AdminUserName,

    [Parameter(Mandatory=$true)]
    [string] $AdminPassword,

    [Parameter(Mandatory=$false)]
    [String] $SubscriptionID = "getcustomerdefault",

    [Parameter(Mandatory=$False)]
    [String] $NetworkparametersNetWorkName = "getcustomerdefault",

    [Parameter(Mandatory=$False)]
    [String] $backuppolicyparameterspolicyName = "getcustomerdefault"
)


$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 

if ($SubscriptionID -eq "getcustomerdefault") {$SubscriptionID = Get-AutomationVariable -Name DefaultSubscriptionID}
if ($NetworkparametersNetWorkName -eq "getcustomerdefault") {$NetworkparametersNetWorkName = Get-AutomationVariable -Name NetworkparametersNetWorkName}
if ($backuppolicyparameterspolicyName  -eq "getcustomerdefault") {$backuppolicyparameterspolicyName = Get-AutomationVariable -Name backuppolicyparameterspolicyName}

Select-AzureRmSubscription -SubscriptionId $SubscriptionId


}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}



#Get Parameters
$KeyVaultAccessApplicationName = Get-AutomationVariable -Name KeyVaultAccessApplicationName
#$UserPrincipalName = (Get-AzureRmContext).Account.Id
#$azureAdApplication = (Get-AzureRmADApplication -DisplayNameStartWith $KeyVaultAccessApplicationName)
$kekkey = Get-AutomationVariable -Name KekKey
$LogAnalyticsResourceGroupName =  Get-AutomationVariable -Name LogAnalyticsResourceGroupName

$aadClientSecret = Get-AutomationVariable -Name aadClientSecret
$keyVaultName =  Get-AutomationVariable -Name keyVaultName
$KeyVaultResourceGroupName = Get-AutomationVariable -Name KeyVaultResourceGroupName 
$SAScontainertoken = Get-AutomationVariable -Name SAScontainertoken
$NetworkparametersResourceGroupName =Get-AutomationVariable -Name NetworkparametersResourceGroupName
$azureAdApplicationApplicationId =Get-AutomationVariable -Name azureAdApplicationApplicationId
$LogAnalyticsworkspaceid =Get-AutomationVariable -Name LogAnalyticsworkspaceid
$LogAnalyticsPrimaryKey =Get-AutomationVariable -Name LogAnalyticsPrimaryKey
$azurelocation =Get-AutomationVariable -Name azurelocation
$RecoveryServicesVaultCreateparametersvaultName  = Get-AutomationVariable -Name RecoveryServicesVaultCreateparametersvaultName

$baseuri=Get-AutomationVariable -Name baseuri

Select-AzureRmSubscription -SubscriptionId $SubscriptionId

#Configuration for Azure Admin Access (the non office 365 AD)

$Azureparameters = @{}
$Azureparameters.Add("ServerStorageType", "Standard_LRS")
$Azureparameters.Add("VmSize", "Standard_D2_v2")
$Azureparameters.Add("ServerbaseName", $ServerbaseName)
$Azureparameters.Add("AdminUserName", $AdminUserName)
$Azureparameters.Add("AdminPassword", $AdminPassword)
$Azureparameters.Add("ServersStorageName", $StorageAccountName) #Storage account name must be between 3 and 24 characters in length and use numbers and lower-case letters only.
$NetworkparametersNetWorkName
$NetworkparametersResourceGroupName
$azurelocation
#-----------------------
#First we make an array with parameters needed for all deployments
#-----------------------
$Staticparameters = @{}
$Staticparameters.Add("WindowsOSVersion", "2012-R2-Datacenter")
$Staticparameters.Add("virtualNetworkResourceGroup", $NetworkparametersResourceGroupName)
$Staticparameters.Add("virtualNetworkName", $NetworkparametersNetWorkName)
$Staticparameters.Add("virtualNetworkLocation", $azurelocation)
$Staticparameters.Add("aadClientID", $azureAdApplicationApplicationId)
$Staticparameters.Add("aadClientSecret", $aadClientSecret)
$Staticparameters.Add("keyVaultName", $keyVaultName)
$Staticparameters.Add("keyVaultResourceGroup", $KeyVaultResourceGroupName)
$Staticparameters.Add("keyEncryptionKeyURL", $kekkey)
$Staticparameters.Add("workspaceId", $LogAnalyticsworkspaceid)
$Staticparameters.Add("workspacePrimaryKey", $LogAnalyticsPrimaryKey)
$Staticparameters.Add("SAStoken", $SAScontainertoken)


#Create the AD Connect for o365 resource group
New-AzureRmResourceGroup -Name $AzureResourceGroupName -Location $azurelocation -Verbose -Force -ErrorAction Stop

#generate template url
$TemplateUri  = $baseuri + "VirtualServers/" + "Generic2NodePair.json" + $SAScontainertoken

$Azureparameters= $Azureparameters + $Staticparameters #Static list of parameters we need
$Azureparameters.Add("virtualNetworkSubnetName", $NetworkparametersnetworkSubnetName)
$Azureparameters
Test-AzureRmResourceGroupDeployment -ResourceGroupName $AzureResourceGroupName  -TemplateUri $TemplateUri -TemplateParameterObject $Azureparameters
New-AzureRmResourceGroupDeployment -Name "automation"  -ResourceGroupName $AzureResourceGroupName -TemplateUri $TemplateUri -TemplateParameterObject $Azureparameters -Verbose

#Time to configure the backup
Get-AzureRmRecoveryServicesVault -Name $RecoveryServicesVaultCreateparametersvaultName | Set-AzureRmRecoveryServicesVaultContext 
$pol=Get-AzureRmRecoveryServicesBackupProtectionPolicy -Name $backuppolicyparameterspolicyName
foreach($name in (Get-AzureRmvm | where {$_.resourcegroupname -eq $AzureResourceGroupName}).NAME)
{Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name $name -ResourceGroupName $AzureResourceGroupName}
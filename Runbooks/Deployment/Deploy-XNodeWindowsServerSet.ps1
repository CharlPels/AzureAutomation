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
    [String] $vmNamePrefix,

    #Storage account name must be between 3 and 24 characters in length and use numbers and lower-case letters only.
    [Parameter(Mandatory=$true)]
    [String] $StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string] $NetworkparametersnetworkSubnetName,

    [Parameter(Mandatory=$True)]
    [int] $numberOfInstances,

    [Parameter(Mandatory=$False)]
    [String] $AdminUserName,

    [Parameter(Mandatory=$False)]
    [String] $WindowsOSVersion = "getcustomerdefault",

    [Parameter(Mandatory=$False)]
    [String] $ServerStorageType = "getcustomerdefault",

    [Parameter(Mandatory=$False)]
    [String] $VmSize = "getcustomerdefault",

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

if ($SubscriptionID -eq "getcustomerdefault" -or $SubscriptionID.tolower() -eq "none") {$SubscriptionID = Get-AutomationVariable -Name DefaultSubscriptionID}
if ($NetworkparametersNetWorkName -eq "getcustomerdefault" -or $SubscriptionID.tolower() -eq "none") {$NetworkparametersNetWorkName = Get-AutomationVariable -Name NetworkparametersNetWorkName}
if ($backuppolicyparameterspolicyName -eq "getcustomerdefault" -or $SubscriptionID.tolower() -eq "none") {$backuppolicyparameterspolicyName = Get-AutomationVariable -Name backuppolicyparameterspolicyName}
if ($NetworkparametersNetWorkName -eq "getcustomerdefault" -or $SubscriptionID.tolower() -eq "none") {$NetworkparametersNetWorkName = Get-AutomationVariable -Name NetworkparametersNetWorkName}
if ($WindowsOSVersion  -eq "getcustomerdefault" -or $SubscriptionID.tolower() -eq "none") {$WindowsOSVersion = Get-AutomationVariable -Name CustomerDefaultWindowsOSVersion}
if ($ServerStorageType  -eq "getcustomerdefault" -or $SubscriptionID.tolower() -eq "none") {$ServerStorageType = Get-AutomationVariable -Name CustomerDefaultServerStorageType}
if ($VmSize  -eq "getcustomerdefault" -or $SubscriptionID.tolower() -eq "none") {$VmSize = Get-AutomationVariable -Name CustomerDefaultVmSize}
$StorageAccountName=$StorageAccountName.tolower()


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

$SAScontainertoken = Get-AutomationVariable -Name SAScontainertoken
$azurelocation =Get-AutomationVariable -Name azurelocation

$baseuri=Get-AutomationVariable -Name baseuri

Select-AzureRmSubscription -SubscriptionId $SubscriptionId

#Creating admin password function
#Generate random passwords
#source: https://gallery.technet.microsoft.com/scriptcenter/Generate-a-random-and-5c879ed5
function New-SWRandomPassword {
    <#
    .DESCRIPTION
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .LINK
       http://blog.simonw.se/powershell-generating-random-password-for-active-directory/
   
    #>
    [CmdletBinding(DefaultParameterSetName='FixedLength',ConfirmImpact='None')]
    [OutputType([String])]
    Param
    (
        # Specifies minimum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({$_ -gt 0})]
        [Alias('Min')] 
        [int]$MinPasswordLength = 8,
        
        # Specifies maximum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({
                if($_ -ge $MinPasswordLength){$true}
                else{Throw 'Max value cannot be lesser than min value.'}})]
        [Alias('Max')]
        [int]$MaxPasswordLength = 12,

        # Specifies a fixed password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='FixedLength')]
        [ValidateRange(1,2147483647)]
        [int]$PasswordLength = 8,
        
        # Specifies an array of strings containing charactergroups from which the password will be generated.
        # At least one char from each group (string) will be used.
        [String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '123456789', '!%'),

        # Specifies a string containing a character group from which the first character in the password will be generated.
        # Useful for systems which requires first char in password to be alphabetic.
        [String] $FirstChar,
        
        # Specifies number of passwords to generate.
        [ValidateRange(1,2147483647)]
        [int]$Count = 1
    )
    Begin {
        Function Get-Seed{
            # Generate a seed for randomization
            $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
            $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
            $Random.GetBytes($RandomBytes)
            [BitConverter]::ToUInt32($RandomBytes, 0)
        }
    }
    Process {
        For($iteration = 1;$iteration -le $Count; $iteration++){
            $Password = @{}
            # Create char arrays containing groups of possible chars
            [char[][]]$CharGroups = $InputStrings

            # Create char array containing all chars
            $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

            # Set password length
            if($PSCmdlet.ParameterSetName -eq 'RandomLength')
            {
                if($MinPasswordLength -eq $MaxPasswordLength) {
                    # If password length is set, use set length
                    $PasswordLength = $MinPasswordLength
                }
                else {
                    # Otherwise randomize password length
                    $PasswordLength = ((Get-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
                }
            }

            # If FirstChar is defined, randomize first char in password from that string.
            if($PSBoundParameters.ContainsKey('FirstChar')){
                $Password.Add(0,$FirstChar[((Get-Seed) % $FirstChar.Length)])
            }
            # Randomize one char from each group
            Foreach($Group in $CharGroups) {
                if($Password.Count -lt $PasswordLength) {
                    $Index = Get-Seed
                    While ($Password.ContainsKey($Index)){
                        $Index = Get-Seed                        
                    }
                    $Password.Add($Index,$Group[((Get-Seed) % $Group.Count)])
                }
            }

            # Fill out with chars from $AllChars
            for($i=$Password.Count;$i -lt $PasswordLength;$i++) {
                $Index = Get-Seed
                While ($Password.ContainsKey($Index)){
                    $Index = Get-Seed                        
                }
                $Password.Add($Index,$AllChars[((Get-Seed) % $AllChars.Count)])
            }
            Write-Output -InputObject $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
        }
    }
}

#Showing the temp local admin password
$AdminPassword = New-SWRandomPassword
Write-Output "The temp local admin password is: $AdminPassword"

$Azureparameters = @{}
$Azureparameters.Add("ServerStorageType", $ServerStorageType)
$Azureparameters.Add("VmSize", $VmSize)
$Azureparameters.Add("vmNamePrefix", $vmNamePrefix)
$Azureparameters.Add("AdminUserName", $AdminUserName)
$Azureparameters.Add("AdminPassword", $AdminPassword)
$Azureparameters.Add("ServersStorageName", $StorageAccountName) #Storage account name must be between 3 and 24 characters in length and use numbers and lower-case letters only.
$Azureparameters.Add("numberOfInstances", $numberOfInstances)
$Azureparameters.Add("WindowsOSVersion", $WindowsOSVersion)
$Azureparameters.Add("virtualNetworkResourceGroup", (Get-AutomationVariable -Name NetworkparametersResourceGroupName))
$Azureparameters.Add("virtualNetworkName", $NetworkparametersNetWorkName)
$Azureparameters.Add("virtualNetworkLocation", $azurelocation)
$Azureparameters.Add("aadClientID", (Get-AutomationVariable -Name azureAdApplicationApplicationId))
$Azureparameters.Add("aadClientSecret", (Get-AutomationVariable -Name aadClientSecret))
$Azureparameters.Add("keyVaultName", (Get-AutomationVariable -Name keyVaultName))
$Azureparameters.Add("keyVaultResourceGroup", (Get-AutomationVariable -Name KeyVaultResourceGroupName))
$Azureparameters.Add("keyEncryptionKeyURL", (Get-AutomationVariable -Name KekKey))
$Azureparameters.Add("workspaceId", (Get-AutomationVariable -Name LogAnalyticsworkspaceid))
$Azureparameters.Add("workspacePrimaryKey", (Get-AutomationVariable -Name LogAnalyticsPrimaryKey))
$Azureparameters.Add("SAStoken", $SAScontainertoken)
$Azureparameters.Add("virtualNetworkSubnetName", $NetworkparametersnetworkSubnetName)

#Create the AD Connect for o365 resource group
New-AzureRmResourceGroup -Name $AzureResourceGroupName -Location $azurelocation -Verbose -Force -ErrorAction Stop

#generate template url
$TemplateUri  = $baseuri + "VirtualServers/" + "Generic2NodePair.json" + $SAScontainertoken

Test-AzureRmResourceGroupDeployment -ResourceGroupName $AzureResourceGroupName  -TemplateUri $TemplateUri -TemplateParameterObject $Azureparameters
New-AzureRmResourceGroupDeployment -Name "automation"  -ResourceGroupName $AzureResourceGroupName -TemplateUri $TemplateUri -TemplateParameterObject $Azureparameters -Verbose

#Time to configure the backup
Get-AzureRmRecoveryServicesVault -Name (Get-AutomationVariable -Name RecoveryServicesVaultCreateparametersvaultName) | Set-AzureRmRecoveryServicesVaultContext 
$pol=Get-AzureRmRecoveryServicesBackupProtectionPolicy -Name $backuppolicyparameterspolicyName
foreach($name in (Get-AzureRmvm | where {$_.resourcegroupname -eq $AzureResourceGroupName}).NAME)
{
    Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name $name -ResourceGroupName $AzureResourceGroupName
}
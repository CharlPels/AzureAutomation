<#
    .DESCRIPTION
        Update AzureRM modules in automation accounts when needed

    .NOTES
        Source: https://social.msdn.microsoft.com/Forums/SqlServer/en-US/eb95fcc1-d94f-42b1-a8d5-274d287bb2cd/updating-modules-in-azure?forum=azureautomation
        Made some changes to fit our needs
#>


try {
 

    $connectionName = "AzureRunAsConnection"
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    
}
catch {
    if(!$cred) {
        throw "Connection $connectionName not found."
    }
    else {
        throw $_.Exception
    }
}

Set-AzureRmContext -SubscriptionId (Get-AutomationVariable -Name DefaultSubscriptionID)
$ResourceGroupName = Get-AutomationVariable -Name AutomationAccountResourceGroup
$AutomationAccountName = Get-AutomationVariable -Name AutomationAccountName


$Modules = Get-AzureRmAutomationModule `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName | where {$_.name -like "*AzureRM.*"}

$AzureRMProfileModule = Get-AzureRmAutomationModule `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -Name 'AzureRM.Profile'

# Force AzureRM.Profile to be evaluated first since some other modules depend on it 
# being there / up to date to import successfully
$Modules = @($AzureRMProfileModule) + $Modules

foreach($Module in $Modules) {

    $Module = $Modules = Get-AzureRmAutomationModule `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $Module.Name
    
    $ModuleName = $Module.Name
    $ModuleVersionInAutomation = $Module.Version

    Write-Output "Checking if module '$ModuleName' is up to date in your automation account"

    $Url = "https://www.powershellgallery.com/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$ModuleName%27&targetFramework=%27%27&includePrerelease=false&`$skip=0&`$top=1" 
    Write-output $Url
    $SearchResult = Invoke-RestMethod -Method Get -Uri $Url -UseBasicParsing

    if(!$SearchResult) {
        Write-Error "Could not find module '$ModuleName' in PowerShell Gallery."
    }
    elseif($SearchResult.Length -and $SearchResult.Length -gt 1) {
        Write-Error "Module name '$ModuleName' returned multiple results. Please specify an exact module name."
    }
    else {
        $PackageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $SearchResult.id 
        $LatestModuleVersionOnPSGallery = $PackageDetails.entry.properties.version

        if($ModuleVersionInAutomation -ne $LatestModuleVersionOnPSGallery) {
            Write-Output "Module '$ModuleName' is not up to date. Latest version on PS Gallery is '$LatestModuleVersionOnPSGallery' but this automation account has version '$ModuleVersionInAutomation'"
            Write-Output "Importing latest version of '$ModuleName' into your automation account"

            $ModuleContentUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$ModuleVersion"

            # Find the actual blob storage location of the module
            do {
                $ActualUrl = $ModuleContentUrl
                $ModuleContentUrl = (Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore).Headers.Location 
            } while($ModuleContentUrl -ne $Null)

            $Module = New-AzureRmAutomationModule `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name $ModuleName `
                -ContentLink $ActualUrl
                
            while($Module.ProvisioningState -ne 'Succeeded' -and $Module.ProvisioningState -ne 'Failed') {
                Start-Sleep -Seconds 10
            
                $Module = Get-AzureRmAutomationModule `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -Name $ModuleName

                Write-Output 'Polling for import completion...'
            }

            if($Module.ProvisioningState -eq 'Succeeded') {
                Write-Output "Successfully imported latest version of $ModuleName"
            }
            else {
                Write-Error "Failed to import latest version of $ModuleName"
            }   
        }
        else {
            Write-Output "Module '$ModuleName' is up to date."
        }
   }
}
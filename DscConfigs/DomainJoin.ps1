
configuration DomainJoin
{
	Import-DscResource -ModuleName xDSCDomainjoin
	$domainCred = Get-AutomationPSCredential -Name DomainJoinAccount
    $DomainToJoin = Get-AutomationVariable -Name DomainToJoin

    Node DomainJoin
    {
		xDSCDomainjoin JoinDomain
		{
			Domain = "$DomainToJoin"
			Credential = $domainCred  # Credential to join to domain
		}
    }
}



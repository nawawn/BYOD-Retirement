[CmdletBinding()]
Param()

#Requires -Modules ActiveDirectory

$ScriptPath = (Split-Path $MyInvocation.MyCommand.Path)
$Config = Import-PowerShellDataFile -Path $ScriptPath\BYOD-AD-config.psd1
$Time   = $Config.RetireTime
$Attribute1 = $Config.ADParam.extensionAttribute1
$ExpiryTimeSpan = $Config.ADParam.ExpiryTimeSpan

Function Test-ByodADGroup{
    [OutputType([Bool])]
    Param(
        [String]$UserName
    )
    $IntuneADGroup = $Config.ADParam.ADGroup
    $MemberOf = (Get-ADPrincipalGroupMembership -Identity $UserName).Name
    <#    
    $IsMember = $false
    Foreach($Group in $IntuneADGroup){
        If ($MemberOf -contains $Group) {
            $IsMember = $true
            break
        }
    }
    return $IsMember
    #>
    return ($null -ne ($IntuneADGroup | Where-Object{$MemberOf -contains $_}))
}

Function Get-ByodADAttribute{
    Param(
        [String]$UserName
    )
    return (Get-AdUser -Identity $UserName -Properties extensionAttribute1 | Select-Object -ExpandProperty extensionAttribute1)
}

Function Set-ByodADAttribute{
    Param(
        [String]$UserName
    )
    Set-ADUser -Identity $UserName -Add @{extensionAttribute1 = $Attribute1}
}

Function Send-ReminderEmail{
    Param(
        $FullName,
        $UPN,
        $ShortDate,
        $Time
    )

    [String]$Body = $Config.EmailParam.Body | Out-String
    $Body = $Body.replace("{FullName}",$FullName).
        replace("{UserPrincipalName}",$UPN). 
        replace("{ShortDate}",$ShortDate).
        replace("{Time}",$Time)

    $EmailParam = @{
        From       = $Config.EmailParam.From
        To         = $Config.EmailParam.To
        Subject    = $Config.EmailParam.Subject        
        Body       = $Body
        BodyAsHtml = $Config.EmailParam.BodyAsHtml
        SmtpServer = $Config.EmailParam.SmtpServer
        Priority   = $Config.EmailParam.Priority
    }    
    Send-MailMessage @EmailParam
}

#region Controller script
Write-Verbose "Getting AD users expiring in $ExpiryTimeSpan..."
$ExpiringUsers = Search-ADAccount -AccountExpiring -UsersOnly -TimeSpan $ExpiryTimeSpan

Foreach ($User in $ExpiringUsers){
    Write-Verbose "Checking if the $($User.Name) is part of the BYOD group..."
    If(Test-ByodADGroup -UserName $($User.Name)){        
        Write-Verbose "$($User.Name) is part of BYOD Group. Checking if the AD attribute has not got RetireBYOD..."        
        If ((Get-ByodADAttribute -UserName $($User.Name)) -ne $Attribute1){
            
            $FullName  = (Get-AdUser -identity $($User.Name) -Properties DisplayName).DisplayName
            $ShortDate = ((Get-Date $($User.AccountExpirationDate)).AddSeconds(-1)).ToShortDateString()
            
            Write-Verbose "Sending an email to IT Support..."
            Send-ReminderEmail -FullName $FullName -UPN $($User.UserPrincipalName) -ShortDate $ShortDate -Time $Time
            
            Write-Verbose "Updating the AD attribute with the value RetireBYOD..."
            Set-ByodADAttribute -UserName $($User.Name)
        }
    }
}
#endregion Controller script
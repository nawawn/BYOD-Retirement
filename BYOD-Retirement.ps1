[CmdletBinding()]
Param()

Import-Module ActiveDirectory, MSOnline

$ScriptPath = (Split-Path $MyInvocation.MyCommand.Path)
$Config = Import-PowerShellDataFile -Path $ScriptPath\BYOD-config.psd1
$Time   = $Config.RetireTime
$MsolSkuID   = $Config.MsolParam.MsolLicense
$UserName    = $Config.MsolParam.MsolUser
$AESKeyFile  = $Config.MsolParam.AESKeyFile
$SStringFile = $Config.MsolParam.SStringFile

Function Invoke-SqlQuery{    
    Param(            
        [String]$ServerName,
        [String]$Database,
        [String]$Query        
    )
    #[Parameter(Mandatory)] not available in PS 2.0
    Begin{
        $SqlConn = New-Object System.Data.SqlClient.SqlConnection
        $Connstr = "Server=$ServerName;Database=$Database;Integrated Security=True;"
        $SqlConn.ConnectionString = $Connstr
    }
    Process{
        $SqlConn.Open()    
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($Query,$SqlConn)    
        $SqlDA  = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)
        $SqlDS  = New-Object System.Data.DataSet
        [void]$SqlDA.fill($SqlDS)
        [Array]$Data = $SqlDS.Tables[0]
        $SqlConn.Close()
        return ($Data)
    }
    End{}
}

Function Invoke-SqlCommand{    
    Param(            
        [String]$ServerName,
        [String]$Database,
        [String]$Command        
    )
    Begin{
        $SqlConn = New-Object System.Data.SqlClient.SqlConnection
        $Connstr = "Server=$ServerName;Database=$Database;Integrated Security=True;"
        $SqlConn.ConnectionString = $Connstr
    }
    Process{
        $SqlConn.Open()
        $SqlCmd = $SqlConn.CreateCommand()
        $SqlCmd.CommandText = $Command

        $SqlCmd.ExecuteNonQuery()
        $SqlConn.Close()        
    }
    End{}
}

#################################################################################
#  Single quotes are sensitive inside SQL SELECT INSERT UPDATE DELETE Statement  #

Function Get-ByodTable{
    $QueryParam = @{
        ServerName = $Config.SQLParam.ServerName
        Database   = $Config.SQLParam.Database
        Query      = "SELECT * FROM BYOD_Retirement_Audit"
    }
    #Select -ExcludeProperty RowError,RowState,Table,ItemArray,HasError from the DataSet
    $Property = @(  'Audit_ID',
                    'User_Principal_Name',
                    'User_Expiry_Date',
                    'Email_Sent_Flag',
                    'Email_Sent_Date'
                )
    return (Invoke-SqlQuery @QueryParam | Select-Object -Property $Property)
}

Function New-ByodRetirement{
    Param(            
        [MailAddress]$UPN,
        [DateTime]$ExpiryDate,        
        [ValidateSet("Y","N")]
        [Char]$EmailFlag,
        [DateTime]$EmailSentDate
    )
    $CommandParam = @{
        ServerName = 'Dev-sql-02'
        Database   = 'BYOD_Retirement'
        Command    = "INSERT INTO BYOD_Retirement_Audit (User_Principal_Name, User_Expiry_Date, Email_Sent_Flag, Email_Sent_Date)
                      VALUES('$($UPN)','$($ExpiryDate)','$($EmailFlag)','$($EmailSentDate)')"

    }
    Invoke-SqlCommand @CommandParam
<#
.EXAMPLE 
    New-ByodRetirement -UPN 'CalendarT@britishmuseum.org' -ExpiryDate ((Get-Date).AddDays(20)) -EmailFlag 'Y' -EmailSentDate (Get-Date)
#>
}

Function Set-ByodRetirement{
    Param(            
        [MailAddress]$UPN,               
        [ValidateSet("Y","N")]
        [Char]$EmailFlag,
        [DateTime]$EmailSentDate
    )

    $CommandParam = @{
        ServerName = $Config.SQLParam.ServerName
        Database   = $Config.SQLParam.Database
        Command    = "UPDATE BYOD_Retirement_Audit SET Email_Sent_Flag = '$($EmailFlag)', Email_Sent_Date = '$($EmailSentDate)' WHERE User_Principal_Name = '$($UPN)'"
    }
    Invoke-SqlCommand @CommandParam
<#
.EXAMPLE
    Set-ByodRetirement -UPN 'CalendarTest@britishmuseum.org' -EmailFlag 'Y' -EmailSentDate (Get-Date)
#>   
}

Function Remove-ByodRecord{
    Param(
        $NumOfDays = $Config.SQLParam.NumOfDays
    )   

    $CommandParam = @{
        ServerName = $Config.SQLParam.ServerName
        Database   = $Config.SQLParam.Database
        Command    = "Delete FROM BYOD_Retirement_Audit WHERE User_Expiry_Date < (SELECT dateadd(dd,$($NumOfDays),getdate()))"
    }
    Invoke-SqlCommand @CommandParam
}

Function New-PSCredential{
    [OutputType([PSCredential])]
    Param(
        [Parameter(Mandatory)][String]$UserName,
        [Parameter(Mandatory)][String]$EncryptedFilePath,
        [Parameter(Mandatory)][String]$AESKeyFilePath        
    )
    $EncryptedString = Get-Content $EncryptedFilePath
    $Key = Get-Content $AESKeyFilePath
    Return (New-Object -TypeName System.Management.Automation.PSCredential($UserName,($EncryptedString | ConvertTo-SecureString -Key $Key)))
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

#region Controller Script Main()

Write-Verbose "Signing in to Office 365 via PowerShell..."
$Credential  = New-PSCredential -UserName $UserName -EncryptedFilePath (Convert-Path $SStringFile) -AESKeyFilePath (Convert-Path $AESKeyFile)
Connect-MsolService -Credential $Credential

Write-Verbose "Retrieving expiring users from local AD..."
$ExpiringUsers = Search-ADAccount -AccountExpiring

Write-Verbose "Bringing BYOD Users out of expiring users..."
$IntuneUsers = Foreach($User in $ExpiringUsers){
                $IsLicensed = Get-MsolUser -UserPrincipalName $User.UserPrincipalName | Where-Object {$_.isLicensed -eq $true -and $_.Licenses.AccountSkuID -eq $MsolSkuID}
                If ($IsLicensed){            
                    New-Object PSObject -Property @{
                        UPN        = $User.UserPrincipalName
                        FullName   = (Get-AdUser $($User.Name) -Properties DisplayName).DisplayName
                        ExpiryDate = (Get-Date $($User.AccountExpirationDate)).AddSeconds(-1)                        
                    }               
                }
}

#Remove the records with expiry date older than 90 days from the database table
Write-Verbose "Cleaning up the BYOD database with expiry date older than 90 days..."
Remove-ByodRecord | Out-Null

#Extract the user list from the database and save it to a variable
Write-Verbose "Getting the existing users list from the BYOD Database..."
$ByodTable = (Get-ByodTable)

Write-Verbose "Going through each user with Intune License"
Foreach($ByodUser in $IntuneUsers){
    #Check if the ByodUser is in the database
    If($ByodTable.User_Principal_Name -contains $ByodUser.UPN){
        #Check if the email has NOT been sent for this user
        $EmailSent = $ByodTable | Where-Object {$_.User_Principal_Name -like $ByodUser.UPN} | Select-Object -ExpandProperty Email_Sent_Flag
        If($EmailSent -Contains 'N'){
            #Send an email to IS Support
            If ($ByodUser.ExpiryDate){
                $ShortDate = (Get-Date $($ByodUser.ExpiryDate)).ToShortDateString()   
            }
            Else {
                $ShortDate = (Get-Date '1753-01-01 00:00:00').ToShortDateString()    
            }
            
            Write-Verbose "Sending reminder email for $($ByodUser.FullName) with Email_Sent_Flag set to N..."
            Send-ReminderEmail -FullName $($ByodUser.FullName) -UPN $($ByodUser.UPN) -ShortDate $ShortDate -Time $Time       

            Write-Verbose "Updating the Database Table to set Email_Sent_Flag to Y..."            
            Set-ByodRetirement -UPN $($ByodUser.UPN) -EmailFlag 'Y' -EmailSentDate (Get-Date)
        }
    }
    #If ByodUser is Not in the database
    #Send an email to issupport and Insert a new record
    Else{
        If ($ByodUser.ExpiryDate){
            $ShortDate = (Get-Date $($ByodUser.ExpiryDate)).ToShortDateString()   
        }
        Else {
            $ShortDate = (Get-Date '1753-01-01 00:00:00').ToShortDateString()    
        }        

        Write-Verbose "Send a new reminder email for user $($ByodUser.FullName)..."
        Send-ReminderEmail -FullName $($ByodUser.FullName) -UPN $($ByodUser.UPN) -ShortDate $ShortDate -Time $Time
        Write-Verbose "Insert a new record in the Database for $($ByodUser.FullName)..." 
        New-ByodRetirement -UPN $($ByodUser.UPN) -ExpiryDate $($ByodUser.ExpiryDate) -EmailFlag 'Y' -EmailSentDate (Get-Date)
    }
}

#endregion Controller Script
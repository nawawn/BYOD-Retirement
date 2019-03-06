Import-Module ActiveDirectory, MSOnline

$ScriptPath   = (Split-Path $MyInvocation.MyCommand.Path)
$Config = Import-PowerShellDataFile -Path $ScriptPath\BYOD-config.psd1
$Time   = $Config.RetireTime
$SkuID  = $Config.MsolLicense
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
#  Single quote are sensitive inside SQL SELECT INSERT UPDATE DELETE Statement  #

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
        $NumOfDays = $Config.SQLParam.$NumOfDays
    )   

    $CommandParam = @{
        ServerName = $Config.SQLParam.ServerName
        Database   = $Config.SQLParam.Database
        Command    = "Delete FROM BYOD_Retirement_Audit WHERE User_Expiry_Date < (SELECT dateadd(dd,$($NumOfDays),getdate()))"
    }
    Invoke-SqlCommand @CommandParam
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
#Get the Key and secure string and build the credential
#$Credential = New-Object System.Management.Automation.PSCredential($UserName,$Password)

#Sign into Office 365 via PowerShell
Connect-MsolService -Credential $Credential
#Get expiring users
$ExpiringUsers = Search-ADAccount -AccountExpiring
#Get Byod Users out of expiring users
$IntuneUsers = Foreach($User in $ExpiringUsers){
                $IsLicensed = Get-MsolUser -UserPrincipalName $User.UserPrincipalName | Where-Object {$_.isLicensed -eq $true -and $_.Licenses.AccountSkuID -eq $SkuID}
                If ($IsLicensed){            
                    New-Object PSObject -Property @{
                        UPN        = $User.UserPrincipalName
                        FullName   = (Get-AdUser $User.Name -Properties DisplayName).DisplayName
                        ExpiryDate = (Get-Date $User.AccountExpirationDate).AddSeconds(-1)                        
                    }               
                }
}

#Remove the records with expiry date older than 90 days from the database table
Remove-ByodRecord

#Extract the user list from the database and save it to a variable
$ByodTable = (Get-ByodTable)

Foreach($ByodUser in $IntuneUsers){
    #Check if the ByodUser is in the database
    If($ByodTable.User_Principal_Name -contains $ByodUser.UPN){
        #Check if the email has NOT been sent for this user
        $EmailSent = $ByodTable | Where-Object {$_.User_Principal_Name -like $ByodUser.UPN} | Select-Object -ExpandProperty Email_Sent_Flag
        If($EmailSent -Contains 'N'){
            #Send an email to IS Support
            $ShortDate = (Get-Date $BoydUser.ExpiryDate).ToShortDateString()            
            Send-ReminderEmail -FullName $($BoydUser.FullName) -UPN $($ByodUser.UPN) -ShortDate $ShortDate -Time $Time       

            #Update the Database Table            
            Set-ByodRetirement -UPN $($ByodUser.UPN) -EmailFlag 'Y' -EmailSentDate (Get-Date)
        }
    }
    #If ByodUser is Not in the database
    #Send an email to issupport and Insert a new record
    Else{
        $ShortDate = (Get-Date $BoydUser.ExpiryDate).ToShortDateString()        

        #Send an email to IS Support
        Send-ReminderEmail -FullName $($BoydUser.FullName) -UPN $($ByodUser.UPN) -ShortDate $ShortDate -Time $Time
        #INSERT a new record in the Database 
        New-ByodRetirement -UPN $($ByodUser.UPN) -ExpiryDate $($ByodUser.ExpiryDate) -EmailFlag 'Y' -EmailSentDate (Get-Date)
    }

}


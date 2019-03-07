@{
    Description = "Configuration data file for BYOD-Retirement.ps1"
    RetireTime  = "5:29 PM"
    
    SQLParam = @{
        ServerName = 'SqlServer'
        Database   = 'BYOD_Database'
        NumOfDays  = -90
    }

    MsolParam = @{        
        MsolUser    = 'svcBYODCheck@mycompany.com'
        AESKeyFile  = '.\Encstr\svcBYOD-AES.key'
        SStringFile = '.\Encstr\svcBYOD-SS.txt'
        MsolLicense = 'mycompany:INTUNE_A_VL'
    }

    EmailParam = @{
        From    = 'naw.awn@mycompany.com'
        To      = 'naw.awn@mycompany.com','itsupport@mycompany.com'
        Subject = 'Action Required - Retire BYOD mobile phone'
        Body    = "Dear ISSupport <br/><br/> 
                  {FullName} ({UserPrincipalName}) is leaving the Company on {ShortDate} and is signed up for BYOD service. Please remove the Company data on the user's device on {ShortDate} at {Time}.
                  <br/><br/>Regards"
        BodyAsHtml = $true
        SmtpServer = 'exchangeserver.mycompany.com'
        Priority   = 'High'
    }
}
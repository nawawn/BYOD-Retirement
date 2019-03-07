@{
    Description = "Configuration data file for BYOD-Retirement.ps1"
    RetireTime  = "5:12 PM"
    
    SQLParam = @{
        ServerName = 'Dev-SQL-02'
        Database   = 'BYOD_Retirement'
        NumOfDays  = -90
    }

    MsolParam = @{        
        MsolUser    = 'svcBYODCheck@britishmuseum.org'
        AESKeyFile  = '.\Encstr\svcBYOD-AES.key'
        SStringFile = '.\Encstr\svcBYOD-SS.txt'
        MsolLicense = 'britishmuseum:INTUNE_A_VL'
    }

    EmailParam = @{
        From    = 'nawn@britishmuseum.org'
        To      = 'nawn@britishmuseum.org','issupport@britishmuseum.org'
        Subject = 'Action Required - Retire BYOD mobile phone'
        Body    = "Dear ISSupport <br/><br/> 
                  {FullName} ({UserPrincipalName}) is leaving the Museum on {ShortDate} and is signed up for BYOD service. Please remove the Museum's data on the user's device on {ShortDate} at {Time}.
                  <br/><br/>Regards"
        BodyAsHtml = $true
        SmtpServer = 'blm-exc-03.adbm.britishmuseum.org'
        Priority   = 'High'
    }
}
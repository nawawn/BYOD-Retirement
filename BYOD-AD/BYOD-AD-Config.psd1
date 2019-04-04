@{
    Description = "Configuration data file for BYOD-AD-Retirement.ps1"
    RetireTime  = "5:29 PM"
    
    ADParam = @{        
        ADGroup = 'App-IntuneBYOD-Android','App-IntuneBYOD-iOS','App-IntuneAndroidforWork'        
        ExpiryTimeSpan = "3.00:00:00"
        extensionAttribute1 = "RetireBYOD"
        
    }    

    EmailParam = @{
        From    = 'nawn@mycompany.com'
        To      = 'nawn@mycompany.com','itsupport@mycompany.com'
        Subject = 'Action Required - Retire BYOD mobile phone'
        Body    = "Dear IT Support <br/><br/> 
                  {FullName} ({UserPrincipalName}) is leaving the company on {ShortDate} and is signed up for BYOD service. Please remove the company data on the user's device on {ShortDate} at {Time}.
                  <br/><br/>Regards"
        BodyAsHtml = $true
        SmtpServer = 'smtpserver.mycompany.com'
        Priority   = 'High'
    }
}
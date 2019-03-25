# BYOD-Retirement

![FlowChart](/images/ByodRetire.png)
## Prerequisites for the process to run
* Needs an SQL Database
* Minimum Database user role: db_datawriter
* Needs a standard office365 user to retrieve the Licence status

__How To Deploy__
Deploy the SQL Database and create the table using the 'CREATE_DB_BYOD_Retirement.sql' sql script.
Copy the BYOD-Retirement.ps1 and BYOD-config.psd1 into a folder.
Create a sub folder, call it 'Encstr', where the powershell script is stored.
Create the key and secure string for standard office365 user's password using New-AESencryption.ps1 from InfraScripts Repo and place them inside the subfolder created.
Update the data on BYOD-config.psd1 as required.
Create a scheduled task to run the BYOD-Retiremnet.ps1 PowerShell script.


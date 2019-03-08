/*****************************************************************************
Create BYOD_Retirement database
Creates database and adds a single table
Credit goes to Rebecca G.
*****************************************************************************/

USE master;
GO

CREATE DATABASE BYOD_Retirement ON PRIMARY
	(NAME = N'BYOD_Retirement', FILENAME = 'D:\SQLData\BYOD_Retirement.mdf')
	LOG ON 
	(NAME = N'BYOD_Retirement_Log', FILENAME = 'D:\SQLLogs\BYOD_Retirement_log.ldf')

--2. Create the table required, including constraints

USE BYOD_Retirement;
GO

CREATE TABLE BYOD_Retirement_Audit
(
		Audit_ID INTEGER IDENTITY (1,1) NOT NULL CONSTRAINT PK_BYOD_Retirement_Audit PRIMARY KEY
	,	User_Principal_Name NVARCHAR(255) NOT NULL
	,	User_Expiry_Date DATETIME NOT NULL
	,	Email_Sent_Flag NCHAR(1) NOT NULL CONSTRAINT DF_BYOD_Retirement_Audit_Email_Sent_Flag DEFAULT 'N' 
	,	Email_Sent_Date DATETIME NOT NULL CONSTRAINT DF_BYOD_Retirement_Audit_Email_Sent_Date DEFAULT '1753-01-01 00:00:00' 
);



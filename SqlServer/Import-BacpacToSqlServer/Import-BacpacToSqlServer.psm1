﻿<#
.Synopsis
    Imports a .bacpac file to a database on a local SQL Server instance.

.DESCRIPTION
    Imports a .bacpac file to a database on the default local SQL Server instance. Install the attached
    Import-BacpacToSqlServer.reg Registry file to add an "Import to SQL Server with PowerShell" right click context menu
    shortcut for .bacpac files.

.EXAMPLE
    Import-BacpacToSqlServer -BacpacPath "C:\database.bacpac"

.EXAMPLE
    Import-BacpacToSqlServer -BacpacPath "C:\database.bacpac" -DatabaseName "BetterName"

.EXAMPLE
    Import-BacpacToSqlServer -BacpacPath "C:\database.bacpac" -SqlServerName "LocalSqlServer" -DatabaseName "BetterName"

.EXAMPLE
    $importParameters = @{
        BacpacPath = 'C:\database.bacpac'
        ConnectionString = 'Data Source=.\SQLEXPRESS;Initial Catalog=NiceDatabase;Integrated Security=True;'
    }
    Import-BacpacToSqlServer @importParameters
#>


function Import-BacpacToSqlServer
{
    [Diagnostics.CodeAnalysis.SuppressMessage(
        'PSAvoidUsingUsernameAndPasswordParams',
        '',
        Justification = 'We need to pass the user name and password to SqlPackage.')]
    [Diagnostics.CodeAnalysis.SuppressMessage(
        'PSAvoidUsingPlainTextForPassword',
        '',
        Justification = 'SqlPackage needs the password as plain text.')]
    [Diagnostics.CodeAnalysis.SuppressMessage(
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        '',
        Justification = 'We need to convert the plain text password to SecureString and pass it to Test-SqlServer.')]
    [CmdletBinding(DefaultParameterSetName = 'ByConnectionParameters')]
    [Alias('ipbpss')]
    [OutputType([bool])]
    Param
    (
        [Parameter(HelpMessage = 'The path to the "SqlPackage" executable that performs the import process. When not' +
            ' defined, it will try to find the executable installed with the latest SQL Server.')]
        [Parameter(ParameterSetName = 'ByConnectionString')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [string] $SqlPackageExecutablePath = '',

        [Parameter(Mandatory = $true, HelpMessage = 'The path to the .bacpac file to import.')]
        [Parameter(ParameterSetName = 'ByConnectionString')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [string] $BacpacPath = $(throw 'You need to specify the path to the .bacpac file to import.'),

        [Parameter(HelpMessage = 'The connection string that defines the server and database to import the .bacpfile' +
            ' to. If not defined, it will be built using the "SqlServerName" and "DatabaseName" variables.')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ByConnectionString')]
        [string] $ConnectionString = '',

        [Parameter(HelpMessage = 'The name of the SQL Server instance that will host the imported database. If not' +
            ' defined, it will be determined from the system registry.')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [string] $SqlServerName = '',

        [Parameter(HelpMessage = 'The name of the database that will be created for the imported .bacpac file. If not' +
            ' defined, it will be the name of the imported file.')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [string] $DatabaseName = '',

        [Parameter(HelpMessage = 'The name of a user with the necessary access to the server to import a database.')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [string] $Username = '',

        [Parameter(HelpMessage = 'The password of a user with the necessary access to the server to import a database.')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [string] $Password = ''
    )

    Process
    {
        # Setting up SQL Package executable path.
        $finalSqlPackageExecutablePath = ''
        if (-not [string]::IsNullOrEmpty($SqlPackageExecutablePath) -and (Test-Path $SqlPackageExecutablePath))
        {
            $finalSqlPackageExecutablePath = $SqlPackageExecutablePath
        }
        else
        {
            if (-not [string]::IsNullOrEmpty($SqlPackageExecutablePath))
            {
                Write-Warning ("SQL Package executable for importing the database is not found at '$path'!" +
                    ' Trying to locate default SQL Package executables...')
            }

            $defaultSqlPackageExecutablePath = @(
                [System.IO.Path]::Combine($Env:ProgramFiles, 'Microsoft SQL Server'),
                [System.IO.Path]::Combine(${Env:ProgramFiles(x86)}, 'Microsoft SQL Server')) |
                Where-Object { Test-Path $PSItem } |
                ForEach-Object { Get-ChildItem $PSItem | Where-Object { [int] $dummy = 0; [int]::TryParse($PSItem.Name, [ref] $dummy) } } |
                ForEach-Object { [System.IO.Path]::Combine($PSItem.FullName, 'DAC', 'bin', 'SqlPackage.exe') } |
                Where-Object { Test-Path $PSItem } |
                Sort-Object -Descending |
                Select-Object -First 1

            if ([string]::IsNullOrWhiteSpace($locatedPath))
            {
                $finalSqlPackageExecutablePath = $defaultSqlPackageExecutablePath
                Write-Verbose "SQL Package executable for importing the database found at '$finalSqlPackageExecutablePath'!"
            }
        }

        if ([string]::IsNullOrEmpty($finalSqlPackageExecutablePath))
        {
            throw ('No SQL Package executable found for importing the database! You can download it from' +
                ' "https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download"!')
        }



        # Checking the validity of the bacpac file.
        $bacpacFile = Get-Item $BacpacPath
        if ($null -eq $bacpacFile -or -not ($bacpacFile -is [System.IO.FileInfo]) -or -not ($bacpacFile.Extension -eq '.bacpac'))
        {
            throw "The .bacpac file is not found at '$BacpacPath'!"
        }



        # Given that the parameter set uses the ConnectionString, we're deconstructing it to check its validity.
        if ($PSCmdlet.ParameterSetName -eq 'ByConnectionString')
        {
            $connectionStringSegments = $ConnectionString.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)

            $serverSegment = $connectionStringSegments | Where-Object {
                $PSItem.StartsWith('Data Source=') -or $PSItem.StartsWith('Server=')
            }
            if (-not [string]::IsNullOrEmpty($serverSegment))
            {
                $SqlServerName = $serverSegment.Split('=', 2, [System.StringSplitOptions]::RemoveEmptyEntries)[1]
            }

            $databaseSegment = $connectionStringSegments | Where-Object {
                $PSItem.StartsWith('Initial Catalog=') -or $PSItem.StartsWith('Database=')
            }
            if (-not [string]::IsNullOrEmpty($databaseSegment))
            {
                $DatabaseName = $databaseSegment.Split('=', 2, [System.StringSplitOptions]::RemoveEmptyEntries)[1]
            }

            $usernameSegment = $connectionStringSegments | Where-Object { $PSItem.StartsWith('User Id=') }
            if (-not [string]::IsNullOrEmpty($usernameSegment))
            {
                $Username = $usernameSegment.Split('=', 2, [System.StringSplitOptions]::RemoveEmptyEntries)[1]
            }

            $passwordSegment = $connectionStringSegments | Where-Object { $PSItem.StartsWith('Password=') }
            if (-not [string]::IsNullOrEmpty($passwordSegment))
            {
                $Password = $passwordSegment.Split('=', 2, [System.StringSplitOptions]::RemoveEmptyEntries)[1]
            }
        }



        # Validating parameters.
        if ([string]::IsNullOrEmpty($DatabaseName))
        {
            $DatabaseName = $bacpacFile.BaseName
        }

        # If the DatabaseUserName parameter is defined, then DatabaseUserPassword needs to be defined as well and vice
        # versa.
        if ([string]::IsNullOrEmpty($Username) -xor [string]::IsNullOrEmpty($Password))
        {
            throw 'Either both DatabaseUserName and DatabaseUserPassword parameters must be defined or neither of them!'
        }



        [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null

        # SqlServerName is not defined, so let's try to find one.
        if ([string]::IsNullOrEmpty($SqlServerName))
        {
            $SqlServerName = ".\$(Get-DefaultSqlServerName)"
        }

        $securePassword = $null
        if (-not [string]::IsNullOrEmpty($Password))
        {
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        }
        if (-not (Test-SqlServer $SqlServerName $Username $securePassword))
        {
            Write-Warning "Could not find SQL Server at '$SqlServerName'!"
            $SqlServerName = 'localhost'

            if (-not (Test-SqlServer $SqlServerName))
            {
                throw 'Could not find any SQL Server instances!'
            }
        }


        # Handling the case when there's already a database with this name on the target server.
        $databaseExists = Test-SqlServerDatabase -SqlServerName $SqlServerName -DatabaseName $DatabaseName -UserName $Username -Password $securePassword
        if ($databaseExists)
        {
            $originalDatabaseName = $DatabaseName
            $DatabaseName += '-' + [System.Guid]::NewGuid()
        }



        [Collections.ArrayList] $parameters = @(
            '/Action:Import',
            "/TargetServerName:`"$SqlServerName`"",
            "/TargetDatabaseName:`"$DatabaseName`"",
            '/TargetTrustServerCertificate:True',
            '/TargetTimeout:0',
            "/SourceFile:`"$BacpacPath`""
        )

        if (-not [string]::IsNullOrEmpty($Username) -and -not [string]::IsNullOrEmpty($Password))
        {
            $parameters += "/TargetUser:`"$Username`""
            $parameters += "/TargetPassword:`"$Password`""
        }

        # And now we get to actually importing the database after setting up all the necessary parameters.
        & "$finalSqlPackageExecutablePath" @parameters



        # Importing the database was successful.
        if ($LASTEXITCODE -eq 0)
        {
            # If there was a database with an identical name on the target server, we'll swap it with the one we've just
            # imported.
            if ($databaseExists)
            {
                $server = New-Object ('Microsoft.SqlServer.Management.Smo.Server') (New-SqlServerConnection $SqlServerName $Username $securePassword)
                $server.KillAllProcesses($originalDatabaseName)
                $server.Databases[$originalDatabaseName].Drop()
                $server.Databases[$DatabaseName].Rename($originalDatabaseName)

                Write-Warning ("The original database with the name '$originalDatabaseName' has been deleted and the" +
                    ' imported one has been renamed to use that name.')
            }
        }
        # Importing the database failed.
        else
        {
            if ($databaseExists)
            {
                Write-Warning ("The database '$originalDatabaseName' remains intact and depending on the error in the" +
                    " import process, a new database may have been created with the name '$DatabaseName'!")
            }

            throw ('Importing the database failed! You might need to update SqlPackage to the latest version. You can' +
                ' download it from "https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download"!')
        }
    }
}

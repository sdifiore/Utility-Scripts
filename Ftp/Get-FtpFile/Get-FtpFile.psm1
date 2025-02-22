﻿<#
.Synopsis
   Downloads all files from a folder on an FTP server.
#>


# Session.FileTransferProgress event handler.
function Get-FtpFileTransferProgress
{
    param
    (
        [System.Object] $TransferEvent
    )

    Process
    {
        if ($null -ne $script:lastFileName -and $script:lastFileName -ne $TransferEvent.FileName)
        {
            Write-Verbose "Next File: $($TransferEvent.FileName)"
        }

        $currentFileName = $TransferEvent.FileName
        $currentFileProgress = $TransferEvent.FileProgress

        # If the progress changed compared to the previous state.
        if ($currentFileName -ne $script:lastFileName -or $currentFileProgress -ne $script:lastFileProgress)
        {
            # Print transfer progress.
            Write-Verbose ("$($TransferEvent.FileName): $($TransferEvent.FileProgress * 100)%, Overall: $($TransferEvent.OverallProgress * 100)%")

            # Remember the name of the last file reported.
            $script:lastFileName = $TransferEvent.FileName
            $script:lastFileProgress = $TransferEvent.FileProgress
        }
    }
}


function Get-FtpFile
{
    [CmdletBinding()]
    [Alias('gff')]
    Param
    (
        # The path of a folder that contains "WinSCPnet.dll" and "WinSCPnet.exe".
        [Parameter(
            Mandatory = $true,
            HelpMessage = "You need to provide the path to a folder that contains `"WinSCPnet.dll`" and `"WinSCPnet.exe`".")]
        [string] $WinSCPPath,

        [Parameter(Mandatory = $true)]
        [string] $FtpHostName,

        [Parameter(Mandatory = $true)]
        [string] $FtpUsername,

        [Parameter(Mandatory = $true)]
        [SecureString] $FtpSecurePassword,

        [Parameter(Mandatory = $true)]
        [string] $DownloadSourcePath,

        [Parameter(Mandatory = $true)]
        [string] $DownloadDestinationPath
    )

    Begin
    {
        [Reflection.Assembly]::LoadFrom("\\$WinSCPPath\WinSCPnet.dll") | Out-Null

        $script:lastFileName = ''
        $script:lastFileProgress = ''
    }
    Process
    {
        $sessionOptions = New-Object WinSCP.SessionOptions -Property @{
            Protocol = [WinSCP.Protocol]::Ftp
            FtpSecure = [WinSCP.FtpSecure]::Explicit
            HostName = $FtpHostName
            UserName = $FtpUsername
            SecurePassword = $FtpSecurePassword
        }

        $session = New-Object WinSCP.Session

        try
        {
            $session.add_FileTransferProgress({ Get-FtpFileTransferProgress($PSItem) })

            $session.Open($sessionOptions)

            if ($session.FileExists($DownloadSourcePath))
            {
                $session.GetFiles("$DownloadSourcePath/*", "$DownloadDestinationPath\*").Check()
            }
            else
            {
                throw ("The path `"$DownloadSourcePath`" is invalid!")
            }
        }
        finally
        {
            $session.Dispose()
        }
    }
}
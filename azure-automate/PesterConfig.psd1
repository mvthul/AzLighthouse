# Pester Configuration for New-AppRegistrationCredentialCheck Tests
# This file configures how Pester 5 should run the tests

@{
  Run          = @{
    Path     = @('.\New-AppRegistrationCredentialCheck.Tests.ps1')
    PassThru = $true
    Exit     = $false
  }

  TestResult   = @{
    Enabled      = $true
    OutputFormat = 'NUnitXml'
    OutputPath   = '.\TestResults.xml'
  }

  CodeCoverage = @{
    Enabled        = $true
    Path           = @('.\New-AppRegistrationCredentialCheck.ps1')
    OutputFormat   = 'JaCoCo'
    OutputPath     = '.\coverage.xml'
    OutputEncoding = 'UTF8'
    UseBreakpoints = $false
  }

  Output       = @{
    Verbosity           = 'Detailed'
    StackTraceVerbosity = 'Filtered'
    CIFormat            = 'Auto'
  }

  Should       = @{
    ErrorAction = 'Stop'
  }

  Debug        = @{
    ShowFullErrors         = $true
    WriteDebugMessages     = $false
    WriteDebugMessagesFrom = @()
    ShowNavigationMarkers  = $false
    ReturnRawResultObject  = $false
  }
}

# PSScriptAnalyzer settings for core/scripts/QeetIdKit.ps1 (CI: validate.yml).
@{
    Severity     = @('Error', 'Warning')
    # Interactive console tool: Write-Host is the intended output channel, its
    # functions are commands rather than cmdlets (no -WhatIf), and some names are
    # deliberately plural (Assert-Prerequisites, Show-Ready).
    ExcludeRules = @('PSAvoidUsingWriteHost', 'PSUseShouldProcessForStateChangingFunctions', 'PSUseSingularNouns')
    Rules        = @{
        # Must run on Windows PowerShell 5.1 (the Windows default) and PowerShell 7.
        PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1', '7.4') }
    }
}

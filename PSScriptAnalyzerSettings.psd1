@{
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')
    ExcludeRules        = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns'
    )

    Rules = @{
        PSAvoidTrailingWhitespace      = @{ Enable = $true }
        PSUseConsistentIndentation     = @{ Enable = $true; IndentationSize = 4; Kind = 'space'; PipelineIndentation = 'IncreaseIndentation' }
        PSUseConsistentWhitespace      = @{ Enable = $true; CheckInnerBrace = $true; CheckOpenBrace = $true; CheckOpenParen = $true; CheckOperator = $false; CheckPipe = $true; CheckSeparator = $true }
        PSUseCorrectCasing             = @{ Enable = $true }
        PSAlignAssignmentStatement     = @{ Enable = $true; CheckHashtable = $true; CheckPipeline = $false }
    }
}

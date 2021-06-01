# The PowerShell Script Analyzer will generate a warning
# diagnostic record for this file due to a bug -
# https://github.com/PowerShell/PSScriptAnalyzer/issues/472
@{
    # Only diagnostic records of the specified severity will be generated.
    # Uncomment the following line if you only want Errors and Warnings but
    # not Information diagnostic records.
    Severity = @('Error')

    # Analyze **only** the following rules. Use IncludeRules when you want
    # to invoke only a small subset of the defualt rules.
    # IncludeRules = @('PSAvoidDefaultValueSwitchParameter',
    #                  'PSMisleadingBacktick',
    #                  'PSMissingModuleManifestField',
    #                  'PSReservedCmdletChar',
    #                  'PSReservedParams',
    #                  'PSShouldProcess',
    #                  'PSUseApprovedVerbs',
    #                  'PSAvoidUsingCmdletAliases',
    #                  'PSUseDeclaredVarsMoreThanAssignments')

    # Do not analyze the following rules. Use ExcludeRules when you have
    # commented out the IncludeRules settings above and want to include all
    # the default rules except for those you exclude below.
    # Note: if a rule is in both IncludeRules and ExcludeRules, the rule
    # will be excluded.
    ExcludeRules = @(
        # Currently Scoop widely uses Write-Host to output colored text.
        'PSAvoidUsingWriteHost',
        # Temporarily allow uses of Invoke-Expression,
        # this command is used by some core functions and hard to be removed.
        'PSAvoidUsingInvokeExpression',
        # PSUseDeclaredVarsMoreThanAssignments doesn't currently work due to:
        # https://github.com/PowerShell/PSScriptAnalyzer/issues/636
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}

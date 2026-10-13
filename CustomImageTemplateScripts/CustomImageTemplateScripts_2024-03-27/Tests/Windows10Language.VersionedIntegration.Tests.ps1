[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$publicationRoot = Split-Path -Parent $PSScriptRoot
$installEntry = Join-Path $publicationRoot 'InstallLanguagePacks.ps1'
$lcuEntry = Join-Path $publicationRoot 'InstallWindows10Lcu.ps1'
$defaultEntry = Join-Path $publicationRoot 'SetDefaultLang.ps1'
$removedEntry = Join-Path $publicationRoot 'SetDefaultLangWin10.ps1'
$orchestrator = Join-Path $publicationRoot 'Set-Windows10MachineLanguage.ps1'
$copyHelper = Join-Path $publicationRoot 'Copy-UserInternationalSettingsToSystemCompat.ps1'
$healthCheck = Join-Path $publicationRoot 'Test-Windows10MachineLanguageHealth.ps1'
$servicingGuide = Join-Path $publicationRoot 'Windows10-Language-Servicing.md'
$customizerExample = Join-Path $publicationRoot 'Windows10-Language-ThreeRestart.Customizers.example.json'
$removedProductionFiles = @(
    'Aib-Customizers.TwoRestartCandidate.example.json',
    'Invoke-Windows10MachineLanguageAib.ps1',
    'Invoke-Windows10MachineLanguageCit.ps1'
)
$failures = New-Object System.Collections.Generic.List[string]
$passed = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Condition) {
        $script:passed++
    }
    else {
        $script:failures.Add($Message)
    }
}

function Assert-ThrowsLike {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    try {
        & $Action
        $script:failures.Add($Message)
    }
    catch {
        if ($_.Exception.Message -match $Pattern) {
            $script:passed++
        }
        else {
            $script:failures.Add("$Message Actual: $($_.Exception.Message)")
        }
    }
}

function Get-NormalizedSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha.ComputeHash(
                [Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n", "`n"))
            )
        )).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

foreach ($path in @(
    $installEntry,
    $lcuEntry,
    $defaultEntry,
    $orchestrator,
    $copyHelper,
    $healthCheck,
    $servicingGuide,
    $customizerExample
)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required file is missing: $path"
}
Assert-True (-not (Test-Path -LiteralPath $removedEntry)) 'The separate Windows 10 entry point still exists.'
foreach ($fileName in $removedProductionFiles) {
    Assert-True (
        -not (Test-Path -LiteralPath (Join-Path $publicationRoot $fileName))
    ) "Removed production phase file still exists: $fileName"
}

foreach ($path in @($installEntry, $lcuEntry, $defaultEntry, $orchestrator, $copyHelper, $healthCheck)) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$parseErrors
    )
    Assert-True ($parseErrors.Count -eq 0) "PowerShell parse errors in $path`: $($parseErrors -join '; ')"
}

$installText = [IO.File]::ReadAllText($installEntry)
$lcuEntryText = [IO.File]::ReadAllText($lcuEntry)
$defaultText = [IO.File]::ReadAllText($defaultEntry)
$orchestratorText = [IO.File]::ReadAllText($orchestrator)
$guideText = [IO.File]::ReadAllText($servicingGuide)
$customizerExampleText = [IO.File]::ReadAllText($customizerExample)

$installBodyStart = $installText.IndexOf('function Install-LanguagePack', [StringComparison]::Ordinal)
Assert-True ($installBodyStart -ge 0) 'The Windows 11 InstallLanguagePacks body marker is missing.'
if ($installBodyStart -ge 0) {
    Assert-True (
        (Get-NormalizedSha256 $installText.Substring($installBodyStart)) -eq
        '89260239FEAE261A2D17F9B02E0C8A9B19A70F80A58A83D75511AFED8BA4C16A'
    ) 'The pre-existing Windows 11 InstallLanguagePacks body changed.'
}

$defaultBodyStart = $defaultText.IndexOf('function Get-RegionInfo', [StringComparison]::Ordinal)
Assert-True ($defaultBodyStart -ge 0) 'The Windows 11 SetDefaultLang body marker is missing.'
if ($defaultBodyStart -ge 0) {
    Assert-True (
        (Get-NormalizedSha256 $defaultText.Substring($defaultBodyStart)) -eq
        'F8F81A3789D77CE0DBCB5C72EDD5914E4FEBE426F2149963452DE919CFCC1D9A'
    ) 'The pre-existing Windows 11 SetDefaultLang body changed.'
}

Assert-True (
    $installText -match '\$osBuildForDispatch\s+-in\s+@\(19044,\s*19045\)'
) 'InstallLanguagePacks Windows 10 dispatch is not restricted to builds 19044 and 19045.'
Assert-True (
    $defaultText -match '\$osBuildForDispatch\s+-in\s+@\(19044,\s*19045\)'
) 'SetDefaultLang Windows 10 dispatch is not restricted to builds 19044 and 19045.'
Assert-True (
    $installText -match '&\s+\$windows10OrchestratorPath[\s\S]+-AibPhase InstallLanguage[\s\S]+-AllowRecognizedNonServicingPendingFileRenames[\s\S]+return'
) 'InstallLanguagePacks does not invoke the approved install phase with the narrow PFRO opt-in and return.'
Assert-True (
    $lcuEntryText -match '-Resume[\s\S]+-AibPhase InstallLcu[\s\S]+-WorkingDirectory'
) 'InstallWindows10Lcu does not invoke only the durable LCU resume phase.'
Assert-True (
    $defaultText -match '&\s+\$windows10OrchestratorPath[\s\S]+-Resume[\s\S]+-AibPhase ApplyMachineLanguage[\s\S]+-ExpectedLanguageTag \$languageTag[\s\S]+return'
) 'SetDefaultLang does not invoke the persisted apply phase and return.'

Assert-True (
    $installText -match '\[System\.String\[\]\]\$LanguageList'
) 'The existing InstallLanguagePacks LanguageList parameter contract changed.'
Assert-True (
    $defaultText -match '\[string\]\$Language\s*\r?\n\)'
) 'The existing SetDefaultLang Language parameter contract changed.'
Assert-True (
    $installText -match 'List\[string\][\s\S]+HashSet\[string\][\s\S]+foreach \(\$language in \$LanguageList\)[\s\S]+\$seenLanguageTags\.Add\(\$languageTag\)'
) 'Windows 10 language mapping is not deterministic or does not de-duplicate while retaining request order.'
Assert-True (
    $orchestratorText -match "\[Parameter\(Mandatory = \`$true, ParameterSetName = 'OnlineMultiLanguage'\)\][\s\S]+\[string\[\]\]\`$LanguageTags"
) 'The orchestrator multi-language online parameter set is missing.'
Assert-True (
    $orchestratorText -match 'Get-LanguagePacksFromMicrosoft[\s\S]+foreach \(\$targetLanguageTag in \$TargetLanguageTags\)'
) 'The official language media is not shared across all requested languages.'
Assert-True (
    $orchestratorText -match 'foreach \(\$targetLanguageTag in \$targetLanguageTags\) \{[\s\S]+?Install-TargetLanguage'
) 'InstallAndService does not install every requested language deterministically.'
Assert-True (
    $orchestratorText -match 'Get-WindowsUpdateLcuSelection[\s\S]+Cumulative Update for Windows 10[\s\S]+-notmatch ''\\\.NET\|Preview'''
) 'The approved non-preview Windows Update LCU selection path changed.'
Assert-True (
    $orchestratorText -match 'foreach \(\$targetLanguageTag in \$targetLanguageTags\) \{\s*Assert-LanguageServicedToCurrentUbr'
) 'Language/UBR parity is not checked for every requested language.'
Assert-True (
    $orchestratorText -match 'Get-DiskImage -ImagePath \$ImagePath[\s\S]+Get-Volume'
) 'Language media discovery is not scoped to the exact mounted ISO association.'
Assert-True (
    $orchestratorText -match 'AddSeconds\(30\)[\s\S]+Start-Sleep -Seconds 1'
) 'Language media discovery does not use bounded polling.'
Assert-True (
    $orchestratorText -match "\`$candidateDriveType -ne 'CD-ROM'" -and
    $orchestratorText -match "\`$candidateFileSystem -notin @\('UDF', 'CDFS'\)"
) 'Language media discovery does not require the expected optical filesystem.'
Assert-True (
    $orchestratorText -match 'Get-Volume -ErrorAction Stop[\s\S]+Get-PSDrive -PSProvider FileSystem'
) 'Temporary drive-letter allocation does not exclude both volume and filesystem allocations.'
Assert-True (
    $orchestratorText -match "foreach \(\`$codePoint in \[int\]\[char\]'Z'\.\.\[int\]\[char\]'D'\)"
) 'Temporary drive-letter allocation is not restricted to Z through D.'
Assert-True (
    $orchestratorText -match 'Add-PartitionAccessPath[\s\S]+Verified temporary access path'
) 'Temporary ISO access-path assignment is not ownership-verified.'
Assert-True (
    $orchestratorText -match 'Remove-PartitionAccessPath[\s\S]+Dismount-DiskImage -ImagePath \$isoPath[\s\S]+Remove-Item -LiteralPath \$isoPath'
) 'Temporary access path, exact dismount, and ISO deletion cleanup are incomplete.'
Assert-True (
    $orchestratorText -match 'Language-pack ISO processing failed:[\s\S]+Cleanup also failed:'
) 'Primary and cleanup ISO failures are not preserved together.'
Assert-True (
    $orchestratorText -notmatch 'Set-StorageSetting|automount|mountvol'
) 'Language media recovery changes global automount behavior.'
Assert-True (
    $orchestratorText -match 'DeferLanguageSelection[\s\S]+Requested default language[\s\S]+Set-CurrentUserLanguage'
) 'Default language selection is not deferred to SetDefaultLang.'
Assert-True (
    $installText -notmatch '-AibPhase\s+Validate' -and
    $defaultText -notmatch '-AibPhase\s+Validate'
) 'A production entry still invokes the removed Validate phase.'

$orchestratorTokens = $null
$orchestratorParseErrors = $null
$orchestratorAst = [Management.Automation.Language.Parser]::ParseFile(
    $orchestrator,
    [ref]$orchestratorTokens,
    [ref]$orchestratorParseErrors
)
$stateLanguageTagsAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-StateLanguageTags'
}, $true)
$stateLanguagePackPathAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-StateLanguagePackPath'
}, $true)
$initialPhaseAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-InitialPhase'
}, $true)
$installLanguagePhaseAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-InstallLanguagePhase'
}, $true)
$installLcuPhaseAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-InstallLcuPhase'
}, $true)
$servicingReadyStateAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Test-ServicingReadyState'
}, $true)
$windowsUpdateFailureDispositionAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-WindowsUpdateInstallFailureDisposition'
}, $true)
$lcuStartBlockReasonAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-LcuStartBlockReason'
}, $true)
$readStateAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Read-State'
}, $true)
$writeStateAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Write-State'
}, $true)
$getFileSha256Ast = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-FileSha256'
}, $true)
$assertStateContractAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Assert-StateContract'
}, $true)
$assertPortalRestartCompletedAst = $orchestratorAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Assert-PortalRestartCompleted'
}, $true)
Assert-True ($null -ne $stateLanguageTagsAst) 'Get-StateLanguageTags is missing.'
Assert-True ($null -ne $stateLanguagePackPathAst) 'Get-StateLanguagePackPath is missing.'
Assert-True ($null -ne $initialPhaseAst) 'Invoke-InitialPhase is missing.'
Assert-True ($null -ne $installLanguagePhaseAst) 'Invoke-InstallLanguagePhase is missing.'
Assert-True ($null -ne $installLcuPhaseAst) 'Invoke-InstallLcuPhase is missing.'
Assert-True ($null -ne $servicingReadyStateAst) 'Test-ServicingReadyState is missing.'
Assert-True ($null -ne $windowsUpdateFailureDispositionAst) 'Get-WindowsUpdateInstallFailureDisposition is missing.'
Assert-True ($null -ne $lcuStartBlockReasonAst) 'Get-LcuStartBlockReason is missing.'
Assert-True ($null -ne $readStateAst) 'Read-State is missing.'
Assert-True ($null -ne $writeStateAst) 'Write-State is missing.'
Assert-True ($null -ne $getFileSha256Ast) 'Get-FileSha256 is missing.'
Assert-True ($null -ne $assertStateContractAst) 'Assert-StateContract is missing.'
Assert-True ($null -ne $assertPortalRestartCompletedAst) 'Assert-PortalRestartCompleted is missing.'
if ($null -ne $stateLanguageTagsAst -and $null -ne $stateLanguagePackPathAst) {
    . ([scriptblock]::Create($stateLanguageTagsAst.Extent.Text))
    . ([scriptblock]::Create($stateLanguagePackPathAst.Extent.Text))

    $liveState = [pscustomobject]@{
        LanguageTags = @('fr-FR', 'de-DE')
        LanguagePackCabPaths = @{
            'fr-FR' = 'C:\staged\fr-FR.cab'
            'de-DE' = 'C:\staged\de-DE.cab'
        }
    }
    Assert-True (
        (@(Get-StateLanguageTags -State $liveState) -join '|') -ceq 'fr-FR|de-DE'
    ) 'Live multi-language state does not preserve deterministic order.'
    Assert-True (
        (Get-StateLanguagePackPath -State $liveState -TargetLanguageTag 'de-DE') -eq
        'C:\staged\de-DE.cab'
    ) 'Live multi-language state does not resolve a staged CAB.'

    $persistedState = $liveState | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    Assert-True (
        (@(Get-StateLanguageTags -State $persistedState) -join '|') -ceq 'fr-FR|de-DE'
    ) 'Persisted multi-language state does not preserve deterministic order.'
    Assert-True (
        (Get-StateLanguagePackPath -State $persistedState -TargetLanguageTag 'fr-FR') -eq
        'C:\staged\fr-FR.cab'
    ) 'Persisted multi-language state does not resolve a staged CAB.'
}

if ($null -ne $initialPhaseAst) {
    Assert-True (
        $initialPhaseAst.Extent.Text -notmatch 'Get-WindowsUpdateLcuSelection'
    ) 'The initial phase still queries Windows Update before language installation.'
}
if ($null -ne $servicingReadyStateAst) {
    . ([scriptblock]::Create($servicingReadyStateAst.Extent.Text))
    Assert-True (
        -not (Test-ServicingReadyState `
            -PendingReasons @() `
            -ActiveInstallerNames @('TiWorker') `
            -AllowPendingRestart)
    ) 'AllowPendingRestart incorrectly bypasses an active servicing installer.'
    Assert-True (
        (Test-ServicingReadyState `
            -PendingReasons @('CBS RebootPending') `
            -ActiveInstallerNames @() `
            -AllowPendingRestart)
    ) 'AllowPendingRestart no longer permits the planned pre-LCU restart state.'
    Assert-True (
        -not (Test-ServicingReadyState `
            -PendingReasons @('CBS RebootPending') `
            -ActiveInstallerNames @())
    ) 'Normal servicing readiness no longer fails closed for a pending restart.'
}
if ($null -ne $windowsUpdateFailureDispositionAst) {
    . ([scriptblock]::Create($windowsUpdateFailureDispositionAst.Extent.Text))
    Assert-True (
        (Get-WindowsUpdateInstallFailureDisposition `
            -HResult -2145124330 `
            -PendingReasons @()) -eq 'TransientBusy'
    ) '0x80240016 without reboot signals is not classified as a transient servicing race.'
    Assert-True (
        (Get-WindowsUpdateInstallFailureDisposition `
            -HResult -2145124330 `
            -PendingReasons @('Windows Update RebootRequired')) -eq 'PendingRestart'
    ) '0x80240016 with a reboot signal is not classified as a mandatory restart.'
    Assert-True (
        (Get-WindowsUpdateInstallFailureDisposition `
            -HResult -2145124329 `
            -PendingReasons @()) -eq 'Fatal'
    ) 'An unrelated Windows Update error is incorrectly retryable.'
}
if ($null -ne $lcuStartBlockReasonAst) {
    . ([scriptblock]::Create($lcuStartBlockReasonAst.Extent.Text))
    Assert-True (
        $null -eq (Get-LcuStartBlockReason -PendingReasons @())
    ) 'LCU installation is blocked when no servicing restart is pending.'
    $pendingRestartBlockReason = Get-LcuStartBlockReason -PendingReasons @(
        'CBS RebootPending',
        'Windows Update RebootRequired'
    )
    Assert-True (
        $pendingRestartBlockReason -match 'CBS RebootPending' -and
        $pendingRestartBlockReason -match 'Windows Update RebootRequired' -and
        $pendingRestartBlockReason -match 'two-restart AIB workflow' -and
        $pendingRestartBlockReason -match 'restart boundary before the LCU'
    ) 'The pre-LCU pending-restart failure is not explicit and actionable.'
    Assert-True (
        $pendingRestartBlockReason -notmatch '267014|0x41306|success'
    ) 'The pre-LCU guard incorrectly treats the task termination code as an install result.'
}
if (
    $null -ne $readStateAst -and
    $null -ne $writeStateAst -and
    $null -ne $getFileSha256Ast -and
    $null -ne $assertStateContractAst
) {
    . ([scriptblock]::Create($readStateAst.Extent.Text))
    . ([scriptblock]::Create($writeStateAst.Extent.Text))
    . ([scriptblock]::Create($getFileSha256Ast.Extent.Text))
    . ([scriptblock]::Create($assertStateContractAst.Extent.Text))

    $stateTestRoot = Join-Path ([IO.Path]::GetTempPath()) (
        'Windows10LanguageStateTest-{0}' -f [guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $stateTestRoot -Force | Out-Null
    try {
        $script:WorkingDirectory = $stateTestRoot
        $script:statePath = Join-Path $stateTestRoot 'state.json'
        $script:installedScriptPath = Join-Path $stateTestRoot 'Set-Windows10MachineLanguage.ps1'
        $script:installedHelperPath = Join-Path $stateTestRoot 'Copy-UserInternationalSettingsToSystemCompat.ps1'
        Set-Content -LiteralPath $script:installedScriptPath -Value 'orchestrator' -Encoding ASCII
        Set-Content -LiteralPath $script:installedHelperPath -Value 'helper' -Encoding ASCII
        $packagePath = Join-Path $stateTestRoot 'lcu.msu'
        Set-Content -LiteralPath $packagePath -Value 'package' -Encoding ASCII
        $validState = [pscustomobject][ordered]@{
            StateSchemaVersion = 2
            OperationId = [guid]::NewGuid().ToString('D')
            Phase = 'PostLanguageContentRestart'
            LanguageTags = @('fr-FR')
            LcuMode = 'Package'
            LcuPackagePath = $packagePath
            RequireRdp = $true
            WorkingDirectory = $stateTestRoot
            OrchestratorSha256 = Get-FileSha256 -Path $script:installedScriptPath
            CopyHelperSha256 = Get-FileSha256 -Path $script:installedHelperPath
            StartedUtc = (Get-Date).AddMinutes(-5).ToUniversalTime().ToString('o')
            PhaseStartedUtc = (Get-Date).AddMinutes(-2).ToUniversalTime().ToString('o')
            FailureCount = 0
            UpdatedUtc = $null
        }
        Write-State -State $validState
        $roundTrippedState = Read-State
        Assert-StateContract -State $roundTrippedState
        Assert-True (
            [string]$roundTrippedState.OperationId -eq [string]$validState.OperationId -and
            -not (Test-Path -LiteralPath "$script:statePath.partial")
        ) 'Valid durable state did not round-trip atomically.'

        Set-Content -LiteralPath $script:statePath -Value '{' -Encoding ASCII
        Assert-ThrowsLike {
            [void](Read-State)
        } 'corrupt or unreadable' 'Corrupt state did not fail closed.'
        Remove-Item -LiteralPath $script:statePath -Force
        Assert-ThrowsLike {
            [void](Read-State)
        } 'State file was not found' 'Missing durable state did not fail closed.'

        $missingPropertyState = $validState | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $missingPropertyState.PSObject.Properties.Remove('OperationId')
        Assert-ThrowsLike {
            Assert-StateContract -State $missingPropertyState
        } 'missing required property' 'State missing a required property did not fail closed.'

        $staleState = $validState | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $staleState.WorkingDirectory = Join-Path $stateTestRoot 'different'
        Assert-ThrowsLike {
            Assert-StateContract -State $staleState
        } 'does not match the requested directory' 'Stale state from another working directory did not fail closed.'

        $wrongSchemaState = $validState | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $wrongSchemaState.StateSchemaVersion = 1
        Assert-ThrowsLike {
            Assert-StateContract -State $wrongSchemaState
        } 'Unsupported state schema version' 'An old state schema did not fail closed.'

        $inconsistentTimestampState = $validState | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $inconsistentTimestampState.StartedUtc = (Get-Date).AddMinutes(10).ToUniversalTime().ToString('o')
        Assert-ThrowsLike {
            Assert-StateContract -State $inconsistentTimestampState
        } 'timestamps are inconsistent' 'Inconsistent phase timestamps did not fail closed.'

        $emptyLanguageState = $validState | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $emptyLanguageState.LanguageTags = @('')
        Assert-ThrowsLike {
            Assert-StateContract -State $emptyLanguageState
        } 'empty language tag' 'An empty durable language contract did not fail closed.'

        Add-Content -LiteralPath $script:installedScriptPath -Value 'changed'
        Assert-ThrowsLike {
            Assert-StateContract -State $validState
        } 'orchestrator no longer matches' 'Modified durable orchestrator did not fail closed.'
        Set-Content -LiteralPath $script:installedScriptPath -Value 'orchestrator' -Encoding ASCII

        Remove-Item -LiteralPath $packagePath -Force
        Assert-ThrowsLike {
            Assert-StateContract -State $validState
        } 'durable LCU package.+is missing' 'Missing package-mode LCU did not fail closed.'
    }
    finally {
        Remove-Item -LiteralPath $stateTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($null -ne $assertPortalRestartCompletedAst) {
    . ([scriptblock]::Create($assertPortalRestartCompletedAst.Extent.Text))
    try {
        function script:Get-CimInstance {
            [pscustomobject]@{ LastBootUpTime = [datetime]'2026-10-13T10:00:00Z' }
        }
        Assert-PortalRestartCompleted -State ([pscustomobject]@{
            PhaseStartedUtc = '2026-10-13T09:59:59Z'
        })
        $script:passed++
        Assert-ThrowsLike {
            Assert-PortalRestartCompleted -State ([pscustomobject]@{
                PhaseStartedUtc = '2026-10-13T10:00:00Z'
            })
        } 'required portal restart customizer did not run' 'Missing boot boundary did not fail closed.'
    }
    finally {
        Remove-Item Function:\script:Get-CimInstance -ErrorAction SilentlyContinue
    }
}
if ($null -ne $installLanguagePhaseAst) {
    $installLanguageText = $installLanguagePhaseAst.Extent.Text
    Assert-True (
        $installLanguageText -match "Phase = 'PostLanguageContentRestart'" -and
        $installLanguageText -match 'Request-Restart.+before LCU evaluation'
    ) 'The language/FoD phase does not persist the pre-LCU restart boundary.'
    Assert-True (
        $installLanguageText -notmatch 'Get-WindowsUpdateLcuSelection|Install-LcuFrom'
    ) 'The language/FoD phase can still start LCU acquisition or installation.'
}
if ($null -ne $installLcuPhaseAst) {
    $installLcuText = $installLcuPhaseAst.Extent.Text
    $assertRestartIndex = $installLcuText.IndexOf(
        'Assert-PortalRestartCompleted',
        [StringComparison]::Ordinal
    )
    $waitReadyIndex = $installLcuText.IndexOf(
        'Wait-ForServicingReady',
        [StringComparison]::Ordinal
    )
    $verifyLanguageIndex = $installLcuText.IndexOf(
        'Wait-ForLanguagePackage',
        [StringComparison]::Ordinal
    )
    $selectLcuIndex = $installLcuText.IndexOf(
        'Get-WindowsUpdateLcuSelection',
        [StringComparison]::Ordinal
    )
    $installLcuIndex = $installLcuText.IndexOf(
        'Install-LcuFromWindowsUpdate',
        [StringComparison]::Ordinal
    )
    Assert-True (
        $assertRestartIndex -ge 0 -and
        $waitReadyIndex -gt $assertRestartIndex -and
        $verifyLanguageIndex -gt $waitReadyIndex -and
        $selectLcuIndex -gt $verifyLanguageIndex -and
        $installLcuIndex -gt $selectLcuIndex
    ) 'InstallLcu does not verify boot, servicing readiness, language presence, and parity before WUA.'
    $assertLcuStartIndex = $installLcuText.IndexOf(
        'Assert-LcuInstallationCanStart',
        [StringComparison]::Ordinal
    )
    Assert-True (
        $assertLcuStartIndex -gt $verifyLanguageIndex -and
        $assertLcuStartIndex -lt $selectLcuIndex
    ) 'The resumed LCU path does not reject a genuine pending restart before Windows Update.'
    Assert-True (
        $installLcuText -match "Phase = 'PostLcuRestart'" -and
        $installLcuText -match 'Request-Restart'
    ) 'InstallLcu does not persist confirmed completion before the LCU restart.'

    . ([scriptblock]::Create($installLcuPhaseAst.Extent.Text))
    try {
        $script:phaseCallLog = New-Object System.Collections.Generic.List[string]
        $script:parityFailure = $true
        $script:blockLcuStart = $false
        function script:Assert-PortalRestartCompleted { $script:phaseCallLog.Add('BootBoundary') }
        function script:Start-Sleep { $script:phaseCallLog.Add('Stabilization') }
        function script:Wait-ForServicingReady { $script:phaseCallLog.Add('ServicingReady') }
        function script:Get-StateLanguageTags { param($State) return @($State.LanguageTags) }
        function script:Wait-ForLanguagePackage {
            param($TargetLanguageTag)
            $script:phaseCallLog.Add("Language:$TargetLanguageTag")
            return [pscustomobject]@{ PackageName = $TargetLanguageTag }
        }
        function script:Write-Operation { param($Message) }
        function script:Assert-LanguageServicedToCurrentUbr {
            if ($script:parityFailure) { throw 'revision mismatch' }
            $script:phaseCallLog.Add('Parity')
        }
        function script:Assert-LcuInstallationCanStart {
            $script:phaseCallLog.Add('LcuGuard')
            if ($script:blockLcuStart) { throw 'pending restart remains' }
        }
        function script:Install-LcuFromPackage {
            param($PackagePath)
            $script:phaseCallLog.Add("Package:$PackagePath")
        }
        function script:Get-WindowsUpdateLcuSelection {
            $script:phaseCallLog.Add('WuSelect')
            return [pscustomobject]@{
                Session = 'session'
                Update = [pscustomobject]@{ Title = 'LCU' }
            }
        }
        function script:Install-LcuFromWindowsUpdate {
            param($Selection)
            $script:phaseCallLog.Add('WuInstall')
        }
        function script:Write-State { param($State) $script:phaseCallLog.Add("State:$($State.Phase)") }
        function script:Register-ResumeTask { $script:phaseCallLog.Add('Register') }
        function script:Request-Restart { param($Reason) $script:phaseCallLog.Add('Restart') }

        $packageState = [pscustomobject]@{
            LanguageTags = @('fr-FR')
            LcuMode = 'Package'
            LcuPackagePath = 'C:\staged\lcu.msu'
            Phase = 'PostLanguageContentRestart'
            PhaseStartedUtc = (Get-Date).AddMinutes(-5).ToString('o')
            Error = 'old'
        }
        Invoke-InstallLcuPhase -State $packageState
        Assert-True (
            ($script:phaseCallLog -join '|') -match
                'BootBoundary\|Stabilization\|ServicingReady\|Language:fr-FR\|LcuGuard\|Package:C:\\staged\\lcu.msu' -and
            $packageState.Phase -eq 'PostLcuRestart' -and
            $script:phaseCallLog -contains 'Restart'
        ) 'Package-mode LCU resume did not preserve the required verified order.'

        $script:phaseCallLog.Clear()
        $windowsUpdateState = [pscustomobject]@{
            LanguageTags = @('fr-FR')
            LcuMode = 'OnlineMultiLanguage'
            LcuPackagePath = $null
            Phase = 'PostLanguageContentRestart'
            PhaseStartedUtc = (Get-Date).AddMinutes(-5).ToString('o')
            Error = $null
        }
        Invoke-InstallLcuPhase -State $windowsUpdateState
        Assert-True (
            ($script:phaseCallLog -join '|') -match 'LcuGuard\|WuSelect\|WuInstall' -and
            $windowsUpdateState.Phase -eq 'PostLcuRestart'
        ) 'Windows Update mode did not select and confirm the LCU after resume.'

        $script:phaseCallLog.Clear()
        $windowsUpdateState.Phase = 'PostLanguageContentRestart'
        function script:Install-LcuFromWindowsUpdate {
            param($Selection)
            $script:phaseCallLog.Add('WuInstall')
            throw 'LCU result was not confirmed'
        }
        Assert-ThrowsLike {
            Invoke-InstallLcuPhase -State $windowsUpdateState
        } 'LCU result was not confirmed' 'An unconfirmed Windows Update result did not fail closed.'
        Assert-True (
            $windowsUpdateState.Phase -eq 'PostLanguageContentRestart' -and
            $script:phaseCallLog -notcontains 'Restart'
        ) 'An unconfirmed LCU result advanced durable state or requested restart.'
        function script:Install-LcuFromWindowsUpdate {
            param($Selection)
            $script:phaseCallLog.Add('WuInstall')
        }

        $script:phaseCallLog.Clear()
        $script:parityFailure = $false
        $noLcuState = [pscustomobject]@{
            LanguageTags = @('fr-FR')
            LcuMode = 'WindowsUpdate'
            LcuPackagePath = $null
            Phase = 'PostLanguageContentRestart'
            PhaseStartedUtc = (Get-Date).AddMinutes(-5).ToString('o')
            Error = $null
        }
        Invoke-InstallLcuPhase -State $noLcuState
        Assert-True (
            $script:phaseCallLog -notcontains 'WuSelect' -and
            -not (($script:phaseCallLog -join '|') -match 'Package:') -and
            $noLcuState.Phase -eq 'PostLcuRestart' -and
            $script:phaseCallLog -contains 'Restart'
        ) 'Parity-satisfied resume did not skip LCU installation while retaining the managed restart.'

        $script:phaseCallLog.Clear()
        $script:parityFailure = $true
        $script:blockLcuStart = $true
        Assert-ThrowsLike {
            Invoke-InstallLcuPhase -State $windowsUpdateState
        } 'pending restart remains' 'A genuine pending restart after resume did not fail before WUA.'
        Assert-True (
            $script:phaseCallLog -notcontains 'WuSelect' -and
            $script:phaseCallLog -notcontains 'WuInstall'
        ) 'WUA started after the resumed pre-LCU guard failed.'

        $script:phaseCallLog.Clear()
        $script:blockLcuStart = $false
        function script:Wait-ForServicingReady {
            throw 'servicing activity timeout'
        }
        Assert-ThrowsLike {
            Invoke-InstallLcuPhase -State $windowsUpdateState
        } 'servicing activity timeout' 'Installer activity timeout after resume did not fail closed.'
        Assert-True (
            $script:phaseCallLog -notcontains 'WuSelect' -and
            $script:phaseCallLog -notcontains 'WuInstall'
        ) 'WUA started after servicing readiness timed out.'
    }
    finally {
        foreach ($functionName in @(
            'Assert-PortalRestartCompleted',
            'Start-Sleep',
            'Wait-ForServicingReady',
            'Get-StateLanguageTags',
            'Wait-ForLanguagePackage',
            'Write-Operation',
            'Assert-LanguageServicedToCurrentUbr',
            'Assert-LcuInstallationCanStart',
            'Install-LcuFromPackage',
            'Get-WindowsUpdateLcuSelection',
            'Install-LcuFromWindowsUpdate',
            'Write-State',
            'Register-ResumeTask',
            'Request-Restart'
        )) {
            Remove-Item "Function:\script:$functionName" -ErrorAction SilentlyContinue
        }
    }
}
if ($null -ne $initialPhaseAst) {
    $initialPhaseText = $initialPhaseAst.Extent.Text
    $installLanguageIndex = $initialPhaseText.IndexOf(
        'Install-TargetLanguage',
        [StringComparison]::Ordinal
    )
    Assert-True (
        $initialPhaseText -match "StateSchemaVersion\s+= 2" -and
        $initialPhaseText -match "Phase\s+= 'InstallingLanguage'" -and
        $initialPhaseText -match 'OrchestratorSha256' -and
        $initialPhaseText -match 'CopyHelperSha256'
    ) 'Initial state is not versioned and integrity-bound for durable resume.'
    Assert-True (
        $initialPhaseText -match "Phase -eq 'InstallingLanguage'[\s\S]+Invoke-InstallLanguagePhase" -and
        $initialPhaseText -match "Phase -eq 'PostLanguageContentRestart'[\s\S]+already complete"
    ) 'The initial AIB phase is not idempotent for interrupted or completed durable state.'
}

Assert-True ($orchestratorText -match 'AllowRecognizedNonServicingPendingFileRenames') 'The PFRO opt-in is missing.'
Assert-True ($orchestratorText -match 'Test-RecognizedNonServicingPendingFileRenamePair') 'The PFRO allowlist classifier is missing.'
Assert-True ($orchestratorText -match 'Operations\.Count % 2') 'Malformed PFRO pair counts are not fail-closed.'
Assert-True ($orchestratorText -match 'servicing|winsxs|cbstemp|softwaredistribution') 'Servicing-related PFRO paths are not explicitly classified.'
Assert-True ($orchestratorText -notmatch 'Remove-ItemProperty.+PendingFileRenameOperations') 'The workflow modifies PFRO registry data.'

$orchestratorHash = Get-NormalizedSha256 ([IO.File]::ReadAllText($orchestrator))
$copyHelperHash = Get-NormalizedSha256 ([IO.File]::ReadAllText($copyHelper))
Assert-True ($installText -match [regex]::Escape($orchestratorHash)) 'InstallLanguagePacks does not pin the current orchestrator hash.'
Assert-True ($lcuEntryText -match [regex]::Escape($orchestratorHash)) 'InstallWindows10Lcu does not pin the current orchestrator hash.'
Assert-True ($defaultText -match [regex]::Escape($orchestratorHash)) 'SetDefaultLang does not pin the current orchestrator hash.'
Assert-True ($installText -match [regex]::Escape($copyHelperHash)) 'InstallLanguagePacks does not pin the current compatibility-helper hash.'
Assert-True ($lcuEntryText -match [regex]::Escape($copyHelperHash)) 'InstallWindows10Lcu does not re-verify the compatibility-helper hash.'
Assert-True ($defaultText -match [regex]::Escape($copyHelperHash)) 'SetDefaultLang does not re-verify the compatibility-helper hash.'
Assert-True (
    ([regex]::Matches($installText, 'windows10SupportBaseUri')).Count -ge 3
) 'The Windows 10 support location is not isolated behind one base URI.'
$immutableSupportBaseUri = (
    'https://raw.githubusercontent.com/anshuljswl/RDS-Templates/' +
    'dcaa3564c8975df11a09e152e3b852cc9277a6cb/' +
    'CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27'
)
Assert-True (
    $installText -match [regex]::Escape($immutableSupportBaseUri)
) 'InstallLanguagePacks does not use the immutable validation support source.'
Assert-True (
    $defaultText -match [regex]::Escape($immutableSupportBaseUri)
) 'SetDefaultLang does not identify the immutable validation support source.'
Assert-True (
    $immutableSupportBaseUri -match '/[0-9a-f]{40}/'
) 'The Windows 10 support source is not pinned to a full commit SHA.'
Assert-True (
    $orchestratorText -match 'Assert-PortalRestartCompleted[\s\S]+LastBootUpTime[\s\S]+did not run or did not complete'
) 'The second entry cannot detect a missing or incomplete portal restart.'
Assert-True (
    $orchestratorText -match 'Language/UBR parity requires LCU reapplication'
) 'The LCU reapplication decision does not preserve its diagnostic reason.'
Assert-True (
    $orchestratorText -match 'MaximumInstallAttempts = 3' -and
    $orchestratorText -match "Get-WindowsUpdateInstallFailureDisposition" -and
    $orchestratorText -match 'Inspect Windows Update, CBS, and UsoClient logs'
) 'The Windows Update busy retry is not bounded or does not retain actionable failure diagnostics.'
Assert-True (
    $orchestratorText -notmatch '267014|0x41306'
) 'The orchestrator accepts or interprets the AIB task-termination code.'
Assert-True (
    $orchestratorText -match "AIB phase '\`$AibPhase' is already complete" -and
    $orchestratorText -match "InstallLcu'\) \{\s*'PostLcuRestart'" -and
    $orchestratorText -match "ApplyMachineLanguage'\) \{\s*'PostLanguageRestart'"
) 'AIB phase resume is not idempotent after a confirmed durable transition.'

$customizerExampleObject = $customizerExampleText | ConvertFrom-Json
$customizerNames = @($customizerExampleObject.customize | ForEach-Object { $_.name })
Assert-True (
    ($customizerNames -join '|') -eq (
        'Windows10Language-1-InstallLanguage|' +
        'Windows10Language-2-RestartBeforeLcu|' +
        'Windows10Language-3-InstallLcu|' +
        'Windows10Language-4-RestartAfterLcu|' +
        'Windows10Language-5-ApplyMachineLanguage|' +
        'Windows10Language-6-RestartAfterLanguage'
    )
) 'The Windows 10 customizer example does not preserve the fixed three-restart order.'
Assert-True (
    @($customizerExampleObject.customize | Where-Object type -eq 'WindowsRestart').Count -eq 3
) 'The Windows 10 customizer example does not contain exactly three managed restarts.'
Assert-True (
    @(
        $customizerExampleObject.customize |
            Where-Object type -eq 'WindowsRestart' |
            Where-Object {
                $_.restartTimeout -eq '30m' -and
                $_.restartCheckCommand -match 'Start-Sleep -Seconds 180'
            }
    ).Count -eq 3
) 'The three managed restarts do not use the validated timeout and stabilization command.'
$powerShellCustomizers = @($customizerExampleObject.customize | Where-Object type -eq 'PowerShell')
Assert-True (
    @(
        $powerShellCustomizers |
            Where-Object {
                @($_.validExitCodes).Count -eq 1 -and
                [int]$_.validExitCodes[0] -eq 0
            }
    ).Count -eq 3
) 'The PowerShell customizers do not accept exit code 0 exclusively.'
Assert-True (
    @($powerShellCustomizers[0].inline).Count -eq 1 -and
    [string]$powerShellCustomizers[0].inline[0] -match 'Invoke-WebRequest' -and
    [string]$powerShellCustomizers[0].inline[0] -match 'Get-FileHash' -and
    [string]$powerShellCustomizers[0].inline[0] -match "-LanguageList @\('French \(France\)'\)"
) 'The language customizer does not securely invoke the parameterized wrapper.'
Assert-True (
    [string]$powerShellCustomizers[1].scriptUri -eq '<immutable-install-windows10-lcu-uri>' -and
    [string]$powerShellCustomizers[1].sha256Checksum -eq '<install-windows10-lcu-sha256>'
) 'The parameterless LCU customizer is not represented by an integrity-pinned script URI.'
Assert-True (
    @($powerShellCustomizers[2].inline).Count -eq 1 -and
    [string]$powerShellCustomizers[2].inline[0] -match 'Invoke-WebRequest' -and
    [string]$powerShellCustomizers[2].inline[0] -match 'Get-FileHash' -and
    [string]$powerShellCustomizers[2].inline[0] -match "-Language 'French \(France\)'"
) 'The apply-language customizer does not securely invoke the parameterized wrapper.'
Assert-True (
    $customizerExampleText -notmatch '267014|0x41306|allowedExitCodes|shutdown.+PowerShell'
) 'The customizer example uses an unsafe task-exit or self-reboot workaround.'

Assert-True ($guideText -match 'There is\s+no production `Validate` customizer') 'The guide does not document external-only validation.'
Assert-True ($guideText -match 'restartTimeout`: at least `30m`') 'The guide does not document the validated restart timeout.'
Assert-True (
    $guideText -match 'Start-Sleep -Seconds 180; Get-Service WinRM \| Where-Object Status -eq ''Running'''
) 'The guide does not document the validated restart stabilization command.'
Assert-True (
    $guideText -match 'customize` array is static' -and
    $guideText -match 'fixed three-restart sequence' -and
    $guideText -match 'generate different static customizer arrays before'
) 'The guide does not document the supported pre-LCU restart architecture and conditional limitation.'
Assert-True (
    $guideText -match 'pending AVD Portal PM\s+confirmation'
) 'The manual template workaround is not marked as pending PM confirmation.'

if ($failures.Count -gt 0) {
    throw "Versioned integration validation failed ($($failures.Count) failure(s), $passed passed):`n - $($failures -join "`n - ")"
}

Write-Host "Versioned integration validation passed: $passed assertions."

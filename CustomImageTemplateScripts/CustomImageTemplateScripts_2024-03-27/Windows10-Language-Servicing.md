# Windows 10 language servicing

> [!IMPORTANT]
> This support is under validation in [Azure/RDS-Templates#840](https://github.com/Azure/RDS-Templates/pull/840).
> The pull request must remain draft until the LCU and restart-timeout contracts
> are approved and Gen1, Gen2, and Multi-Session validation passes.

This integration supports Windows 10 client builds 19044 and 19045 through the
existing portal entry points. The pre-existing Windows 11 parameter contracts
and execution bodies remain unchanged.

The intended portal sequence is:

1. Run `InstallLanguagePacks.ps1`, then use a Windows 10-only pre-LCU restart.
2. Run `InstallWindows10Lcu.ps1`, then use the LCU restart.
3. Run `SetDefaultLang.ps1`, then use the final language restart.
4. Run the explicit durable `Validate` phase, then continue to Sysprep.
5. Qualify the produced image externally.

The `Validate` customizer is an internal seventh template step. It invokes the
durably staged, state-pinned orchestrator directly; the existing portal entry
wrappers must not invoke `Validate`, and no additional visible AVD UX parameter
or route is required.

### Conditional pre-LCU restart limitation

The AIB `customize` array is static, and a `WindowsRestart` customizer is an
unconditional managed reboot-and-wait step. The current AVD portal workflow
does not expose a runtime condition that can insert or skip that customizer
after language/FoD servicing. Do not emulate one by accepting
`0x41306`/`267014`, rebooting inside the PowerShell customizer, or making a
`WindowsRestart.restartCommand` conditionally do nothing; none of those
preserves the supported managed-restart boundary.

The minimum supported template architecture for source variants that can leave
a genuine pre-LCU restart is therefore a fixed three-restart sequence:

1. Install language/FoD content and persist immutable phase state.
2. Run a first-class `WindowsRestart` customizer.
3. Revalidate the persisted contract, servicing readiness, language presence,
   and revision parity, then install the LCU.
4. Run the LCU `WindowsRestart` customizer.
5. Apply machine/default-user language settings.
6. Run the final language `WindowsRestart` customizer.
7. Verify the durable orchestrator against its persisted SHA-256 and invoke
   `-Resume -AibPhase Validate` with the selected language tag.

That sequence adds one restart even when the source would not have required the
pre-LCU restart. Preserving two restarts for those sources would require the AVD
portal/template producer to generate different static customizer arrays before
the build starts; it cannot be selected safely at runtime by these scripts.

## Servicing contract

Adding Windows 10 language content can leave a language package at an older
revision than the operating system. The workflow must therefore install the
requested language content, apply an applicable current non-preview Windows 10
cumulative update, and fail closed unless every installed language package
revision matches the OS UBR.

An isolated Gen2 diagnostic against the exact draft branch source image proved
that installing `fr-FR` first caused Windows Update to offer an applicable
Windows 10 LCU. The AIB Windows Update customizer installed it, restarted, and
produced revision parity: OS `19045.6456` and language package `19041.6456`.
The diagnostic then stopped intentionally before publication.

This result validates the post-language Windows Update order for that exact
source image only. It does not establish a universal production LCU source
contract for every supported image or variant. The draft remains blocked until
the post-language acquisition path is implemented and validated across Gen1,
Gen2, and Multi-Session, or an approved managed immutable LCU URI and SHA-256
contract is supplied. Do not hardcode a qualification KB, scrape unsupported
Update Catalog pages, reuse undocumented caches, or use a transient URL.

The recognized non-servicing pending-file-rename allowance is enabled only in
the Windows 10 install path. Every PFRO pair must be well formed and match the
validated allowlist. Unknown, mixed, malformed, servicing, language, FOD, LCU,
or CBS-related entries remain blocking. PFRO registry data is never modified
or cleared. The produced-image SetupAPI log rotation is recognized only for the
exact normalized pair `C:\Windows\INF\setupapi.dev.log` to
`C:\Windows\INF\setupapi.setup.log`; other SetupAPI paths or pairings remain
blocking.

## Using the scripts

### Preconditions

- Windows 10 client build 19044 or 19045.
- SYSTEM or elevated AIB execution context.
- Supported display names accepted by the existing entry-script parameters.
- Adequate disk space and network access to approved Microsoft endpoints.
- No unsupported or ambiguous pending servicing state.
- An approved LCU acquisition contract for the selected source image.

Use the versioned entry points with the portal's existing parameters:

```powershell
.\InstallLanguagePacks.ps1 -LanguageList @('French (France)', 'German (Germany)')
# Windows 10-only portal-managed pre-LCU restart.

.\InstallWindows10Lcu.ps1
# Portal-managed LCU restart.

.\SetDefaultLang.ps1 -Language 'French (France)'
# Final portal-managed language restart.

& 'C:\ProgramData\Windows10MachineLanguage\Set-Windows10MachineLanguage.ps1' `
    -Resume `
    -AibPhase Validate `
    -ExpectedLanguageTag 'fr-FR' `
    -WorkingDirectory 'C:\ProgramData\Windows10MachineLanguage'
# Continue to Sysprep only after this durable validation succeeds.
```

`InstallLanguagePacks.ps1` installs every requested language deterministically;
it does not silently choose a default. After the LCU restart,
`SetDefaultLang.ps1` selects one installed language as the machine default.

These commands describe the existing entry-point contract, not a production
release endorsement. Do not run the draft as a final production workflow until
the LCU acquisition/order and restart-timeout release gates above are approved.

The Windows 10 support files are:

- `Set-Windows10MachineLanguage.ps1`
- `Copy-UserInternationalSettingsToSystemCompat.ps1`
- `InstallWindows10Lcu.ps1`
- `Test-Windows10MachineLanguageHealth.ps1`

Entry scripts must verify SHA-256 before using downloaded or durably staged
support code. Branch validation may use a fork URL only when the exact commit
and every downloaded file hash are pinned. The final design must use an
immutable, supported upstream or managed-artifact contract.

The official language-pack ISO is discovered only through its exact
`Get-DiskImage -ImagePath` association. Discovery is polled for a bounded
30 seconds to allow storage enumeration and automatic drive-letter assignment
to converge. The workflow requires one optical UDF/CDFS volume and uses its
existing drive letter when present. If that exact volume remains unlettered,
the workflow may add one temporary unused drive-letter access path from Z
through D to its uniquely mapped partition, verify ownership, search only that
root, and remove only the path created by that invocation. It never changes
global automount policy or scans unrelated drives. Ambiguity, unexpected media,
an occupied or concurrently claimed path, verification failure, or any cleanup
failure remains fail-closed.

## Internal branch/AIB validation

1. Pin the exact branch commit and record SHA-256 for every downloaded entry
   script and support file.
2. Use a new isolated template and gallery version tagged
   `qualification=true` and `productionApproved=false`; exclude it from latest.
3. Use the validated Windows 10 restart settings for all three boundaries:
   - `restartTimeout`: at least `30m`.
   - `restartCheckCommand`:
     `powershell.exe -NoProfile -Command "Start-Sleep -Seconds 180; Get-Service WinRM | Where-Object Status -eq 'Running'"`
4. Run Gen1, Gen2, and Multi-Session as separate qualifications.

The AVD UX default restart timeout is five minutes and is insufficient for the
validated Windows 10 flow. The template producer must emit the fixed
Windows 10-only three-restart sequence from
`Windows10-Language-ThreeRestart.Customizers.example.json`; Windows 11 must
retain its existing customizer sequence and script bodies. Exporting a deployed
template, editing restart settings, deleting the original, and redeploying is
an internal validation workaround only. It is pending AVD Portal PM
confirmation and is not final customer guidance.

The example uses immutable phase-wrapper URI placeholders because the AIB
PowerShell customizer schema does not pass arbitrary script arguments. The
template producer must generate the install-language and apply-language
wrappers from the portal selections, pin their SHA-256 values, and use the
parameterless `InstallWindows10Lcu.ps1` between the first and second managed
restarts. After the third managed restart, the seventh customizer must verify
the durable orchestrator against `state.json` and invoke it with `-Resume
-AibPhase Validate`, the selected `-ExpectedLanguageTag`, and the fixed working
directory.

## Produced-image validation

The seventh customizer performs the durable post-restart language validation
and transitions state from `PostLanguageRestart` to `Completed`. After it
succeeds:

- Verify every requested language is installed.
- Verify each language-package revision equals the OS UBR and the expected
  current LCU is installed.
- Verify the selected machine language and Default User settings.
- Verify firewall/RDP, Defender, required services, and the guest agent.
- Review relevant servicing, system, and application events.
- Run DISM `ScanHealth` and verify the pending-restart state is acceptable.
- Perform one additional controlled reboot, then repeat health and pending-state
  checks.
- Preserve template, build, customization, servicing, and produced-image
  evidence before deleting temporary resources.

`Test-Windows10MachineLanguageHealth.ps1` can support external qualification;
it is not a production AIB customizer.

## Failure handling

Fail closed and retain `customization.log`, durable state, update inventory, and
qualification evidence. Never clear PFRO, bypass revision parity, substitute a
hardcoded LCU, or suppress an unsupported servicing state.

- **No LCU offered:** confirm the WUA search occurs after language/FOD
  installation. If the selected source still has no applicable offer, stop and
  require the approved managed LCU URI/SHA contract.
- **Windows Update busy (`0x80240016`):** the Windows 10 orchestrator waits for
  active servicing installers and retries this status a bounded number of times
  only when no reboot-pending signal is present. A reported mandatory restart,
  a persistent busy state, or any other update error fails closed with the
  pending signals and competing installer processes in the operation log.
- **Pending restart before LCU:** fail before selecting or starting the LCU.
  `0x41306`/`267014` from the AIB PowerShell host is only a task-termination
  status and is not evidence that the LCU completed. The current two-restart
  workflow cannot safely continue when language/FoD servicing requires a
  restart before the LCU; qualification must either use a source where that
  state does not occur or approve an additional restart boundary.
- **Unknown PFRO:** inspect every pair; do not broaden the allowlist or delete
  registry data.
- **Language ISO has no drive letter:** retain the mount/volume/partition
  diagnostics. The script polls the exact ISO association and performs only the
  bounded temporary access-path recovery described above. Do not assign a
  letter manually, enable global automount, or scan unrelated volumes.
- **Restart timeout/stabilization:** use the validated 30-minute timeout and
  180-second post-WinRM stabilization for internal qualification.
- **Unsupported OS build:** stop; only builds 19044 and 19045 are supported.

## Promotion checklist

- [ ] Gen1 passes against the exact final pull-request commit. The latest
      completed Gen1 evidence passed commit
      `26494cd2509e39cbc08955f25299c129b0ec538e`.
- [ ] Gen2 passes against the exact final pull-request commit. The latest
      completed Gen2 evidence passed commit
      `26494cd2509e39cbc08955f25299c129b0ec538e`.
- [ ] Multi-Session passes against the exact pull-request branch.
- [ ] The production LCU source/order contract is approved.
- [ ] The Windows 10 restart-timeout/check mechanism is approved.
- [ ] Windows 11 regression coverage passes with unchanged behavior.
- [ ] External produced-image and additional-reboot qualification passes.
- [ ] [Draft PR #840](https://github.com/Azure/RDS-Templates/pull/840) is
      reviewed; internal tracking is recorded in ADO Task 64267767.
- [ ] Only then mark the pull request ready for review.

# 43 — Crash history

**Status:** Implemented for 1.6. Stays within [ADR-007](decisions/ADR-007-event-log-only-v1.md) (Event Log only) and is read-only, so no new ADR. Minidump analysis is a separate phase that needs one (see *Future improvements*).

**Question it answers:** "What crashed on this PC lately, how often, and why?"

---

## Architecture

```
Crashes page / Reports / Assistant
        │  GetCrashHistory { days }            (pulse.proto, Envelope field 39)
        ▼
PulseService ─ CrashHistoryCollector (collectors/)
        │  EvtQuery System       XPath: crash events in the last N days, newest first
        │  EvtQuery Application  XPath: app crashes and hangs
        │  each log capped at 5000 events
        ▼
intelligence/crash_history
        ToCrashRecord            event → kind, group key, subject, version, module, code
        DropDuplicateBlueScreens Kernel-Power 41 + BugCheck 1001 of one blue screen count once
        GroupCrashRecords        counts, first/last, timestamps, versions, newest events
        ExplainCrashGroup        title / summary / recommendation from the newest event,
                                 plus the faulting file's publisher (version resource)
        │
        ▼  CrashHistory { groups }              (Envelope field 40)
Flutter ─ CrashHistoryController → CrashesPage (hero, filters, groups, inspector)
                                 → Timeline details panel for a single event
```

Nothing runs in the background: the service reads the logs only when the page is shown (and its data is older than two minutes), on Refresh, for a Crash history report, or when the Assistant calls `crash_history`.

## Sources

Provider names were checked with `Get-WinEvent -ListProvider` on Windows 11 (build 26100); the XPath filters use them verbatim.

| Kind | Event | Log | Data used |
|------|-------|-----|-----------|
| App crash | `Application Error` 1000 | Application | AppName, AppVersion, ModuleName, ModulePath, AppPath, ExceptionCode |
| App hang | `Application Hang` 1002 | Application | AppName, AppVersion, ExeFileName |
| Blue screen | `Microsoft-Windows-WER-SystemErrorReporting` 1001 (BugCheck) | System | Stop code from the first parameter, else the message |
| Blue screen or unexpected restart | `Microsoft-Windows-Kernel-Power` 41 | System | BugcheckCode (decimal), PowerButtonTimestamp, LongPowerButtonPressDetected, SleepInProgress |
| Graphics driver reset | `Display` 4101 | System | Driver name (`%1`, the only value) |
| Service crash | `Service Control Manager` 7031 (with recovery) / 7034 | System | `param1`, the service's display name |
| Hardware error | `Microsoft-Windows-WHEA-Logger`, level Critical or Error | System | — (corrected errors, level Warning, are not crashes) |

Windows 11 names the Application Error / Hang fields. Older builds write the same values without names; `FindEventDataField` then reads them by position, in the order of the event's message template (checked against a real event: the named order and the message order match).

## Responsibilities

**PulseService** reads, classifies, removes duplicates, groups, explains and caps. All logic except the log query and the version-resource read is in pure functions with unit tests (`crash_history_tests`, `app_crash_explainer_tests`).

**Flutter** shows the result: one-sentence hero, a counter per category (each filters the list), a bar per local day, the groups, and an inspector. A single event opens in the Timeline details panel through `GetTimelineEventDetail` (channel + record id), so Level 2 and Level 3 work as in the Timeline.

## Grouping

| Kind | Group key | Subject |
|------|-----------|---------|
| App crash | `app\|<app>\|<module>\|<exception code>` | App image name |
| App hang | `hang\|<app>` | App image name |
| Blue screen | `bsod\|<stop code>` | Stop code name (catalog) or `0x…` |
| Unexpected restart | `restart\|power_button`, `restart\|power_loss` or `restart\|unknown` | — |
| Graphics driver reset | `gpu\|<driver>` | Driver name |
| Service crash | `service\|<display name>` | Service display name |
| Hardware error | `whea\|<event id>` | — |

Names are compared case-insensitively. A Kernel-Power 41 with a stop code and a BugCheck 1001 with the same stop code within ten minutes are the same blue screen (both are written during the next boot); the 41 is dropped. The window matches the Timeline's `unexpected-shutdown` correlation rule ([37](37-timeline-correlation-rules.md)).

Caps per reply: 150 groups (newest first), 1000 timestamps and 10 events per group, 5000 events per log (the reply's `truncated` flag says when older events were skipped). A reply stays far below the 2 MB frame limit.

## Explanations

The same rules explain the Timeline rows, so an Application Error 1000 there now reads "Discord Crashed" instead of "Application Crashed".

- **Exception codes** (`intelligence/exception_catalog`): values and names from `ntstatus.h` (Windows SDK 10.0.26100), the debugger's [Specific Exceptions](https://learn.microsoft.com/windows-hardware/drivers/debugger/specific-exceptions) table (`0xE06D7363` C++), [`__fastfail`](https://learn.microsoft.com/cpp/intrinsics/fastfail) (`0xC0000409`), the [delay-load exceptions](https://learn.microsoft.com/cpp/build/reference/error-handling-and-notification) (`0xC06D007E/7F`) and the [IIS crash guide](https://learn.microsoft.com/troubleshoot/developer/webapps/iis/site-behavior-performance/process-termination-crash) (`0xE0434352`, .NET). Each code has a plain phrase and a cause; the cause picks the recommendation. Unknown codes are shown as `0x…`, never guessed.
- **Where the file comes from** (`ClassifyFaultingModule`), checked in this order: the app's own program file → `X:\Windows\System32\DriverStore\…` (device driver) → `X:\Windows\…` (Windows, unless its publisher is not Microsoft: then another program) → the app's folder (the app's own) → anything else (another program). Without paths (old event format) the origin is unknown and no claim is made.
- **Publisher**: `CompanyName` from the file's version resource (`GetFileVersionInfoW` / `VerQueryValueW`), read by the service only for paths on a local fixed drive (`GetDriveTypeW == DRIVE_FIXED`), so a crash on a network share never makes Pulse touch the network. The Timeline path does no file I/O, so its text omits the publisher.

## Public API

| Layer | API |
|-------|-----|
| IPC | `GetCrashHistory { days }` → `CrashHistory { days, collected_unix_ms, groups, scanned_events, truncated, unreadable_channels }`; `CrashGroup`, `CrashOccurrence`, `CrashVersion`, enums `CrashKind`, `FaultingModuleOrigin` |
| C++ | `CrashHistoryCollector::Collect(days)`; `ToCrashRecord`, `DropDuplicateBlueScreens`, `GroupCrashRecords`, `ExplainCrashGroup`; `ParseApplicationFault`, `ClassifyFaultingModule`, `ExplainApplicationFault`; `FindException`; `QueryFileVersionString` |
| Dart | `PulseIpcClient.getCrashHistory`, `CrashHistoryController`, `CrashHistorySummary`, `CrashesPage`; report template `crashHistory`; Assistant tool `crash_history` |

An older PulseService answers `GetCrashHistory` with "Unsupported message"; the page then asks to update or reinstall Pulse instead of showing a channel error.

## Example

The developer PC, 90 days: 39 events in 24 ms, 11 groups, among them

- *Pulse Crashed* ×5 — "after an unhandled error in code that Windows called. The error happened in flutter_windows.dll, one of the app's own files." (`0xC000041D`, the 1.4.0 shutdown crash fixed in 1.4.3, #32)
- *SQL Server (SQLEXPRESS) Service Crashed* ×10, with *sqlservr Crashed* ×6 in `sqlTsEs.dll` (Microsoft Corporation, the app's own file)
- *PC Lost Power or Stopped Suddenly* ×4

## Privacy

- Everything stays on the PC; the Assistant only talks to a local model and gets no file paths.
- Module paths can contain the user name; reports run them through `PersonalDataRedactor` like every other export.
- No network: no symbol server, no WER upload, version resources only on local fixed drives.

## Limitations

- **WER report folders are not read.** Each report folder under `ProgramData\Microsoft\Windows\WER\ReportArchive` is readable only by the user who crashed and Administrators, so LocalService cannot open them; the Event Log carries the same fields.
- **No minidump analysis yet.** `C:\Windows\Minidump` files need Administrator rights, and the kernel dump format is only exposed through the debugger engine. See *Future improvements*.
- **LiveKernelEvent** reports (WER 1001 "LiveKernelEvent", e.g. 141/117/193) are not listed: most are diagnostic live dumps; GPU timeouts the user notices appear as Display 4101.
- **EventLog 6008** is not used: Kernel-Power 41 records every unexpected restart and says more.
- **.NET details** (.NET Runtime 1026: exception type and stack) are not read yet.
- Files LocalService cannot read (for example in a user profile) have no publisher.
- The Windows folder is recognised as `X:\Windows\`; a Windows installed elsewhere makes its files "unknown" or "another program".
- Windows logs are size-capped (20 MB by default), so a busy PC can lose old events before the period ends.
- The daily chart uses at most 1000 timestamps per group.

## Future improvements

1. **Minidump summary (phase 2).** Needs an ADR and a prototype: an elevated helper started by an explicit user action (UAC), the in-box `dbgeng.dll` (System32; its `dbghelp` has no symbol server, so it cannot reach the network), reading the bug check data, the loaded drivers and the drivers on the crash stack — labelled as clues, not a verdict, because there are no symbols.
2. Read .NET Runtime 1026 for the exception type.
3. Hide one app's crashes in the Timeline instead of every Application Error 1000.
4. Point at changes before a crash starts repeating (driver and app installs from Inventory, Windows Update 19).

## References

- [Event ID 41: The system has rebooted without cleanly shutting down first](https://learn.microsoft.com/troubleshoot/windows-client/performance/event-id-41-restart)
- [Consuming events: XPath queries](https://learn.microsoft.com/windows/win32/wes/consuming-events) (`timediff`)
- [GetFileVersionInfoW](https://learn.microsoft.com/windows/win32/api/winver/nf-winver-getfileversioninfow), [VerQueryValueW](https://learn.microsoft.com/windows/win32/api/winver/nf-winver-verqueryvaluew), [GetDriveTypeW](https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-getdrivetypew)
- [DbgHelp versions](https://learn.microsoft.com/windows/win32/debug/dbghelp-versions) (the in-box copy has no symbol server)

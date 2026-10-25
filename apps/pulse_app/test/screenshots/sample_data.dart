// Sample data for the README and website screenshots. No value comes from a
// real PC. Titles, summaries and recommendations are the wording PulseService
// writes for these events (event_intelligence.cpp, crash_explainer.cpp,
// app_crash_explainer.cpp), so the screenshots show what Pulse really says.

import 'dart:math';

import 'package:pulse_protocol/pulse_wire.dart';

const _gib = 1024 * 1024 * 1024;

int _ago(DateTime now, Duration d) => now.subtract(d).millisecondsSinceEpoch;

TimelineEvent _event(
  DateTime now, {
  required Duration ago,
  required int record,
  required String channel,
  required String provider,
  required int id,
  required int severity,
  required String title,
  required String summary,
  String recommendation = '',
  bool actionRequired = false,
  String category = '',
  int importance = Importance.low,
  String processName = '',
}) {
  final ms = _ago(now, ago);
  final level = switch (severity) {
    Severity.critical => 'Critical',
    Severity.error => 'Error',
    Severity.warning => 'Warning',
    _ => 'Information',
  };
  return TimelineEvent(
    eventId: '$channel|$record',
    timestampUnixMs: ms,
    timestampIso: DateTime.fromMillisecondsSinceEpoch(ms).toUtc().toIso8601String(),
    severity: severity,
    channel: channel,
    providerName: provider,
    winEventId: id,
    recordId: record,
    computerName: 'DESKTOP-SAMPLE',
    title: title,
    summary: summary,
    recommendation: recommendation,
    actionRequired: actionRequired,
    importance: importance,
    category: category,
    technicalSummary: '$provider Event ID $id · $channel',
    message: summary,
    levelName: level,
    processName: processName,
  );
}

/// The last day of a quiet PC: one app crash, one DNS timeout, the rest
/// routine. The Discord crash is the newest event of the Crashes sample.
List<TimelineEvent> sampleTimelineEvents(DateTime now) => [
      _event(
        now,
        ago: const Duration(minutes: 3),
        record: 48211,
        channel: 'System',
        provider: 'Microsoft-Windows-WindowsUpdateClient',
        id: 19,
        severity: Severity.info,
        title: 'Windows Update Installed Successfully',
        summary: 'Windows successfully installed an update.',
        category: 'Update',
      ),
      _event(
        now,
        ago: const Duration(minutes: 26),
        record: 48207,
        channel: 'System',
        provider: 'Microsoft-Windows-DNS-Client',
        id: 1014,
        severity: Severity.warning,
        title: 'DNS Name Resolution Timed Out',
        summary: 'Windows timed out resolving a DNS name.',
        recommendation: 'Check network connectivity and DNS server settings.',
        category: 'Network',
        importance: Importance.medium,
      ),
      _event(
        now,
        ago: const Duration(minutes: 42),
        record: 9137,
        channel: 'Application',
        provider: 'Application Error',
        id: 1000,
        severity: Severity.error,
        title: 'Discord Crashed',
        summary:
            'Discord closed unexpectedly after a memory access error. The error '
            'happened in nvwgf2umx.dll, part of a device driver.',
        recommendation:
            "Update or reinstall the driver from the device maker's website.",
        actionRequired: true,
        category: 'Crash',
        importance: Importance.high,
        processName: 'Discord.exe',
      ),
      _event(
        now,
        ago: const Duration(hours: 2, minutes: 4),
        record: 48190,
        channel: 'System',
        provider: 'Microsoft-Windows-Kernel-Power',
        id: 107,
        severity: Severity.info,
        title: 'Windows Resumed From Sleep',
        summary: 'The system has resumed from sleep.',
        category: 'Power',
      ),
      _event(
        now,
        ago: const Duration(hours: 4, minutes: 31),
        record: 48177,
        channel: 'System',
        provider: 'Microsoft-Windows-Kernel-Power',
        id: 42,
        severity: Severity.info,
        title: 'Windows Entered Sleep',
        summary: 'The system is entering a sleep state.',
        category: 'Power',
      ),
      _event(
        now,
        ago: const Duration(hours: 6, minutes: 12),
        record: 48160,
        channel: 'System',
        provider: 'Microsoft-Windows-TPM-WMI',
        id: 1808,
        severity: Severity.info,
        title: 'Secure Boot Certificates Up to Date',
        summary:
            'This PC has the 2023 Secure Boot certificates and boot manager. '
            'Nothing else needs to be done.',
        category: 'Security',
      ),
      _event(
        now,
        ago: const Duration(hours: 9, minutes: 2),
        record: 48122,
        channel: 'System',
        provider: 'Microsoft-Windows-Kernel-General',
        id: 12,
        severity: Severity.info,
        title: 'Windows Started',
        summary: 'Windows has started successfully.',
        category: 'Boot',
      ),
      _event(
        now,
        ago: const Duration(hours: 9, minutes: 3),
        record: 48120,
        channel: 'System',
        provider: 'EventLog',
        id: 6005,
        severity: Severity.info,
        title: 'Event Log Service Started',
        summary: 'The Windows Event Log service started (typical at boot).',
        category: 'Boot',
      ),
      _event(
        now,
        ago: const Duration(hours: 9, minutes: 6),
        record: 48117,
        channel: 'System',
        provider: 'User32',
        id: 1074,
        severity: Severity.info,
        title: 'Shutdown or Restart Initiated',
        summary: 'A user or application initiated a shutdown or restart.',
        category: 'Boot',
      ),
      _event(
        now,
        ago: const Duration(hours: 13, minutes: 40),
        record: 48095,
        channel: 'System',
        provider: 'Microsoft-Windows-WindowsUpdateClient',
        id: 44,
        severity: Severity.info,
        title: 'Windows Update Download Started',
        summary: 'Windows Update started downloading an update.',
        category: 'Update',
      ),
      _event(
        now,
        ago: const Duration(hours: 19, minutes: 15),
        record: 48061,
        channel: 'System',
        provider: 'Service Control Manager',
        id: 7000,
        severity: Severity.error,
        title: 'Windows Service Failed to Start',
        summary: 'A Windows service failed to start.',
        recommendation:
            'Open the service name from the event and check its dependencies and '
            'recent software changes.',
        actionRequired: true,
        category: 'Service',
        importance: Importance.high,
      ),
    ];

/// Twelve crashes in five groups over the last month, newest first.
CrashHistory sampleCrashHistory(DateTime now, int days) {
  List<int> times(List<Duration> agos) => [for (final a in agos) _ago(now, a)];
  CrashGroup group({
    required CrashKind kind,
    required String key,
    required String title,
    required String summary,
    String recommendation = '',
    String subject = '',
    String moduleName = '',
    String modulePath = '',
    String moduleCompany = '',
    FaultingModuleOrigin origin = FaultingModuleOrigin.unknown,
    int? code,
    required List<Duration> agos,
    List<CrashVersion> versions = const [],
    String channel = 'System',
  }) {
    final when = times(agos);
    return CrashGroup(
      kind: kind,
      key: key,
      subject: subject,
      moduleName: moduleName,
      modulePath: modulePath,
      moduleCompany: moduleCompany,
      moduleOrigin: origin,
      code: code ?? 0,
      hasCode: code != null,
      title: title,
      summary: summary,
      recommendation: recommendation,
      count: when.length,
      firstUnixMs: when.last,
      lastUnixMs: when.first,
      occurrenceUnixMs: when,
      versions: List.of(versions),
      recent: [
        for (final (i, t) in when.indexed)
          CrashOccurrence(
            timestampUnixMs: t,
            channel: channel,
            recordId: 9137 - i * 41,
            version: versions.isEmpty ? '' : versions.first.version,
          ),
      ],
    );
  }

  const discordPath =
      r'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_5c3e1b0f9d2a4e77\nvwgf2umx.dll';
  final groups = [
    group(
      kind: CrashKind.appCrash,
      key: 'app|discord.exe|nvwgf2umx.dll|0xc0000005',
      title: 'Discord Crashed',
      summary:
          'Discord closed unexpectedly after a memory access error. The error '
          'happened in nvwgf2umx.dll, part of a device driver from NVIDIA '
          'Corporation.',
      recommendation:
          "Update or reinstall the driver from the device maker's website.",
      subject: 'Discord.exe',
      moduleName: 'nvwgf2umx.dll',
      modulePath: discordPath,
      moduleCompany: 'NVIDIA Corporation',
      origin: FaultingModuleOrigin.driver,
      code: 0xC0000005,
      channel: 'Application',
      agos: const [
        Duration(minutes: 42),
        Duration(days: 3, hours: 5),
        Duration(days: 9, hours: 2),
        Duration(days: 14, hours: 7),
        Duration(days: 21, hours: 1),
      ],
      versions: [
        CrashVersion(version: '1.0.9175.0', count: 3, lastUnixMs: _ago(now, const Duration(minutes: 42))),
        CrashVersion(version: '1.0.9168.0', count: 2, lastUnixMs: _ago(now, const Duration(days: 14))),
      ],
    ),
    group(
      kind: CrashKind.blueScreen,
      key: 'bsod|0x0000009f',
      title: 'Windows Crashed With a Blue Screen',
      summary:
          'Stop code: DRIVER_POWER_STATE_FAILURE (0x0000009F). A driver or '
          'device took too long to respond, so Windows stopped to protect '
          'itself.',
      recommendation:
          'Update chipset, storage and graphics drivers and the BIOS, and check '
          'any recently added devices.',
      subject: 'DRIVER_POWER_STATE_FAILURE',
      code: 0x0000009F,
      agos: const [Duration(days: 4, hours: 6)],
    ),
    group(
      kind: CrashKind.appHang,
      key: 'hang|photoshop.exe',
      title: 'Photoshop Stopped Responding',
      summary: 'Photoshop stopped responding and was closed.',
      recommendation:
          'If this repeats, update the app and check its add-ons or plugins.',
      subject: 'Photoshop.exe',
      channel: 'Application',
      agos: const [Duration(days: 6, hours: 3), Duration(days: 13, hours: 8)],
    ),
    group(
      kind: CrashKind.unexpectedRestart,
      key: 'restart|power_loss',
      title: 'PC Lost Power or Stopped Suddenly',
      summary:
          'The PC turned off without recording an error. This usually means a '
          'power cut, a drained battery, a faulty or underpowered power supply, '
          'overheating, or a complete freeze.',
      recommendation:
          'If it repeats, check the power supply and cables, temperatures and '
          'any overclocking. New hardware such as a CPU or graphics card may '
          'need a stronger power supply.',
      agos: const [Duration(days: 8, hours: 1), Duration(days: 23, hours: 4)],
    ),
    group(
      kind: CrashKind.appCrash,
      key: 'app|explorer.exe|ntdll.dll|0xc0000005',
      title: 'explorer Crashed',
      summary:
          'explorer closed unexpectedly after a memory access error. The error '
          'surfaced in ntdll.dll, a Windows file. This usually means the app '
          'itself, or something running inside it, caused it.',
      recommendation:
          'Update the app. If several different apps crash with memory errors, '
          'test the memory with Windows Memory Diagnostic and undo any '
          'overclock.',
      subject: 'explorer.exe',
      moduleName: 'ntdll.dll',
      modulePath: r'C:\Windows\SYSTEM32\ntdll.dll',
      moduleCompany: 'Microsoft Corporation',
      origin: FaultingModuleOrigin.windows,
      code: 0xC0000005,
      channel: 'Application',
      agos: const [Duration(days: 10, hours: 2), Duration(days: 24, hours: 6)],
    ),
  ];
  final cutoff = _ago(now, Duration(days: days));
  return CrashHistory(
    days: days,
    collectedUnixMs: now.millisecondsSinceEpoch,
    groups: [
      for (final g in groups)
        if (g.lastUnixMs >= cutoff) g,
    ],
    scannedEvents: 214,
  );
}

const _cpuModel = 'AMD Ryzen 7 7700X 8-Core Processor';
const _gpuModel = 'NVIDIA GeForce RTX 4070';
const _netAdapter = 'Intel(R) Ethernet Controller I225-V';

HealthStaticInfo sampleHealthInfo() => HealthStaticInfo(
      windowsEdition: 'Windows 11 Pro',
      windowsVersion: '24H2 (Build 26100.4351)',
      cpuModel: _cpuModel,
      gpuModel: _gpuModel,
      installedRamBytes: 32 * _gib,
      primaryStorageBytes: 931 * _gib,
      activeNetworkAdapter: _netAdapter,
      cpuBaseMhz: 4500,
      cpuSockets: 1,
      cpuCores: 8,
      cpuLogicalProcessors: 16,
      cpuVirtualizationEnabled: true,
      gpuDedicatedBytes: 12 * _gib,
      gpuSharedBytes: 16 * _gib,
      cpuArchitecture: 'x64',
      gpuVendor: 'NVIDIA',
      gpuDriverVersion: '32.0.15.6094',
      netManufacturer: 'Intel',
      netDescription: _netAdapter,
      netConnectionType: 'Ethernet',
      hasNetLinkSpeedBps: true,
      netLinkSpeedBps: 2500000000,
    );

/// One second of a calm desktop; [i] walks a smooth, repeatable curve.
HealthSample sampleHealthSample(DateTime now, int i, {int total = 60}) {
  final rng = Random(i * 7919 + 13);
  double wave(double base, double amp, double period, double noise) =>
      max(0, base + amp * sin(i / period) + (rng.nextDouble() - 0.5) * noise);
  final cpu = wave(11, 6, 5, 5);
  final gpu = wave(9, 5, 7, 4);
  const total32 = 32 * _gib;
  final used = (13.4 * _gib + wave(0, 0.25 * _gib, 9, 0.05 * _gib)).round();
  return HealthSample(
    unixMs: now.subtract(Duration(seconds: total - 1 - i)).millisecondsSinceEpoch,
    hasCpuPercent: true,
    cpuPercent: cpu,
    memoryUsedBytes: used,
    memoryTotalBytes: total32,
    memoryAvailableBytes: total32 - used,
    hasGpuPercent: true,
    gpuPercent: gpu,
    hasNetDownloadBps: true,
    netDownloadBps: wave(180000, 140000, 4, 90000),
    hasNetUploadBps: true,
    netUploadBps: wave(42000, 25000, 6, 20000),
    hasDiskReadBps: true,
    diskReadBps: wave(2.4e6, 2.0e6, 3, 1.5e6),
    hasDiskWriteBps: true,
    diskWriteBps: wave(1.1e6, 0.9e6, 4, 0.8e6),
    diskUsedBytes: 412 * _gib,
    diskTotalBytes: 931 * _gib,
    uptimeMs: const Duration(hours: 9, minutes: 2).inMilliseconds + i * 1000,
    hasCpuCurrentMhz: true,
    cpuCurrentMhz: 4700 + 300 * sin(i / 6),
    hasCpuTempC: true,
    cpuTempC: 52 + 4 * sin(i / 8),
    hasGpuTempC: true,
    gpuTempC: 41 + 2 * sin(i / 9),
    hasSsdTempC: true,
    ssdTempC: 38,
    ipv4: '192.168.1.24',
    gateway: '192.168.1.1',
    dns: '192.168.1.1',
    cpuCorePercent: [for (var c = 0; c < 16; c++) wave(9.0 + c % 5, 7, 4.0 + c, 8)],
    volumes: [
      HealthVolume(
        id: 'C:',
        mountPoint: r'C:\',
        label: 'Windows',
        fileSystem: 'NTFS',
        kind: HealthDriveKind.fixed,
        usedBytes: 412 * _gib,
        totalBytes: 931 * _gib,
        hasCapacity: true,
        includedInSummary: true,
      ),
      HealthVolume(
        id: 'D:',
        mountPoint: r'D:\',
        label: 'Games',
        fileSystem: 'NTFS',
        kind: HealthDriveKind.fixed,
        usedBytes: 1210 * _gib,
        totalBytes: 1863 * _gib,
        hasCapacity: true,
        includedInSummary: true,
      ),
    ],
    gpus: [
      HealthGpuAdapter(
        name: _gpuModel,
        vendor: 'NVIDIA',
        isPrimary: true,
        dedicatedTotalBytes: 12 * _gib,
        sharedTotalBytes: 16 * _gib,
        hasPercent: true,
        percent: gpu,
        hasDedicatedUsed: true,
        dedicatedUsedBytes: (1.9 * _gib).round(),
        hasSharedUsed: true,
        sharedUsedBytes: (0.3 * _gib).round(),
      ),
    ],
  );
}

InventoryDomainSnapshot sampleInventory(DateTime now, InventoryDomainId domain) {
  final base = InventoryDomainSnapshot(
    domain: domain,
    status: InventoryStatus.available,
    generation: 3,
    generatedAtUnixMs: now.millisecondsSinceEpoch,
  );
  switch (domain) {
    case InventoryDomainId.services:
      base.services.addAll([
        for (final (name, display, state, start) in _services)
          InventoryServiceEntry(
            id: name,
            displayName: display,
            state: state,
            startType: start,
            account: name == 'PulseService' ? r'NT AUTHORITY\LocalService' : 'LocalSystem',
            binaryPath: name == 'PulseService'
                ? r'"C:\Program Files\Pulse\service\PulseService.exe"'
                : r'C:\Windows\system32\svchost.exe -k netsvcs -p',
            description: name == 'PulseService'
                ? 'Reads Windows event logs and system health for the Pulse app. Read-only.'
                : '',
          ),
      ]);
    case InventoryDomainId.cpu:
      base.cpu.add(InventoryCpuEntry(
        id: 'CPU0',
        name: _cpuModel,
        manufacturer: 'AuthenticAMD',
        architecture: 'x64',
        sockets: 1,
        hasSockets: true,
        physicalCores: 8,
        hasPhysicalCores: true,
        logicalProcessors: 16,
        hasLogicalProcessors: true,
        baseClockMhz: 4500,
        hasBaseClockMhz: true,
        smtEnabled: true,
        hasSmtEnabled: true,
        virtualizationVendor: 'AMD-V',
      ));
    default:
      break;
  }
  return base;
}

const _services = [
  ('AudioSrv', 'Windows Audio', 'running', 'automatic'),
  ('BITS', 'Background Intelligent Transfer Service', 'running', 'manual'),
  ('BthAvctpSvc', 'AVCTP service', 'running', 'manual'),
  ('CryptSvc', 'Cryptographic Services', 'running', 'automatic'),
  ('Dhcp', 'DHCP Client', 'running', 'automatic'),
  ('Dnscache', 'DNS Client', 'running', 'automatic'),
  ('EventLog', 'Windows Event Log', 'running', 'automatic'),
  ('LanmanWorkstation', 'Workstation', 'running', 'automatic'),
  ('mpssvc', 'Windows Defender Firewall', 'running', 'automatic'),
  ('PulseService', 'Pulse', 'running', 'automatic'),
  ('Schedule', 'Task Scheduler', 'running', 'automatic'),
  ('Spooler', 'Print Spooler', 'running', 'automatic'),
  ('W32Time', 'Windows Time', 'stopped', 'manual'),
  ('WinDefend', 'Microsoft Defender Antivirus Service', 'running', 'automatic'),
  ('wuauserv', 'Windows Update', 'running', 'manual'),
];

DiagnosticsSnapshot sampleDiagnostics(DateTime now, String version) {
  final start = now.subtract(const Duration(hours: 9, minutes: 1));
  return DiagnosticsSnapshot(
    serviceVersion: version,
    protocolVersion: 1,
    serviceStartUnixMs: start.millisecondsSinceEpoch,
    serviceUptimeMs: now.difference(start).inMilliseconds,
    runMode: 'Windows Service',
    ipcListening: true,
    liveSubscribed: true,
    liveChannel: 'System',
    liveEventsPushed: 37,
    lastLiveEventUnixMs: _ago(now, const Duration(minutes: 3)),
    lastLiveEventTitle: 'Windows Update Installed Successfully',
    liveQueueCapacity: 1024,
    ipcMessagesReceived: 1843,
    ipcMessagesSent: 1851,
    connectedClients: 1,
    servicePid: 4316,
    hasCpuPercent: true,
    cpuPercent: 0.2,
    workingSetBytes: 21 * 1024 * 1024,
    threadCount: 14,
    handleCount: 312,
    windowsEdition: 'Windows 11 Pro',
    windowsVersion: '24H2 (Build 26100.4351)',
    executablePath: r'C:\Program Files\Pulse\service\PulseService.exe',
    buildVersion: version,
    installPath: r'C:\Program Files\Pulse\service\PulseService.exe',
    hasPathsMatch: true,
    pathsMatch: true,
    scmState: 'Running',
    scmStartupType: 'Automatic',
    healthMonitoringActive: true,
    healthSampleRateHz: 1,
  );
}

const sampleAssistantQuestion = 'What crashed on this PC this month?';

/// What a local model answers from the crash_history tool result above.
const sampleAssistantAnswer = """In the last 30 days Windows recorded **12 crashes** in 5 groups:

- **Discord crashed 5 times**, each time in `nvwgf2umx.dll`, part of the NVIDIA graphics driver. The last one was 42 minutes ago.
- **One blue screen** 4 days ago, *DRIVER_POWER_STATE_FAILURE*: a driver or device took too long to respond.
- Photoshop stopped responding twice, and the PC lost power twice.

Start with the graphics driver: update or reinstall it from NVIDIA's website. If the blue screen comes back, update the chipset and storage drivers and the BIOS too.""";

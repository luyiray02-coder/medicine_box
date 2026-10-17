import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

enum ApiHealth { checking, healthy, failed }

class _ApiHttpStatusException implements Exception {
  const _ApiHttpStatusException(this.statusCode);
  final int statusCode;
}

class _ApiProbeResult<T> {
  const _ApiProbeResult.success(this.value) : failureReason = null;
  const _ApiProbeResult.failure(this.failureReason) : value = null;

  final T? value;
  final String? failureReason;
  bool get isSuccess => failureReason == null;
}

class TrayApi {
  TrayApi._();
  static final instance = TrayApi._();
  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://10.0.2.2:8080',
  );
  static const _weightUrlKey = 'weight_api_base_url';
  static const _environmentUrlKey = 'environment_api_base_url';
  static const _lightUrlKey = 'light_api_base_url';

  SharedPreferencesAsync? _preferencesInstance;
  SharedPreferencesAsync get _preferences =>
      _preferencesInstance ??= SharedPreferencesAsync();
  String _weightBaseUrl = _defaultBaseUrl;
  String _environmentBaseUrl = _defaultBaseUrl;
  String _lightBaseUrl = _defaultBaseUrl;

  String get weightBaseUrl => _weightBaseUrl;
  String get environmentBaseUrl => _environmentBaseUrl;
  String get lightBaseUrl => _lightBaseUrl;

  Future<void> loadSavedUrls() async {
    _weightBaseUrl =
        await _preferences.getString(_weightUrlKey) ?? _defaultBaseUrl;
    _environmentBaseUrl =
        await _preferences.getString(_environmentUrlKey) ?? _defaultBaseUrl;
    _lightBaseUrl =
        await _preferences.getString(_lightUrlKey) ?? _defaultBaseUrl;
  }

  Future<void> configure({
    required String weightBaseUrl,
    required String environmentBaseUrl,
    required String lightBaseUrl,
  }) async {
    final weightUrl = _normalizeUrl(weightBaseUrl);
    final environmentUrl = _normalizeUrl(environmentBaseUrl);
    final lightUrl = _normalizeUrl(lightBaseUrl);

    await Future.wait([
      _preferences.setString(_weightUrlKey, weightUrl),
      _preferences.setString(_environmentUrlKey, environmentUrl),
      _preferences.setString(_lightUrlKey, lightUrl),
    ]);

    _weightBaseUrl = weightUrl;
    _environmentBaseUrl = environmentUrl;
    _lightBaseUrl = lightUrl;
  }

  String _normalizeUrl(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = (_, _, _) => true;

  Future<dynamic> _get(String baseUrl, String path) =>
      _performGet(baseUrl, path).timeout(const Duration(seconds: 5));

  Future<dynamic> _performGet(String baseUrl, String path) async {
    final request = await _client.getUrl(Uri.parse('$baseUrl$path'));
    final response = await request.close();
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices) {
      await response.drain<void>();
      throw _ApiHttpStatusException(response.statusCode);
    }
    return jsonDecode(await utf8.decodeStream(response));
  }

  Future<List<double>> weights() async {
    final data = await _get(_weightBaseUrl, '/api/weight');
    if (data is! List ||
        data.length != 4 ||
        data.any((value) => value is! num)) {
      throw const FormatException('Invalid weight response');
    }
    return data.map((value) => (value as num).toDouble()).toList();
  }

  Future<Map<String, dynamic>> status() async {
    final data = await _get(_environmentBaseUrl, '/api/status');
    if (data is! Map || data['tem'] is! num || data['hum'] is! num) {
      throw const FormatException('Invalid environment response');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<List<bool>> lightStatus() async {
    final data = await _get(_lightBaseUrl, '/api/lightStatus');
    if (data is! List ||
        data.length != 4 ||
        data.any((value) => value is! bool)) {
      throw const FormatException('Invalid light response');
    }
    return data.cast<bool>();
  }

  Future<void> light(int target, bool on) async =>
      _get(_lightBaseUrl, '/api/${on ? 'lightOn' : 'lightOff'}?target=$target');
}

class PrescriptionMedication {
  const PrescriptionMedication({
    required this.name,
    required this.dose,
    required this.timing,
    required this.frequency,
    required this.days,
    required this.totalQuantity,
    this.expiry,
  });

  final String name;
  final String dose;
  final String timing;
  final String? frequency;
  final int days;
  final int totalQuantity;
  final String? expiry;

  Map<String, dynamic> toJson() => {
    'name': name,
    'dose': dose,
    'timing': timing,
    'frequency': frequency,
    'days': days,
    'totalQuantity': totalQuantity,
    'expiry': expiry,
  };

  factory PrescriptionMedication.fromJson(Map<String, dynamic> json) {
    final days = (json['days'] as num).toInt();
    final totalQuantity = (json['totalQuantity'] as num).toInt();
    if (days < 1 || totalQuantity < 1) {
      throw const FormatException('Invalid prescription medication');
    }
    return PrescriptionMedication(
      name: json['name'] as String,
      dose: json['dose'] as String,
      timing: json['timing'] as String,
      frequency: json['frequency'] as String?,
      days: days,
      totalQuantity: totalQuantity,
      expiry: json['expiry'] as String?,
    );
  }
}

class Tray {
  Tray({
    required this.name,
    required this.emptyWeight,
    this.medicineName,
    this.expiry,
    this.usage,
    this.total = 0,
    this.medicineWeight = 0,
    this.barcode,
    this.person,
    this.dose,
    this.frequency,
    this.timing,
    this.startDate,
    this.days,
    this.scheduleId,
    this.contents = const [],
  });
  String name;
  final double emptyWeight;
  String? medicineName, expiry, usage, barcode;
  String? person, dose, frequency, timing, startDate, scheduleId;
  int? days;
  int total;
  double medicineWeight;
  final List<PrescriptionMedication> contents;
  bool get hasMedicine => medicineName != null || contents.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'emptyWeight': emptyWeight,
    'medicineName': medicineName,
    'expiry': expiry,
    'usage': usage,
    'total': total,
    'medicineWeight': medicineWeight,
    'barcode': barcode,
    'person': person,
    'dose': dose,
    'frequency': frequency,
    'timing': timing,
    'startDate': startDate,
    'days': days,
    'scheduleId': scheduleId,
    'contents': contents.map((item) => item.toJson()).toList(),
  };

  factory Tray.fromJson(Map<String, dynamic> json) => Tray(
    name: json['name'] as String,
    emptyWeight: (json['emptyWeight'] as num).toDouble(),
    medicineName: json['medicineName'] as String?,
    expiry: json['expiry'] as String?,
    usage: json['usage'] as String?,
    total: (json['total'] as num?)?.toInt() ?? 0,
    medicineWeight: (json['medicineWeight'] as num?)?.toDouble() ?? 0,
    barcode: json['barcode'] as String?,
    person: json['person'] as String?,
    dose: json['dose'] as String?,
    frequency: json['frequency'] as String?,
    timing: json['timing'] as String?,
    startDate: json['startDate'] as String?,
    days: (json['days'] as num?)?.toInt(),
    scheduleId: json['scheduleId'] as String?,
    contents: _contentsFromJson(json['contents']),
  );

  static List<PrescriptionMedication> _contentsFromJson(dynamic value) {
    if (value is! List) return const [];
    final contents = <PrescriptionMedication>[];
    for (final item in value) {
      try {
        contents.add(
          PrescriptionMedication.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        );
      } catch (_) {}
    }
    return contents;
  }
}

class ConfiguredTrayZeroMonitor {
  ConfiguredTrayZeroMonitor({this.zeroThreshold = 0.5});

  final double zeroThreshold;
  List<double>? _previousWeights;
  final Set<int> _pendingSlots = {};

  Set<int> get pendingSlots => Set.unmodifiable(_pendingSlots);

  Set<int> update({
    required List<Tray?> trays,
    required List<double> weights,
    required bool apiConnected,
  }) {
    final previousWeights = _previousWeights;
    if (apiConnected && previousWeights != null) {
      final count = [
        trays.length,
        weights.length,
        previousWeights.length,
      ].reduce((left, right) => left < right ? left : right);
      for (var index = 0; index < count; index++) {
        final tray = trays[index];
        if (tray?.hasMedicine == true &&
            previousWeights[index] > zeroThreshold &&
            weights[index] <= zeroThreshold) {
          _pendingSlots.add(index);
        }
      }
    }

    _previousWeights = List<double>.of(weights);
    _pendingSlots.removeWhere(
      (index) =>
          index >= trays.length ||
          index >= weights.length ||
          trays[index]?.hasMedicine != true ||
          weights[index] > zeroThreshold,
    );
    return pendingSlots;
  }

  void markHandled(int index) => _pendingSlots.remove(index);

  void reset() {
    _previousWeights = null;
    _pendingSlots.clear();
  }
}

void resetTraySlotConfiguration({
  required int index,
  required List<Tray?> trays,
  required List<MedicationSchedule> schedules,
}) {
  if (index < 0 || index >= trays.length) {
    throw RangeError.index(index, trays, 'index');
  }
  trays[index] = null;
  schedules.removeWhere((schedule) => schedule.tray == index + 1);
}

sealed class MedicineScanResult {
  const MedicineScanResult();
}

class BarcodeScanResult extends MedicineScanResult {
  const BarcodeScanResult(this.code);
  final String code;
}

class PrescriptionScanResult extends MedicineScanResult {
  const PrescriptionScanResult({
    required this.person,
    required this.tray,
    required this.dose,
    required this.frequency,
    required this.timing,
    required this.startDate,
    required this.days,
    required this.medications,
  });

  factory PrescriptionScanResult.demo(int tray) => PrescriptionScanResult(
    person: '盧奎佑',
    tray: tray,
    dose: '1 錠',
    frequency: null,
    timing: '早餐後吃',
    startDate: DateTime(2026, 9, 5),
    days: 28,
    medications: const [
      PrescriptionMedication(
        name: 'OlsaaCa Tablets 5/',
        dose: '1 錠',
        timing: '早餐後吃',
        frequency: null,
        days: 28,
        totalQuantity: 28,
      ),
      PrescriptionMedication(
        name: 'ROBESTAR SANDOZ. FI',
        dose: '1 錠',
        timing: '早餐後吃',
        frequency: null,
        days: 28,
        totalQuantity: 28,
      ),
    ],
  );

  final String person;
  final int tray;
  final String dose;
  final String? frequency;
  final String timing;
  final DateTime startDate;
  final int days;
  final List<PrescriptionMedication> medications;

  Map<String, dynamic> toJson() => {
    'person': person,
    'tray': tray,
    'dose': dose,
    'frequency': frequency,
    'timing': timing,
    'startDate': _formatDate(startDate),
    'days': days,
    'medications': medications.map((item) => item.toJson()).toList(),
  };

  factory PrescriptionScanResult.fromJson(Map<String, dynamic> json) =>
      PrescriptionScanResult(
        person: json['person'] as String,
        tray: (json['tray'] as num).toInt(),
        dose: json['dose'] as String,
        frequency: json['frequency'] as String?,
        timing: json['timing'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        days: (json['days'] as num).toInt(),
        medications: (json['medications'] as List? ?? const [])
            .map(
              (item) => PrescriptionMedication.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
}

class MedicineDetails {
  const MedicineDetails({
    required this.name,
    required this.expiry,
    required this.usage,
    required this.total,
    required this.weight,
    required this.barcode,
  });

  final String name;
  final String expiry;
  final String usage;
  final int total;
  final double weight;
  final String barcode;

  Map<String, dynamic> toJson() => {
    'name': name,
    'expiry': expiry,
    'usage': usage,
    'total': total,
    'weight': weight,
    'barcode': barcode,
  };

  factory MedicineDetails.fromJson(Map<String, dynamic> json) =>
      MedicineDetails(
        name: json['name'] as String,
        expiry: json['expiry'] as String,
        usage: json['usage'] as String,
        total: (json['total'] as num).toInt(),
        weight: (json['weight'] as num).toDouble(),
        barcode: json['barcode'] as String,
      );
}

class MedicationSchedule {
  const MedicationSchedule({
    required this.id,
    required this.person,
    required this.tray,
    required this.medicineName,
    required this.dose,
    required this.frequency,
    required this.timing,
    required this.startDate,
    required this.days,
    required this.reminderTimes,
    this.enabled = true,
  });

  final String id;
  final String person;
  final int tray;
  final String medicineName;
  final String dose;
  final String? frequency;
  final String timing;
  final DateTime startDate;
  final int days;
  final List<String> reminderTimes;
  final bool enabled;

  DateTime get endDate => startDate.add(Duration(days: days - 1));

  /// Returns only the occurrences that belong to [date] in local time.
  ///
  /// Reminder polling deliberately calls this with today's date so an
  /// unhandled dose from a previous calendar day can never be carried into
  /// today's reminder queue.
  List<DateTime> occurrencesOn(DateTime date) {
    if (!enabled) return const [];
    final requestedDay = DateTime(date.year, date.month, date.day);
    final firstDay = DateTime(startDate.year, startDate.month, startDate.day);
    final lastDay = DateTime(endDate.year, endDate.month, endDate.day);
    if (requestedDay.isBefore(firstDay) || requestedDay.isAfter(lastDay)) {
      return const [];
    }
    return reminderTimes.map((value) {
      final parts = value.split(':');
      return DateTime(
        requestedDay.year,
        requestedDay.month,
        requestedDay.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    }).toList();
  }

  DateTime? nextReminder([DateTime? from]) {
    if (!enabled) return null;
    final now = from ?? DateTime.now();
    var date = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(startDate.year, startDate.month, startDate.day);
    if (date.isBefore(firstDate)) date = firstDate;
    final lastDate = DateTime(endDate.year, endDate.month, endDate.day);
    while (!date.isAfter(lastDate)) {
      for (final value in reminderTimes) {
        final parts = value.split(':');
        final occurrence = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        if (!occurrence.isBefore(now)) return occurrence;
      }
      date = date.add(const Duration(days: 1));
    }
    return null;
  }

  List<DateTime> upcomingReminders({int count = 5, DateTime? from}) {
    if (!enabled) return const [];
    final now = from ?? DateTime.now();
    final results = <DateTime>[];
    var date = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(startDate.year, startDate.month, startDate.day);
    if (date.isBefore(firstDate)) date = firstDate;
    final lastDate = DateTime(endDate.year, endDate.month, endDate.day);
    while (!date.isAfter(lastDate) && results.length < count) {
      for (final value in reminderTimes) {
        final parts = value.split(':');
        final occurrence = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        if (!occurrence.isBefore(now)) {
          results.add(occurrence);
          if (results.length == count) break;
        }
      }
      date = date.add(const Duration(days: 1));
    }
    return results;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'person': person,
    'tray': tray,
    'medicineName': medicineName,
    'dose': dose,
    'frequency': frequency,
    'timing': timing,
    'startDate': _formatDate(startDate),
    'days': days,
    'reminderTimes': reminderTimes,
    'enabled': enabled,
  };

  factory MedicationSchedule.fromJson(Map<String, dynamic> json) {
    final times =
        (json['reminderTimes'] as List).cast<String>().toSet().toList()..sort();
    if (times.isEmpty) throw const FormatException('Missing reminder times');
    for (final value in times) {
      final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
      final hour = int.tryParse(match?.group(1) ?? '');
      final minute = int.tryParse(match?.group(2) ?? '');
      if (hour == null || hour > 23 || minute == null || minute > 59) {
        throw const FormatException('Invalid reminder time');
      }
    }
    final tray = (json['tray'] as num).toInt();
    final days = (json['days'] as num).toInt();
    if (tray < 1 || tray > 4 || days < 1) {
      throw const FormatException('Invalid schedule range');
    }
    return MedicationSchedule(
      id: json['id'] as String,
      person: json['person'] as String,
      tray: tray,
      medicineName: json['medicineName'] as String,
      dose: json['dose'] as String,
      frequency: json['frequency'] as String?,
      timing: json['timing'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      days: days,
      reminderTimes: times,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  MedicationSchedule copyWith({
    String? person,
    int? tray,
    String? medicineName,
    String? dose,
    String? frequency,
    String? timing,
    DateTime? startDate,
    int? days,
    List<String>? reminderTimes,
    bool? enabled,
  }) => MedicationSchedule(
    id: id,
    person: person ?? this.person,
    tray: tray ?? this.tray,
    medicineName: medicineName ?? this.medicineName,
    dose: dose ?? this.dose,
    frequency: frequency ?? this.frequency,
    timing: timing ?? this.timing,
    startDate: startDate ?? this.startDate,
    days: days ?? this.days,
    reminderTimes: reminderTimes ?? this.reminderTimes,
    enabled: enabled ?? this.enabled,
  );
}

class MedicineSetupResult {
  const MedicineSetupResult({required this.tray, this.schedule});
  final Tray tray;
  final MedicationSchedule? schedule;

  Map<String, dynamic> toJson() => {
    'tray': tray.toJson(),
    'schedule': schedule?.toJson(),
  };

  factory MedicineSetupResult.fromJson(Map<String, dynamic> json) =>
      MedicineSetupResult(
        tray: Tray.fromJson(Map<String, dynamic>.from(json['tray'] as Map)),
        schedule: json['schedule'] == null
            ? null
            : MedicationSchedule.fromJson(
                Map<String, dynamic>.from(json['schedule'] as Map),
              ),
      );
}

enum DoseStatus { taken, skipped, snoozed }

enum ReminderAction { taken, skipped, snoozed }

class DoseRecord {
  const DoseRecord({
    required this.scheduleId,
    required this.plannedAt,
    required this.status,
    required this.actedAt,
    this.person,
    this.snoozedUntil,
  });

  final String scheduleId;
  final DateTime plannedAt;
  final DoseStatus status;
  final DateTime actedAt;
  final String? person;
  final DateTime? snoozedUntil;

  String get occurrenceKey => '$scheduleId|${plannedAt.toIso8601String()}';
  String? get groupOccurrenceKey {
    final value = person?.trim();
    if (value == null || value.isEmpty) return null;
    return doseGroupOccurrenceKey(value, plannedAt);
  }

  DoseRecord copyWithPerson(String value) => DoseRecord(
    scheduleId: scheduleId,
    plannedAt: plannedAt,
    status: status,
    actedAt: actedAt,
    person: value,
    snoozedUntil: snoozedUntil,
  );

  Map<String, dynamic> toJson() => {
    'scheduleId': scheduleId,
    'plannedAt': plannedAt.toIso8601String(),
    'status': status.name,
    'actedAt': actedAt.toIso8601String(),
    'person': person,
    'snoozedUntil': snoozedUntil?.toIso8601String(),
  };

  factory DoseRecord.fromJson(Map<String, dynamic> json) => DoseRecord(
    scheduleId: json['scheduleId'] as String,
    plannedAt: DateTime.parse(json['plannedAt'] as String),
    status: DoseStatus.values.byName(json['status'] as String),
    actedAt: DateTime.parse(json['actedAt'] as String),
    person: json['person'] as String?,
    snoozedUntil: json['snoozedUntil'] == null
        ? null
        : DateTime.parse(json['snoozedUntil'] as String),
  );
}

String doseGroupOccurrenceKey(String person, DateTime plannedAt) {
  final minute = DateTime(
    plannedAt.year,
    plannedAt.month,
    plannedAt.day,
    plannedAt.hour,
    plannedAt.minute,
  );
  return '${person.trim()}|${minute.toIso8601String()}';
}

class _DueDoseGroup {
  const _DueDoseGroup({
    required this.person,
    required this.plannedAt,
    required this.schedules,
  });

  final String person;
  final DateTime plannedAt;
  final List<MedicationSchedule> schedules;

  Set<int> get trays => schedules.map((schedule) => schedule.tray).toSet();
  String get id => '$person|${plannedAt.toIso8601String()}';
}

class PersistedMediBoxState {
  const PersistedMediBoxState({
    required this.trays,
    required this.schedules,
    this.doseRecords = const [],
  });

  factory PersistedMediBoxState.empty() => PersistedMediBoxState(
    trays: List<Tray?>.filled(4, null),
    schedules: const [],
    doseRecords: const [],
  );

  final List<Tray?> trays;
  final List<MedicationSchedule> schedules;
  final List<DoseRecord> doseRecords;

  Map<String, dynamic> toJson() => {
    'version': 4,
    'trays': trays.map((tray) => tray?.toJson()).toList(),
    'schedules': schedules.map((schedule) => schedule.toJson()).toList(),
    'doseRecords': doseRecords.map((record) => record.toJson()).toList(),
  };

  factory PersistedMediBoxState.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt();
    if (version != 1 && version != 2 && version != 3 && version != 4) {
      throw const FormatException('Unsupported state version');
    }
    final savedTrays = json['trays'] as List? ?? const [];
    final trays = List<Tray?>.generate(4, (index) {
      if (index >= savedTrays.length || savedTrays[index] == null) return null;
      try {
        return Tray.fromJson(
          Map<String, dynamic>.from(savedTrays[index] as Map),
        );
      } catch (_) {
        return null;
      }
    });
    final schedules = <MedicationSchedule>[];
    for (final value in json['schedules'] as List? ?? const []) {
      try {
        schedules.add(
          MedicationSchedule.fromJson(Map<String, dynamic>.from(value as Map)),
        );
      } catch (_) {}
    }
    final doseRecords = <DoseRecord>[];
    for (final value in json['doseRecords'] as List? ?? const []) {
      try {
        doseRecords.add(
          DoseRecord.fromJson(Map<String, dynamic>.from(value as Map)),
        );
      } catch (_) {}
    }
    return PersistedMediBoxState(
      trays: trays,
      schedules: schedules,
      doseRecords: doseRecords,
    );
  }
}

class MediBoxStateRepository {
  MediBoxStateRepository._();
  static final instance = MediBoxStateRepository._();
  static const _stateKey = 'medibox_state_v2';
  static const _legacyStateKey = 'medibox_state_v1';
  SharedPreferencesAsync? _preferencesInstance;
  SharedPreferencesAsync get _preferences =>
      _preferencesInstance ??= SharedPreferencesAsync();

  Future<PersistedMediBoxState> load() async {
    try {
      final value =
          await _preferences.getString(_stateKey) ??
          await _preferences.getString(_legacyStateKey);
      if (value == null) return PersistedMediBoxState.empty();
      return PersistedMediBoxState.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      return PersistedMediBoxState.empty();
    }
  }

  Future<void> save(PersistedMediBoxState state) =>
      _preferences.setString(_stateKey, jsonEncode(state.toJson()));
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrayApi.instance.loadSavedUrls();
  final savedState = await MediBoxStateRepository.instance.load();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(MediBoxApp(initialState: savedState));
}

class MediBoxApp extends StatelessWidget {
  const MediBoxApp({super.key, required this.initialState});
  final PersistedMediBoxState initialState;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '智慧藥箱',
    theme: buildMediBoxTheme(),
    home: MediBoxHome(initialState: initialState),
  );
}

class MediBoxHome extends StatefulWidget {
  const MediBoxHome({super.key, required this.initialState});
  final PersistedMediBoxState initialState;
  @override
  State<MediBoxHome> createState() => _MediBoxHomeState();
}

class _MediBoxHomeState extends State<MediBoxHome> {
  static const double _weightChangeThreshold = 0.5;
  late final List<Tray?> trays;
  late final List<MedicationSchedule> schedules;
  late final List<DoseRecord> doseRecords;
  List<double> measuredWeights = List.filled(4, 0);
  List<bool> lightStates = List.filled(4, false);
  double temperature = 26, humidity = 62;
  ApiHealth _apiHealth = ApiHealth.checking;
  String? _apiFailureReason;
  bool _refreshInProgress = false;
  bool _migratedDoseRecordPeople = false;
  int _apiConfigurationRevision = 0;
  bool get apiConnected => _apiHealth == ApiHealth.healthy;
  Timer? _poller;
  Timer? _reminderPoller;
  bool _checkingReminders = false;
  final Set<String> _handledReminderGroupIds = {};
  final Set<int> _promptedSlots = {};
  final Set<int> _resetRequiredSlots = {};
  final ConfiguredTrayZeroMonitor _configuredTrayZeroMonitor =
      ConfiguredTrayZeroMonitor(zeroThreshold: _weightChangeThreshold);
  int? _configuredTrayZeroDialogSlot;
  BuildContext? _configuredTrayZeroDialogContext;
  bool _dialogOpen = false;
  bool _settingsOpen = false;
  bool _apiEditorOpen = false;
  final Set<int> _lightRequestsInProgress = {};
  late final TextEditingController _weightApiUrlController;
  late final TextEditingController _environmentApiUrlController;
  late final TextEditingController _lightApiUrlController;
  @override
  void initState() {
    super.initState();
    trays = List<Tray?>.of(widget.initialState.trays);
    schedules = List<MedicationSchedule>.of(widget.initialState.schedules);
    doseRecords = widget.initialState.doseRecords.map((record) {
      final migrated = _recoverDoseRecordPerson(record);
      if (!identical(migrated, record)) _migratedDoseRecordPeople = true;
      return migrated;
    }).toList();
    _weightApiUrlController = TextEditingController(
      text: TrayApi.instance.weightBaseUrl,
    );
    _environmentApiUrlController = TextEditingController(
      text: TrayApi.instance.environmentBaseUrl,
    );
    _lightApiUrlController = TextEditingController(
      text: TrayApi.instance.lightBaseUrl,
    );
    _refreshApi();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) => _refreshApi());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_migratedDoseRecordPeople) unawaited(_persistState());
      _checkReminders();
    });
    _reminderPoller = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkReminders(),
    );
  }

  DoseRecord _recoverDoseRecordPerson(DoseRecord record) {
    if (record.person?.trim().isNotEmpty == true) return record;
    for (final schedule in schedules) {
      if (schedule.id == record.scheduleId) {
        return record.copyWithPerson(schedule.person);
      }
    }

    final day = DateTime(
      record.plannedAt.year,
      record.plannedAt.month,
      record.plannedAt.day,
    );
    final time =
        '${record.plannedAt.hour.toString().padLeft(2, '0')}:${record.plannedAt.minute.toString().padLeft(2, '0')}';
    final matchingPeople = <String>{};
    for (final schedule in schedules) {
      final start = DateTime(
        schedule.startDate.year,
        schedule.startDate.month,
        schedule.startDate.day,
      );
      final end = DateTime(
        schedule.endDate.year,
        schedule.endDate.month,
        schedule.endDate.day,
      );
      if (!day.isBefore(start) &&
          !day.isAfter(end) &&
          schedule.reminderTimes.contains(time)) {
        matchingPeople.add(schedule.person);
      }
    }
    return matchingPeople.length == 1
        ? record.copyWithPerson(matchingPeople.single)
        : record;
  }

  @override
  void dispose() {
    _poller?.cancel();
    _reminderPoller?.cancel();
    _weightApiUrlController.dispose();
    _environmentApiUrlController.dispose();
    _lightApiUrlController.dispose();
    super.dispose();
  }

  Future<void> _persistState() async {
    try {
      await MediBoxStateRepository.instance.save(
        PersistedMediBoxState(
          trays: trays,
          schedules: schedules,
          doseRecords: doseRecords,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('資料儲存失敗，請再試一次')));
      }
    }
  }

  MedicationSchedule? _scheduleForTray(int trayNumber) {
    for (final schedule in schedules) {
      if (schedule.tray == trayNumber) return schedule;
    }
    return null;
  }

  Future<void> _refreshApi() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    final revision = _apiConfigurationRevision;

    try {
      final weightFuture = _probeApi(TrayApi.instance.weights);
      final environmentFuture = _probeApi(TrayApi.instance.status);
      final lightFuture = _probeApi(TrayApi.instance.lightStatus);
      final weightResult = await weightFuture;
      final environmentResult = await environmentFuture;
      final lightResult = await lightFuture;

      if (!mounted || revision != _apiConfigurationRevision) return;

      final failures = <(String, String)>[
        if (!weightResult.isSuccess) ('重量', weightResult.failureReason!),
        if (!environmentResult.isSuccess)
          ('溫溼度', environmentResult.failureReason!),
        if (!lightResult.isSuccess) ('燈號', lightResult.failureReason!),
      ];

      setState(() {
        if (weightResult.isSuccess) measuredWeights = weightResult.value!;
        if (environmentResult.isSuccess) {
          final environment = environmentResult.value!;
          temperature = (environment['tem'] as num).toDouble();
          humidity = (environment['hum'] as num).toDouble();
        }
        if (lightResult.isSuccess) lightStates = lightResult.value!;

        if (failures.isEmpty) {
          _apiHealth = ApiHealth.healthy;
          _apiFailureReason = null;
        } else {
          _apiHealth = ApiHealth.failed;
          _apiFailureReason = _combineApiFailures(failures);
        }
      });

      if (weightResult.isSuccess) {
        final values = weightResult.value!;
        _configuredTrayZeroMonitor.update(
          trays: trays,
          weights: values,
          apiConnected: failures.isEmpty,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _dismissConfiguredTrayZeroDialogIfWeightRecovered(values);
          if (_dialogOpen || _settingsOpen) return;

          if (failures.isEmpty) {
            for (final index
                in _configuredTrayZeroMonitor.pendingSlots.toList()..sort()) {
              if (index < values.length) {
                _showConfiguredTrayZeroDialog(index, values[index]);
              }
              if (_dialogOpen) return;
            }
          }

          for (var index = 0; index < values.length; index++) {
            final tray = trays[index];
            final rawWeight = values[index];
            if (rawWeight == 0) {
              if (_configuredTrayZeroDialogSlot != index) {
                _promptedSlots.remove(index);
              }
              _resetRequiredSlots.remove(index);
            } else if (tray != null && !tray.hasMedicine) {
              final difference = rawWeight - tray.emptyWeight;
              if (difference.abs() <= _weightChangeThreshold) {
                _promptedSlots.remove(index);
                _resetRequiredSlots.remove(index);
              } else if (difference < -_weightChangeThreshold) {
                if (!_resetRequiredSlots.contains(index)) {
                  _promptedSlots.remove(index);
                }
              } else if (_resetRequiredSlots.remove(index)) {
                _promptedSlots.remove(index);
              }
            }
            if (!_promptedSlots.contains(index)) {
              _detectWeight(index, rawWeight);
            }
          }
        });
      }
    } finally {
      _refreshInProgress = false;
      if (mounted && revision != _apiConfigurationRevision) {
        unawaited(_refreshApi());
      }
    }
  }

  Future<_ApiProbeResult<T>> _probeApi<T>(Future<T> Function() request) async {
    try {
      return _ApiProbeResult<T>.success(await request());
    } catch (error) {
      return _ApiProbeResult<T>.failure(_friendlyApiError(error));
    }
  }

  String _friendlyApiError(Object error) {
    if (error is TimeoutException) return '回應逾時';
    if (error is _ApiHttpStatusException) return '伺服器回應異常';
    if (error is SocketException ||
        error is HandshakeException ||
        error is HttpException) {
      return '無法連線';
    }
    if (error is FormatException || error is TypeError) {
      return '回傳資料格式錯誤';
    }
    return '發生未知錯誤';
  }

  String _combineApiFailures(List<(String, String)> failures) {
    final sourcesByReason = <String, List<String>>{};
    for (final (source, reason) in failures) {
      sourcesByReason.putIfAbsent(reason, () => []).add(source);
    }
    return sourcesByReason.entries
        .map((entry) => '${entry.value.join('、')} API ${entry.key}')
        .join('；');
  }

  void _toggleApiEditor() {
    setState(() {
      _apiEditorOpen = !_apiEditorOpen;
      _settingsOpen = _apiEditorOpen;
      if (_apiEditorOpen) {
        _weightApiUrlController.text = TrayApi.instance.weightBaseUrl;
        _environmentApiUrlController.text = TrayApi.instance.environmentBaseUrl;
        _lightApiUrlController.text = TrayApi.instance.lightBaseUrl;
      }
    });
  }

  bool _isValidApiUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _applyApiUrls() async {
    final weightUrl = _weightApiUrlController.text.trim();
    final environmentUrl = _environmentApiUrlController.text.trim();
    final lightUrl = _lightApiUrlController.text.trim();

    if (![weightUrl, environmentUrl, lightUrl].every(_isValidApiUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入三個有效的 http 或 https API 網址')),
      );
      return;
    }

    try {
      await TrayApi.instance.configure(
        weightBaseUrl: weightUrl,
        environmentBaseUrl: environmentUrl,
        lightBaseUrl: lightUrl,
      );
      if (!mounted) return;
      setState(() {
        _apiEditorOpen = false;
        _settingsOpen = false;
        _apiConfigurationRevision++;
        _apiHealth = ApiHealth.checking;
        _apiFailureReason = null;
        _configuredTrayZeroMonitor.reset();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API 網址已儲存')));
      unawaited(_refreshApi());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API 網址儲存失敗，請再試一次')));
    }
  }

  void _dismissConfiguredTrayZeroDialogIfWeightRecovered(List<double> weights) {
    final index = _configuredTrayZeroDialogSlot;
    if (index == null) return;

    final trayStillConfigured =
        index < trays.length && trays[index]?.hasMedicine == true;
    final weightRecovered =
        index < weights.length && weights[index] > _weightChangeThreshold;
    if (trayStillConfigured && !weightRecovered) return;

    final dialogContext = _configuredTrayZeroDialogContext;
    _configuredTrayZeroDialogSlot = null;
    _configuredTrayZeroDialogContext = null;
    _configuredTrayZeroMonitor.markHandled(index);
    _promptedSlots.remove(index);
    if (dialogContext != null &&
        dialogContext.mounted &&
        Navigator.of(dialogContext).canPop()) {
      Navigator.of(dialogContext).pop();
    }
  }

  void _showConfiguredTrayZeroDialog(int index, double rawWeight) {
    final tray = trays[index];
    if (_dialogOpen ||
        _settingsOpen ||
        !apiConnected ||
        tray?.hasMedicine != true ||
        rawWeight > _weightChangeThreshold) {
      return;
    }

    _configuredTrayZeroMonitor.markHandled(index);
    _promptedSlots.add(index);
    _configuredTrayZeroDialogSlot = index;
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (_configuredTrayZeroDialogSlot == index) {
          _configuredTrayZeroDialogContext = dialogContext;
        }
        return _ConfiguredTrayZeroDialog(
          slot: index + 1,
          currentWeight: rawWeight,
          onReset: () {
            if (measuredWeights[index] > _weightChangeThreshold) {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('重量已恢復，不需要重置藥格')));
              return;
            }
            setState(() {
              resetTraySlotConfiguration(
                index: index,
                trays: trays,
                schedules: schedules,
              );
              _configuredTrayZeroMonitor.markHandled(index);
              _promptedSlots.remove(index);
              _resetRequiredSlots.remove(index);
              lightStates[index] = false;
            });
            unawaited(_persistState());
            unawaited(_setReminderLights({index + 1}, false));
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('第 ${index + 1} 格已歸零重置')));
          },
        );
      },
    ).whenComplete(() {
      if (_configuredTrayZeroDialogSlot == index) {
        _configuredTrayZeroDialogSlot = null;
        _configuredTrayZeroDialogContext = null;
      }
      _promptedSlots.remove(index);
      if (mounted) {
        setState(() => _dialogOpen = false);
      }
    });
  }

  void _detectWeight(int index, double rawWeight) {
    if (_dialogOpen || _settingsOpen) return;
    final tray = trays[index];
    if (rawWeight <= 0) return;
    if (tray == null) {
      _showDetectedTrayDialog(index, rawWeight);
      return;
    }
    final medicineWeight = rawWeight - tray.emptyWeight;
    if (!tray.hasMedicine && medicineWeight < -_weightChangeThreshold) {
      _showTrayResetDialog(index, rawWeight);
      return;
    }
    if (!tray.hasMedicine && medicineWeight > _weightChangeThreshold) {
      _promptedSlots.add(index);
      _dialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _DetectedMedicineDialog(
          slot: index + 1,
          addedWeight: medicineWeight,
          onLater: () => Navigator.pop(dialogContext),
          onStart: () {
            Navigator.pop(dialogContext);
            _addMedicine(index);
          },
        ),
      ).whenComplete(() {
        if (mounted) {
          setState(() => _dialogOpen = false);
        }
      });
    }
  }

  void _showDetectedTrayDialog(int index, double rawWeight) {
    if (_dialogOpen ||
        _settingsOpen ||
        rawWeight <= 0 ||
        trays[index] != null) {
      return;
    }

    _promptedSlots.add(index);
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DetectedTrayDialog(
        slot: index + 1,
        weight: rawWeight,
        onLater: () => Navigator.pop(dialogContext),
        onConfirm: () {
          setState(
            () => trays[index] = Tray(
              name: '第 ${index + 1} 格藥盤',
              emptyWeight: rawWeight,
            ),
          );
          _promptedSlots.remove(index);
          unawaited(_persistState());
          Navigator.pop(dialogContext);
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() => _dialogOpen = false);
      }
    });
  }

  bool _trayNeedsReset(int index) {
    final tray = trays[index];
    final rawWeight = measuredWeights[index];
    return tray != null &&
        !tray.hasMedicine &&
        rawWeight > 0 &&
        rawWeight < tray.emptyWeight - _weightChangeThreshold;
  }

  void _showTrayResetDialog(int index, double rawWeight) {
    final tray = trays[index];
    if (_dialogOpen ||
        _settingsOpen ||
        tray == null ||
        tray.hasMedicine ||
        rawWeight <= 0 ||
        rawWeight >= tray.emptyWeight - _weightChangeThreshold) {
      return;
    }

    _promptedSlots.add(index);
    _resetRequiredSlots.add(index);
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _TrayResetDialog(
        slot: index + 1,
        previousWeight: tray.emptyWeight,
        currentWeight: rawWeight,
        onLater: () => Navigator.pop(dialogContext),
        onReset: () {
          setState(() {
            trays[index] = Tray(name: tray.name, emptyWeight: rawWeight);
            _promptedSlots.remove(index);
            _resetRequiredSlots.remove(index);
          });
          unawaited(_persistState());
          Navigator.pop(dialogContext);
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() => _dialogOpen = false);
      }
    });
  }

  Future<void> _toggleTrayLight(int index) async {
    if (_lightRequestsInProgress.contains(index)) return;
    final turnOn = !lightStates[index];
    setState(() => _lightRequestsInProgress.add(index));
    try {
      await TrayApi.instance.light(index + 1, turnOn);
      if (!mounted) return;
      setState(() => lightStates[index] = turnOn);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('燈號 API ${_friendlyApiError(error)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _lightRequestsInProgress.remove(index));
      }
    }
  }

  Future<void> _addMedicine(int index) async {
    final tray = trays[index]!;
    try {
      await TrayApi.instance.light(index + 1, true);
    } catch (_) {}
    if (!mounted) return;
    final result = await Navigator.push<MedicineSetupResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicineWeightPage(
          tray: tray,
          slot: index + 1,
          api: TrayApi.instance,
        ),
      ),
    );
    try {
      await TrayApi.instance.light(index + 1, false);
    } catch (_) {}
    if (result != null && mounted) {
      setState(() {
        trays[index] = result.tray;
        if (result.schedule != null) {
          schedules.removeWhere((schedule) => schedule.tray == index + 1);
          schedules.add(result.schedule!);
        }
      });
      unawaited(_persistState());
    }
  }

  String _contentsDetails(List<PrescriptionMedication> contents) => contents
      .asMap()
      .entries
      .map((entry) {
        final item = entry.value;
        final expiry = item.expiry?.isNotEmpty == true ? item.expiry : '未提供';
        return '內容物 ${entry.key + 1}：${item.name}\n'
            '  劑量：${item.dose}／時機：${item.timing}\n'
            '  頻率：${item.frequency ?? '未辨識'}／療程：${item.days} 天\n'
            '  總量：${item.totalQuantity}／效期：$expiry';
      })
      .join('\n\n');

  void _viewTray(int index) {
    final tray = trays[index];
    if (tray == null) return;
    final schedule = _scheduleForTray(index + 1);
    final medicineDetails = tray.contents.isNotEmpty
        ? '家人：${tray.person ?? '未指定'}\n'
              '藥格內容物：${tray.contents.length} 種\n\n'
              '${_contentsDetails(tray.contents)}\n\n'
              '處方日期：${tray.startDate ?? '-'}\n'
              '提醒：${schedule == null ? '未設定提醒' : schedule.reminderTimes.join('、')}'
        : '家人：${tray.person ?? '未指定'}\n'
              '藥品：${tray.medicineName}\n'
              '劑量：${tray.dose ?? '-'}\n'
              '服用時機：${tray.timing ?? tray.usage ?? '-'}\n'
              '效期：${tray.expiry?.isNotEmpty == true ? tray.expiry : '-'}\n'
              '療程：${tray.startDate ?? '-'}／${tray.days?.toString() ?? '-'} 天\n'
              '總量：${tray.total}\n'
              '提醒：${schedule == null ? '未設定提醒' : schedule.reminderTimes.join('、')}';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tray.name),
        content: SingleChildScrollView(
          child: Text(
            '藥盤重量：${tray.emptyWeight.toStringAsFixed(1)} g\n\n'
            '${tray.hasMedicine ? medicineDetails : '尚未設定藥品'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _editTray(index);
            },
            child: const Text('修改'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _confirmDeleteTray(index);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除藥格'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTray(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除藥格？'),
        content: Text('刪除第 ${index + 1} 格後，藥盤、藥品與這一格的所有排程都會一併刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      resetTraySlotConfiguration(
        index: index,
        trays: trays,
        schedules: schedules,
      );
      _configuredTrayZeroMonitor.markHandled(index);
      _promptedSlots.remove(index);
      _resetRequiredSlots.remove(index);
    });
    await _persistState();
  }

  Future<void> _editTray(int index) async {
    final controller = TextEditingController(text: trays[index]!.name);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改藥盤'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '藥盤名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              setState(
                () => trays[index]!.name = controller.text.trim().isEmpty
                    ? trays[index]!.name
                    : controller.text.trim(),
              );
              unawaited(_persistState());
              Navigator.pop(dialogContext);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void _viewSchedule(MedicationSchedule schedule) {
    final next = schedule.nextReminder();
    final tray = schedule.tray >= 1 && schedule.tray <= trays.length
        ? trays[schedule.tray - 1]
        : null;
    final contents = tray?.contents ?? const <PrescriptionMedication>[];
    final contentsText = contents.isEmpty
        ? ''
        : '\n\n${_contentsDetails(contents)}';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.calendar_month_outlined,
          size: 44,
          color: AppPalette.primary,
        ),
        title: Text('${schedule.person}的服藥排程'),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppPalette.border),
            ),
            child: Text(
              '狀態：${schedule.enabled ? '提醒已啟用' : '提醒已停用'}\n'
              '藥品：${schedule.medicineName}\n'
              '藥格：第 ${schedule.tray} 格\n'
              '療程：${_formatDate(schedule.startDate)}～${_formatDate(schedule.endDate)}\n'
              '每日提醒：${schedule.reminderTimes.join('、')}\n'
              '下一次：${!schedule.enabled
                  ? '已停用'
                  : next == null
                  ? '療程已結束'
                  : _formatDateTime(next)}'
              '$contentsText',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _editSchedule(schedule);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('修改排程'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _toggleScheduleEnabled(schedule);
            },
            icon: Icon(
              schedule.enabled
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
            ),
            label: Text(schedule.enabled ? '停用提醒' : '啟用提醒'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _confirmDeleteSchedule(schedule);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除排程'),
          ),
        ],
      ),
    );
  }

  Future<void> _editSchedule(MedicationSchedule schedule) async {
    final updated = await Navigator.push<MedicationSchedule>(
      context,
      MaterialPageRoute(builder: (_) => ScheduleEditPage(schedule: schedule)),
    );
    if (updated == null || !mounted) return;
    setState(() {
      final index = schedules.indexWhere((item) => item.id == schedule.id);
      if (index >= 0) schedules[index] = updated;
      final tray = trays[updated.tray - 1];
      if (tray != null) {
        tray.person = updated.person;
        tray.dose = updated.dose;
        tray.timing = updated.timing;
        tray.startDate = _formatDate(updated.startDate);
        tray.days = updated.days;
      }
    });
    await _persistState();
  }

  Future<void> _toggleScheduleEnabled(MedicationSchedule schedule) async {
    setState(() {
      final index = schedules.indexWhere((item) => item.id == schedule.id);
      if (index >= 0) {
        schedules[index] = schedule.copyWith(enabled: !schedule.enabled);
      }
    });
    await _persistState();
  }

  Future<void> _confirmDeleteSchedule(MedicationSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除排程？'),
        content: Text(
          '確定刪除 ${schedule.person}／${schedule.medicineName} 的提醒排程嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      schedules.removeWhere((item) => item.id == schedule.id);
      final tray = trays[schedule.tray - 1];
      if (tray?.scheduleId == schedule.id) tray!.scheduleId = null;
    });
    await _persistState();
  }

  List<_DueDoseGroup> _dueReminderGroups(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final records = <String, DoseRecord>{
      for (final record in doseRecords) record.occurrenceKey: record,
    };
    final handledGroups = <String>{
      ..._handledReminderGroupIds,
      for (final record in doseRecords)
        if (record.status != DoseStatus.snoozed &&
            record.groupOccurrenceKey != null)
          record.groupOccurrenceKey!,
    };
    final grouped = <String, List<MedicationSchedule>>{};
    for (final schedule in schedules) {
      for (final plannedAt in schedule.occurrencesOn(today)) {
        // Keep this explicit boundary check even though occurrencesOn already
        // normalizes the date. It prevents future changes from accidentally
        // reintroducing reminders from an earlier calendar day.
        if (plannedAt.isBefore(today) || !plannedAt.isBefore(tomorrow)) {
          continue;
        }
        final groupKey = doseGroupOccurrenceKey(schedule.person, plannedAt);
        if (handledGroups.contains(groupKey)) continue;
        final occurrenceKey = '$schedule.id|${plannedAt.toIso8601String()}';
        final record = records[occurrenceKey];
        if (record != null && record.status != DoseStatus.snoozed) continue;
        final dueAt = record?.snoozedUntil ?? plannedAt;
        // A snoozed dose is also valid only within the original local day.
        // Snoozes crossing midnight expire instead of appearing tomorrow.
        if (!dueAt.isBefore(tomorrow)) continue;
        if (dueAt.isAfter(now)) continue;
        grouped.putIfAbsent(groupKey, () => []).add(schedule);
      }
    }
    final groups = grouped.entries.map((entry) {
      final schedules = entry.value;
      final time = schedules.first.reminderTimes.firstWhere((value) {
        final parts = value.split(':');
        return entry.key.endsWith(
          DateTime(
            today.year,
            today.month,
            today.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          ).toIso8601String(),
        );
      });
      final parts = time.split(':');
      return _DueDoseGroup(
        person: schedules.first.person,
        plannedAt: DateTime(
          today.year,
          today.month,
          today.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        ),
        schedules: schedules,
      );
    }).toList()..sort((a, b) => a.plannedAt.compareTo(b.plannedAt));
    return groups;
  }

  Future<bool> _setReminderLights(Set<int> trayNumbers, bool on) async {
    var failed = false;
    for (final trayNumber in trayNumbers) {
      try {
        await TrayApi.instance.light(trayNumber, on);
      } catch (_) {
        failed = true;
      }
    }
    if (mounted) {
      setState(() {
        for (final trayNumber in trayNumbers) {
          if (trayNumber >= 1 && trayNumber <= lightStates.length) {
            lightStates[trayNumber - 1] = on;
          }
        }
      });
    }
    return failed;
  }

  Future<void> _recordReminderAction(
    _DueDoseGroup group,
    ReminderAction action,
  ) async {
    final now = DateTime.now();
    final status = switch (action) {
      ReminderAction.taken => DoseStatus.taken,
      ReminderAction.skipped => DoseStatus.skipped,
      ReminderAction.snoozed => DoseStatus.snoozed,
    };
    final groupKey = doseGroupOccurrenceKey(group.person, group.plannedAt);
    if (action == ReminderAction.snoozed) {
      _handledReminderGroupIds.remove(groupKey);
    } else {
      // Set this before any asynchronous work so the 20-second poller cannot
      // enqueue the same logical dose while persistence or the light API runs.
      _handledReminderGroupIds.add(groupKey);
    }
    setState(() {
      for (final schedule in group.schedules) {
        final key = '$schedule.id|${group.plannedAt.toIso8601String()}';
        doseRecords.removeWhere((record) => record.occurrenceKey == key);
        doseRecords.add(
          DoseRecord(
            scheduleId: schedule.id,
            plannedAt: group.plannedAt,
            status: status,
            actedAt: now,
            person: group.person,
            snoozedUntil: action == ReminderAction.snoozed
                ? now.add(const Duration(minutes: 10))
                : null,
          ),
        );
      }
    });
    await _persistState();
    await _setReminderLights(group.trays, false);
  }

  Future<void> _checkReminders() async {
    if (!mounted ||
        _checkingReminders ||
        _dialogOpen ||
        _settingsOpen ||
        schedules.isEmpty) {
      return;
    }
    final groups = _dueReminderGroups(DateTime.now());
    if (groups.isEmpty) return;
    _checkingReminders = true;
    _dialogOpen = true;
    final allTrays = groups.expand((group) => group.trays).toSet();
    final lightWarning = await _setReminderLights(allTrays, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DoseReminderDialog(
        groups: groups,
        lightWarning: lightWarning,
        onAction: _recordReminderAction,
      ),
    );
    await _setReminderLights(allTrays, false);
    _dialogOpen = false;
    _checkingReminders = false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    body: SafeArea(
      child: ResponsiveCanvas(
        child: Padding(
          padding: const EdgeInsets.all(34),
          child: Row(
            children: [
              Expanded(flex: 11, child: _trayPanel()),
              const SizedBox(width: 34),
              Expanded(
                flex: 9,
                child: SchedulePanel(
                  schedules: schedules,
                  onTap: _viewSchedule,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _trayPanel() => Container(
    padding: const EdgeInsets.all(30),
    decoration: appPanelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.medical_services_outlined,
                color: AppPalette.primary,
                size: 36,
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '機箱目前狀態',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '4 格藥盤 · 即時監測',
                    style: TextStyle(fontSize: 18, color: AppPalette.textMuted),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _toggleApiEditor,
              icon: Icon(
                apiConnected
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                size: 19,
              ),
              label: Text(apiConnected ? 'API 已連線' : '設定 API'),
              style: OutlinedButton.styleFrom(
                foregroundColor: apiConnected
                    ? AppPalette.primary
                    : AppPalette.warning,
              ),
            ),
            const SizedBox(width: 12),
            _apiStatusBadge(),
          ],
        ),
        if (_apiEditorOpen) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: AppPalette.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.border),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings_ethernet, color: AppPalette.primary),
                    SizedBox(width: 10),
                    Text(
                      'API 網址設定',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '設定會儲存在此裝置，下次開啟 App 時自動載入',
                      style: TextStyle(color: AppPalette.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _apiUrlField(
                  label: '取得重量',
                  endpoint: '/api/weight',
                  controller: _weightApiUrlController,
                ),
                const SizedBox(height: 8),
                _apiUrlField(
                  label: '取得溫溼度',
                  endpoint: '/api/status',
                  controller: _environmentApiUrlController,
                ),
                const SizedBox(height: 8),
                _apiUrlField(
                  label: '燈號控制',
                  endpoint: '/api/lightStatus、lightOn、lightOff',
                  controller: _lightApiUrlController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _applyApiUrls(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _toggleApiEditor,
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _applyApiUrls,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('儲存並套用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _metric(
                Icons.thermostat,
                '溫度',
                apiConnected ? '${temperature.toStringAsFixed(0)}°C' : '-',
                const Color(0xffffeee7),
                const Color(0xffe66c32),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _metric(
                Icons.water_drop_outlined,
                '濕度',
                apiConnected ? '${humidity.toStringAsFixed(0)}%' : '-',
                const Color(0xffe8f5ff),
                const Color(0xff2587d9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              const gap = 16.0;
              final ratio =
                  ((box.maxWidth - gap) / 2) / ((box.maxHeight - gap) / 2);
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  childAspectRatio: ratio,
                ),
                itemBuilder: (_, i) => TrayCard(
                  number: i + 1,
                  tray: trays[i],
                  schedule: _scheduleForTray(i + 1),
                  lightOn: lightStates[i],
                  lightBusy: _lightRequestsInProgress.contains(i),
                  needsTrayReset: _trayNeedsReset(i),
                  onView: () => _viewTray(i),
                  onMedicine: () => _addMedicine(i),
                  onLightToggle: () => _toggleTrayLight(i),
                  onResetTray: () =>
                      _showTrayResetDialog(i, measuredWeights[i]),
                  onRetryDetection:
                      trays[i] == null &&
                          _promptedSlots.contains(i) &&
                          measuredWeights[i] > 0
                      ? () => _showDetectedTrayDialog(i, measuredWeights[i])
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _apiStatusBadge() {
    final (background, foreground, icon, label) = switch (_apiHealth) {
      ApiHealth.checking => (
        AppPalette.warningSoft,
        AppPalette.warning,
        Icons.sync,
        '檢查中',
      ),
      ApiHealth.healthy => (
        AppPalette.primarySoft,
        AppPalette.primary,
        Icons.check_circle,
        '正常運作',
      ),
      ApiHealth.failed => (
        AppPalette.dangerSoft,
        AppPalette.danger,
        Icons.error_outline,
        '連線異常',
      ),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 310),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: .25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: foreground),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      color: foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_apiHealth == ApiHealth.failed &&
                      _apiFailureReason != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _apiFailureReason!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: foreground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _apiUrlField({
    required String label,
    required String endpoint,
    required TextEditingController controller,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) => Row(
    children: [
      SizedBox(
        width: 185,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              endpoint,
              style: const TextStyle(fontSize: 12, color: AppPalette.textMuted),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'https://192.168.50.224:8080',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    ],
  );

  Widget _metric(
    IconData icon,
    String label,
    String value,
    Color background,
    Color color,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppPalette.border),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(width: 13),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, color: AppPalette.textMuted),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DoseReminderDialog extends StatefulWidget {
  const _DoseReminderDialog({
    required this.groups,
    required this.lightWarning,
    required this.onAction,
  });

  final List<_DueDoseGroup> groups;
  final bool lightWarning;
  final Future<void> Function(_DueDoseGroup, ReminderAction) onAction;

  @override
  State<_DoseReminderDialog> createState() => _DoseReminderDialogState();
}

class _DoseReminderDialogState extends State<_DoseReminderDialog> {
  static const _audioInterval = Duration(seconds: 5);
  static const _audioAsset = 'audio/medication_reminder.mp3';
  late final List<_DueDoseGroup> _remaining = [...widget.groups];
  final AudioPlayer _reminderPlayer = AudioPlayer();
  Timer? _audioTimer;
  StreamSubscription<void>? _audioCompletionSubscription;
  bool _audioActive = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _audioCompletionSubscription = _reminderPlayer.onPlayerComplete.listen((_) {
      _scheduleNextAudio();
    });
    _startReminderAudio();
  }

  void _startReminderAudio() {
    _audioTimer?.cancel();
    _audioActive = true;
    unawaited(_playReminderAudio());
  }

  void _scheduleNextAudio() {
    if (!_audioActive) return;
    _audioTimer?.cancel();
    _audioTimer = Timer(_audioInterval, () {
      if (_audioActive) unawaited(_playReminderAudio());
    });
  }

  Future<void> _playReminderAudio() async {
    if (!_audioActive) return;
    try {
      await _reminderPlayer.stop();
      await _reminderPlayer.play(
        AssetSource(_audioAsset),
        volume: 1,
        ctx: AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );
    } catch (_) {
      // The visual reminder remains usable if audio playback is unavailable.
      _scheduleNextAudio();
    }
  }

  Future<void> _stopReminderAudio() async {
    _audioActive = false;
    _audioTimer?.cancel();
    _audioTimer = null;
    try {
      await _reminderPlayer.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioActive = false;
    _audioTimer?.cancel();
    unawaited(_audioCompletionSubscription?.cancel());
    unawaited(_reminderPlayer.dispose());
    super.dispose();
  }

  Future<void> _handle(_DueDoseGroup group, ReminderAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    unawaited(_stopReminderAudio());
    await widget.onAction(group, action);
    if (!mounted) return;
    setState(() {
      _remaining.removeWhere((item) => item.id == group.id);
      _busy = false;
    });
    if (_remaining.isEmpty && mounted) {
      Navigator.pop(context);
    } else {
      _startReminderAudio();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 920),
        child: Padding(
          padding: const EdgeInsets.all(34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.alarm,
                      color: AppPalette.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _remaining.length > 1 ? '今日待處理服藥提醒' : '服藥時間到了',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              if (widget.lightWarning) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppPalette.dangerSoft,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: AppPalette.danger),
                      SizedBox(width: 10),
                      Expanded(child: Text('藥格燈號連線失敗，仍可正常記錄服藥結果。')),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: _remaining.map(_groupCard).toList()),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _groupCard(_DueDoseGroup group) {
    final trayNumbers = group.trays.toList()..sort();
    final overdue = group.plannedAt.isBefore(
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: overdue ? AppPalette.warning : AppPalette.border,
          width: overdue ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 29,
                backgroundColor: overdue
                    ? AppPalette.warningSoft
                    : AppPalette.primarySoft,
                child: Text(
                  group.person.isEmpty ? '?' : group.person[0],
                  style: TextStyle(
                    color: overdue ? AppPalette.warning : AppPalette.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.person,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${overdue ? '原定' : '服藥時間'} ${group.plannedAt.hour.toString().padLeft(2, '0')}:${group.plannedAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: overdue
                            ? AppPalette.warning
                            : AppPalette.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '第 ${trayNumbers.join('、')} 格',
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final schedule in group.schedules)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: AppPalette.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medication, color: AppPalette.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      schedule.medicineName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text('${schedule.dose} · ${schedule.timing}'),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _handle(group, ReminderAction.taken),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('已服用'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _handle(group, ReminderAction.snoozed),
                  icon: const Icon(Icons.snooze),
                  label: const Text('稍後 10 分鐘'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _handle(group, ReminderAction.skipped),
                  icon: const Icon(Icons.skip_next_outlined),
                  label: const Text('略過'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetectedTrayDialog extends StatelessWidget {
  const _DetectedTrayDialog({
    required this.slot,
    required this.weight,
    required this.onLater,
    required this.onConfirm,
  });

  final int slot;
  final double weight;
  final VoidCallback onLater;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 44, vertical: 10),
                  child: Text(
                    '已偵測到新藥盤',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: '關閉',
                    onPressed: onLater,
                    icon: const Icon(Icons.close, color: Color(0xff687081)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xfff8fbf9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xffdce8df)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 104,
                    height: 86,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xffeef2f0),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xffc9d1cd),
                              width: 3,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x18000000),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.inventory_2_outlined,
                              size: 42,
                              color: Color(0xff8ba097),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 3,
                          right: 3,
                          bottom: 13,
                          child: Container(
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xff42bd50),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '$slot',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '第 $slot 格藥盤',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              '目前重量',
                              style: TextStyle(
                                fontSize: 17,
                                color: Color(0xff687081),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${weight.toStringAsFixed(1)} g',
                              style: const TextStyle(
                                fontSize: 25,
                                color: Color(0xff159443),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xfff1fbf4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.scale_outlined,
                    size: 30,
                    color: Color(0xff159443),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '確認後，此重量將設為藥盤的歸零基準。',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  '確認歸零',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onLater,
                child: const Text(
                  '稍後',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConfiguredTrayZeroDialog extends StatelessWidget {
  const _ConfiguredTrayZeroDialog({
    required this.slot,
    required this.currentWeight,
    required this.onReset,
  });

  final int slot;
  final double currentWeight;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 62,
              color: AppPalette.danger,
            ),
            const SizedBox(height: 12),
            const Text(
              '偵測到重量歸零',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              '第 $slot 格原本已設定藥品，但目前重量為 ${currentWeight.toStringAsFixed(1)} g。',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, height: 1.45),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xfffff7ed),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xffffc980)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Color(0xffb45309)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '若只是暫時拿起藥盤，請直接放回；重量恢復後，此提示會自動關閉。',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '確認後會清除第 $slot 格的藥盤、藥品與未來排程，讓此格回到未設定狀態；歷史服藥紀錄仍會保留。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: AppPalette.textMuted,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.danger,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('確認歸零並重置藥格'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TrayResetDialog extends StatelessWidget {
  const _TrayResetDialog({
    required this.slot,
    required this.previousWeight,
    required this.currentWeight,
    required this.onLater,
    required this.onReset,
  });

  final int slot;
  final double previousWeight;
  final double currentWeight;
  final VoidCallback onLater;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.scale_outlined,
              size: 58,
              color: Color(0xffd97706),
            ),
            const SizedBox(height: 12),
            Text(
              '第 $slot 格藥盤需要重新歸零',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              '尚未新增藥品，但藥盤重量已減輕。請確認藥盤放置正確後重新歸零。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: Color(0xff687081)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xfffff7ed),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xffffd7aa)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _weightValue('原歸零重量', previousWeight),
                  const Icon(Icons.arrow_forward, color: Color(0xffd97706)),
                  _weightValue('目前重量', currentWeight),
                ],
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('以目前重量重新歸零'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onLater, child: const Text('稍後處理')),
          ],
        ),
      ),
    ),
  );

  Widget _weightValue(String label, double value) => Column(
    children: [
      Text(label, style: const TextStyle(color: Color(0xff687081))),
      const SizedBox(height: 4),
      Text(
        '${value.toStringAsFixed(1)} g',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _DetectedMedicineDialog extends StatelessWidget {
  const _DetectedMedicineDialog({
    required this.slot,
    required this.addedWeight,
    required this.onLater,
    required this.onStart,
  });

  final int slot;
  final double addedWeight;
  final VoidCallback onLater;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 44, vertical: 10),
                  child: Text(
                    '已偵測到新藥品',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: '關閉',
                    onPressed: onLater,
                    icon: const Icon(Icons.close, color: Color(0xff687081)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xfff8fbf9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xffdce8df)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 104,
                    height: 86,
                    decoration: BoxDecoration(
                      color: const Color(0xffe7f8ec),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.medication_outlined,
                          size: 50,
                          color: Color(0xff159443),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff159443),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$slot',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '第 $slot 格藥盤',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              '增加重量',
                              style: TextStyle(
                                fontSize: 17,
                                color: Color(0xff687081),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '+${addedWeight.toStringAsFixed(1)} g',
                              style: const TextStyle(
                                fontSize: 25,
                                color: Color(0xff159443),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xfff1fbf4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 32,
                    color: Color(0xff159443),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '開始設定後，將確認藥品重量並掃描藥品條碼。',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.arrow_forward),
                label: const Text(
                  '開始設定',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onLater,
                child: const Text(
                  '稍後設定',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ResponsiveCanvas extends StatelessWidget {
  const ResponsiveCanvas({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(width: 1920, height: 1080, child: child),
    ),
  );
}

class TrayCard extends StatelessWidget {
  const TrayCard({
    super.key,
    required this.number,
    required this.tray,
    required this.schedule,
    required this.lightOn,
    required this.lightBusy,
    required this.needsTrayReset,
    required this.onView,
    required this.onMedicine,
    required this.onLightToggle,
    required this.onResetTray,
    this.onRetryDetection,
  });
  final int number;
  final Tray? tray;
  final MedicationSchedule? schedule;
  final bool lightOn;
  final bool lightBusy;
  final bool needsTrayReset;
  final VoidCallback onView, onMedicine, onLightToggle, onResetTray;
  final VoidCallback? onRetryDetection;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: tray == null ? null : onView,
    borderRadius: BorderRadius.circular(24),
    child: Container(
      decoration: BoxDecoration(
        color: tray == null ? AppPalette.surface : const Color(0xfff5fbf6),
        border: Border.all(
          color: tray == null ? AppPalette.border : const Color(0xff8fd19f),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: tray == null
                    ? AppPalette.surfaceMuted
                    : AppPalette.primarySoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '第 $number 格',
                style: TextStyle(
                  fontSize: 20,
                  color: tray == null
                      ? AppPalette.textMuted
                      : AppPalette.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (tray == null) ...[
              const Icon(
                Icons.inventory_2_outlined,
                color: AppPalette.textMuted,
                size: 38,
              ),
              const SizedBox(height: 7),
              const Text(
                '尚未放置藥盤',
                style: TextStyle(
                  color: AppPalette.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                onRetryDetection == null ? '等待秤重器偵測' : '已偵測到藥盤，等待設定',
                style: const TextStyle(
                  color: AppPalette.textMuted,
                  fontSize: 15,
                ),
              ),
              if (onRetryDetection != null) ...[
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: onRetryDetection,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('再次開啟設定'),
                ),
              ],
            ] else ...[
              Text(
                tray!.name,
                style: const TextStyle(
                  fontSize: 24,
                  color: AppPalette.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (tray!.contents.isNotEmpty) ...[
                Text(
                  '${tray!.person ?? '未指定家人'} · ${tray!.contents.length} 種藥品',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  tray!.contents.map((item) => item.name).join('、'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppPalette.textMuted,
                  ),
                ),
                Text(
                  schedule == null
                      ? '未設定提醒'
                      : schedule!.nextReminder() == null
                      ? '療程已結束'
                      : '下次提醒 ${_formatDateTime(schedule!.nextReminder()!)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (tray!.hasMedicine) ...[
                Text(
                  '${tray!.person ?? '未指定家人'} · ${tray!.medicineName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${tray!.dose ?? '-'} · ${tray!.timing ?? tray!.usage ?? '-'}',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppPalette.textMuted,
                  ),
                ),
                Text(
                  schedule == null
                      ? '未設定提醒'
                      : schedule!.nextReminder() == null
                      ? '療程已結束'
                      : '下次提醒 ${_formatDateTime(schedule!.nextReminder()!)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else
                Text(
                  '藥盤重量 ${tray!.emptyWeight.toStringAsFixed(1)} g',
                  style: const TextStyle(fontSize: 17),
                ),
              if (needsTrayReset) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xfffff3e3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Color(0xffc56700),
                      ),
                      SizedBox(width: 5),
                      Text(
                        '重量已減輕，請重新歸零',
                        style: TextStyle(
                          color: Color(0xff9a4f00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    lightOn ? Icons.lightbulb : Icons.lightbulb_outline,
                    size: 18,
                    color: lightOn ? AppPalette.warning : AppPalette.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    lightOn ? '燈號開啟中' : '燈號關閉',
                    style: TextStyle(
                      fontSize: 15,
                      color: lightOn
                          ? AppPalette.warning
                          : AppPalette.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: lightBusy ? null : onLightToggle,
                    icon: lightBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            lightOn ? Icons.lightbulb_outline : Icons.lightbulb,
                            size: 18,
                          ),
                    label: Text(lightOn ? '關閉測試燈' : '開啟測試燈'),
                  ),
                  OutlinedButton(
                    onPressed: needsTrayReset ? null : onMedicine,
                    child: Text(tray!.hasMedicine ? '修改藥品' : '新增藥品'),
                  ),
                  if (needsTrayReset)
                    FilledButton.icon(
                      onPressed: onResetTray,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('重新歸零'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class TraySetupPage extends StatefulWidget {
  const TraySetupPage({super.key, required this.slot, required this.api});
  final int slot;
  final TrayApi api;
  @override
  State<TraySetupPage> createState() => _TraySetupPageState();
}

class _TraySetupPageState extends State<TraySetupPage> {
  double? weight;
  final name = TextEditingController();
  Timer? _poller;
  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final values = await widget.api.weights();
        if (mounted && values[widget.slot - 1] > 0) {
          setState(() => weight = values[widget.slot - 1]);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('新增第 ${widget.slot} 格藥盤')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: AppPageCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.scale_outlined,
                size: 90,
                color: Color(0xff159443),
              ),
              const SizedBox(height: 20),
              const Text(
                '秤重器量測',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                weight == null
                    ? '請將藥盤放在秤重器上'
                    : '偵測到藥盤重量：${weight!.toStringAsFixed(1)} g',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 22),
              if (weight == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: '藥盤名稱',
                    hintText: '例如：早上藥盤',
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    Tray(
                      name: name.text.trim().isEmpty
                          ? '第 ${widget.slot} 格藥盤'
                          : name.text.trim(),
                      emptyWeight: weight!,
                    ),
                  ),
                  child: const Text('確認並完成歸零設定'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class MedicineWeightPage extends StatefulWidget {
  const MedicineWeightPage({
    super.key,
    required this.tray,
    required this.slot,
    required this.api,
  });
  final Tray tray;
  final int slot;
  final TrayApi api;
  @override
  State<MedicineWeightPage> createState() => _MedicineWeightPageState();
}

class _MedicineWeightPageState extends State<MedicineWeightPage> {
  double? weight;
  Timer? _poller;
  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final values = await widget.api.weights();
        final change = values[widget.slot - 1] - widget.tray.emptyWeight;
        if (mounted && change > 0) setState(() => weight = change);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Tray _updatedTray(
    MedicineDetails medicine, {
    PrescriptionScanResult? prescription,
    String? scheduleId,
  }) => Tray(
    name: widget.tray.name,
    emptyWeight: widget.tray.emptyWeight,
    medicineName: medicine.name,
    expiry: medicine.expiry,
    usage: medicine.usage,
    total: medicine.total,
    medicineWeight: medicine.weight,
    barcode: medicine.barcode,
    person: prescription?.person ?? widget.tray.person,
    dose: prescription?.dose ?? widget.tray.dose,
    frequency: prescription?.frequency ?? widget.tray.frequency,
    timing: prescription?.timing ?? widget.tray.timing,
    startDate: prescription == null
        ? widget.tray.startDate
        : _formatDate(prescription.startDate),
    days: prescription?.days ?? widget.tray.days,
    scheduleId: scheduleId ?? widget.tray.scheduleId,
  );

  Tray _updatedPrescriptionTray(
    PrescriptionScanResult prescription,
    MedicationSchedule schedule,
  ) => Tray(
    name: widget.tray.name,
    emptyWeight: widget.tray.emptyWeight,
    medicineName: '${prescription.medications.length} 種藥品',
    usage: '內容物清單',
    total: prescription.medications.fold(
      0,
      (sum, item) => sum + item.totalQuantity,
    ),
    medicineWeight: weight!,
    barcode: 'DEMO-PRESCRIPTION',
    person: prescription.person,
    dose: '依內容物資訊',
    frequency: null,
    timing: '自訂每日提醒',
    startDate: _formatDate(prescription.startDate),
    days: prescription.days,
    scheduleId: schedule.id,
    contents: List<PrescriptionMedication>.of(prescription.medications),
  );

  Future<void> _scanAndConfigure() async {
    final scanResult = await Navigator.push<MedicineScanResult>(
      context,
      MaterialPageRoute(builder: (_) => ScannerPage(slot: widget.slot)),
    );
    if (scanResult == null || !mounted) return;

    if (scanResult is BarcodeScanResult) {
      final medicine = await Navigator.push<MedicineDetails>(
        context,
        MaterialPageRoute(
          builder: (_) => MedicineFormPage(
            weight: weight!,
            scanLabel: scanResult.code,
            barcode: scanResult.code,
          ),
        ),
      );
      if (medicine != null && mounted) {
        Navigator.pop(
          context,
          MedicineSetupResult(tray: _updatedTray(medicine)),
        );
      }
      return;
    }

    final prescription = scanResult as PrescriptionScanResult;
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PrescriptionResultPage(result: prescription),
      ),
    );
    if (confirmed != true || !mounted) return;

    final schedule = await Navigator.push<MedicationSchedule>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderSchedulePage(prescription: prescription),
      ),
    );
    if (schedule == null || !mounted) return;

    Navigator.pop(
      context,
      MedicineSetupResult(
        tray: _updatedPrescriptionTray(prescription, schedule),
        schedule: schedule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新增藥品')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: AppPageCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.medication_outlined,
                size: 90,
                color: Color(0xff159443),
              ),
              const SizedBox(height: 20),
              const Text(
                '請將藥包放到藥盤上',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              Text(
                weight == null
                    ? '等待秤重器偵測重量變化'
                    : '藥品重量變化：${weight!.toStringAsFixed(1)} g',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 23),
              ),
              const SizedBox(height: 22),
              if (weight == null)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton.icon(
                  onPressed: _scanAndConfigure,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('掃描藥品／處方'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.slot});
  final int slot;
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;
  bool _processingDemo = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runDemo() async {
    if (_done || _processingDemo) return;
    setState(() => _processingDemo = true);
    await _controller.stop();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _done = true;
    Navigator.pop(context, PrescriptionScanResult.demo(widget.slot));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('掃描藥品／處方'),
      backgroundColor: AppPalette.text,
      foregroundColor: Colors.white,
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (!_done &&
                !_processingDemo &&
                capture.barcodes.firstOrNull?.rawValue != null) {
              _done = true;
              Navigator.pop(
                context,
                BarcodeScanResult(capture.barcodes.first.rawValue!),
              );
            }
          },
        ),
        Center(
          child: Container(
            width: 430,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppPalette.accent, width: 6),
              borderRadius: BorderRadius.circular(26),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, .58),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xdd101713),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              '將條碼或處方完整放入綠色框內',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 28,
          child: Center(
            child: FilledButton.icon(
              onPressed: _processingDemo ? null : _runDemo,
              icon: _processingDemo
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(_processingDemo ? '辨識中…' : '拍照 DEMO'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class PrescriptionResultPage extends StatelessWidget {
  const PrescriptionResultPage({super.key, required this.result});
  final PrescriptionScanResult result;

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 145,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xff687081), fontSize: 17),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _medicationCard(int index, PrescriptionMedication medication) => Card(
    margin: const EdgeInsets.only(top: 12),
    color: const Color(0xfff6fbf7),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '內容物 ${index + 1}：${medication.name}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 7,
            children: [
              Text('每次劑量：${medication.dose}'),
              Text('服用時機：${medication.timing}'),
              Text('頻率：${medication.frequency ?? '未辨識'}'),
              Text('療程：${medication.days} 天'),
              Text('總量：${medication.totalQuantity}'),
              Text(
                '效期：${medication.expiry?.isNotEmpty == true ? medication.expiry : '未提供'}',
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('處方辨識結果')),
    body: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.document_scanner_outlined,
                        size: 68,
                        color: Color(0xff159443),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '已辨識到家人處方資訊',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _row('家人', result.person),
                      _row('藥格', '第 ${result.tray} 格'),
                      _row('開始日期', _formatDate(result.startDate)),
                      _row('療程天數', '${result.days} 天'),
                      const SizedBox(height: 14),
                      Text(
                        '藥格內容物（${result.medications.length} 種）',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      for (
                        var index = 0;
                        index < result.medications.length;
                        index++
                      )
                        _medicationCard(index, result.medications[index]),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('確認內容物並設定提醒'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MedicineFormPage extends StatefulWidget {
  const MedicineFormPage({
    super.key,
    required this.weight,
    required this.scanLabel,
    required this.barcode,
  });
  final double weight;
  final String scanLabel;
  final String barcode;
  @override
  State<MedicineFormPage> createState() => _MedicineFormPageState();
}

class _MedicineFormPageState extends State<MedicineFormPage> {
  late final TextEditingController name;
  late final TextEditingController expiry;
  late final TextEditingController usage;
  late final TextEditingController total;

  @override
  void initState() {
    super.initState();
    name = TextEditingController();
    expiry = TextEditingController();
    usage = TextEditingController();
    total = TextEditingController(text: '30');
  }

  @override
  void dispose() {
    name.dispose();
    expiry.dispose();
    usage.dispose();
    total.dispose();
    super.dispose();
  }

  void _submit() {
    final count = int.tryParse(total.text.trim());
    if (name.text.trim().isEmpty || expiry.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填寫藥品名稱與藥品日期／效期')));
      return;
    }
    if (count == null || count <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('總量必須大於 0')));
      return;
    }
    Navigator.pop(
      context,
      MedicineDetails(
        name: name.text.trim(),
        expiry: expiry.text.trim(),
        usage: usage.text.trim(),
        total: count,
        weight: widget.weight,
        barcode: widget.barcode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = int.tryParse(total.text) ?? 0;
    final each = count == 0 ? 0 : widget.weight / count;
    return Scaffold(
      appBar: AppBar(title: const Text('確認藥品資料')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: AppPageCard(
            padding: const EdgeInsets.all(28),
            child: ListView(
              children: [
                Text(
                  '掃描結果：${widget.scanLabel}',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xff159443),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '藥品名稱'),
                ),
                TextField(
                  controller: expiry,
                  decoration: const InputDecoration(labelText: '藥品日期／效期'),
                ),
                TextField(
                  controller: usage,
                  decoration: const InputDecoration(
                    labelText: '用法（例如：每日 2 次，每次 1 顆）',
                  ),
                ),
                TextField(
                  controller: total,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: '總量（顆／包）'),
                ),
                const SizedBox(height: 18),
                Text(
                  '每次應消耗重量：${each.toStringAsFixed(2)} g',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 25),
                FilledButton(onPressed: _submit, child: const Text('確定設定完成')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReminderSchedulePage extends StatefulWidget {
  const ReminderSchedulePage({super.key, required this.prescription});

  final PrescriptionScanResult prescription;

  @override
  State<ReminderSchedulePage> createState() => _ReminderSchedulePageState();
}

class _ReminderSchedulePageState extends State<ReminderSchedulePage> {
  final List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];

  String _timeValue(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  List<String> get _sortedValues {
    final values = _times.map(_timeValue).toSet().toList()..sort();
    return values;
  }

  MedicationSchedule _schedule({String? id}) => MedicationSchedule(
    id: id ?? 'preview',
    person: widget.prescription.person,
    tray: widget.prescription.tray,
    medicineName: '${widget.prescription.medications.length} 種藥品',
    dose: '${widget.prescription.medications.length} 筆內容物',
    frequency: null,
    timing: '自訂每日提醒',
    startDate: widget.prescription.startDate,
    days: widget.prescription.days,
    reminderTimes: _sortedValues,
  );

  Future<void> _pickTime([int? index]) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: index == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : _times[index],
    );
    if (picked == null || !mounted) return;
    final duplicate = _times.asMap().entries.any(
      (entry) =>
          entry.key != index &&
          entry.value.hour == picked.hour &&
          entry.value.minute == picked.minute,
    );
    if (duplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('這個提醒時段已經存在')));
      return;
    }
    setState(() {
      if (index == null) {
        _times.add(picked);
      } else {
        _times[index] = picked;
      }
      _times.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
      );
    });
  }

  void _removeTime(int index) {
    if (_times.length == 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少需要保留一個提醒時段')));
      return;
    }
    setState(() => _times.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule();
    final preview = schedule.upcomingReminders();
    return Scaffold(
      appBar: AppBar(title: const Text('最後一步：設定每日提醒時間')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.prescription.person} · ${widget.prescription.medications.length} 種藥品',
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '第 ${widget.prescription.tray} 格｜提醒時間由您自行設定',
                        style: const TextStyle(fontSize: 18),
                      ),
                      Text(
                        '${_formatDate(widget.prescription.startDate)}～${_formatDate(schedule.endDate)}（${widget.prescription.days} 天）',
                        style: const TextStyle(
                          color: Color(0xff687081),
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xffeef9f1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xff159443)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '可設定一個或多個每日提醒時間。藥品內容物不會自動改變這裡的時間。',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '每日提醒時段',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < _times.length; index++) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xffdff9e8),
                      foregroundColor: const Color(0xff10833a),
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      _timeValue(_times[index]),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text('每日提醒'),
                    onTap: () => _pickTime(index),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '修改時間',
                          onPressed: () => _pickTime(index),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '刪除時間',
                          onPressed: () => _removeTime(index),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.add_alarm_outlined),
                  label: const Text('新增另一個提醒時間'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '接下來的提醒預覽',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (preview.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('此療程已結束，沒有尚未到達的提醒。'),
                  ),
                )
              else
                ...preview.map(
                  (value) => ListTile(
                    leading: const Icon(
                      Icons.notifications_active_outlined,
                      color: Color(0xff159443),
                    ),
                    title: Text(_formatDateTime(value)),
                    subtitle: const Text('每日自訂提醒'),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _schedule(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                  ),
                ),
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('完成設定並建立排程'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScheduleEditPage extends StatefulWidget {
  const ScheduleEditPage({super.key, required this.schedule});

  final MedicationSchedule schedule;

  @override
  State<ScheduleEditPage> createState() => _ScheduleEditPageState();
}

class _ScheduleEditPageState extends State<ScheduleEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _person;
  late final TextEditingController _dose;
  late final TextEditingController _timing;
  late final TextEditingController _days;
  late DateTime _startDate;
  late List<TimeOfDay> _times;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _person = TextEditingController(text: schedule.person);
    _dose = TextEditingController(text: schedule.dose);
    _timing = TextEditingController(text: schedule.timing);
    _days = TextEditingController(text: '${schedule.days}');
    _startDate = schedule.startDate;
    _times = schedule.reminderTimes.map((value) {
      final parts = value.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }).toList();
    _enabled = schedule.enabled;
  }

  @override
  void dispose() {
    _person.dispose();
    _dose.dispose();
    _timing.dispose();
    _days.dispose();
    super.dispose();
  }

  String _timeValue(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime([int? index]) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: index == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : _times[index],
    );
    if (picked == null || !mounted) return;
    final value = _timeValue(picked);
    if (_times.asMap().entries.any(
      (entry) => entry.key != index && _timeValue(entry.value) == value,
    )) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('這個提醒時段已經存在')));
      return;
    }
    setState(() {
      if (index == null) {
        _times.add(picked);
      } else {
        _times[index] = picked;
      }
      _times.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
      );
    });
  }

  Future<void> _pickStartDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _startDate = value);
  }

  void _removeTime(int index) {
    if (_times.length == 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少需要保留一個提醒時段')));
      return;
    }
    setState(() => _times.removeAt(index));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      widget.schedule.copyWith(
        person: _person.text.trim(),
        dose: _dose.text.trim(),
        timing: _timing.text.trim(),
        startDate: _startDate,
        days: int.parse(_days.text.trim()),
        reminderTimes: _times.map(_timeValue).toList()..sort(),
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('修改服藥排程')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
          child: AppPageCard(
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.medication_outlined,
                          color: AppPalette.primary,
                          size: 34,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '第 ${widget.schedule.tray} 格 · ${widget.schedule.medicineName}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _person,
                    decoration: const InputDecoration(
                      labelText: '服藥使用者',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '請輸入使用者姓名'
                        : null,
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: _dose,
                    decoration: const InputDecoration(
                      labelText: '每次服用劑量',
                      prefixIcon: Icon(Icons.local_pharmacy_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '請輸入服用劑量'
                        : null,
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: _timing,
                    decoration: const InputDecoration(
                      labelText: '服用時機／說明',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickStartDate,
                          icon: const Icon(Icons.event_outlined),
                          label: Text('開始 ${_formatDate(_startDate)}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _days,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '療程天數',
                            suffixText: '天',
                          ),
                          validator: (value) =>
                              (int.tryParse(value ?? '') ?? 0) < 1
                              ? '請輸入大於 0 的天數'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '每日提醒時間',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var index = 0; index < _times.length; index++)
                        InputChip(
                          avatar: const Icon(Icons.alarm, size: 19),
                          label: Text(_timeValue(_times[index])),
                          onPressed: () => _pickTime(index),
                          onDeleted: () => _removeTime(index),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_alarm, size: 19),
                        label: const Text('新增時間'),
                        onPressed: _pickTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('啟用此排程'),
                    subtitle: const Text('停用後不會顯示下一次提醒'),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('儲存排程'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SchedulePanel extends StatelessWidget {
  const SchedulePanel({
    super.key,
    required this.schedules,
    required this.onTap,
  });

  final List<MedicationSchedule> schedules;
  final ValueChanged<MedicationSchedule> onTap;
  static const double _scheduleCardHeight = 146;
  static const double _scheduleGap = 16;
  static const int _visibleScheduleCount = 4;
  static const double _scheduleListHeight =
      _scheduleCardHeight * _visibleScheduleCount +
      _scheduleGap * (_visibleScheduleCount - 1);

  @override
  Widget build(BuildContext context) {
    final ordered = List<MedicationSchedule>.from(schedules)
      ..sort((left, right) {
        final leftNext = left.nextReminder();
        final rightNext = right.nextReminder();
        if (leftNext == null && rightNext == null) {
          return right.endDate.compareTo(left.endDate);
        }
        if (leftNext == null) return 1;
        if (rightNext == null) return -1;
        return leftNext.compareTo(rightNext);
      });

    return Container(
      padding: const EdgeInsets.all(30),
      decoration: appPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: _SeniorClock()),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppPalette.primarySoft,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  size: 32,
                  color: AppPalette.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '服藥排程',
                style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${schedules.length} 筆',
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: _scheduleListHeight,
            child: ordered.isEmpty
                ? const _EmptyScheduleState()
                : ListView.separated(
                    itemCount: ordered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: _scheduleGap),
                    itemBuilder: (context, index) {
                      final schedule = ordered[index];
                      return SizedBox(
                        height: _scheduleCardHeight,
                        child: _ScheduleCard(
                          schedule: schedule,
                          onTap: () => onTap(schedule),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SeniorClock extends StatefulWidget {
  const _SeniorClock();

  @override
  State<_SeniorClock> createState() => _SeniorClockState();
}

class _SeniorClockState extends State<_SeniorClock> {
  static const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final time = '${_twoDigits(_now.hour)}:${_twoDigits(_now.minute)}';
    final seconds = _twoDigits(_now.second);
    final date =
        '${_now.year} 年 ${_now.month} 月 ${_now.day} 日　${_weekdays[_now.weekday - 1]}';

    return Semantics(
      liveRegion: true,
      label: '$date，現在時間 $time $seconds 秒',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        decoration: BoxDecoration(
          color: AppPalette.primarySoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xffa8d8b3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.access_time_rounded,
                size: 57,
                color: AppPalette.primary,
              ),
            ),
            const SizedBox(width: 26),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            time,
                            style: const TextStyle(
                              color: AppPalette.text,
                              fontSize: 116,
                              height: 0.9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 14, bottom: 7),
                            child: Text(
                              '$seconds 秒',
                              style: const TextStyle(
                                color: AppPalette.primary,
                                fontSize: 30,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      date,
                      style: const TextStyle(
                        color: AppPalette.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyScheduleState extends StatelessWidget {
  const _EmptyScheduleState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(
            color: AppPalette.primarySoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.event_busy_outlined,
            size: 55,
            color: AppPalette.primary,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '尚未設定服藥排程',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          '完成處方掃描與提醒設定後會顯示在這裡',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, color: AppPalette.textMuted),
        ),
      ],
    ),
  );
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule, required this.onTap});

  final MedicationSchedule schedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = schedule.nextReminder();
    final disabled = !schedule.enabled;
    final ended = disabled || next == null;
    return Material(
      color: ended ? AppPalette.surfaceMuted : AppPalette.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: ended ? AppPalette.border : const Color(0xffa8d8b3),
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: ended
                    ? const Color(0xffe2e5e3)
                    : AppPalette.primarySoft,
                child: Text(
                  schedule.person.isEmpty ? '?' : schedule.person[0],
                  style: TextStyle(
                    color: ended ? const Color(0xff6e7671) : AppPalette.primary,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${schedule.person} · ${schedule.medicineName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '第 ${schedule.tray} 格 · ${schedule.dose} · ${schedule.timing}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        color: AppPalette.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      disabled
                          ? '提醒已停用'
                          : ended
                          ? '療程已結束'
                          : '下一次 ${_formatDateTime(next)}',
                      style: TextStyle(
                        fontSize: 17,
                        color: ended
                            ? const Color(0xff777f7a)
                            : AppPalette.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 38,
                color: ended ? const Color(0xff8c938f) : AppPalette.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

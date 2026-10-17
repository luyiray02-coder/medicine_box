import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibox_rebuilt/main.dart';

void main() {
  MedicationSchedule buildSchedule() => MedicationSchedule(
    id: 'schedule-1',
    person: '盧奎佑',
    tray: 2,
    medicineName: '範例藥品',
    dose: '1 錠',
    frequency: null,
    timing: '早餐後吃',
    startDate: DateTime(2026, 9, 5),
    days: 28,
    reminderTimes: const ['08:00', '20:00'],
  );

  test('療程結束日與下一次提醒計算正確', () {
    final schedule = buildSchedule();

    expect(schedule.endDate, DateTime(2026, 10, 2));
    expect(
      schedule.nextReminder(DateTime(2026, 10, 1, 9)),
      DateTime(2026, 10, 1, 20),
    );
    expect(schedule.nextReminder(DateTime(2026, 10, 2, 21)), isNull);
  });

  test('提醒預覽排除已過時間並依時間排序', () {
    final schedule = buildSchedule();

    expect(
      schedule.upcomingReminders(count: 3, from: DateTime(2026, 10, 1, 9)),
      [
        DateTime(2026, 10, 1, 20),
        DateTime(2026, 10, 2, 8),
        DateTime(2026, 10, 2, 20),
      ],
    );
  });

  test('服藥提醒嚴格限制在指定的本地日期', () {
    final schedule = buildSchedule();

    expect(schedule.occurrencesOn(DateTime(2026, 10, 1, 23, 59)), [
      DateTime(2026, 10, 1, 8),
      DateTime(2026, 10, 1, 20),
    ]);
    expect(
      schedule.occurrencesOn(DateTime(2026, 10, 3)),
      isEmpty,
      reason: '療程結束後，不應補送前一天或更早的提醒',
    );
  });

  test('藥格與排程 JSON 可完整復原', () {
    final schedule = buildSchedule();
    final demo = PrescriptionScanResult.demo(2);
    final tray = Tray(
      name: '第 2 格藥盤',
      emptyWeight: 120,
      medicineName: '2 種藥品',
      usage: '內容物清單',
      total: 56,
      medicineWeight: 56,
      barcode: 'DEMO-PRESCRIPTION',
      person: '盧奎佑',
      dose: '1 錠',
      timing: '早餐後吃',
      startDate: '2026-09-05',
      days: 28,
      scheduleId: schedule.id,
      contents: demo.medications,
    );
    final original = PersistedMediBoxState(
      trays: [null, tray, null, null],
      schedules: [schedule],
    );

    final restored = PersistedMediBoxState.fromJson(original.toJson());

    expect(original.toJson()['version'], 4);
    expect(restored.trays[1]?.person, '盧奎佑');
    expect(restored.trays[1]?.medicineName, '2 種藥品');
    expect(restored.trays[1]?.contents, hasLength(2));
    expect(restored.trays[1]?.contents.first.name, 'OlsaaCa Tablets 5/');
    expect(restored.schedules.single.reminderTimes, ['08:00', '20:00']);
    expect(restored.schedules.single.enabled, isTrue);
    expect(restored.schedules.single.endDate, DateTime(2026, 10, 2));
  });

  test('停用排程不產生下一次提醒且可復原', () {
    final schedule = buildSchedule().copyWith(enabled: false);
    final restored = MedicationSchedule.fromJson(schedule.toJson());

    expect(restored.enabled, isFalse);
    expect(restored.nextReminder(DateTime(2026, 10, 1, 7)), isNull);
    expect(restored.upcomingReminders(from: DateTime(2026, 10, 1, 7)), isEmpty);
  });

  test('服藥結果與稍後時間可持久化', () {
    final record = DoseRecord(
      scheduleId: 'schedule-1',
      plannedAt: DateTime(2026, 10, 1, 8),
      status: DoseStatus.snoozed,
      actedAt: DateTime(2026, 10, 1, 8, 1),
      person: '盧奎佑',
      snoozedUntil: DateTime(2026, 10, 1, 8, 11),
    );
    final state = PersistedMediBoxState(
      trays: List<Tray?>.filled(4, null),
      schedules: [buildSchedule()],
      doseRecords: [record],
    );

    final restored = PersistedMediBoxState.fromJson(state.toJson());
    expect(restored.doseRecords.single.status, DoseStatus.snoozed);
    expect(restored.doseRecords.single.person, '盧奎佑');
    expect(
      restored.doseRecords.single.snoozedUntil,
      DateTime(2026, 10, 1, 8, 11),
    );
  });

  test('已服用紀錄可跨排程 ID 阻止同一家人同時間重複提醒', () {
    final plannedAt = DateTime(2026, 10, 1, 8);
    final record = DoseRecord(
      scheduleId: 'old-schedule-id',
      plannedAt: plannedAt,
      status: DoseStatus.taken,
      actedAt: DateTime(2026, 10, 1, 8, 1),
      person: '盧奎佑',
    );

    expect(record.groupOccurrenceKey, doseGroupOccurrenceKey('盧奎佑', plannedAt));
    expect(
      record.groupOccurrenceKey,
      doseGroupOccurrenceKey(' 盧奎佑 ', plannedAt),
      reason: '排程重建或 ID 改變後，同一人同一時間仍視為已處理',
    );
  });

  testWidgets('已服用後即使排程 ID 改變也不再彈出同一提醒', (tester) async {
    final now = DateTime.now();
    final plannedAt = DateTime(now.year, now.month, now.day);
    final schedule = MedicationSchedule(
      id: 'rebuilt-schedule-id',
      person: '盧奎佑',
      tray: 1,
      medicineName: '每日藥品',
      dose: '1 錠',
      frequency: null,
      timing: '飯後服用',
      startDate: plannedAt,
      days: 1,
      reminderTimes: const ['00:00'],
    );
    final takenRecord = DoseRecord(
      scheduleId: 'previous-schedule-id',
      plannedAt: plannedAt,
      status: DoseStatus.taken,
      actedAt: plannedAt.add(const Duration(minutes: 1)),
    );

    await tester.pumpWidget(
      MediBoxApp(
        initialState: PersistedMediBoxState(
          trays: List<Tray?>.filled(4, null),
          schedules: [schedule],
          doseRecords: [takenRecord],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('服藥時間到了'), findsNothing);
    expect(find.text('今日待處理服藥提醒'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('按下已服用後經過下一次輪詢也不會再次彈出', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final schedule = MedicationSchedule(
      id: 'active-schedule',
      person: '盧奎佑',
      tray: 1,
      medicineName: '每日藥品',
      dose: '1 錠',
      frequency: null,
      timing: '飯後服用',
      startDate: today,
      days: 1,
      reminderTimes: const ['00:00'],
    );

    await tester.pumpWidget(
      MediBoxApp(
        initialState: PersistedMediBoxState(
          trays: List<Tray?>.filled(4, null),
          schedules: [schedule],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已服用'), findsOneWidget);

    await tester.tap(find.text('已服用'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已服用'), findsNothing);

    await tester.pump(const Duration(seconds: 21));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已服用'), findsNothing);
    expect(find.text('服藥時間到了'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('單筆損壞資料不影響其他藥格與排程', () {
    final schedule = buildSchedule();
    final state = PersistedMediBoxState.fromJson({
      'version': 1,
      'trays': [
        {'name': 42, 'emptyWeight': 'bad'},
        Tray(name: '第 2 格藥盤', emptyWeight: 100).toJson(),
      ],
      'schedules': [
        {'id': 'bad'},
        schedule.toJson(),
      ],
    });

    expect(state.trays[0], isNull);
    expect(state.trays[1]?.name, '第 2 格藥盤');
    expect(state.schedules.single.id, schedule.id);
  });

  test('DEMO 精確帶入兩筆內容物', () {
    final result = PrescriptionScanResult.demo(3);

    expect(result.person, '盧奎佑');
    expect(result.tray, 3);
    expect(result.medications, hasLength(2));
    expect(result.medications[0].name, 'OlsaaCa Tablets 5/');
    expect(result.medications[1].name, 'ROBESTAR SANDOZ. FI');
    for (final medication in result.medications) {
      expect(medication.dose, '1 錠');
      expect(medication.timing, '早餐後吃');
      expect(medication.frequency, isNull);
      expect(medication.days, 28);
      expect(medication.totalQuantity, 28);
      expect(medication.expiry, isNull);
    }

    final restored = PrescriptionScanResult.fromJson(result.toJson());
    expect(restored.medications[1].name, 'ROBESTAR SANDOZ. FI');
  });

  test('舊版單一藥品資料仍可載入', () {
    final state = PersistedMediBoxState.fromJson({
      'version': 1,
      'trays': [
        {
          'name': '舊版藥盤',
          'emptyWeight': 80,
          'medicineName': '舊版藥品',
          'total': 10,
          'medicineWeight': 20,
        },
      ],
      'schedules': <Object?>[],
    });

    expect(state.trays.first?.medicineName, '舊版藥品');
    expect(state.trays.first?.contents, isEmpty);
    expect(state.trays.first?.hasMedicine, isTrue);
  });

  test('已設定藥品的重量由正常值降為零時才建立重置提示', () {
    final monitor = ConfiguredTrayZeroMonitor();
    final configuredTray = Tray(
      name: '第 1 格藥盤',
      emptyWeight: 100,
      medicineName: '每日藥品',
      medicineWeight: 20,
    );
    final trays = <Tray?>[configuredTray, null, null, null];

    expect(
      monitor.update(
        trays: trays,
        weights: const [120, 0, 0, 0],
        apiConnected: true,
      ),
      isEmpty,
      reason: '第一次成功讀值只建立比較基準，不應誤判為突然歸零',
    );
    expect(
      monitor.update(
        trays: trays,
        weights: const [0, 0, 0, 0],
        apiConnected: true,
      ),
      {0},
    );
    expect(
      monitor.update(
        trays: trays,
        weights: const [120, 0, 0, 0],
        apiConnected: true,
      ),
      isEmpty,
      reason: '重量恢復後必須立即清除待顯示的歸零提示',
    );
  });

  test('API 異常或尚未設定藥品時不提示重量歸零', () {
    final disconnectedMonitor = ConfiguredTrayZeroMonitor();
    final configuredTray = Tray(
      name: '第 1 格藥盤',
      emptyWeight: 100,
      medicineName: '每日藥品',
    );
    disconnectedMonitor.update(
      trays: <Tray?>[configuredTray],
      weights: const [100],
      apiConnected: true,
    );
    expect(
      disconnectedMonitor.update(
        trays: <Tray?>[configuredTray],
        weights: const [0],
        apiConnected: false,
      ),
      isEmpty,
    );

    final emptyTrayMonitor = ConfiguredTrayZeroMonitor();
    final emptyTray = Tray(name: '空藥盤', emptyWeight: 100);
    emptyTrayMonitor.update(
      trays: <Tray?>[emptyTray],
      weights: const [100],
      apiConnected: true,
    );
    expect(
      emptyTrayMonitor.update(
        trays: <Tray?>[emptyTray],
        weights: const [0],
        apiConnected: true,
      ),
      isEmpty,
    );
  });

  test('確認歸零重置會清除該格設定與未來排程並保留歷史紀錄', () {
    final trays = <Tray?>[
      Tray(name: '爺爺藥盤', emptyWeight: 100, medicineName: '每日藥品', person: '爺爺'),
      Tray(name: '第 2 格藥盤', emptyWeight: 80),
      null,
      null,
    ];
    final firstTraySchedule = MedicationSchedule(
      id: 'first-tray-schedule',
      person: '爺爺',
      tray: 1,
      medicineName: '每日藥品',
      dose: '1 錠',
      frequency: null,
      timing: '飯後服用',
      startDate: DateTime(2026, 10, 4),
      days: 30,
      reminderTimes: const ['08:00'],
    );
    final otherSchedule = buildSchedule();
    final schedules = <MedicationSchedule>[firstTraySchedule, otherSchedule];
    final history = <DoseRecord>[
      DoseRecord(
        scheduleId: firstTraySchedule.id,
        plannedAt: DateTime(2026, 10, 4, 8),
        status: DoseStatus.taken,
        actedAt: DateTime(2026, 10, 4, 8, 1),
        person: '爺爺',
      ),
    ];

    resetTraySlotConfiguration(index: 0, trays: trays, schedules: schedules);

    expect(trays[0], isNull);
    expect(trays[1], isNotNull);
    expect(schedules, [otherSchedule]);
    expect(history, hasLength(1), reason: '歷史服藥紀錄不在重置範圍內');
    expect(history.single.status, DoseStatus.taken);
  });

  test('單筆損壞內容物不影響其他內容物', () {
    final valid = PrescriptionScanResult.demo(1).medications.first;
    final tray = Tray.fromJson({
      'name': '第 1 格藥盤',
      'emptyWeight': 100,
      'contents': [
        {'name': 123},
        valid.toJson(),
      ],
    });

    expect(tray.contents, hasLength(1));
    expect(tray.contents.single.name, 'OlsaaCa Tablets 5/');
  });

  testWidgets('DEMO 辨識結果顯示兩筆內容物且不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionResultPage(result: PrescriptionScanResult.demo(1)),
      ),
    );

    expect(find.textContaining('OlsaaCa Tablets 5/'), findsOneWidget);
    expect(find.textContaining('ROBESTAR SANDOZ. FI'), findsOneWidget);
    expect(find.text('確認內容物並設定提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最後步驟明確顯示多時間設定', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ReminderSchedulePage(
          prescription: PrescriptionScanResult.demo(1),
        ),
      ),
    );

    expect(find.text('最後一步：設定每日提醒時間'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('新增另一個提醒時間'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('完成設定並建立排程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('四筆排程在較大系統字級下不會溢位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1080));
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final schedules = List.generate(
      4,
      (index) => MedicationSchedule(
        id: 'layout-$index',
        person: '家人 ${index + 1}',
        tray: index + 1,
        medicineName: '每日藥品',
        dose: '1 錠',
        frequency: null,
        timing: '飯後服用',
        startDate: tomorrow,
        days: 30,
        reminderTimes: const ['08:00'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 820,
              height: 1012,
              child: SchedulePanel(schedules: schedules, onTap: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('家人 4 · 每日藥品'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

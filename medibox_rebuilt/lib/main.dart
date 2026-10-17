import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class TrayApi {
  TrayApi._();
  static final instance = TrayApi._();
  String _baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://10.0.2.2:8080',
  );
  String get baseUrl => _baseUrl;
  void configure(String value) =>
      _baseUrl = value.replaceAll(RegExp(r'/+$'), '');
  final HttpClient _client = HttpClient()
    ..badCertificateCallback = (_, __, ___) => true;
  Future<dynamic> _get(String path) async {
    final request = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    final response = await request.close();
    return jsonDecode(await utf8.decodeStream(response));
  }

  Future<List<double>> weights() async => (await _get('/api/weight') as List)
      .map((v) => (v as num).toDouble())
      .toList();
  Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await _get('/api/status') as Map);
  Future<List<bool>> lightStatus() async =>
      (await _get('/api/lightStatus') as List).cast<bool>();
  Future<void> light(int target, bool on) async =>
      _get('/api/${on ? 'lightOn' : 'lightOff'}?target=$target');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MediBoxApp());
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
  });
  String name;
  final double emptyWeight;
  String? medicineName, expiry, usage, barcode;
  int total;
  double medicineWeight;
  bool get hasMedicine => medicineName != null;
}

class MediBoxApp extends StatelessWidget {
  const MediBoxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '智慧藥箱',
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xff159443),
    ),
    home: const MediBoxHome(),
  );
}

class MediBoxHome extends StatefulWidget {
  const MediBoxHome({super.key});
  @override
  State<MediBoxHome> createState() => _MediBoxHomeState();
}

class _MediBoxHomeState extends State<MediBoxHome> {
  final List<Tray?> trays = List.filled(4, null);
  List<double> measuredWeights = List.filled(4, 0);
  List<bool> lightStates = List.filled(4, false);
  double temperature = 26, humidity = 62;
  bool apiConnected = false;
  Timer? _poller;
  final Set<int> _promptedSlots = {};
  bool _dialogOpen = false;
  bool _settingsOpen = false;
  bool _apiEditorOpen = false;
  late final TextEditingController _apiUrlController;
  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: TrayApi.instance.baseUrl);
    _refreshApi();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) => _refreshApi());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _refreshApi() async {
    try {
      final values = await TrayApi.instance.weights();
      final env = await TrayApi.instance.status();
      final lights = await TrayApi.instance.lightStatus();
      if (mounted) {
        setState(() {
          measuredWeights = values;
          temperature = (env['tem'] as num).toDouble();
          humidity = (env['hum'] as num).toDouble();
          lightStates = lights;
          apiConnected = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _dialogOpen || _settingsOpen) return;
          for (var index = 0; index < values.length; index++) {
            if (values[index] == 0) _promptedSlots.remove(index);
            if (!_promptedSlots.contains(index))
              _detectWeight(index, values[index]);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => apiConnected = false);
    }
  }

  void _toggleApiEditor() {
    setState(() {
      _apiEditorOpen = !_apiEditorOpen;
      _settingsOpen = _apiEditorOpen;
      if (_apiEditorOpen) _apiUrlController.text = TrayApi.instance.baseUrl;
    });
  }

  void _applyApiUrl() {
    final value = _apiUrlController.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    TrayApi.instance.configure(value);
    setState(() {
      _apiEditorOpen = false;
      _settingsOpen = false;
      apiConnected = false;
    });
    unawaited(_refreshApi());
  }

  void _detectWeight(int index, double rawWeight) {
    if (_dialogOpen || _settingsOpen) return;
    final tray = trays[index];
    if (rawWeight <= 0) return;
    if (tray == null) {
      _promptedSlots.add(index);
      _dialogOpen = true;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('偵測到藥盤'),
          content: Text(
            '第 ${index + 1} 格偵測到 ${rawWeight.toStringAsFixed(1)} g。\n按「確認歸零」後，這個重量會成為藥盤基準。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('稍後'),
            ),
            FilledButton(
              onPressed: () {
                setState(
                  () => trays[index] = Tray(
                    name: '第 ${index + 1} 格藥盤',
                    emptyWeight: rawWeight,
                  ),
                );
                _promptedSlots.remove(index);
                Navigator.pop(dialogContext);
              },
              child: const Text('確認歸零'),
            ),
          ],
        ),
      ).whenComplete(() {
        if (mounted) _dialogOpen = false;
      });
      return;
    }
    final medicineWeight = rawWeight - tray.emptyWeight;
    if (!tray.hasMedicine && medicineWeight > 0.5) {
      _promptedSlots.add(index);
      _dialogOpen = true;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('偵測到藥品'),
          content: Text(
            '第 ${index + 1} 格增加 ${medicineWeight.toStringAsFixed(1)} g。\n將此重量視為藥品重量並開始設定嗎？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('稍後'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _addMedicine(index);
              },
              child: const Text('開始設定'),
            ),
          ],
        ),
      ).whenComplete(() {
        if (mounted) _dialogOpen = false;
      });
    }
  }

  Future<void> _addTray(int index) async {
    final tray = await Navigator.push<Tray>(
      context,
      MaterialPageRoute(
        builder: (_) => TraySetupPage(slot: index + 1, api: TrayApi.instance),
      ),
    );
    if (tray != null && mounted) setState(() => trays[index] = tray);
  }

  Future<void> _addMedicine(int index) async {
    final tray = trays[index]!;
    try {
      await TrayApi.instance.light(index + 1, true);
    } catch (_) {}
    final updated = await Navigator.push<Tray>(
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
    if (updated != null && mounted) setState(() => trays[index] = updated);
  }

  void _viewTray(int index) {
    final tray = trays[index];
    if (tray == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tray.name),
        content: Text(
          '藥盤重量：${tray.emptyWeight.toStringAsFixed(1)} g\n${tray.hasMedicine ? '藥品：${tray.medicineName}\n效期：${tray.expiry}\n用法：${tray.usage}\n總量：${tray.total}' : '尚未設定藥品'}',
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
              setState(() => trays[index] = null);
            },
            child: const Text('刪除'),
          ),
        ],
      ),
    );
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
              Navigator.pop(dialogContext);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: ResponsiveCanvas(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Row(
            children: [
              Expanded(flex: 11, child: _trayPanel()),
              const SizedBox(width: 54),
              Expanded(flex: 9, child: const SchedulePanel()),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _trayPanel() => Container(
    padding: const EdgeInsets.all(34),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xfff8fffa), Colors.white],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: const Color(0xffd9f0e0), width: 2),
      borderRadius: BorderRadius.circular(32),
      boxShadow: const [
        BoxShadow(
          color: Color(0x160b3520),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xffddf8e6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.medical_services_outlined,
                color: Color(0xff159443),
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
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '4 格藥盤 · 即時監測',
                    style: TextStyle(fontSize: 18, color: Color(0xff687081)),
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
                    ? const Color(0xff159443)
                    : const Color(0xff8b5e00),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xffddf8e6),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, size: 20, color: Color(0xff159443)),
                  SizedBox(width: 7),
                  Text(
                    '正常運作',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xff159443),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_apiEditorOpen) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xfff4fbf6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xffcdebd7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_ethernet, color: Color(0xff159443)),
                const SizedBox(width: 10),
                const Text(
                  'API：',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _apiUrlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _applyApiUrl(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'https://10.0.2.2:8080',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _toggleApiEditor,
                  child: const Text('取消'),
                ),
                FilledButton(onPressed: _applyApiUrl, child: const Text('套用')),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _metric(
                Icons.thermostat,
                '溫度',
                '${temperature.toStringAsFixed(0)}°C',
                const Color(0xffffeee7),
                const Color(0xffe66c32),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metric(
                Icons.water_drop_outlined,
                '濕度',
                '${humidity.toStringAsFixed(0)}%',
                const Color(0xffe8f5ff),
                const Color(0xff2587d9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              const gap = 20.0;
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
                  lightOn: lightStates[i],
                  onView: () => _viewTray(i),
                  onMedicine: () => _addMedicine(i),
                ),
              );
            },
          ),
        ),
      ],
    ),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xffedf0ee)),
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
              style: const TextStyle(fontSize: 16, color: Color(0xff687081)),
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
    required this.lightOn,
    required this.onView,
    required this.onMedicine,
  });
  final int number;
  final Tray? tray;
  final bool lightOn;
  final VoidCallback onView, onMedicine;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: tray == null ? null : onView,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      decoration: BoxDecoration(
        color: tray == null ? Colors.white : const Color(0xfff2fcf5),
        border: Border.all(
          color: tray == null
              ? const Color(0xffd8e7dc)
              : const Color(0xff98dbae),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d0b3520),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
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
                    ? const Color(0xfff1f5f2)
                    : const Color(0xffd8f7e2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '第${const ['一', '二', '三', '四'][number - 1]}格',
                style: TextStyle(
                  fontSize: 20,
                  color: tray == null
                      ? const Color(0xff52605a)
                      : const Color(0xff10833a),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (tray == null) ...[
              const Icon(
                Icons.inventory_2_outlined,
                color: Color(0xff99a79e),
                size: 38,
              ),
              const SizedBox(height: 7),
              const Text(
                '尚未放置藥盤',
                style: TextStyle(
                  color: Color(0xff52605a),
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '等待秤重器偵測',
                style: TextStyle(color: Color(0xff8a9a90), fontSize: 15),
              ),
            ] else ...[
              Text(
                tray!.name,
                style: const TextStyle(
                  fontSize: 24,
                  color: Color(0xff159443),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '藥盤重量 ${tray!.emptyWeight.toStringAsFixed(1)} g',
                style: const TextStyle(fontSize: 17),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    lightOn ? Icons.lightbulb : Icons.lightbulb_outline,
                    size: 18,
                    color: lightOn
                        ? const Color(0xffffb020)
                        : const Color(0xff809087),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    lightOn ? '燈號開啟中' : '燈號關閉',
                    style: TextStyle(
                      fontSize: 15,
                      color: lightOn
                          ? const Color(0xffa05b00)
                          : const Color(0xff617168),
                    ),
                  ),
                ],
              ),
              if (tray!.hasMedicine)
                Text(tray!.medicineName!, style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onMedicine,
                child: Text(tray!.hasMedicine ? '修改藥品' : '新增藥品'),
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
        if (mounted && values[widget.slot - 1] > 0)
          setState(() => weight = values[widget.slot - 1]);
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
        child: Padding(
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新增藥品')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Padding(
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
                  onPressed: () async {
                    final code = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(builder: (_) => const ScannerPage()),
                    );
                    if (code != null && mounted) {
                      final updated = await Navigator.push<Tray>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MedicineFormPage(
                            tray: widget.tray,
                            weight: weight!,
                            barcode: code,
                          ),
                        ),
                      );
                      if (updated != null && mounted)
                        Navigator.pop(context, updated);
                    }
                  },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('掃描藥品條碼'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('掃描藥品條碼')),
    body: Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (!done && capture.barcodes.firstOrNull?.rawValue != null) {
              done = true;
              Navigator.pop(context, capture.barcodes.first.rawValue);
            }
          },
        ),
        const Center(
          child: SizedBox(
            width: 430,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.green, width: 5),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class MedicineFormPage extends StatefulWidget {
  const MedicineFormPage({
    super.key,
    required this.tray,
    required this.weight,
    required this.barcode,
  });
  final Tray tray;
  final double weight;
  final String barcode;
  @override
  State<MedicineFormPage> createState() => _MedicineFormPageState();
}

class _MedicineFormPageState extends State<MedicineFormPage> {
  final name = TextEditingController(),
      expiry = TextEditingController(),
      usage = TextEditingController(),
      total = TextEditingController(text: '30');
  @override
  void dispose() {
    name.dispose();
    expiry.dispose();
    usage.dispose();
    total.dispose();
    super.dispose();
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
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ListView(
              children: [
                Text(
                  '掃描結果：${widget.barcode}',
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
                FilledButton(
                  onPressed: () {
                    widget.tray.medicineName = name.text.trim().isEmpty
                        ? '未命名藥品'
                        : name.text.trim();
                    widget.tray.expiry = expiry.text.trim();
                    widget.tray.usage = usage.text.trim();
                    widget.tray.total = count;
                    widget.tray.medicineWeight = widget.weight;
                    widget.tray.barcode = widget.barcode;
                    Navigator.pop(context, widget.tray);
                  },
                  child: const Text('確定設定完成'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SchedulePanel extends StatelessWidget {
  const SchedulePanel({super.key});
  static const people = [
    ('assets/flutter_assets/assets/grandpa.png', '阿公', '下午 20:00 服藥前', false),
    ('assets/flutter_assets/assets/aunt.png', '阿姨', '下午 18:00 晚餐後', true),
    ('assets/flutter_assets/assets/father.png', '爸爸', '下午 07:00 早餐後', false),
    ('assets/flutter_assets/assets/mother.png', '媽媽', '下午 12:00 午餐後', false),
  ];
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      people.length,
      (i) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(bottom: i == 3 ? 0 : 20),
          child: _card(people[i]),
        ),
      ),
    ),
  );
  Widget _card((String, String, String, bool) p) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
    decoration: BoxDecoration(
      color: p.$4 ? const Color(0xffdff9e8) : const Color(0xfffcfcfc),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      children: [
        Image.asset(p.$1, width: 90, height: 90),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.$2,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                p.$3,
                style: const TextStyle(
                  fontSize: 20,
                  color: Color(0xff4e5968),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (p.$4)
                const Text(
                  '即將服藥',
                  style: TextStyle(
                    color: Color(0xff159443),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right,
          size: 50,
          color: p.$4 ? const Color(0xff159443) : const Color(0xff777777),
        ),
      ],
    ),
  );
}

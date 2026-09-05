import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const _serviceUuid = '12345678-1234-1234-1234-123456789abc';
const _animationPresets = ['reactor', 'comet', 'shockwave', 'rainbow', 'pulse', 'scanner', 'aurora'];

        const _fields = <BleField>[
          BleField('wifi_ssid', 'WLAN Name', '002', Icons.wifi),
          BleField('wifi_password', 'WLAN Passwort', '003', Icons.password, secret: true),
          BleField('mqtt_host', 'MQTT Server', '004', Icons.dns_outlined),
          BleField('mqtt_port', 'MQTT Port', '005', Icons.settings_ethernet),
          BleField('mqtt_user', 'MQTT Benutzer', '006', Icons.person_outline),
          BleField('mqtt_password', 'MQTT Passwort', '007', Icons.key_outlined, secret: true),
          BleField('base_topic', 'Basis Topic', '008', Icons.account_tree_outlined),
          BleField('brightness', 'Ring Helligkeit', '009', Icons.brightness_6_outlined),
          BleField('anim_single', 'Einfachklick', '010', Icons.looks_one_outlined, presets: _animationPresets),
          BleField('anim_double', 'Doppelklick', '011', Icons.looks_two_outlined, presets: _animationPresets),
          BleField('anim_triple', 'Dreifachklick', '012', Icons.looks_3_outlined, presets: _animationPresets),
          BleField('anim_long', 'Gedrueckt halten', '013', Icons.touch_app_outlined, presets: _animationPresets),
          BleField('durations', 'Klick-Zeitfenster', '014', Icons.timer_outlined),
          BleField('hid_mapping', 'Media-Key Zuordnung', '015', Icons.media_bluetooth_on_outlined),
        ];

        void main() => runApp(const PultControlApp());

        class BleField {
          const BleField(this.key, this.label, this.suffix, this.icon, {this.secret = false, this.presets});
          final String key, label, suffix;
          final IconData icon;
          final bool secret;
          final List<String>? presets;
          String get uuid => '12345678-1234-1234-1234-123456789$suffix';
        }

        class PultControlApp extends StatelessWidget {
          const PultControlApp({super.key});
          @override
          Widget build(BuildContext context) => MaterialApp(
            title: 'PULT Control', debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true, fontFamily: 'monospace', colorScheme: const ColorScheme.dark(primary: Color(0xffffbd45), secondary: Color(0xff64dbff), surface: Color(0xff10151b), error: Color(0xffff6b5e))),
            home: const ControlConsole(),
          );
        }

        class ControlConsole extends StatefulWidget {
          const ControlConsole({super.key});
          @override
          State<ControlConsole> createState() => _ControlConsoleState();
        }

        class _ControlConsoleState extends State<ControlConsole> {
          final _controllers = {for (final field in _fields) field.key: TextEditingController()};
          final _chars = <String, BluetoothCharacteristic>{};
          final _results = <ScanResult>[];
          StreamSubscription<List<ScanResult>>? _scanSubscription;
          StreamSubscription<List<int>>? _actionSubscription;
          StreamSubscription<List<int>>? _temperatureSubscription;
          StreamSubscription<List<int>>? _humiditySubscription;
          BluetoothDevice? _device;
          bool _scanning = false, _connecting = false;
          int _tab = 0;
          String _headline = 'Bereit fuer Scan';
          String _testAnimation = _animationPresets.first;
          String _lastAction = 'Warte auf Eingabe';
          String _temperature = '--';
          String _humidity = '--';

          @override
          void initState() {
            super.initState();
            _scanSubscription = FlutterBluePlus.scanResults.listen((items) {
              if (mounted) setState(() { _results..clear()..addAll(items.where((item) => item.device.platformName.isNotEmpty)); });
            });
          }

          @override
          void dispose() { _scanSubscription?.cancel(); _actionSubscription?.cancel(); _temperatureSubscription?.cancel(); _humiditySubscription?.cancel(); for (final item in _controllers.values) { item.dispose(); } super.dispose(); }

          Future<void> _scan() async {
            if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) { _notify('Bluetooth bitte einschalten.'); return; }
            setState(() { _results.clear(); _scanning = true; _headline = 'Suche nach PULT...'; });
            try { await FlutterBluePlus.startScan(withServices: [Guid(_serviceUuid)], timeout: const Duration(seconds: 8)); }
            catch (error) { _notify('Scan fehlgeschlagen: $error'); }
            if (mounted) setState(() => _scanning = false);
          }

          Future<void> _connect(BluetoothDevice device) async {
            setState(() => _connecting = true);
            try {
              await FlutterBluePlus.stopScan();
              await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
              final services = await device.discoverServices();
              final matches = services.where((item) => item.uuid.str == _serviceUuid);
              if (matches.isEmpty) throw Exception('PULT Config Service nicht gefunden');
              _chars.clear();
              for (final item in matches.first.characteristics) { _chars[item.uuid.str] = item; }
              _device = device; _headline = 'PULT Mechanical Button MK-IV';
              await _subscribeToButtonAction();
              await _subscribeToClimate();
              await _readValues();
              if (mounted) setState(() => _tab = 1);
            } catch (error) { _notify('Verbindung fehlgeschlagen: $error'); }
            if (mounted) setState(() => _connecting = false);
          }

          Future<void> _subscribeToButtonAction() async {
            final characteristic = _chars['12345678-1234-1234-1234-123456789019'];
            if (characteristic == null) return;
            await _actionSubscription?.cancel();
            _actionSubscription = characteristic.onValueReceived.listen((value) {
              if (mounted) setState(() => _lastAction = utf8.decode(value));
            });
            await characteristic.setNotifyValue(true);
            _lastAction = utf8.decode(await characteristic.read());
          }

          Future<void> _subscribeToClimate() async {
            final temperature = _chars['12345678-1234-1234-1234-123456789020'];
            final humidity = _chars['12345678-1234-1234-1234-123456789021'];
            if (temperature != null) {
              await _temperatureSubscription?.cancel();
              _temperatureSubscription = temperature.onValueReceived.listen((value) {
                if (mounted) setState(() => _temperature = utf8.decode(value));
              });
              await temperature.setNotifyValue(true);
              _temperature = utf8.decode(await temperature.read());
            }
            if (humidity != null) {
              await _humiditySubscription?.cancel();
              _humiditySubscription = humidity.onValueReceived.listen((value) {
                if (mounted) setState(() => _humidity = utf8.decode(value));
              });
              await humidity.setNotifyValue(true);
              _humidity = utf8.decode(await humidity.read());
            }
          }

          Future<void> _readValues() async {
            for (final field in _fields) {
              final characteristic = _chars[field.uuid];
              if (characteristic == null || !characteristic.properties.read) continue;
              try { _controllers[field.key]!.text = utf8.decode(await characteristic.read()); } catch (_) {}
            }
            if (mounted) setState(() {});
          }

          Future<void> _write(BleField field) async {
            final characteristic = _chars[field.uuid];
            if (characteristic == null) return;
            try { await characteristic.write(utf8.encode(_controllers[field.key]!.text)); _notify('${field.label} uebertragen'); }
            catch (error) { _notify('Schreiben fehlgeschlagen: $error'); }
          }

          Future<void> _command(String suffix, String status) async {
            final characteristic = _chars['12345678-1234-1234-1234-123456789$suffix'];
            if (characteristic == null) return;
            try { await characteristic.write(utf8.encode('1')); _notify(status); } catch (error) { _notify('Befehl fehlgeschlagen: $error'); }
          }

          Future<void> _testLedAnimation() async {
            final characteristic = _chars['12345678-1234-1234-1234-123456789018'];
            if (characteristic == null) { _notify('LED-Test wird von der Firmware noch nicht unterstuetzt.'); return; }
            try { await characteristic.write(utf8.encode(_testAnimation)); _notify('$_testAnimation wird auf dem Ring getestet'); }
            catch (error) { _notify('LED-Test fehlgeschlagen: $error'); }
          }

          void _notify(String text) { if (mounted) ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text))); }

          @override
          Widget build(BuildContext context) {
            final connected = _device != null;
            return Scaffold(backgroundColor: const Color(0xff070b10), body: SafeArea(child: Column(children: [
              _Header(connected: connected, text: _headline),
              Expanded(child: IndexedStack(index: _tab, children: [_connectionTab(connected), _configTab(connected), _systemTab(connected)])),
              NavigationBar(backgroundColor: const Color(0xff10151b), selectedIndex: _tab, onDestinationSelected: (value) => setState(() => _tab = value), destinations: const [NavigationDestination(icon: Icon(Icons.radar), label: 'Verbindung'), NavigationDestination(icon: Icon(Icons.tune), label: 'Konfiguration'), NavigationDestination(icon: Icon(Icons.memory), label: 'System')] ),
            ])));
          }

          Widget _connectionTab(bool connected) => ListView(padding: const EdgeInsets.all(20), children: [
            _Reactor(scanning: _scanning, connected: connected), const SizedBox(height: 20),
            _ActionStatus(action: _lastAction, connected: connected), const SizedBox(height: 20),
            _ClimateStatus(temperature: _temperature, humidity: _humidity, connected: connected), const SizedBox(height: 20),
            FilledButton.icon(onPressed: _scanning || _connecting ? null : _scan, icon: Icon(_scanning ? Icons.hourglass_top : Icons.radar), label: Text(_scanning ? 'SCAN AKTIV' : 'PULT SUCHEN')),
            const SizedBox(height: 22), const Text('ERKANNTE EINHEITEN'), const SizedBox(height: 8),
            if (_results.isEmpty) const _Empty('Starte einen Scan, um dein PULT zu finden.'),
            ..._results.map((item) => _DeviceCard(result: item, busy: _connecting, connect: () => _connect(item.device))),
          ]);

          Widget _configTab(bool connected) => !connected ? const _Empty('Zuerst im Tab Verbindung mit PULT verbinden.') : ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [Text('KONFIGURATION', style: Theme.of(context).textTheme.titleLarge), const Spacer(), IconButton(onPressed: _readValues, tooltip: 'Werte lesen', icon: const Icon(Icons.sync))]),
            const SizedBox(height: 8), ..._fields.map((field) => _FieldCard(field: field, controller: _controllers[field.key]!, write: () => _write(field))),
          ]);

          Widget _systemTab(bool connected) => !connected ? const _Empty('Keine aktive BLE-Verbindung.') : ListView(padding: const EdgeInsets.all(20), children: [
            const _Readout('GERAET', 'MECHANICAL BUTTON'), _Readout('BLE ID', _device!.remoteId.str), const _Readout('GATT SERVICE', '...789ABC'), const SizedBox(height: 28),
            DropdownButtonFormField<String>(initialValue: _testAnimation, decoration: const InputDecoration(labelText: 'LED-Ring Animation testen'), items: _animationPresets.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => _testAnimation = value!)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _testLedAnimation, icon: const Icon(Icons.play_arrow), label: const Text('LED-ANIMATION TESTEN')),
            const SizedBox(height: 28),
            FilledButton.icon(onPressed: () => _command('016', 'Speicherbefehl gesendet'), icon: const Icon(Icons.save_outlined), label: const Text('KONFIGURATION SPEICHERN')),
            const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _command('017', 'Neustart angefordert'), icon: const Icon(Icons.restart_alt), label: const Text('PULT NEUSTARTEN')),
          ]);
        }

        class _Header extends StatelessWidget { const _Header({required this.connected, required this.text}); final bool connected; final String text; @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x33ffbd45))), gradient: LinearGradient(colors: [Color(0xff17110b), Color(0xff070b10)])), child: Row(children: [const Icon(Icons.power_settings_new, color: Color(0xffffbd45), size: 28), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('PULT // CONTROL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)), Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xff91a6b6), fontSize: 11))])), Container(width: 11, height: 11, decoration: BoxDecoration(color: connected ? const Color(0xff64dbff) : const Color(0xffff6b5e), shape: BoxShape.circle))])); }
        class _Reactor extends StatelessWidget { const _Reactor({required this.scanning, required this.connected}); final bool scanning, connected; @override Widget build(BuildContext context) => Center(child: Container(width: 190, height: 190, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xffffbd45), width: 2), boxShadow: const [BoxShadow(color: Color(0x66ff9d00), blurRadius: 30)]), child: Container(width: 136, height: 136, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xff64dbff), width: scanning ? 5 : 2)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth_searching, color: const Color(0xff64dbff), size: 38), const SizedBox(height: 8), Text(connected ? 'ONLINE' : scanning ? 'SCANNING' : 'STANDBY', style: const TextStyle(fontWeight: FontWeight.bold))])))); }
        class _ActionStatus extends StatelessWidget { const _ActionStatus({required this.action, required this.connected}); final String action; final bool connected; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xff10151b), border: Border.all(color: const Color(0x3364dbff))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('LETZTE TASTENAKTION', style: TextStyle(color: Color(0xffffbd45), fontSize: 11)), const SizedBox(height: 6), Text(connected ? action.toUpperCase() : 'NICHT VERBUNDEN', style: const TextStyle(fontSize: 20, color: Color(0xff64dbff), fontWeight: FontWeight.bold))])); }
        class _ClimateStatus extends StatelessWidget { const _ClimateStatus({required this.temperature, required this.humidity, required this.connected}); final String temperature, humidity; final bool connected; @override Widget build(BuildContext context) => Row(children: [_ClimateValue(icon: Icons.thermostat_outlined, label: 'TEMPERATUR', value: connected && temperature != '--' ? '$temperature C' : '--'), const SizedBox(width: 10), _ClimateValue(icon: Icons.water_drop_outlined, label: 'LUFTFEUCHTE', value: connected && humidity != '--' ? '$humidity %' : '--')]); }
        class _ClimateValue extends StatelessWidget { const _ClimateValue({required this.icon, required this.label, required this.value}); final IconData icon; final String label, value; @override Widget build(BuildContext context) => Expanded(child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xff10151b), border: Border.all(color: const Color(0x3364dbff))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xffffbd45)), const SizedBox(height: 10), Text(label, style: const TextStyle(color: Color(0xff91a6b6), fontSize: 10)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: Color(0xff64dbff), fontSize: 18, fontWeight: FontWeight.bold))]))); }
        class _DeviceCard extends StatelessWidget { const _DeviceCard({required this.result, required this.busy, required this.connect}); final ScanResult result; final bool busy; final VoidCallback connect; @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 9), decoration: BoxDecoration(color: const Color(0xff10151b), border: Border.all(color: const Color(0x3364dbff))), child: ListTile(leading: const Icon(Icons.bluetooth, color: Color(0xff64dbff)), title: Text(result.device.platformName), subtitle: Text('${result.device.remoteId.str}  //  ${result.rssi} dBm'), trailing: IconButton(onPressed: busy ? null : connect, tooltip: 'Verbinden', icon: const Icon(Icons.link)))); }
        class _FieldCard extends StatelessWidget { const _FieldCard({required this.field, required this.controller, required this.write}); final BleField field; final TextEditingController controller; final VoidCallback write; @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xff10151b), border: Border.all(color: const Color(0x22ffffff))), child: Row(children: [Icon(field.icon, color: const Color(0xffffbd45)), const SizedBox(width: 12), Expanded(child: field.presets == null ? TextField(controller: controller, obscureText: field.secret, decoration: InputDecoration(labelText: field.label, border: InputBorder.none, isDense: true)) : DropdownButtonFormField<String>(initialValue: field.presets!.contains(controller.text) ? controller.text : null, decoration: InputDecoration(labelText: field.label, border: InputBorder.none, isDense: true), items: field.presets!.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) { controller.text = value!; write(); })), if (field.presets == null) IconButton(onPressed: write, tooltip: '${field.label} senden', icon: const Icon(Icons.upload_outlined, color: Color(0xff64dbff)))])); }
        class _Empty extends StatelessWidget { const _Empty(this.text); final String text; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 55), child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xff91a6b6))))); }
        class _Readout extends StatelessWidget { const _Readout(this.label, this.value); final String label, value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xffffbd45), fontSize: 11)), const SizedBox(height: 4), Text(value)])); }

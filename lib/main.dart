import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CueSyncApp());
}

class CueSyncApp extends StatelessWidget {
  const CueSyncApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CueSync Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
          ),
        ),
      ),
      home: const RoleSelectionScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// 1. HALAMAN PILIH PERAN
// ==========================================
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1E1E1E), Color(0xFF000000)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('CUESYNC PRO', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
                  const SizedBox(height: 10),
                  const Text('Dual Mode: Live Cue & Teleprompter', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 50),
                  _buildRoleCard(context, 'MASTER FOH', 'Mac / Windows System', Icons.laptop_mac, Colors.blueAccent, const MasterScreen()),
                  const SizedBox(height: 24),
                  _buildRoleCard(context, 'CLIENT MC', 'Android Mobile / Tablet', Icons.smartphone, Colors.orangeAccent, const ClientScreen()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, String title, String sub, IconData icon, Color color, Widget screen) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.4), width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 4),
                  Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. HALAMAN MASTER (MAC / WINDOWS)
// ==========================================
class MasterScreen extends StatefulWidget {
  const MasterScreen({super.key});
  @override
  State<MasterScreen> createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  HttpServer? _server;
  final List<dynamic> _clients = [];
  String _localIp = 'Mencari IP...';
  String _currentStatus = "idle";
  
  // Dua controller terpisah untuk mode yang berbeda
  final TextEditingController _cueController = TextEditingController(text: "STANDBY MC");
  final TextEditingController _scriptController = TextEditingController(text: "Ini Halaman 1\n\n===\n\nIni Halaman 2\nMC bisa geser (swipe) layar ini.");
  final TextEditingController _timerController = TextEditingController(text: "5");

  Timer? _countdownTimer;
  int _timeInSeconds = 0;
  bool _isScriptMode = false; // Toggle Mode

  @override
  void initState() {
    super.initState();
    _startServer();
    _getLocalIp();
  }

  Future<void> _getLocalIp() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          setState(() => _localIp = addr.address);
          return;
        }
      }
    }
  }

  void _startServer() async {
    var handler = webSocketHandler((webSocket) {
      _clients.add(webSocket);
      _sendData("update");
      webSocket.stream.listen((message) {}, onDone: () => _clients.remove(webSocket));
    });
    _server = await shelf_io.serve(handler, '0.0.0.0', 8080);
  }

  void _startTimer() {
    int minutes = int.tryParse(_timerController.text) ?? 0;
    if (minutes > 0) {
      _countdownTimer?.cancel();
      _timeInSeconds = minutes * 60;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_timeInSeconds > 0) {
          setState(() => _timeInSeconds--);
          _sendData("update");
        } else {
          timer.cancel();
        }
      });
    }
  }

  void _stopTimer() {
    _countdownTimer?.cancel();
    setState(() => _timeInSeconds = 0);
    _sendData("update");
  }

  String get _formattedTime {
    if (_timeInSeconds <= 0) return "";
    int m = _timeInSeconds ~/ 60;
    int s = _timeInSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _changeStatus(String status) {
    _currentStatus = status;
    _sendData("update");
  }

  // Mengirim semua data sekaligus ke HP MC
  void _sendData(String command) {
    final message = jsonEncode({
      "mode": _isScriptMode ? "script" : "cue",
      "status": _currentStatus,
      "text": _cueController.text,
      "script": _scriptController.text,
      "time": _formattedTime,
      "timeRaw": _timeInSeconds,
      "command": command 
    });
    for (var client in _clients) {
      client.sink.add(message);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('FOH Master - IP: $_localIp', style: const TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // SWITCH MODE & INPUT TEKS
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(15)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_isScriptMode ? "📝 MODE SCRIPT (MC Baca Sendiri)" : "🪧 MODE CUE (Layar Penuh FOH)", 
                             style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        Switch(
                          value: _isScriptMode, 
                          activeColor: Colors.blueAccent,
                          onChanged: (val) {
                            setState(() => _isScriptMode = val);
                            _sendData("update");
                          }
                        )
                      ],
                    ),
                    const Divider(color: Colors.grey),
                    if (_isScriptMode)
                      const Text("Ketik '===' (3 sama dengan) untuk memisahkan halaman Script.", style: TextStyle(color: Colors.orangeAccent)),
                    const SizedBox(height: 10),
                    
                    Expanded(
                      child: TextField(
                        controller: _isScriptMode ? _scriptController : _cueController,
                        maxLines: null,
                        expands: true,
                        onChanged: (_) => _sendData("update"), // Auto update saat diketik
                        style: const TextStyle(fontSize: 24, color: Colors.white),
                        decoration: const InputDecoration(border: InputBorder.none),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // KONTROL BAWAH (Selalu Tampil)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _timerController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 22),
                    decoration: InputDecoration(labelText: 'Menit', filled: true, fillColor: const Color(0xFF2A2A2A), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, color: Colors.white), label: const Text('START', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 22)),
                    onPressed: _startTimer,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop, color: Colors.white), label: const Text('STOP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 22)),
                    onPressed: _stopTimer,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 4,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.vibration, color: Colors.white), label: const Text('GETARKAN HP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, padding: const EdgeInsets.symmetric(vertical: 22)),
                    onPressed: () => _sendData("vibrate"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildStatusButton("STANDBY", "standby", Colors.yellow[700]!, Colors.black),
                const SizedBox(width: 20),
                _buildStatusButton("GO", "go", Colors.greenAccent[700]!, Colors.black),
                const SizedBox(width: 20),
                _buildStatusButton("IDLE / BLACK", "idle", const Color(0xFF333333), Colors.white),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton(String title, String status, Color bgColor, Color textColor) {
    bool isActive = _currentStatus == status;
    return Expanded(
      child: InkWell(
        onTap: () => _changeStatus(status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 100,
          decoration: BoxDecoration(
            color: bgColor.withOpacity(isActive ? 1.0 : 0.4),
            borderRadius: BorderRadius.circular(15),
            border: isActive ? Border.all(color: Colors.white, width: 3) : null,
            boxShadow: isActive ? [BoxShadow(color: bgColor.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)] : [],
          ),
          child: Center(child: Text(title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor))),
        ),
      ),
    );
  }
}

// ==========================================
// 3. HALAMAN CLIENT (ANDROID MC & TABLET)
// ==========================================
class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});
  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  WebSocketChannel? _channel;
  
  String _mode = "cue"; 
  String _status = "idle"; 
  String _text = "Menunggu FOH...";
  String _script = "";
  String _timeText = "";
  int _timeRaw = 0;
  bool _isConnected = false;
  
  final TextEditingController _ipController = TextEditingController();
  final PageController _pageController = PageController(); // Controller Halaman Script

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    _loadLastIp();
  }

  Future<void> _loadLastIp() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastIp = prefs.getString('last_ip');
    if (lastIp != null && lastIp.isNotEmpty) {
      _ipController.text = lastIp;
      _connect(); 
    }
  }

  // FUNGSI GETAR PAKSA (Loop Dart Haptic) 100% Berhasil di Semua Android
  void _triggerVibration() async {
    for (int i = 0; i < 7; i++) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  void _connect() async {
    if (_ipController.text.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', _ipController.text);

    try {
      final wsUrl = Uri.parse('ws://${_ipController.text}:8080');
      _channel = WebSocketChannel.connect(wsUrl);
      
      setState(() => _isConnected = true);

      _channel!.stream.listen((message) {
        final data = jsonDecode(message);
        
        if (data['command'] == 'vibrate') {
          _triggerVibration(); // Panggil fungsi getar denyut
        }

        setState(() {
          _mode = data['mode'] ?? _mode;
          _status = data['status'] ?? _status;
          _text = data['text'] ?? _text;
          _script = data['script'] ?? _script;
          _timeText = data['time'] ?? _timeText;
          _timeRaw = data['timeRaw'] ?? _timeRaw;
        });
      }, 
      onDone: _handleDisconnect, 
      onError: (_) => _handleDisconnect());
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _text = "Mencoba Reconnect...";
      _status = "idle";
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isConnected) _connect();
    });
  }

  List<Color> _getBgColors() {
    if (_status == "standby") return [Colors.orange[800]!, Colors.yellow[700]!];
    if (_status == "go") return [Colors.green[800]!, Colors.greenAccent[700]!];
    return [const Color(0xFF1A1A1A), Colors.black];
  }

  Color _getTextColor() => _status == "idle" ? Colors.white : Colors.black;
  Color _getTimerColor() => (_timeRaw > 0 && _timeRaw <= 60) ? Colors.redAccent : _getTextColor();

  @override
  void dispose() {
    WakelockPlus.disable(); 
    _channel?.sink.close();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Koneksi FOH'), backgroundColor: const Color(0xFF1E1E1E)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, size: 70, color: Colors.orangeAccent),
                const SizedBox(height: 12),
                TextField(
                  controller: _ipController,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(labelText: 'IP FOH Address', filled: true, fillColor: const Color(0xFF2A2A2A), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: Colors.blueAccent),
                  onPressed: _connect, child: const Text('SAMBUNGKAN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))
                )
              ],
            ),
          ),
        ),
      );
    }

    // TAMPILAN MODE SCRIPT (MC)
    if (_mode == "script") {
      List<String> scriptPages = _script.split('===');
      if (scriptPages.isEmpty) scriptPages = ["..."];

      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Area Baca Script yang bisa di-Swipe
              PageView.builder(
                controller: _pageController,
                itemCount: scriptPages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 80.0, left: 20, right: 20, bottom: 20),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scriptPages[index].trim(),
                            style: const TextStyle(fontSize: 40, color: Colors.white, height: 1.4),
                          ),
                          const SizedBox(height: 50),
                          Center(child: Text("Halaman ${index + 1} dari ${scriptPages.length}", style: const TextStyle(color: Colors.grey, fontSize: 16))),
                        ],
                      ),
                    ),
                  );
                },
              ),
              
              // SPANDUK CUE MELAYANG (Muncul jika FOH kirim Go/Standby)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                top: _status == "idle" ? -150 : 10,
                left: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _getBgColors()),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, spreadRadius: 2)],
                    border: Border.all(color: Colors.white, width: 2)
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(_text, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _getTextColor())),
                      ),
                      if (_timeText.isNotEmpty)
                        Text(_timeText, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: _getTimerColor(), fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // TAMPILAN MODE CUE LAMA (Layar Penuh)
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(gradient: LinearGradient(colors: _getBgColors(), begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  Text(
                    _text, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 55, fontWeight: FontWeight.w900, color: _getTextColor(), height: 1.25),
                  ),
                  if (_timeText.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      _timeText, textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 90, fontWeight: FontWeight.w900, color: _getTimerColor(), fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

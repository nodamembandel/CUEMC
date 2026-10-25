import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart'; // Package baru untuk paksa getar

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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 5,
          ),
        ),
      ),
      home: const RoleSelectionScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// 1. HALAMAN PILIH PERAN (Anti Terpotong)
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
              padding: const EdgeInsets.all(20.0),
              // Wrap akan otomatis membuat kotak turun ke bawah jika layar HP sempit
              child: Wrap(
                spacing: 20,
                runSpacing: 20,
                alignment: WrapAlignment.center,
                children: [
                  _buildRoleCard(context, 'MASTER FOH\n(Mac / Win)', Icons.laptop_mac, Colors.blueAccent, const MasterScreen()),
                  _buildRoleCard(context, 'CLIENT MC\n(Android)', Icons.smartphone, Colors.orangeAccent, const ClientScreen()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, String title, IconData icon, Color color, Widget screen) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 200, // Ukuran kotak dikecilkan sedikit agar pas di HP
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 70, color: color),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
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
  
  final TextEditingController _cueController = TextEditingController(text: "STANDBY MC");
  final TextEditingController _timerController = TextEditingController(text: "5");

  Timer? _countdownTimer;
  int _timeInSeconds = 0;

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

  void _sendData(String command) {
    final message = jsonEncode({
      "status": _currentStatus,
      "text": _cueController.text,
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
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: TextField(
                  controller: _cueController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontSize: 26, color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Ketik Script / Instruksi MC',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(20),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _timerController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 22),
                    decoration: InputDecoration(
                      labelText: 'Menit',
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: const Text('START TIMER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 22)),
                    onPressed: _startTimer,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop, color: Colors.white),
                    label: const Text('STOP TIMER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 22)),
                    onPressed: _stopTimer,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 4,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.vibration, color: Colors.white),
                    label: const Text('GETARKAN HP MC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, padding: const EdgeInsets.symmetric(vertical: 22)),
                    onPressed: () => _sendData("vibrate"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            
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
          height: 120,
          decoration: BoxDecoration(
            color: bgColor.withOpacity(isActive ? 1.0 : 0.4),
            borderRadius: BorderRadius.circular(15),
            border: isActive ? Border.all(color: Colors.white, width: 3) : null,
            boxShadow: isActive ? [BoxShadow(color: bgColor.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)] : [],
          ),
          child: Center(
            child: Text(title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor)),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. HALAMAN CLIENT (ANDROID MC) - Anti Terpotong
// ==========================================
class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});
  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  WebSocketChannel? _channel;
  String _status = "idle"; 
  String _text = "Menunggu FOH...";
  String _timeText = "";
  int _timeRaw = 0;
  bool _isConnected = false;
  
  final TextEditingController _ipController = TextEditingController();

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

  void _connect() async {
    if (_ipController.text.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', _ipController.text);

    try {
      final wsUrl = Uri.parse('ws://${_ipController.text}:8080');
      _channel = WebSocketChannel.connect(wsUrl);
      
      setState(() => _isConnected = true);

      _channel!.stream.listen((message) async {
        final data = jsonDecode(message);
        
        // Eksekusi Paksa Mesin Getar Hardware (Lebih kuat)
        if (data['command'] == 'vibrate') {
          bool? hasVibrator = await Vibration.hasVibrator();
          if (hasVibrator == true) {
            // Bergetar selama 1 detik (1000 milidetik)
            Vibration.vibrate(duration: 1000); 
          }
        }

        setState(() {
          _status = data['status'] ?? _status;
          _text = data['text'] ?? _text;
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
    if (_status == "standby") return [Colors.orange, Colors.yellow[700]!];
    if (_status == "go") return [Colors.green[600]!, Colors.greenAccent[700]!];
    return [const Color(0xFF1E1E1E), Colors.black];
  }

  Color _getTextColor() => _status == "idle" ? Colors.white : Colors.black;
  Color _getTimerColor() => (_timeRaw > 0 && _timeRaw <= 60) ? Colors.redAccent : _getTextColor();

  @override
  void dispose() {
    WakelockPlus.disable(); 
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Menyambungkan FOH...'), backgroundColor: const Color(0xFF1E1E1E)),
        body: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_tethering_off, size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              TextField(
                controller: _ipController,
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  labelText: 'IP FOH',
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                onPressed: _connect, 
                child: const Text('CONNECT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(gradient: LinearGradient(colors: _getBgColors(), begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Layout Fleksibel Anti-Terpotong
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        _text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 45, // Ukuran sedikit disesuaikan untuk layar HP
                          fontWeight: FontWeight.w900, 
                          color: _getTextColor(),
                          height: 1.2,
                          shadows: _status == "idle" ? [] : [
                            Shadow(color: Colors.white.withOpacity(0.5), blurRadius: 20)
                          ]
                        ),
                      ),
                    ),
                  ),
                ),
                
                if (_timeText.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    _timeText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 80, 
                      fontWeight: FontWeight.w900, 
                      color: _getTimerColor(),
                      fontFeatures: const [FontFeature.tabularFigures()]
                    ),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}

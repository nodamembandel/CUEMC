import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Untuk fitur Getar (Haptic)
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // Untuk fitur layar nyala terus

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CueSyncApp());
}

class CueSyncApp extends StatelessWidget {
  const CueSyncApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CueSync',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
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
      appBar: AppBar(title: const Text('CueSync - Select Role'), backgroundColor: Colors.grey[900]),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(40), backgroundColor: Colors.blueAccent),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterScreen())),
              child: const Text('MASTER FOH\n(Mac / Windows)', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: Colors.white)),
            ),
            const SizedBox(width: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(40), backgroundColor: Colors.orangeAccent),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientScreen())),
              child: const Text('CLIENT MC\n(Android)', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: Colors.white)),
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
  
  // Ubah controller agar bisa menerima teks panjang/banyak baris
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
      _sendCurrentState(); 
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
          _sendCurrentState(); 
        } else {
          timer.cancel();
        }
      });
    }
  }

  void _stopTimer() {
    _countdownTimer?.cancel();
    setState(() => _timeInSeconds = 0);
    _sendCurrentState();
  }

  String get _formattedTime {
    if (_timeInSeconds <= 0) return "";
    int m = _timeInSeconds ~/ 60;
    int s = _timeInSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _changeStatus(String status) {
    _currentStatus = status;
    _sendCurrentState();
  }

  void _sendCurrentState() {
    final message = jsonEncode({
      "status": _currentStatus,
      "text": _cueController.text,
      "time": _formattedTime,
      "timeRaw": _timeInSeconds 
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
      appBar: AppBar(title: Text('FOH Master - IP: $_localIp'), backgroundColor: Colors.grey[900]),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Text Field dibuat mendukung teks panjang / script MC
            Expanded(
              child: TextField(
                controller: _cueController,
                maxLines: null, // Bebas berapa baris pun
                expands: true,
                style: const TextStyle(fontSize: 24),
                decoration: const InputDecoration(labelText: 'Ketik Script / Instruksi MC di sini', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _timerController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 24),
                    decoration: const InputDecoration(labelText: 'Durasi (Menit)', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _startTimer,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20), backgroundColor: Colors.blueAccent),
                  child: const Text('Start Timer', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _stopTimer,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20), backgroundColor: Colors.redAccent),
                  child: const Text('Stop Timer', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _changeStatus("standby"),
                    child: Container(height: 120, color: Colors.yellow[700], child: const Center(child: Text("STANDBY", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.black)))),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InkWell(
                    onTap: () => _changeStatus("go"),
                    child: Container(height: 120, color: Colors.greenAccent[700], child: const Center(child: Text("GO", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.black)))),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InkWell(
                    onTap: () => _changeStatus("idle"),
                    child: Container(height: 120, color: Colors.grey[800], child: const Center(child: Text("IDLE / BLACK", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)))),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. HALAMAN CLIENT (ANDROID MC)
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
  
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Nyalakan penahan layar (Background Running)
  }

  void _connect() {
    if (_ipController.text.isEmpty) return;
    final wsUrl = Uri.parse('ws://${_ipController.text}:8080');
    _channel = WebSocketChannel.connect(wsUrl);
    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      
      // Logika Getar: Jika Mac menekan Standby atau Go, HP bergetar
      if (data['status'] != _status && (data['status'] == 'standby' || data['status'] == 'go')) {
        HapticFeedback.vibrate();
      }

      setState(() {
        _status = data['status'];
        _text = data['text'];
        _timeText = data['time'] ?? "";
        _timeRaw = data['timeRaw'] ?? 0;
      });
    });
  }

  Color _getBgColor() {
    if (_status == "standby") return Colors.yellow[700]!;
    if (_status == "go") return Colors.greenAccent[700]!;
    return Colors.black;
  }

  Color _getTextColor() => _status == "idle" ? Colors.white : Colors.black;
  
  Color _getTimerColor() {
    if (_timeRaw > 0 && _timeRaw <= 60) return Colors.redAccent; 
    return _getTextColor();
  }

  @override
  void dispose() {
    WakelockPlus.disable(); // Matikan penahan layar saat aplikasi ditutup
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_channel == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Konek ke FOH')),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(labelText: 'Masukkan IP FOH (Misal: 192.168.1.100)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                onPressed: _connect, 
                child: const Text('CONNECT', style: TextStyle(fontSize: 20))
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _getBgColor(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Script Teks (Bisa di-scroll jika panjang)
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _text,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: _getTextColor()),
                  ),
                ),
              ),
              
              // Timer di bagian bawah layar
              if (_timeText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _timeText,
                  style: TextStyle(
                    fontSize: 70, 
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
    );
  }
}

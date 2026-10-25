import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const CueSyncApp());

class CueSyncApp extends StatelessWidget {
  const CueSyncApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CueSync',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const RoleSelectionScreen(),
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
  List<dynamic> _clients = [];
  String _localIp = 'Mencari IP...';
  final TextEditingController _cueController = TextEditingController(text: "STANDBY MC");

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
      webSocket.sink.add(jsonEncode({"status": "idle", "text": "CONNECTED TO FOH"}));
      webSocket.stream.listen((message) {}, onDone: () => _clients.remove(webSocket));
    });
    _server = await shelf_io.serve(handler, '0.0.0.0', 8080);
  }

  void _sendCue(String status) {
    final message = jsonEncode({"status": status, "text": _cueController.text});
    for (var client in _clients) {
      client.sink.add(message);
    }
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('FOH Master - IP Anda: $_localIp:8080'), backgroundColor: Colors.grey[900]),
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          children: [
            TextField(
              controller: _cueController,
              style: const TextStyle(fontSize: 30),
              decoration: const InputDecoration(labelText: 'Teks Instruksi ke MC', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 50),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _sendCue("standby"),
                    child: Container(height: 150, color: Colors.yellow[700], center: const Center(child: Text("STANDBY", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black)))),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InkWell(
                    onTap: () => _sendCue("go"),
                    child: Container(height: 150, color: Colors.greenAccent[700], child: const Center(child: Text("GO", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black)))),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InkWell(
                    onTap: () => _sendCue("idle"),
                    child: Container(height: 150, color: Colors.grey[800], child: const Center(child: Text("IDLE / BLACK", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)))),
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
  String _status = "idle"; // idle, standby, go
  String _text = "Menunggu FOH...";
  final TextEditingController _ipController = TextEditingController();

  void _connect() {
    if (_ipController.text.isEmpty) return;
    final wsUrl = Uri.parse('ws://${_ipController.text}:8080');
    _channel = WebSocketChannel.connect(wsUrl);
    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      setState(() {
        _status = data['status'];
        _text = data['text'];
      });
    });
  }

  Color _getBgColor() {
    if (_status == "standby") return Colors.yellow[700]!;
    if (_status == "go") return Colors.greenAccent[700]!;
    return Colors.black;
  }

  Color _getTextColor() => _status == "idle" ? Colors.white : Colors.black;

  @override
  void dispose() {
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
                decoration: const InputDecoration(labelText: 'Masukkan IP Mac/Win (Misal: 192.168.1.100)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _connect, child: const Text('CONNECT'))
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _getBgColor(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            _text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: _getTextColor()),
          ),
        ),
      ),
    );
  }
}

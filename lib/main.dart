import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const RetroPhoneApp());
}

class RetroPhoneApp extends StatelessWidget {
  const RetroPhoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RetroPhone',
      theme: ThemeData.dark(),
      home: const NicknameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkNickname();
  }

  Future<void> _checkNickname() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNick = prefs.getString('nickname');
    if (savedNick != null && savedNick.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(nickname: savedNick)),
      );
    }
  }

  void _saveNickname() async {
    final nick = _controller.text.trim();
    if (nick.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', nick);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(nickname: nick)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RetroPhone')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Введите ваше имя:'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Alex, Delie, Langa...',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveNickname,
              child: const Text('Продолжить'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String nickname;
  const ChatScreen({super.key, required this.nickname});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Socket? _socket;
  String _status = "Подключение...";
  List<String> _messages = [];
  List<String> _online = [];
  String _currentTarget = "Alex";
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      _socket = await Socket.connect("5.78.212.117", 5000);
      setState(() => _status = "Подключено ✓");
      _socket!.write("${widget.nickname}\n");
      _socket!.listen((data) {
        String msg = utf8.decode(data).trim();
        setState(() {
          if (msg.startsWith("*ONLINE*")) {
            _online = msg.substring(8).split(",");
            if (!_online.contains(_currentTarget) && _online.isNotEmpty) {
              _currentTarget = _online[0];
            }
          } else {
            _messages.add(msg);
            _scrollToBottom();
          }
        });
      }, onError: (e) {
        setState(() => _status = "Ошибка: $e");
      });
    } catch (e) {
      setState(() => _status = "Не удалось подключиться: $e");
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || _socket == null) return;
    String text = _messageController.text.trim();
    _socket!.write("$_currentTarget|$text\n");
    setState(() {
      _messages.add("[Вы] $text");
      _messageController.clear();
    });
    _scrollToBottom();
  }

  Future<void> _sendFile(File file) async {
    if (_socket == null) return;
    String fileName = file.path.split('/').last;
    String? url = await _uploadFile(file);
    if (url != null) {
      _socket!.write("$_currentTarget|FILE|$fileName|$url\n");
      setState(() {
        _messages.add("[Вы] Отправлен файл: $fileName");
      });
      _scrollToBottom();
    } else {
      setState(() {
        _messages.add("[Ошибка] Не удалось загрузить файл");
      });
    }
  }

  Future<String?> _uploadFile(File file) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('http://5.78.212.117:8000/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      if (response.statusCode == 200) {
        var json = await response.stream.bytesToString();
        var data = jsonDecode(json);
        return data['url'];
      }
    } catch (e) {
      print("Upload error: $e");
    }
    return null;
  }

  void _pickImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      _sendFile(File(picked.path));
    }
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      _sendFile(File(result.files.single.path!));
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("RetroPhone - ${widget.nickname}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _pickImage,
            tooltip: 'Отправить изображение',
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _pickFile,
            tooltip: 'Отправить файл',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text("Онлайн: ", style: TextStyle(fontSize: 14)),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _online.map((user) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () => setState(() => _currentTarget = user),
                            child: Chip(
                              label: Text(user),
                              backgroundColor: user == _currentTarget
                                  ? Colors.green.shade700
                                  : Colors.grey.shade700,
                              labelStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.grey[800],
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              "Отправка: $_currentTarget",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_messages[i]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: "Сообщение...",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }
}
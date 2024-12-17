import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
//import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/io.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spark LLM Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    print('Handling submitted text: $text');

    _textController.clear();
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
      ));
      _isLoading = true;
    });

    try {
      final response = await _sendMessage(text);
      print('Received response: $response');
      setState(() {
        _messages.add(ChatMessage(
          text: response,
          isUser: false,
        ));
      });
    } catch (e) {
      print('Error in _handleSubmitted: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String> _sendMessage(String message) async {
    // Using v4.0 endpoint for Ultra version
    const gptUrl = 'wss://spark-api.xf-yun.com/v4.0/chat';
    //const appId = '1914a613';
    const appId = 'b4a5aacb';
    //const apiKey = '5f783f881c4020275442be19e5b7e68f';
    const apiKey = '6e77321814af29ee21a6ad8962f5ff10';
    //const apiSecret = 'ZTlhNzUzZjU3N2I4MWQzNWFhNjU5OGZh';
    const apiSecret = 'ZWNlYjMzMGQ5ZWIwYmRiMTBmZDQ1ODNh';

    final wsParam = WsParam(
      appId: appId,
      apiKey: apiKey,
      apiSecret: apiSecret,
      gptUrl: gptUrl,
    );

    final wsUrl = wsParam.createUrl();
    print('Connecting to WebSocket: $wsUrl');

    try {
      //final channel = HtmlWebSocketChannel.connect(wsUrl);
      final channel = IOWebSocketChannel.connect(wsUrl);
      final completer = Completer<String>();
      var fullResponse = '';

      final data = {
        'header': {
          'app_id': appId,
          'uid': '1234',
        },
        'parameter': {
          'chat': {
            'domain': '4.0Ultra', // Changed to Ultra domain
            'temperature': 0.5,
            'max_tokens': 2048, // Increased token limit
            'auditing': 'default',
          }
        },
        'payload': {
          'message': {
            'text': [
              {'role': 'user', 'content': message}
            ]
          }
        }
      };

      print('Sending message: ${jsonEncode(data)}');
      channel.sink.add(jsonEncode(data));

      channel.stream.listen(
        (response) {
          print('Received WebSocket response: $response');
          try {
            final jsonResponse = jsonDecode(response);

            if (jsonResponse['header']['code'] != 0) {
              completer.completeError(
                  'API Error: ${jsonResponse['header']['message']}');
              channel.sink.close();
              return;
            }

            final choices = jsonResponse['payload']['choices'];
            final status = choices['status'];
            final content = choices['text'][0]['content'];

            fullResponse += content;
            print('Current response: $content'); // Added for debugging

            if (status == 2) {
              completer.complete(fullResponse);
              channel.sink.close();
            }
          } catch (e) {
            print('Error parsing response: $e');
            completer.completeError('Error parsing response: $e');
            channel.sink.close();
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          completer.completeError('WebSocket error: $error');
          channel.sink.close();
        },
        onDone: () {
          if (!completer.isCompleted) {
            if (fullResponse.isNotEmpty) {
              completer.complete(fullResponse);
            } else {
              completer.completeError('Connection closed without response');
            }
          }
          channel.sink.close();
        },
      );

      return await completer.future;
    } catch (e) {
      print('Exception in WebSocket connection: $e');
      throw Exception('Error sending message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spark LLM Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, index) =>
                  _messages[_messages.length - 1 - index],
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
            ),
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Send a message',
              ),
              onSubmitted: _isLoading ? null : _handleSubmitted,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _isLoading
                ? null
                : () => _handleSubmitted(_textController.text),
          ),
        ],
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  const ChatMessage({
    super.key,
    required this.text,
    required this.isUser,
  });

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              child: Text(isUser ? 'U' : 'A'),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? 'User' : 'Assistant',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  child: Text(text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WsParam {
  final String appId;
  final String apiKey;
  final String apiSecret;
  final String gptUrl;
  final Uri parsedUrl;

  WsParam({
    required this.appId,
    required this.apiKey,
    required this.apiSecret,
    required this.gptUrl,
  }) : parsedUrl = Uri.parse(gptUrl);

  String createUrl() {
    final now = DateTime.now().toUtc();
    final date = '${DateFormat('EEE, dd MMM yyyy HH:mm:ss').format(now)} GMT';

    final signatureOrigin = 'host: ${parsedUrl.host}\n'
        'date: $date\n'
        'GET ${parsedUrl.path} HTTP/1.1';

    final hmacKey = utf8.encode(apiSecret);
    final hmacData = utf8.encode(signatureOrigin);
    final hmac = Hmac(sha256, hmacKey);
    final digest = hmac.convert(hmacData);
    final signatureShaBase64 = base64.encode(digest.bytes);

    final authorizationOrigin = 'api_key="$apiKey", algorithm="hmac-sha256", '
        'headers="host date request-line", '
        'signature="$signatureShaBase64"';
    final authorization = base64.encode(utf8.encode(authorizationOrigin));

    final params = {
      'authorization': authorization,
      'date': date,
      'host': parsedUrl.host
    };

    return '${parsedUrl.scheme}://${parsedUrl.host}${parsedUrl.path}?${_encodeParams(params)}';
  }

  String _encodeParams(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}

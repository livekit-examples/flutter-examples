import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'utils.dart';

Future<ByteData> getFileData(String path) async {
  return await rootBundle.load(path);
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  List<String> _logs = [];
  void putLog(String log) {
    setState(() {
      _logs.add(log);
    });
  }

  Future<Room> connectParticipant(String identity, String roomName) async {
    final room = Room();
    var info = await fetchConnectionDetails(identity, roomName);
    final listener = room.createListener();

    listener.on<RoomDisconnectedEvent>((event) {
      putLog('$identity Disconnected from room');
    });

    await room.connect(
      info.serverUrl,
      info.participantToken,
      connectOptions: ConnectOptions(autoSubscribe: true),
    );

    putLog('$identity connected.');

    return room;
  }

  Room? sender, receiver;

  Uint8List? _image;

  void _connect() async {
    var roomName = 'ds-test-room';
    var futures = await Future.wait([
      connectParticipant('caller', roomName),
      connectParticipant('called', roomName),
    ]);

    sender = futures[0];
    receiver = futures[1];

    var tempDirectory = await getTemporaryDirectory();
    print('${tempDirectory.path}');

    receiver?.registerTextStreamHandler('chat', (
      TextStreamReader reader,
      String id,
    ) async {
      reader.onProgress = (p) {
        putLog('process for chat receiver $p');
      };
      var text = await reader.readAll();
      putLog('received text: $text');
    });

    receiver?.registerByteStreamHandler('files', (
      ByteStreamReader reader,
      String id,
    ) async {
      putLog('received file ${reader.info!.name}, size: ${reader.info!.size}');
      reader.onProgress = (p) {
        //putLog('process for files receiver $p');
        setState(() {
          controller.value = p!;
        });
      };

      var writeFile = File('${tempDirectory.path}/copy-lk.png');
      var content = await reader.readAll();
      var data = content.expand((e) => e).toList();
      setState(() {
        _image = Uint8List.fromList(data);
      });
      writeFile.writeAsBytesSync(data);
    });

    sender?.localParticipant?.sendText(
      'hello',
      options: SendTextOptions(
        topic: 'chat',
        destinationIdentities: [receiver!.localParticipant!.identity],
      ),
    );

    var tmpFile = File('${tempDirectory.path}/lk.png');

    tmpFile.writeAsBytesSync(
      (await getFileData('assets/lk.png')).buffer.asUint8List(),
    );

    await sender?.localParticipant?.sendFile(
      tmpFile,
      options: SendFileOptions(topic: 'files'),
    );

    tmpFile.delete();
  }

  late AnimationController controller;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,

        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Received file:'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: controller.value),
            ),
            if (_image != null)
              SizedBox(width: 240, height: 180, child: Image.memory(_image!)),
            const Text('Data stream examples:'),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text('RPC Demo:'),
                    ..._logs.map((log) => Text(log)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _connect,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

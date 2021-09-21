import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

final bigJsonUri = Uri.parse('https://jsonplaceholder.typicode.com/photos');

void main() {
  runApp(const MyApp());
}

// Isolate in charge of Http requests
Future<void> httpIsolateEntryPoint(SendPort mainPort) async {
  final ReceivePort isolatePort = ReceivePort();
  mainPort.send(isolatePort.sendPort);

  isolatePort.listen((dynamic data) async {
    if (data == "Go !") {
      http.get(bigJsonUri).then((response) {
        String body = response.body;
        mainPort.send(body);
      });
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter issue 89786',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showProgressIndicator = false;
  int _startTime = 0;
  int _endTime = 0;
  List<int> _durationsWith = [];
  List<int> _durationsWithout = [];
  List<int> _durationsIsolated = [];

  int get _requestDuration => _endTime - _startTime;

  Future<void> _cooldown() async =>
      await Future.delayed(const Duration(milliseconds: 200));

  Future<void> _run() async {
    _clearResults();

    // Warm up request (first request will initiate a socket)
    await _getBigJson(false);

    for (var i = 0; i < 10; i++) {
      await _getBigJson(false);
      _durationsWithout.add(_requestDuration);
      await _cooldown();

      await _getBigJson(true);
      _durationsWith.add(_requestDuration);
      await _cooldown();

      await _getBigJsonIsolated();
      _durationsIsolated.add(_requestDuration);
      await _cooldown();
    }
  }

  void _clearResults() {
    setState(() {
      _durationsWith = [];
      _durationsWithout = [];
      _durationsIsolated = [];
    });
  }

  Future<void> _getBigJson(bool showProgress) async {
    _onRequestStart(showProgress);
    await http.get(bigJsonUri);
    _onRequestEnd();
  }

  void _onRequestStart(bool showProgress) {
    setState(() {
      _showProgressIndicator = showProgress;
      _startTime = DateTime.now().millisecondsSinceEpoch;
    });
  }

  void _onRequestEnd() {
    setState(() {
      _showProgressIndicator = false;
      _endTime = DateTime.now().millisecondsSinceEpoch;
    });
  }

  Future<void> _getBigJsonIsolated() async {
    _onRequestStart(true);
    var completer = Completer<void>();

    final ReceivePort receivePort = ReceivePort();
    final Isolate httpIsolate = await Isolate.spawn(
      httpIsolateEntryPoint,
      receivePort.sendPort,
      debugName: 'httpIsolated',
    );
    SendPort httpIsolatePort;
    receivePort.listen((dynamic data) async {
      if (data is SendPort) {
        httpIsolatePort = data;
        httpIsolatePort.send('Go !');
      }
      if (data is String) {
        httpIsolate.kill();
        completer.complete();
        _onRequestEnd();
      }
    });

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flutter issue 47246"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 1),
            ElevatedButton(
              onPressed: _run,
              child: const Text('Run'),
            ),
            const Spacer(flex: 1),
            SizedBox(
              width: 60,
              height: 60,
              child: _showProgressIndicator
                  ? const CircularProgressIndicator()
                  : null,
            ),
            const Spacer(flex: 1),
            Expanded(
              flex: 10,
              child: Row(
                children: [
                  Expanded(
                    child: _ResultsPanel(
                      title: 'Without\nindicator',
                      durations: _durationsWithout,
                    ),
                  ),
                  Expanded(
                    child: _ResultsPanel(
                      title: 'With\nindicator',
                      durations: _durationsWith,
                    ),
                  ),
                  Expanded(
                    child: _ResultsPanel(
                      title: 'Run in\nisolate',
                      durations: _durationsIsolated,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const rowHeight = 30.0;

class _ResultsPanel extends StatelessWidget {
  _ResultsPanel({
    Key? key,
    required this.title,
    required this.durations,
  })  : average = durations.isEmpty
            ? 0
            : (durations.reduce((a, b) => a + b) / durations.length).round(),
        super(key: key);

  final String title;
  final List<int> durations;
  final int average;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue, width: 4),
          borderRadius: BorderRadius.circular(2),
        ),
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(thickness: 3),
            Text('Average = $average'),
            const SizedBox(height: rowHeight),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: durations.length,
                itemBuilder: (BuildContext context, int index) {
                  return Container(
                    height: rowHeight,
                    color: Colors.blueGrey[index.isEven ? 800 : 900],
                    child: Center(child: Text('${durations[index]} ms')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

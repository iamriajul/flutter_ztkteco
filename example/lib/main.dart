import 'package:flutter/material.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
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

class _MyHomePageState extends State<MyHomePage> {
  final ipAdress = TextEditingController();
  final port = TextEditingController(text: '4370');
  ZKTeco? fingerprintMachine;
  String btnMessage = 'Connect';
  bool isConnected = false;
  int currentIndex = 0;
  List<UserInfo> users = [];
  List<AttendanceLog> attendances = [];
  bool loadingContent = false;

  void _connectFp() async {
    try {
      setState(() {
        btnMessage = 'Connecting...';
      });
      fingerprintMachine = ZKTeco(ipAdress.text, port: int.parse(port.text));
      await fingerprintMachine?.initSocket();
      final connect = await fingerprintMachine?.connect();
      if (connect == true) {
        setState(() {
          btnMessage = 'Disconnect';
          isConnected = connect ?? false;
        });
      } else {
        setState(() {
          btnMessage = 'Connect';
          isConnected = connect ?? false;
        });
      }
    } catch (e) {
      setState(() {
        btnMessage = 'Connect';
        isConnected = false;
      });
    }
  }

  void getUserData() async {
    setState(() {
      loadingContent = true;
    });
    var users = await fingerprintMachine?.getUsers() ?? [];

    setState(() {
      this.users = users;
      loadingContent = false;
    });
  }

  void getAttendancesData() async {
    setState(() {
      loadingContent = true;
    });
    var attendances = await fingerprintMachine?.getAttendanceLogs() ?? [];

    for (var attend in attendances) {
      debugPrint(
          '${attend.id} - ${attend.timestamp} - ${attend.uid} - ${attend.state} - ${attend.type}');
    }

    setState(() {
      this.attendances = attendances;
      loadingContent = false;
    });
  }

  void _disconnectFp() async {
    await fingerprintMachine?.disconnect();
    setState(() {
      btnMessage = 'Connect';
      isConnected = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(140),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: MediaQuery.of(context).size.width / 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 20,
                  children: <Widget>[
                    Row(
                      spacing: 20,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: ipAdress,
                            enabled: isConnected ? false : true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'IP Address',
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: port,
                            enabled: isConnected ? false : true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Port',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: isConnected ? _disconnectFp : _connectFp,
                          child: Text(btnMessage),
                        ),
                      ],
                    ),
                    TabBar(
                      onTap: (value) {
                        if (isConnected == false) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Connect first'),
                            ),
                          );
                          return;
                        }
                        if (value == 0) {
                          getUserData();
                        } else if (value == 1) {
                          getAttendancesData();
                        }
                        currentIndex = value;
                      },
                      tabs: [
                        Tab(
                          text: 'Get Users Data',
                        ),
                        Tab(
                          text: 'Get Attendances Data',
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            loadingContent
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemBuilder: (_, index) {
                      final user = users[index];
                      return ListTile(
                        title: Text(user.userId ?? '-'),
                        subtitle: Text(user.name ?? '-'),
                      );
                    },
                    itemCount: users.length,
                  ),
            loadingContent
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemBuilder: (_, index) {
                      final attendance = attendances[index];
                      return ListTile(
                        title: Text(attendance.id ?? '-'),
                        subtitle: Text(attendance.timestamp ?? '-'),
                      );
                    },
                    itemCount: attendances.length,
                  ),
          ],
        ),
      ),
    );
  }
}

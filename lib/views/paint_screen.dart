import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:scriclone/views/final_leaderboard.dart';
import 'package:scriclone/views/home_screen.dart';
import 'package:scriclone/models/my_custom_painter.dart';
import 'package:scriclone/models/touch_points.dart';

import 'package:scriclone/views/waiting_lobby_screen.dart';
import 'package:scriclone/widgets/loader.dart';
import 'package:scriclone/widgets/player_scoreboard_popup.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class PaintScreen extends StatefulWidget {
  final Map<String, String> data;
  final String screenFrom;
  const PaintScreen({super.key, required this.data, required this.screenFrom});

  @override
  _PaintScreenState createState() => _PaintScreenState();
}

class _PaintScreenState extends State<PaintScreen> {
  late IO.Socket _socket;
  Map dataOfRoom = {};
  List<TouchPoints?> points = [];
  StrokeCap strokeType = StrokeCap.round;
  Color selectedColor = Colors.black;
  double opacity = 1;
  double strokeWidth = 2;
  List<Widget> textBlankWidget = [];
  final ScrollController _scrollController = ScrollController();
  TextEditingController controller = TextEditingController();
  List<Map> messages = [];
  int guessedUserCtr = 0;
  late int _start = 60;
  late Timer _timer;
  var scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map> scoreboard = [];
  bool isTextInputReadOnly = false;
  int maxPoints = 0;
  String winner = "";
  bool isShowFinalLeaderboard = false;
  bool isInputFocused = false;
  final String serverUrl = dotenv.env['SERVER_URL'] ?? 'http://localhost:3000';

  @override
  void initState() {
    super.initState();
    connect();
  }

  void startTimer() {
    const oneSec = Duration(seconds: 1);
    _timer = Timer.periodic(oneSec, (Timer time) {
      if (_start == 0) {
        _socket.emit('change-turn', dataOfRoom['name']);
        setState(() {
          _timer.cancel();
        });
      } else {
        setState(() {
          _start--;
        });
      }
    });
  }

  void renderTextBlank(String text) {
    textBlankWidget.clear();
    for (int i = 0; i < text.length; i++) {
      textBlankWidget.add(const Text('_', style: TextStyle(fontSize: 30)));
    }
  }

  void connect() {
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false
    });
    _socket.connect();
    print(widget.data);

    if (widget.screenFrom == 'createRoom') {
      _socket.emit('create-game', widget.data);
    } else {
      _socket.emit('join-game', widget.data);
    }

    //listen to socket
    _socket.onConnect((data) {
      print('connected!');
      _socket.on('updateRoom', (roomData) {
        print(roomData['word']);
        setState(() {
          renderTextBlank(roomData['word']);
          dataOfRoom = roomData;
        });
        if (roomData['isJoin'] != true) {
          startTimer();
        }
        scoreboard.clear();
        for (int i = 0; i < roomData['players'].length; i++) {
          setState(() {
            scoreboard.add({
              'username': roomData['players'][i]['nickname'],
              'points': roomData['players'][i]['points'].toString()
            });
          });
        }
      });

      _socket.on(
          'notCorrectGame',
          (data) => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => HomeScreen()),
              (route) => false));

      _socket.on('points', (point) {
        if (point['details'] != null) {
          setState(() { 
            points.add(TouchPoints(
                points: Offset((point['details']['dx']).toDouble(),
                    (point['details']['dy']).toDouble()),
                paint: Paint()
                  ..strokeCap = strokeType
                  ..isAntiAlias = true
                  // ignore: deprecated_member_use
                  ..color = selectedColor.withOpacity(opacity)
                  ..strokeWidth = strokeWidth));
          });
        }
      });

      _socket.on('msg', (msgData) {
        setState(() {
          messages.add(msgData);
          guessedUserCtr = msgData['guessedUserCtr'];
        });
        if (guessedUserCtr == dataOfRoom['players'].length - 1) {
          _socket.emit('change-turn', dataOfRoom['name']);
        }
        _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 40,
            duration: Duration(milliseconds: 200),
            curve: Curves.easeInOut);
      });

      _socket.on('change-turn', (data) {
        String oldWord = dataOfRoom['word'];
        showDialog(
            context: context,
            builder: (context) {
              Future.delayed(Duration(seconds: 3), () {
                setState(() {
                  dataOfRoom = data;
                  renderTextBlank(data['word']);
                  isTextInputReadOnly = false;
                  guessedUserCtr = 0;
                  _start = 60;
                  points.clear();
                });
                Navigator.of(context).pop();
                _timer.cancel();
                startTimer();
              });
              return Center(
                child: Container(
                  padding: EdgeInsets.all(4), // Space for outer border
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent, // Inner background
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: Colors.transparent, // Inner border color
                        width: 8, // Thick inner border
                      ),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Text(
                      'Word was $oldWord',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        decoration: TextDecoration.none, // Remove underline
                      ),
                      textAlign: TextAlign.center, // Center text inside
                    ),
                  ),
                ),
              );
            });
      });

      _socket.on('updateScore', (roomData) {
        scoreboard.clear();
        for (int i = 0; i < roomData['players'].length; i++) {
          setState(() {
            scoreboard.add({
              'username': roomData['players'][i]['nickname'],
              'points': roomData['players'][i]['points'].toString()
            });
          });
        }
      });

      _socket.on("show-leaderboard", (roomPlayers) {
        scoreboard.clear();
        for (int i = 0; i < roomPlayers.length; i++) {
          setState(() {
            scoreboard.add({
              'username': roomPlayers[i]['nickname'],
              'points': roomPlayers[i]['points'].toString()
            });
          });
          if (maxPoints < int.parse(scoreboard[i]['points'])) {
            winner = scoreboard[i]['username'];
            maxPoints = int.parse(scoreboard[i]['points']);
          }
        }
        setState(() {
          _timer.cancel();
          isShowFinalLeaderboard = true;
        });
      });

      _socket.on('color-change', (colorString) {
        int value = int.parse(colorString, radix: 16);
        Color otherColor = Color(value);
        setState(() {
          selectedColor = otherColor;
        });
      });

      _socket.on('stroke-width', (value) {
        setState(() {
          strokeWidth = value.toDouble();
        });
      });

      _socket.on('clear-screen', (data) {
        setState(() {
          points.clear();
        });
      });

      _socket.on('closeInput', (_) {
        _socket.emit('updateScore', widget.data['name']);
        setState(() {
          isTextInputReadOnly = true;
        });
      });
    });
  }

  @override
  void dispose() {
    _socket.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    List<Map<String, dynamic>> transformScoreboard(
        List<Map> originalScoreboard) {
      return originalScoreboard
          .map((player) => {
                'name': player['username'], // Rename 'username' to 'name'
                'score': player['points'], // Rename 'points' to 'score'
              })
          .toList();
    }

    void selectColor() {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose Color'),
          content: SingleChildScrollView(
              child: BlockPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (color) {
                    String colorString = color.toString();
                    String valueString = color.value.toRadixString(16);

                    setState(() {
                      selectedColor = color;
                    });
                    print(colorString);
                    print(valueString);
                    Map map = {
                      'color': valueString,
                      'roomName': dataOfRoom['name']
                    };
                    _socket.emit('color-change', map);
                  })),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('Close'))
          ],
        ),
      );
    }

    return Scaffold(
      key: scaffoldKey,
      drawer: PlayerScorePopup(scoreboard),
      // Changed to true to let the system adjust the layout for keyboard
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(color: Colors.white),
        child: dataOfRoom.isEmpty
            ? const Center(child: Loader())
            : dataOfRoom['isJoin'] != true
                ? !isShowFinalLeaderboard
                    ? SafeArea(
                        child: Column(
                          children: [
                            // New top row with drawer icon, word/blanks, and timer
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.people,
                                        color: Colors.black, size: 38),
                                    onPressed: () =>
                                        scaffoldKey.currentState!.openDrawer(),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            "Guess the Word",
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          dataOfRoom['turn']['nickname'] !=
                                                  widget.data['nickname']
                                              ? Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceEvenly,
                                                  children: List.generate(
                                                    textBlankWidget.length,
                                                    (index) => Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 4.0),
                                                      child: Text(
                                                        '_',
                                                        style: TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  dataOfRoom['word'],
                                                  style: const TextStyle(
                                                      fontSize: 30),
                                                ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 2,
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                          value: _start / 60,
                                          backgroundColor: Colors.grey.shade200,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            _start > 10
                                                ? Colors.blue
                                                : Colors.red,
                                          ),
                                        ),
                                        Text(
                                          '$_start',
                                          style: TextStyle(
                                            color: _start > 10
                                                ? Colors.blue
                                                : Colors.red,
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Main content area (flexible to adjust with keyboard)
                            Expanded(
                              child: SingleChildScrollView(
                                reverse: isKeyboardOpen,
                                child: Column(
                                  children: [
                                    // Drawing canvas - adjusted height
                                    Container(
                                      width: width,
                                      height: isKeyboardOpen
                                          ? height * 0.35
                                          : height * 0.4,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: Colors.grey[300]!),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: GestureDetector(
                                        onPanUpdate: (details) {
                                          _socket.emit('paint', {
                                            'details': {
                                              'dx': details.localPosition.dx,
                                              'dy': details.localPosition.dy,
                                            },
                                            'roomName': widget.data['name'],
                                          });
                                        },
                                        onPanStart: (details) {
                                          _socket.emit('paint', {
                                            'details': {
                                              'dx': details.localPosition.dx,
                                              'dy': details.localPosition.dy,
                                            },
                                            'roomName': widget.data['name'],
                                          });
                                        },
                                        onPanEnd: (details) {
                                          _socket.emit('paint', {
                                            'details': null,
                                            'roomName': widget.data['name'],
                                          });
                                          setState(() {
                                            points.add(null);
                                          });
                                        },
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: CustomPaint(
                                            size: Size.infinite,
                                            painter: MyCustomPainter(
                                                pointsList: points),
                                          ),
                                        ),
                                      ),
                                    ),

                                    if (!isKeyboardOpen) ...[
                                      // Color and stroke width controls
                                      SizedBox(
                                        height: 50,
                                        child: Row(
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.color_lens,
                                                  color: selectedColor),
                                              onPressed: selectColor,
                                            ),
                                            Expanded(
                                              child: Slider(
                                                min: 1.0,
                                                max: 10,
                                                label:
                                                    "Strokewidth $strokeWidth",
                                                activeColor: selectedColor,
                                                value: strokeWidth,
                                                onChanged: (double value) {
                                                  Map map = {
                                                    'value': value,
                                                    'roomName':
                                                        dataOfRoom['name']
                                                  };
                                                  _socket.emit(
                                                      'stroke-width', map);
                                                },
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.layers_clear,
                                                  color: selectedColor),
                                              onPressed: () {
                                                _socket.emit('clean-screen',
                                                    dataOfRoom['name']);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Messages list
                                      Container(
                                        height: height * 0.25,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: Colors.pink[50],
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.pink[200]!),
                                        ),
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8),
                                          itemCount: messages.length,
                                          itemBuilder: (context, index) {
                                            var msg = messages[index].values;
                                            return Card(
                                              elevation: 4,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: BorderSide(
                                                    color:
                                                        Colors.pink.shade200),
                                              ),
                                              color: Colors.pink[100],
                                              margin: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      msg.elementAt(0),
                                                      style: const TextStyle(
                                                        color: Colors.black87,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      msg.elementAt(1),
                                                      style: TextStyle(
                                                        color: Colors.grey[700],
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      SizedBox(height: 8), // Small gap
                                    ],

                                    if (isKeyboardOpen) ...[
                                      // Messages list (reduced height when keyboard is open)
                                      Container(
                                        height: height * 0.15,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.pink[50],
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.pink[200]!),
                                        ),
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8),
                                          itemCount: messages.length,
                                          itemBuilder: (context, index) {
                                            var msg = messages[index].values;
                                            return Card(
                                              elevation: 4,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: BorderSide(
                                                    color:
                                                        Colors.pink.shade200),
                                              ),
                                              color: Colors.pink[100],
                                              margin: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      msg.elementAt(0),
                                                      style: const TextStyle(
                                                        color: Colors.black87,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      msg.elementAt(1),
                                                      style: TextStyle(
                                                        color: Colors.grey[700],
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],

                                    // Text input for guesses
                                    if (dataOfRoom['turn']['nickname'] !=
                                        widget.data['nickname'])
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 10,
                                        ),
                                        child: Card(
                                          elevation: 4,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: BorderSide(
                                                color: Colors.green.shade400),
                                          ),
                                          color: const Color.fromARGB(
                                              255, 152, 220, 155),
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: controller,
                                                    onTap: () {
                                                      setState(() {
                                                        isInputFocused = true;
                                                      });
                                                    },
                                                    onSubmitted: (value) {
                                                      if (value
                                                          .trim()
                                                          .isNotEmpty) {
                                                        Map map = {
                                                          'username': widget
                                                              .data['nickname'],
                                                          'msg': value.trim(),
                                                          'word': dataOfRoom[
                                                              'word'],
                                                          'roomName': widget
                                                              .data['name'],
                                                          'guessedUserCtr':
                                                              guessedUserCtr,
                                                          'totalTime': 60,
                                                          'timeTaken':
                                                              60 - _start,
                                                        };
                                                        _socket.emit(
                                                            'msg', map);
                                                        controller.clear();
                                                        setState(() {
                                                          isInputFocused =
                                                              false;
                                                        });
                                                      }
                                                    },
                                                    decoration: InputDecoration(
                                                      border: InputBorder.none,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                              horizontal: 16,
                                                              vertical: 14),
                                                      hintText:
                                                          'Type your guess here...',
                                                      hintStyle: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: Colors.black
                                                            .withOpacity(0.8),
                                                      ),
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.black,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.send_rounded,
                                                      color: Colors
                                                          .green.shade700),
                                                  onPressed: () {
                                                    if (controller.text
                                                        .trim()
                                                        .isNotEmpty) {
                                                      Map map = {
                                                        'username': widget
                                                            .data['nickname'],
                                                        'msg': controller.text
                                                            .trim(),
                                                        'word':
                                                            dataOfRoom['word'],
                                                        'roomName':
                                                            widget.data['name'],
                                                        'guessedUserCtr':
                                                            guessedUserCtr,
                                                        'totalTime': 60,
                                                        'timeTaken':
                                                            60 - _start,
                                                      };
                                                      _socket.emit('msg', map);
                                                      controller.clear();
                                                      setState(() {
                                                        isInputFocused = false;
                                                      });
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : FinalLeaderboard(transformScoreboard(scoreboard))
                : WaitingLobbyScreen(
                    lobbyName: dataOfRoom['name'],
                    noOfPlayers: dataOfRoom['players'].length,
                    occupancy: dataOfRoom['occupancy'],
                    players: dataOfRoom['players'],
                  ),
      ),
    );
  }
}

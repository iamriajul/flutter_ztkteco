import 'dart:async';
import 'dart:convert';
import 'dart:io';
// import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/util.dart';

class Attendance {
  static late Socket _socket;

  /// Retrieves all attendance records from the device.
  ///
  /// This method sends a command to the device to retrieve all attendance
  /// records. The device must be connected and authenticated before this
  /// method can be used.
  ///
  /// The method returns a [Future] that completes with a [Map] containing all
  /// attendance records, or a [bool] indicating if the device could not be
  /// queried. The map has the user ID as the key, and the value is another
  /// [Map] containing the user ID, name, state, timestamp, and type. If the
  /// user name is empty, the user ID is used instead.
  static Future<List<AttendanceLog>> get(ZKTeco self) async {
    try {
      int command = Util.CMD_ATT_LOG_RRQ;
      String commandString = '';

      var session = await self.command(command, commandString,
          type: Util.COMMAND_TYPE_DATA);

      if (session == false) {
        return [];
      }

      Uint8List? attData = await Util.recData(self);

      List<AttendanceLog> attendance = [];

      if (attData == null || attData.length <= 10) {
        return [];
      }

      attData = attData.sublist(10);

      int chunkSize = 40;

      while (attData!.length >= chunkSize) {
        String u = Util.byteToHex(Uint8List.fromList(attData.sublist(0, 39)));
        int? u1 = int.tryParse(u.substring(4, 6), radix: 16);
        int? u2 = int.tryParse(u.substring(6, 8), radix: 16);
        int? uid = (u1 != null && u2 != null) ? u1 + (u2 * 256) : null;

        List<String>? id = utf8
            .decode(Util.hex2bin(u.substring(8, 18)), allowMalformed: true)
            .split('\x00');
        int state = int.parse(u.substring(56, 58), radix: 16);
        String timestamp = Util.decodeTime(
            int.parse(Util.reverseHex(u.substring(58, 66)), radix: 16));
        int type = int.parse(Util.reverseHex(u.substring(66, 68)), radix: 16);

        final Map<String, dynamic> data = {
          'uid': uid,
          'id': id[0],
          'state': state,
          'timestamp': timestamp,
          'type': type,
        };
        attendance.add(AttendanceLog.fromJson(data));

        attData = attData.sublist(chunkSize);
      }
      debugPrint('✅ Successfully retrieved ${attendance.length} records.');
      return attendance;
    } catch (e, stackTrace) {
      debugPrint('❌ Error retrieving attendances: $e');
      debugPrint(stackTrace.toString());
      return [];
    }
  }

  static _regEvent(ZKTeco self, int flags) async {
    int command = Util.CMD_REG_EVENT;
    String commandString = String.fromCharCode(flags);

    var session = await self.command(command, commandString,
        type: Util.COMMAND_TYPE_DATA);
    if (session == false) {
      return [];
    }
  }

  static Future<void> enableLiveCapture(ZKTeco self) async {
    try {
      _socket = await Socket.connect(
          InternetAddress(self.ip, type: InternetAddressType.IPv4), self.port);
      debugPrint('Connected to: ${self.ip}:${self.port}');
      _socket.setOption(SocketOption.tcpNoDelay, true);

      _socket.listen((List<int> data) {
        debugPrint('Received data: ${String.fromCharCodes(data)}');
      });
      self.liveCapture = true;
    } on SocketException catch (e) {
      debugPrint('Connection failed : $e');
    }
  }

  static dynamic cancelLiveCapture(ZKTeco self) async {
    int command = Util.CMD_CANCELCAPTURE;
    String commandString = '';

    var session = await self.command(command, commandString,
        type: Util.COMMAND_TYPE_DATA);
    if (session == false) {
      return [];
    }
  }

  static Stream<AttendanceLog?> streamLiveCapture(ZKTeco self,
      {Duration? timeout}) async* {
    debugPrint('Read Users Records');
    List<UserInfo> users = await self.getUsers();

    self.liveCapture = true;

    await self.cancelLiveCapture();

    debugPrint('Verify Authentication');
    await self.verifyAuthentication();

    debugPrint('Enable Device');
    await self.enableDevice();

    debugPrint('Registering Event');
    await _regEvent(self, Util.EF_ATTLOG);

    while (self.liveCapture) {
      try {
        debugPrint("Waiting for event");

        // Wait for data from the device
        List<int> dataRecv = await _socket.first;

        // Process the received data
        AttendanceLog? attendance = _liveAttendanceData(dataRecv, users);
        yield attendance;
      } on TimeoutException {
        debugPrint("Timeout");
        yield null;
      } catch (e) {
        if (e is SocketException) {
          debugPrint("Connection error: $e");
          break;
        }
      }
    }
  }

  static AttendanceLog? _liveAttendanceData(
      List<int> dataRecv, List<UserInfo> users) {
    if (dataRecv.isEmpty) return null;

    ByteData byteData = ByteData.sublistView(Uint8List.fromList(dataRecv));

    // Assuming CMD_REG_EVENT is equivalent to 0x500 (adjust to your protocol)
    if (byteData.getUint16(0, Endian.little) != 0x500) {
      debugPrint("Not an event packet!");
      return null;
    }

    if (dataRecv.length < 10) {
      return null;
    }
    // print(byteData.getUint16(4, Endian.little));
    // print(dataRecv[6]);
    // print(dataRecv[7]);
    // print(dataRecv.sublist(8, 14));
    return null;
    // AttendanceLog attendance = AttendanceLog(
    //   uid: byteData.getUint16(2, Endian.little),
    //   state: byteData.getUint16(4, Endian.little),
    //   timestamp: Util.decodeTime(byteData.getUint32(6, Endian.little)),
    //   type: byteData.getUint16(10, Endian.little),
    // );
  }

  /// Clears all attendance records from the device.
  ///
  /// This method sends a command to the device to clear all attendance records.
  /// The device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device could clear all attendance records, or a [String] containing an
  /// error message if the device could not be queried.
  static Future<dynamic> clear(ZKTeco self) async {
    int command = Util.CMD_CLEAR_ATT_LOG;
    String commandString = '';

    return await self.command(command, commandString);
  }
}

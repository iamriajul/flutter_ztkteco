import 'dart:async';
import 'dart:io';
// import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/finger_bridge.dart';
import 'package:flutter_zkteco/src/model/memory_reader.dart';
import 'package:flutter_zkteco/src/model/read_buffer_result.dart';
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
      MemoryReader? sizes = await Util.readSizes(self);

      if (sizes?.records == 0) {
        return [];
      }

      List<UserInfo> users = await self.getUsers();

      List<AttendanceLog> attendances = [];

      ReadBufferResult? results =
          await FingerBridge.readWithBuffer(self, Util.CMD_ATT_LOG_RRQ);

      final Uint8List attendanceDataRaw = results.data;
      final int size = results.data.length;

      if (size < 4) {
        if (self.debug) debugPrint("WRN: no attendance data");
        return [];
      }

      final ByteData sizeData = ByteData.sublistView(attendanceDataRaw, 0, 4);
      final int totalSize = sizeData.getUint32(0, Endian.little);
      final int recordSize = totalSize ~/ sizes!.records!;

      if (self.debug) debugPrint("record_size is $recordSize");

      Uint8List attendanceData = attendanceDataRaw.sublist(4);

      if (recordSize == 8) {
        while (attendanceData.length >= 8) {
          ByteData record = ByteData.sublistView(
              Uint8List.fromList(attendanceData.sublist(0, 8)));
          int uid = record.getUint16(0, Endian.little);
          int status = record.getUint8(2);
          int timestamp = record.getUint32(3, Endian.little);
          int punch = record.getUint8(7);

          attendanceData = attendanceData.sublist(8);

          UserInfo? userMatch = users.firstWhere((u) => u.uid == uid,
              orElse: () => UserInfo(uid: uid, userId: uid.toString()));
          String? userId = userMatch.userId ?? uid.toString();

          String timestampStr = Util.decodeTime(timestamp);
          attendances.add(AttendanceLog(
              uid: uid,
              timestamp: timestampStr,
              state: status,
              type: punch,
              id: userId));
        }
      } else if (recordSize == 16) {
        while (attendanceData.length >= 16) {
          ByteData data = ByteData.sublistView(
              Uint8List.fromList(attendanceData.sublist(0, 16)));
          int userId = data.getUint32(0, Endian.little);
          int timestamp = data.getUint32(4, Endian.little);
          int status = data.getUint8(8);
          int punch = data.getUint8(9);

          attendanceData = attendanceData.sublist(16);

          UserInfo? tuser = users.firstWhere(
              (u) => u.userId == userId.toString(),
              orElse: () => const UserInfo());
          int? uid = tuser.userId != null ? tuser.uid : userId;

          String timestampStr = Util.decodeTime(timestamp);
          attendances.add(AttendanceLog(
              id: userId.toString(),
              timestamp: timestampStr,
              state: status,
              type: punch,
              uid: uid));
        }
      } else {
        while (attendanceData.length >= 40) {
          ByteData data = ByteData.sublistView(
              Uint8List.fromList(attendanceData.sublist(0, 40)));
          int uid = data.getUint16(0, Endian.little);
          List<int> userIdBytes = attendanceData.sublist(2, 26);
          int status = data.getUint8(26);
          int timestamp = data.getUint32(27, Endian.little);
          int punch = data.getUint8(31);

          String userId = String.fromCharCodes(userIdBytes).split('\x00')[0];
          String timestampStr = Util.decodeTime(timestamp);

          attendances.add(AttendanceLog(
              id: userId,
              timestamp: timestampStr,
              state: status,
              type: punch,
              uid: uid));
          attendanceData = attendanceData.sublist(recordSize);
        }
      }

      if (self.debug) {
        debugPrint('✅ Successfully retrieved ${attendances.length} records.');
      }

      await FingerBridge.freeData(self);

      return attendances;
    } catch (e, stackTrace) {
      debugPrint('❌ Error retrieving attendances: $e');
      debugPrint(stackTrace.toString());
      return [];
    }
  }

  static regEvent(ZKTeco self, int flags) async {
    int command = Util.CMD_REG_EVENT;

    var session = await self.command(
      command,
      commandString: Uint8List.fromList([flags]),
    );
    if (session['status'] == false) {
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

    var session = await self.command(command);
    if (session['status'] == false) {
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
    await regEvent(self, Util.EF_ATTLOG);

    while (self.liveCapture) {
      try {
        debugPrint("Waiting for event");

        // Wait for data from the device
        List<int> dataRecv = await _socket.first;

        // Process the received data
        AttendanceLog? attendance = liveAttendanceData(dataRecv, users);
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

  static AttendanceLog? liveAttendanceData(
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

    return await self.command(command);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/error/zk_error_connection.dart';
import 'package:flutter_zkteco/src/finger_bridge.dart';
import 'package:flutter_zkteco/src/model/memory_reader.dart';
import 'package:flutter_zkteco/src/model/read_buffer_result.dart';
import 'package:flutter_zkteco/src/util.dart';

class Attendance {
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

          DateTime timestampStr = Util.decodeTime(timestamp);
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

          DateTime timestampStr = Util.decodeTime(timestamp);
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
          int status = data.getUint8(26);
          int timestamp = data.getUint32(27, Endian.little);
          int punch = data.getUint8(31);

          String userId = Util.extractString(attendanceData.sublist(2, 26));
          DateTime convertedTimestamp = Util.decodeTime(timestamp);

          attendances.add(AttendanceLog(
              id: userId,
              timestamp: convertedTimestamp,
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

  /// Registers events from the device. This method sends a command to the
  /// device to register events. The device must be connected and
  /// authenticated before this method can be used.
  ///
  /// The [flags] parameter is a bit field of the following values:
  ///
  /// * [Util.EVENT_ATTLOG]
  /// * [Util.EVENT_ENROLL]
  /// * [Util.EVENT_DELETE_TEMPLATE]
  /// * [Util.EVENT_CLEAR_ATTLOG]
  /// * [Util.EVENT_CLEAR_TEMPLATE]
  /// * [Util.EVENT_DEVICE]
  /// * [Util.EVENT_FINGER]
  /// * [Util.EVENT_KEY]
  /// * [Util.EVENT_SENSOR]
  /// * [Util.EVENT_DOOR]
  ///
  /// The method returns a [Future] that completes with no value if the
  /// events were successfully registered, or a [String] containing an error
  /// message if the device could not be queried.
  static Future<void> regEvent(ZKTeco self, int flags) async {
    final ByteData commandString = ByteData(4)
      ..setUint32(0, flags, Endian.little);

    final Map<String, dynamic> response = await self.command(
      Util.CMD_REG_EVENT,
      commandString: commandString.buffer.asUint8List(),
    );

    if (response['status'] == false) {
      throw ZKErrorConnection("Can't register events: $flags");
    }
  }

  /// Cancels live capture of attendance records from the device.
  ///
  /// When called, the device will no longer send attendance records in
  /// real-time to the Flutter application. The device must be connected and
  /// authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device could successfully cancel live capture of attendance records.
  static Future<bool> cancelLiveCapture(ZKTeco self) async {
    final Map<String, dynamic> response =
        await self.command(Util.CMD_CANCELCAPTURE);

    if (response['status'] == true) {
      self.liveCapture = false;
    }

    return response['status'];
  }

  /// Stream attendance records from the device in real-time.
  ///
  /// This method must be used after connecting and authenticating with the
  /// device. The device will send attendance records in real-time to the
  /// Flutter application until [cancelLiveCapture] is called. The records
  /// will be yielded as [AttendanceLog] objects.
  ///
  /// The stream will complete when the device is disconnected or
  /// [cancelLiveCapture] is called.
  ///
  /// The method will throw a [TimeoutException] if the device does not
  /// respond within the specified [timeout] period.
  ///
  static Stream<AttendanceLog?> streamLiveCapture(ZKTeco self) async* {
    bool wasEnabled = self.isEnabled;

    if (self.debug) debugPrint('Read Users Records');
    List<UserInfo> users = await self.getUsers();

    await self.cancelLiveCapture();

    if (self.debug) debugPrint('Verify Authentication');
    await self.verifyAuthentication();

    if (!self.isEnabled) {
      if (self.debug) debugPrint('Enable Device');
      await self.enableDevice();
    }

    if (self.debug) debugPrint('Registering Event');
    await regEvent(self, Util.EF_ATTLOG);
    self.liveCapture = true;

    while (self.liveCapture) {
      try {
        if (self.debug) debugPrint("Waiting for event...");

        // Wait for data from the device
        Uint8List dataRecv = await self.streamController.stream.first;
        await self.ackOk();

        // int size;
        List<int> data;
        List<int> header;

        if (self.tcp) {
          // size = ByteData.sublistView(dataRecv).getUint32(4, Endian.little);
          header = ByteData.sublistView(dataRecv, 8, 16).buffer.asUint16List();
          data = dataRecv.sublist(16);
        } else {
          // size = dataRecv.length;
          header = ByteData.sublistView(dataRecv, 0, 8).buffer.asUint16List();
          data = dataRecv.sublist(8);
        }

        if (header[4] != Util.CMD_REG_EVENT) {
          if (self.debug) {
            debugPrint("Not an event! 0x${header[0].toRadixString(16)}");
          }
          continue;
        }

        if (data.isEmpty) {
          if (self.debug) debugPrint("Empty data");
          continue;
        }

        while (data.length >= 10) {
          late String userId;
          late int status;
          late int punch;
          late DateTime timestamp;
          late int uid;

          if (data.length >= 52) {
            final chunk = data.sublist(0, 52);
            userId = utf8
                .decode(chunk.sublist(0, 24), allowMalformed: true)
                .split('\x00')
                .first;
            status = chunk[24];
            punch = chunk[25];
            timestamp = Util.decodeTimeHex(chunk.sublist(26, 40));
            data = data.sublist(52);
          } else if (data.length >= 37) {
            final chunk = data.sublist(0, 37);
            userId = utf8
                .decode(chunk.sublist(0, 24), allowMalformed: true)
                .split('\x00')
                .first;
            status = chunk[24];
            punch = chunk[25];
            timestamp = Util.decodeTimeHex(chunk.sublist(26, 32));
            data = data.sublist(37);
          } else if (data.length >= 36) {
            final chunk = data.sublist(0, 36);
            userId = utf8
                .decode(chunk.sublist(0, 24), allowMalformed: true)
                .split('\x00')
                .first;
            status = chunk[24];
            punch = chunk[25];
            timestamp = Util.decodeTimeHex(chunk.sublist(26, 32));
            data = data.sublist(36);
          } else if (data.length >= 32) {
            final chunk = data.sublist(0, 32);
            userId = utf8
                .decode(chunk.sublist(0, 24), allowMalformed: true)
                .split('\x00')
                .first;
            status = chunk[24];
            punch = chunk[25];
            timestamp = Util.decodeTimeHex(chunk.sublist(26, 32));
            data = data.sublist(32);
          } else if (data.length >= 14) {
            final chunk = data.sublist(0, 14);
            userId = utf8
                .decode(chunk.sublist(0, 2), allowMalformed: true)
                .split('\x00')
                .first;
            status = chunk[2];
            punch = chunk[3];
            timestamp = Util.decodeTimeHex(chunk.sublist(4, 10));
            data = data.sublist(14);
          } else if (data.length >= 12) {
            final chunk = data.sublist(0, 12);
            userId = utf8
                .decode(chunk.sublist(0, 4), allowMalformed: true)
                .split('\x00')
                .first;
            status = chunk[4];
            punch = chunk[5];
            timestamp = Util.decodeTimeHex(chunk.sublist(6, 12));
            data = data.sublist(12);
          } else if (data.length >= 10) {
            final chunk = data.sublist(0, 10);
            userId = utf8
                .decode(chunk.sublist(0, 2), allowMalformed: true)
                .split('\x00')
                .first;
            status = chunk[2];
            punch = chunk[3];
            timestamp = Util.decodeTimeHex(chunk.sublist(4, 10));
            data = data.sublist(10);
          } else {
            break; // handle other formats if needed
          }

          final matchedUser = users.firstWhere(
            (u) => u.userId == userId,
            orElse: () => const UserInfo(),
          );

          uid = matchedUser.uid ?? int.tryParse(userId) ?? 0;

          AttendanceLog log = AttendanceLog(
              uid: uid,
              timestamp: timestamp,
              state: status,
              type: punch,
              id: userId);

          if (self.debug) debugPrint(log.toJson().toString());

          yield log;
        }
      } on TimeoutException {
        debugPrint("Timeout");
        yield null;
      } catch (e) {
        if (e is SocketException) {
          debugPrint("Connection error: $e");
          break;
        }
        rethrow;
      }
    }

    if (self.debug) debugPrint("Exiting live capture...");

    await regEvent(self, 0);

    if (!wasEnabled) {
      self.disableDevice();
    }
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

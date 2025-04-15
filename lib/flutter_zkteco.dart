library flutter_zkteco;

import 'dart:async';
import 'dart:io' hide Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/src/attendance.dart';
import 'package:flutter_zkteco/src/connect.dart';
import 'package:flutter_zkteco/src/device.dart';
import 'package:flutter_zkteco/src/error/zk_error_connection.dart';
import 'package:flutter_zkteco/src/fingerprint.dart';
import 'package:flutter_zkteco/src/model/attendance_log.dart';
import 'package:flutter_zkteco/src/model/user_info.dart';
import 'package:flutter_zkteco/src/os.dart';
import 'package:flutter_zkteco/src/platform.dart';
import 'package:flutter_zkteco/src/serial_number.dart';
import 'package:flutter_zkteco/src/ssr.dart';
import 'package:flutter_zkteco/src/time.dart';
import 'package:flutter_zkteco/src/user.dart';
import 'package:flutter_zkteco/src/util.dart';
import 'package:flutter_zkteco/src/version.dart';
import 'package:flutter_zkteco/src/workcode.dart';

export 'package:flutter_zkteco/src/model/user_info.dart';
export 'package:flutter_zkteco/src/model/attendance_log.dart';

class ZKTeco {
  // The IP address of the device
  String ip;

  // The port number of the device
  int port;

  // The timeout for the connection
  Duration timeout;

  // The live capture
  bool liveCapture = false;

  // The socket used to connect to the device
  int retry;

  // Protocol used to connect to the device
  bool tcp;

  // The debug mode
  bool debug;

  // The socket used to connect to the device using TCP
  Socket? zkSocket;

  int userPacketSize = 28;

  // The socket used to connect to the device using UDP
  RawDatagramSocket? zkClient;

  // The stream controller used to receive the datagrams
  Completer<Datagram?> completer = Completer();
  StreamController<Uint8List> streamController = StreamController.broadcast();

  // The data received from the device
  late Uint8List dataRecv;

  late List<int> data;

  int tcpLength = 0;

  // The session ID
  int sessionId = 0;

  int replyId = -1 + Util.USHRT_MAX;

  late List<int> header;

  bool isConnect = false;

  String? password;

  late int nextUid;
  late String nextUserId;

  bool isEnabled = true;

  // Constructor for ZKTeco
  ZKTeco(this.ip,
      {this.port = 4370,
      this.timeout = const Duration(seconds: 10),
      this.retry = 3,
      this.tcp = true,
      this.debug = false,
      this.password});

  /// Sends a command to the device and waits for a response.
  ///
  /// The [command] parameter is the command to send to the device.
  ///
  /// The [commandString] parameter is the string to include with the command.
  ///
  /// The [type] parameter is the type of command to send. The default is
  /// [Util.COMMAND_TYPE_GENERAL].
  ///
  /// The method returns a [Future] that completes with the response from the
  /// device, or [false] if an error occurred.
  Future<Map<String, dynamic>> command(int command,
      {List<int> commandString = const []}) async {
    if (![Util.CMD_CONNECT, Util.CMD_AUTH].contains(command) && !isConnect) {
      throw ZKErrorConnection("Instance is not connected.");
    }

    List<int> buf =
        Util.createHeader(command, sessionId, replyId, commandString);

    try {
      if (tcp == true) {
        List<int> top = Util.createTcpTop(buf);

        zkSocket?.add(top);

        final data = await streamController.stream.first;

        final Uint8List tcpDataRecv = data;

        if (tcpDataRecv.length < 8) {
          throw ZKNetworkError(
              "Could not get response from device (Incomplete Data)");
        }

        tcpLength = Util.testTcpTop(tcpDataRecv);
        if (tcpLength == 0) {
          throw ZKNetworkError("TCP Packet is invalid");
        }

        final byteData = ByteData.sublistView(tcpDataRecv, 8, 16);
        header = [
          byteData.getUint16(0, Endian.little),
          byteData.getUint16(2, Endian.little),
          byteData.getUint16(4, Endian.little),
          byteData.getUint16(6, Endian.little),
        ];

        dataRecv = tcpDataRecv.sublist(8);
      } else {
        zkClient?.send(
            buf, InternetAddress(ip, type: InternetAddressType.IPv4), port);

        final data = await streamController.stream.first;

        dataRecv = data;
        final byteData = ByteData.sublistView(dataRecv, 0, 8);
        header = [
          byteData.getUint16(0, Endian.little),
          byteData.getUint16(2, Endian.little),
          byteData.getUint16(4, Endian.little),
          byteData.getUint16(6, Endian.little),
        ];
      }
    } catch (e) {
      if (debug) {
        debugPrint('Error: ${e.toString()}');
      }
      throw ZKNetworkError(e.toString());
    }

    int response = header[0];
    replyId = header[3];
    data = dataRecv.sublist(8);

    if ([Util.CMD_ACK_OK, Util.CMD_PREPARE_DATA, Util.CMD_DATA]
        .contains(response)) {
      return {'status': true, 'code': response};
    }
    return {'status': false, 'code': response};
  }

  /// Connects to the ZKTeco device.
  ///
  /// This function sends a connect command to the device, which responds with
  /// a session ID and a checksum. The session ID is stored in the [ZKTeco]
  /// object, and the checksum is used to verify that the device responded with
  /// valid data. If the device does not respond or the checksum is invalid, this
  /// function returns [false]. Otherwise, it returns [true].
  ///
  /// This function must be called before any other functions in this class can
  /// be used.
  Future<bool> connect({bool ommitPing = false}) =>
      Connect.connect(this, ommitPing: ommitPing);

  /// Disconnects from the ZKTeco device.
  ///
  /// This function disconnects from the ZKTeco device using the CMD_EXIT command.
  ///
  /// The function takes no arguments and returns a [Future] that completes with a
  /// [bool] indicating if the device was successfully disconnected, or a [String]
  /// containing an error message if the device could not be disconnected.
  ///
  /// If the device is already disconnected, this function does nothing and returns
  /// [true].
  Future<bool> disconnect() => Connect.disconnect(this);

  /// Retrieves the version of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its version. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the version of the device, or a [bool] indicating if the device could not
  /// be queried.
  Future<dynamic> version() => Version.get(this);

  /// Retrieves the serial number of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its serial
  /// number. The device must be connected and authenticated before this
  /// method can be used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the serial number of the device, or a [bool] indicating if the device
  /// could not be queried.
  Future<dynamic> serialNumber() => SerialNumber.get(this);

  /// Retrieves the platform of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its platform. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the platform of the device, or a [bool] indicating if the device could not
  /// be queried.
  Future<String?> platform() => Platform.get(this);

  /// Retrieves the version of the device's platform as a [String].
  ///
  /// This method sends a command to the device to retrieve its platform
  /// version. The device must be connected and authenticated before this
  /// method can be used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the version of the device's platform, or a [bool] indicating if the device
  /// could not be queried.
  Future<dynamic> platformVersion() => Platform.version(this);

  /// Retrieves the name of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its name. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the name of the device, or a [bool] indicating if the device could not
  /// be queried.
  Future<dynamic> getDeviceName() => Device.name(this);

  /// Enables the device.
  ///
  /// This method sends a command to the device to enable it. The device must
  /// be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device was successfully enabled, or a [String] containing an error
  /// message if the device could not be enabled.
  ///
  /// If the device is already enabled, this method does nothing and returns
  /// [true].
  Future<bool> enableDevice() => Device.enable(this);

  /// Disables the device.
  //
  /// This method sends a command to the device to disable it. The device must
  /// be connected and authenticated before this method can be used.
  //
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device was successfully disabled, or a [String] containing an error
  /// message if the device could not be disabled.
  //
  /// If the device is already disabled, this method does nothing and returns
  /// [true].
  Future<bool> disableDevice() => Device.disable(this);

  /// Powers off the device.
  ///
  /// This method sends a command to the device to power it off. The device must
  /// be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device was successfully powered off, or a [String] containing an error
  /// message if the device could not be powered off.
  Future<dynamic> powerOff() => Device.powerOff(this);

  /// Restarts the device.
  ///
  /// This method sends a command to the device to restart it. The device must
  /// be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device was successfully restarted, or a [String] containing an error
  /// message if the device could not be restarted.
  Future<dynamic> restart() => Device.restart(this);

  /// Puts the device into sleep mode.
  ///
  /// This method sends a command to the device to put it into sleep mode. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device was successfully put into sleep mode, or a [String] containing
  /// an error message if the device could not be put into sleep mode.
  Future<dynamic> sleep() => Device.sleep(this);

  /// Resumes the device from sleep mode.
  ///
  /// This method sends a command to the device to resume from sleep mode. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device was successfully resumed from sleep mode, or a [String]
  /// containing an error message if the device could not be queried.
  Future<dynamic> resume() => Device.resume(this);

  /// Tests the voice of the device.
  ///
  /// This method sends a command to the device to test its voice. The device
  /// must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the voice was successfully tested, or a [String] containing an error
  /// message if the device could not be queried.
  Future<dynamic> testVoice() => Device.testVoice(this);

  /// Clears the device's LCD display.
  ///
  /// This method sends a command to the device to clear its LCD display. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device's LCD was successfully cleared, or a [String] containing an
  /// error message if the device could not be queried.
  Future<dynamic> clearDisplay() => Device.clearLCD(this);

  /// Writes a line of text to the device's LCD display.
  ///
  /// This method sends a command to the device to write a line of text to the
  /// LCD display. The device must be connected and authenticated before this
  /// method can be used.
  ///
  /// The [rank] parameter is the line number on the display to write to. The
  /// value of [rank] must be between 0 and 15, inclusive.
  ///
  /// The [text] parameter is the string to write to the display. The string
  /// should not be longer than 16 characters.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device was successfully queried, or a [String] containing an error
  /// message if the device could not be queried.
  Future<dynamic> writeDisplay(int rank, String text) =>
      Device.writeLCD(this, rank, text);

  /// Retrieves the operating system of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its operating
  /// system. The device must be connected and authenticated before this
  /// method can be used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the operating system of the device, or a [bool] indicating if the device
  /// could not be queried.
  Future<String?> getOS() => Os.get(this);

  /// Retrieves the current time of the device as a [DateTime].
  ///
  /// This method sends a command to the device to retrieve its current time.
  /// The device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [DateTime] containing
  /// the current time of the device, or a [bool] indicating if the device
  /// could not be queried.
  Future<DateTime?> getTime() => Time.get(this);

  /// Sets the device's time to the given [DateTime].
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device's time was successfully set, or a [String] containing an error
  /// message if the device could not be queried.
  Future<dynamic> setTime(DateTime time) => Time.set(this, time);

  /// Retrieves the SSR (Silicon Serial Number Register) of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its SSR. The device
  /// must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the SSR of the device, or a [bool] indicating if the device could not be
  /// queried.
  Future<dynamic> getSsr() => Ssr.get(this);

  Future<String?> getWorkcode() => Workcode.get(this);

  /// Retrieves a fingerprint from the device with the given [uid].
  ///
  /// This method sends a command to the device to retrieve a fingerprint. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [Map] containing the
  /// fingerprint data, or a [bool] indicating if the device could not be
  /// queried. The map contains the size of the fingerprint data, and the
  /// fingerprint data itself as a [Uint8List].
  Future<dynamic> getFingerprint(int uid) => Fingerprint.get(this, uid);

  /// Retrieves all users from the device.
  ///
  /// This method sends a command to the device to retrieve all users. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [List] containing all
  /// users, or a [bool] indicating if the device could not be queried. The list
  /// contains [UserInfo] objects, which have the user ID, name, role, password,
  /// and card number. If the user name is empty, the user ID is used instead.
  Future<List<UserInfo>> getUsers() => User.get(this);

  /// Sets a user in the device.
  ///
  /// The method sends a command to the device to set a user. The device must
  /// be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the user was successfully set, or a [String] containing an error message
  /// if the device could not be queried.
  ///
  /// The [name] parameter is the name of the user to set. The string should not
  /// be longer than 24 characters.
  ///
  /// The [uid] parameter is the user ID of the user to set. The user ID must
  /// be between 1 and [Util.USHRT_MAX], inclusive.
  ///
  /// The [userid] parameter is the user ID of the user to set as a string.
  /// The string should not be longer than 9 characters.
  ///
  /// The [password] parameter is the password of the user to set. The string
  /// should not be longer than 8 characters.
  ///
  /// The [cardNo] parameter is the card number of the user to set. The card
  /// number must be between 0 and 10, inclusive. If the card number is not
  /// specified, it defaults to 0.
  ///
  /// The [role] parameter is the role of the user to set. The role must be one
  /// of the following values:
  ///
  /// * [Util.LEVEL_USER]
  /// * [Util.LEVEL_ADMIN]
  ///
  /// If the role is not specified, it defaults to [Util.LEVEL_USER].
  Future<dynamic> setUser({
    required String name,
    required int uid,
    required String userId,
    required String password,
    int cardNo = 0,
    int role = Util.LEVEL_USER,
  }) =>
      User.setUser(this,
          name: name,
          uid: uid,
          userid: userId,
          password: password,
          cardNo: cardNo,
          role: role);

  /// Clears all users from the device.
  ///
  /// This method sends a command to the device to clear all users. The device
  /// must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the users were successfully cleared, or a [String] containing an error
  /// message if the device could not be queried.
  Future<dynamic> clearUsers() => User.clear(this);

  /// Removes a user from the device.
  ///
  /// This method sends a command to the device to remove a user. The device
  /// must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the user was successfully removed, or a [String] containing an error
  /// message if the device could not be queried.
  ///
  /// The [uid] parameter is the user ID of the user to remove. The user ID must
  /// be between 1 and [Util.USHRT_MAX], inclusive.
  Future<dynamic> removeUser(int uid) => User.remove(this, uid);

  /// Clears all administrators from the device.
  ///
  /// This method sends a command to the device to clear all administrators. The
  /// device must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if the
  /// administrators were successfully cleared, or a [String] containing an error
  /// message if the device could not be queried.
  Future<dynamic> clearAdmins() => User.clearAdmin(this);

  /// Retrieves attendance logs from the machine.
  ///
  /// The method returns a [Future] that completes with a [List] of [AttendanceLog]
  /// objects, or a [bool] indicating if the device could not be queried.
  Future<List<AttendanceLog>> getAttendanceLogs() => Attendance.get(this);

  /// Clears all attendance records from the device.
  ///
  /// The method sends a command to the device to clear all attendance records.
  /// The device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device could clear all attendance records, or a [String] containing an
  /// error message if the device could not be queried.
  Future<dynamic> clearAttendance() => Attendance.clear(this);

  /// Disables live capture of attendance records from the device.
  ///
  /// When disabled, the device will no longer send attendance records in
  /// real-time to the Flutter application. The device must be connected and
  /// authenticated before this method can be used.
  Future<bool> cancelLiveCapture() => Attendance.cancelLiveCapture(this);

  /// Verifies the authentication of the device.
  ///
  /// The method sends a command to the device to verify its authentication. The
  /// device must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if the
  /// device was successfully authenticated, or a [String] containing an error
  /// message if the device could not be queried.
  Future<bool> verifyAuthentication() => Connect.verifyAuth(this);

  /// Sends an acknowledgment to the device that the last command was received
  /// successfully.
  ///
  /// This method sends a command to the device to acknowledge that the last
  /// command was successfully received. The device must be connected and
  /// authenticated before this method can be used.
  Future<void> ackOk() => Connect.ackOk(this);

  Stream<AttendanceLog?> get onAttendanceRecordReceived =>
      Attendance.streamLiveCapture(this);
}

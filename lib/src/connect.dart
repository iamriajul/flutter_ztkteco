import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/error/zk_error_connection.dart';
import 'package:flutter_zkteco/src/util.dart';

class Connect {
  /// Connect to the ZKTeco device.
  ///
  /// This function sends a connect command to the device, which responds with
  /// a session ID and a checksum. The session ID is stored in the [ZKTeco]
  /// object, and the checksum is used to verify that the device responded with
  /// valid data. If the device does not respond or the checksum is invalid, this
  /// function returns [false]. Otherwise, it returns [true].
  ///
  /// This function must be called before any other functions in this class can
  /// be used.
  static Future<bool> connect(ZKTeco self, {bool ommitPing = false}) async {
    self.liveCapture = false;

    if (!ommitPing && !(await Util.testPing(self.ip))) {
      throw ZKNetworkError("Can't reach device (ping ${self.ip})");
    }

    if (self.tcp && (await Util.testTcp(self.ip, self.port) == false)) {
      self.userPacketSize = 72;
    }

    await Util.createSocket(self);
    int command = Util.CMD_CONNECT;
    String commandString = '';

    try {
      var response = await self.command(command, commandString);
      self.sessionId = (self.dataRecv[5] << 8) | self.dataRecv[4];

      if (response['code'] == Util.CMD_ACK_UNAUTH) {
        if (self.debug) {
          debugPrint('Try Auth');
        }

        if (self.password == null) {
          throw ZKErrorConnection('Password is null');
        }

        var commandString = Util.makeCommKey(self.password!, self.sessionId);

        response = await self.command(
            Util.CMD_AUTH, String.fromCharCodes(commandString));
      }

      if (response['status']) {
        self.isConnect = true;
        if (self.debug) {
          debugPrint('✅ Connection Success');
        }
        return true;
      } else {
        if (response['code'] == Util.CMD_ACK_UNAUTH) {
          throw ZKErrorConnection("Unauthenticated");
        }
        throw ZKErrorConnection("Invalid response: Can't connect");
      }
    } catch (e) {
      if (self.debug) {
        debugPrint('Connection error: $e.');
      }
      return false;
    }
  }

  /// Disconnect from ZKTeco device
  ///
  /// This function disconnects from the ZKTeco device using the CMD_EXIT command.
  ///
  /// The function takes a [ZKTeco] object as an argument, which should have all
  /// the necessary properties set for connecting to the device (e.g. IP address,
  /// port number, and session ID). The session ID is used to create the header
  /// for the disconnect command.
  ///
  /// If the data received from the device has insufficient data, this function
  /// returns false. Otherwise, it sends the disconnect command to the device and
  /// returns true if the device responds with a valid acknowledgement, and false
  /// if the device does not respond or the acknowledgement is invalid.
  static Future<bool> disconnect(ZKTeco self) async {
    try {
      int command = Util.CMD_EXIT;
      String commandString = '';

      var response = await self.command(command, commandString);

      if (response['status']) {
        self.isConnect = false;

        if (!self.tcp && self.zkClient != null) {
          self.zkClient?.close();
        }

        if (self.tcp && self.zkSocket != null) {
          self.zkSocket?.close();
        }

        self.streamController.close();

        return true;
      } else {
        throw ZKNetworkError("Can't disconnect");
      }
    } catch (e) {
      throw ZKNetworkError("Error during disconnection: $e");
    }
  }

  /// Starts the verification process on the device.
  ///
  /// The device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the verification process was successfully started, or a [String] containing
  /// an error message if the device could not be queried.
  static Future<dynamic> verifyAuth(ZKTeco self) async {
    int command = Util.CMD_STARTVERIFY;
    String commandString = '';

    var session = await self.command(command, commandString,
        type: Util.COMMAND_TYPE_DATA);
    if (session == false) {
      return [];
    }
  }
}

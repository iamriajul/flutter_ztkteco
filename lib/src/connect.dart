import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/error/zk_error_connection.dart';
import 'package:flutter_zkteco/src/finger_bridge.dart';
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

    await resetStreamController(self);

    await FingerBridge.createSocket(self);

    try {
      self.sessionId = 0;
      self.replyId = Util.USHRT_MAX - 1;

      Map<String, dynamic> response = await self.command(Util.CMD_CONNECT);

      self.sessionId = self.header[2];

      if (response['code'] == Util.CMD_ACK_UNAUTH) {
        if (self.debug) {
          debugPrint('Try Auth');
        }

        if (self.password?.isEmpty == true) {
          throw ZKErrorConnection('Password is empty');
        }

        var commandString = Util.makeCommKey(self.password!, self.sessionId);

        response =
            await self.command(Util.CMD_AUTH, commandString: commandString);
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
      final Map<String, dynamic> response = await self.command(Util.CMD_EXIT);

      if (response['status'] == true) {
        self.isConnect = false;

        // Close UDP or TCP
        if (!self.tcp && self.zkClient != null) {
          self.zkClient?.close();
          self.zkClient = null;
        }

        if (self.tcp && self.zkSocket != null) {
          await self.zkSocket?.close();
          self.zkSocket = null;
        }

        // Check and close streamController safely
        if (!self.streamController.isClosed) {
          await self.streamController.close();
        }

        return true;
      } else {
        throw ZKNetworkError("Can't disconnect");
      }
    } catch (e) {
      throw ZKNetworkError("Error during disconnection: $e");
    }
  }

  static Future<void> resetStreamController(ZKTeco self) async {
    if (!self.streamController.isClosed) {
      await self.streamController.close();
    }
    self.streamController = StreamController.broadcast();
  }

  /// Starts the verification process on the device.
  ///
  /// The device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the verification process was successfully started, or a [String] containing
  /// an error message if the device could not be queried.
  static Future<bool> verifyAuth(ZKTeco self) async {
    final Map<String, dynamic> response =
        await self.command(Util.CMD_STARTVERIFY);
    if (response['status'] == true) {
      return true;
    }

    throw ZKNetworkError("Can't verify auth");
  }

  /// Sends an acknowledgment to the device that the last command was received successfully.
  ///
  /// This function creates a header with the [CMD_ACK_OK] command and sends it to the device
  /// using either TCP or UDP, depending on the connection type. If the connection is over TCP,
  /// the header is wrapped in a TCP packet before being sent. If the connection is over UDP,
  /// the header is sent directly to the device's IP and port.
  ///
  /// The method requires an active connection to the device and uses the session ID of the
  /// [ZKTeco] instance to construct the header.
  ///
  /// Throws a [ZKNetworkError] if an error occurs during the acknowledgment process.
  static Future<void> ackOk(ZKTeco self) async {
    try {
      final List<int> buf = Util.createHeader(
        Util.CMD_ACK_OK,
        self.sessionId,
        Util.USHRT_MAX - 1,
        [],
      );

      if (self.tcp) {
        final Uint8List top = Util.createTcpTop(buf);
        self.zkSocket?.add(top);
      } else {
        self.zkClient?.send(buf, InternetAddress(self.ip), self.port);
      }
    } catch (e) {
      throw ZKNetworkError(e.toString());
    }
  }
}

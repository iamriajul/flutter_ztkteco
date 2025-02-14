import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
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
  static Future<bool> connect(ZKTeco self) async {
    int attempt = 0;
    int delayMs = 500; // Start with 500ms delay

    while (attempt < self.retry) {
      attempt++;
      debugPrint('Attempt $attempt to connect...');
      int command = Util.CMD_CONNECT;
      String commandString = '';
      int chksum = 0;
      int sessionId = 0;
      int replyId = -1 + Util.USHRT_MAX;

      List<int> buf =
          Util.createHeader(command, chksum, sessionId, replyId, commandString);
      try {
        // Send data to the socket
        self.zkClient.send(
          buf,
          InternetAddress(self.ip, type: InternetAddressType.IPv4),
          self.port,
        );

        await for (Datagram? dataRecv
            in self.streamController.stream.timeout(self.timeout)) {
          // Access the byte payload from the Datagram object
          if (dataRecv == null || dataRecv.data.length < 8) {
            debugPrint(
                '[Attempt $attempt] Received invalid response. Retrying...');
            break;
          }
          self.dataRecv = dataRecv.data; // Assuming 'data' holds the byte list

          int session =
              (self.dataRecv[5] << 8) | self.dataRecv[4]; // Little-endian

          if (session == 0) {
            debugPrint('Session ID is 0, connection failed.');
            break;
          } else {
            self.sessionId = session;
            if (Util.checkValid(self.dataRecv)) {
              debugPrint('Successfully connected on attempt $attempt.');
              return true;
            } else {
              debugPrint('Invalid response, retrying...');
            }
          }
        }
        return false;
      } catch (e) {
        debugPrint('Connection error: $e. Retrying in ${delayMs}ms...');
      }

      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs *= 2; // Exponential backoff
    }

    debugPrint('Failed to connect after ${self.retry} attempts.');
    return false;
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
    int attempt = 0;
    int delayMs = 500; // Initial delay

    // Ensure dataRecv has enough data before slicing
    if (self.dataRecv.length < 8) {
      debugPrint('Error: dataRecv has insufficient data.');
      return false;
    }

    int command = Util.CMD_EXIT;
    String commandString = '';
    int chksum = 0;
    int sessionId = self.sessionId;

    // Unpack the first 8 bytes
    List<int> unpacked = self.dataRecv.sublist(0, 8);

    // Parse the replyId from the last byte (7th index in zero-based)
    int replyId = unpacked[7];

    List<int> buf =
        Util.createHeader(command, chksum, sessionId, replyId, commandString);

    while (attempt < self.retry) {
      attempt++;
      debugPrint(
          '[Attempt $attempt] Disconnecting from ${self.ip}:${self.port}');

      try {
        // Send data to the socket
        self.zkClient.send(
          buf,
          InternetAddress(self.ip),
          self.port,
        );

        await for (Datagram? dataRecv
            in self.streamController.stream.timeout(self.timeout)) {
          if (dataRecv == null || dataRecv.data.isEmpty) {
            debugPrint('[Attempt $attempt] No response received. Retrying...');
            break;
          }
          self.dataRecv = dataRecv.data;
          self.sessionId = 0;

          if (Util.checkValid(self.dataRecv)) {
            debugPrint('[Attempt $attempt] Successfully disconnected.');
            self.zkClient.close();
            self.streamController.close();
            return true;
          } else {
            debugPrint('[Attempt $attempt] Invalid response. Retrying...');
          }
        }
      } catch (e) {
        debugPrint('[Attempt $attempt] Disconnect error: $e');
      }

      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs *= 2; // Exponential backoff
    }

    debugPrint('❌ Failed to disconnect after ${self.retry} attempts.');
    return false;
  }

  static verifyAuth(ZKTeco self) async {
    int command = Util.CMD_STARTVERIFY;
    String commandString = '';

    var session = await self.command(command, commandString,
        type: Util.COMMAND_TYPE_DATA);
    if (session == false) {
      return [];
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';

class Util {
  static const int USHRT_MAX = 65535;

  static const int CMD_CONNECT = 1000;
  static const int CMD_EXIT = 1001;
  static const int CMD_ENABLE_DEVICE = 1002;
  static const int CMD_DISABLE_DEVICE = 1003;
  static const int CMD_RESTART = 1004;
  static const int CMD_POWEROFF = 1005;
  static const int CMD_SLEEP = 1006;
  static const int CMD_RESUME = 1007;
  static const int CMD_TEST_TEMP = 1011;
  static const int CMD_TESTVOICE = 1017;
  static const int CMD_CHANGE_SPEED = 1101;
  static const int CMD_AUTH = 1102;

  static const int CMD_WRITE_LCD = 66;
  static const int CMD_CLEAR_LCD = 67;

  static const int CMD_ACK_OK = 2000;
  static const int CMD_ACK_ERROR = 2001;
  static const int CMD_ACK_DATA = 2002;
  static const int CMD_ACK_UNAUTH = 2005;

  static const int CMD_PREPARE_DATA = 1500;
  static const int CMD_DATA = 1501;
  static const int CMD_FREE_DATA = 1502;

  static const int CMD_USER_TEMP_RRQ = 9;
  static const int CMD_ATT_LOG_RRQ = 13;
  static const int CMD_CLEAR_DATA = 14;
  static const int CMD_CLEAR_ATT_LOG = 15;

  static const int CMD_GET_TIME = 201;
  static const int CMD_SET_TIME = 202;

  static const int CMD_VERSION = 1100;
  static const int CMD_DEVICE = 11;

  static const int CMD_SET_USER = 8;
  static const int CMD_USER_TEMP_WRQ = 10;
  static const int CMD_DELETE_USER = 18;
  static const int CMD_DELETE_USER_TEMP = 19;
  static const int CMD_CLEAR_ADMIN = 20;

  // Reference https://github.com/fananimi/pyzk/blob/master/zk/const.py#L91
  static const int CMD_REG_EVENT = 500;

  static const int CMD_STARTVERIFY = 60;
  static const int CMD_CANCELCAPTURE = 62;

  static const int EF_ATTLOG = 1;
  static const int EF_FINGER = (1 << 1);
  static const int EF_ENROLLUSER = (1 << 2);
  static const int EF_ENROLLFINGER = (1 << 3);
  static const int EF_BUTTON = (1 << 4);
  static const int EF_UNLOCK = (1 << 5);
  static const int EF_VERIFY = (1 << 7);
  static const int EF_FPFTR = (1 << 8);
  static const int EF_ALARM = (1 << 9);

  static const int LEVEL_USER = 0;
  static const int LEVEL_ADMIN = 14;

  static const int FCT_ATTLOG = 1;
  static const int FCT_WORKCODE = 8;
  static const int FCT_FINGERTMP = 2;
  static const int FCT_OPLOG = 4;
  static const int FCT_USER = 5;
  static const int FCT_SMS = 6;
  static const int FCT_UDATA = 7;

  static const String COMMAND_TYPE_GENERAL = 'general';
  static const String COMMAND_TYPE_DATA = 'data';

  static const int ATT_STATE_FINGERPRINT = 1;
  static const int ATT_STATE_PASSWORD = 0;
  static const int ATT_STATE_CARD = 2;

  static const int ATT_TYPE_CHECK_IN = 0;
  static const int ATT_TYPE_CHECK_OUT = 1;
  static const int ATT_TYPE_OVERTIME_IN = 4;
  static const int ATT_TYPE_OVERTIME_OUT = 5;

  static const int MACHINE_PREPARE_DATA_1 = 20560;
  static const int MACHINE_PREPARE_DATA_2 = 32130;

  /// Encodes a [DateTime] into a [int] that can be sent to the device.
  ///
  /// The [DateTime] is parsed into its constituent parts, then multiplied
  /// and added together to produce a single [int] that can be sent to the
  /// device.
  ///
  /// The formula used is:
  ///
  ///   (((year % 100) * 12 * 31 + ((month - 1) * 31) + day - 1) *
  ///    (24 * 60 * 60)) +
  ///   ((hour * 60 + minute) * 60) +
  ///   second
  ///
  /// This method returns the [int] that can be sent to the device.
  static int encodeTime(DateTime dateTime) {
    // Extract year, month, day, hour, minute, second from DateTime
    int year = dateTime.year;
    int month = dateTime.month;
    int day = dateTime.day;
    int hour = dateTime.hour;
    int minute = dateTime.minute;
    int second = dateTime.second;

    // Calculate the number of days since the start of the century
    int daysSinceEpoch =
        ((year % 100) * 12 * 31 + ((month - 1) * 31) + (day - 1)) *
            (24 * 60 * 60);

    // Calculate the number of seconds in the current day
    int secondsInDay = (hour * 60 + minute) * 60 + second;

    // Total seconds since the start of the century
    return daysSinceEpoch + secondsInDay;
  }

  /// Decodes a [int] received from the device into a [DateTime].
  ///
  /// The [int] is parsed into its constituent parts, then converted into a
  /// [DateTime] object. The formula used is:
  ///
  ///   year = t ~/ 12 + 2000
  ///   month = t % 12 + 1
  ///   day = t % 31 + 1
  ///   hour = t % 24
  ///   minute = t % 60
  ///   second = t % 60
  ///
  /// This method returns a [String] containing the [DateTime] in ISO8601 format.
  static String decodeTime(int t) {
    int second = t % 60;
    t = t ~/ 60;

    int minute = t % 60;
    t = t ~/ 60;

    int hour = t % 24;
    t = t ~/ 24;

    int day = t % 31 + 1;
    t = t ~/ 31;

    int month = t % 12 + 1;
    t = t ~/ 12;

    int year = t + 2000;

    return DateTime(year, month, day, hour, minute, second).toIso8601String();
  }

  /// Converts a [Uint8List] of bytes into a hexadecimal string.
  ///
  /// Each byte is converted to a hexadecimal string using [int.toRadixString]
  /// with radix 16, and then padded with leading zeros to a length of 2
  /// characters. The resulting strings are then joined together into a single
  /// string with no separator. For example, if [bytes] is `Uint8List.fromList([1, 2, 3, 4])`,
  /// this method returns `"01020304"`.
  static String bin2hex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Reverses a hexadecimal string by swapping each pair of characters.
  ///
  /// This method takes a string of hexadecimal digits and returns a new string
  /// with the same digits, but in reverse order. For example, if [hex] is
  /// "001122334455", this method returns "554433221100".
  ///
  /// The method is used to reverse the byte order of data received from the
  /// device, as the device sends data in little-endian order, but Dart's
  /// [ByteData] class stores data in big-endian order.
  static String reverseHex(String hex) {
    StringBuffer sb = StringBuffer();
    for (int i = hex.length; i > 0; i -= 2) {
      String value = hex.substring(i - 2, i);
      sb.write(value);
    }
    return sb.toString();
  }

  /// Returns the size of the data to be sent to the device as an [int], or
  /// [null] if the device has not sent enough data to be unpacked.
  ///
  /// This method unpacks the first 8 bytes of [dataRecv] to get the command
  /// and checks if it is equal to [CMD_PREPARE_DATA]. If it is, it then
  /// unpacks the next 4 bytes to get the size of the data to be sent to the
  /// device. If the command is not equal to [CMD_PREPARE_DATA], this method
  /// returns [null].
  static int? getSize(ZKTeco self) {
    // Ensure dataRecv has at least 8 bytes
    if (self.dataRecv.length < 8) {
      return null;
    }

    // Extract the first 8 bytes and convert to hex
    int command = (self.dataRecv[1] << 8) | self.dataRecv[0];

    if (self.debug) {
      debugPrint('Command extracted: $command');
    }

    // Unpack the first 8 bytes
    // ByteData byteData =
    //     ByteData.sublistView(Uint8List.fromList(self.dataRecv.sublist(0, 8)));
    // int command = byteData.getUint16(0, Endian.little);

    if (command == CMD_PREPARE_DATA) {
      // Ensure dataRecv has at least 12 bytes
      if (self.dataRecv.length < 12) return null;

      // Extract the next 4 bytes
      int size = (self.dataRecv[11] << 24) |
          (self.dataRecv[10] << 16) |
          (self.dataRecv[9] << 8) |
          self.dataRecv[8];

      if (self.debug) {
        debugPrint('Extracted size: $size');
      }

      return size;
    } else {
      if (self.debug) {
        debugPrint('Unexpected command: $command');
      }
      return null;
    }
  }

  /// Calculates a checksum of the provided data.
  ///
  /// The method is based on the algorithm used by the ZKTeco devices to
  /// calculate checksums. It processes the data in chunks of 2 bytes, and
  /// handles overflow and signed-ness of the checksum. The method returns a
  /// [Uint8List] containing the checksum as a 2-byte, little-endian, unsigned
  /// integer.
  static Uint8List createChkSum(List<int> packet) {
    int l = packet.length;
    int chksum = 0;
    int i = l;
    int j = 0;

    while (i > 1) {
      // Equivalent to unpacking 2 bytes ('S' in PHP)
      int u = (packet[j] & 0xFF) | ((packet[j + 1] & 0xFF) << 8);
      chksum += u;

      // Handle overflow (equivalent to `USHRT_MAX` in PHP)
      if (chksum > 0xFFFF) {
        chksum -= 0xFFFF;
      }

      i -= 2;
      j += 2;
    }

    // If there's an odd byte, add it to the checksum
    if (i > 0) {
      chksum += (packet[l - 1] & 0xFF);
    }

    // Reduce checksum in case of overflow
    while (chksum > 0xFFFF) {
      chksum -= 0xFFFF;
    }

    // Handle signed-ness of checksum (negate if positive)
    if (chksum > 0) {
      chksum = -chksum;
    } else {
      chksum = chksum.abs();
    }

    chksum -= 1;

    // Make sure the checksum is positive and fits within the range
    while (chksum < 0) {
      chksum += 0xFFFF;
    }

    // Return packed checksum (2 bytes)
    ByteData byteData = ByteData(2);
    byteData.setUint16(0, chksum, Endian.little);
    return byteData.buffer.asUint8List();
  }

  /// Creates a header for a command to send to the device.
  ///
  /// The [command] parameter is the command to send to the device.
  ///
  /// The [chksum] parameter is the initial checksum value.
  ///
  /// The [sessionId] parameter is the session ID to send with the command.
  ///
  /// The [replyId] parameter is the reply ID to send with the command.
  ///
  /// The [commandString] parameter is the string to include with the command.
  ///
  /// The method returns a [Uint8List] containing the header, with the
  /// checksum updated and the reply ID incremented.
  static List<int> createHeader(
      int command, int sessionId, int replyId, String commandString) {
    // Create ByteData to pack header fields
    ByteData byteData = ByteData(8);
    byteData.setUint16(0, command, Endian.little);
    byteData.setUint16(2, 0, Endian.little);
    byteData.setUint16(4, sessionId, Endian.little);
    byteData.setUint16(6, replyId, Endian.little);

    // Convert ByteData to Uint8List
    Uint8List buf = byteData.buffer.asUint8List();

    Uint8List commandStringBytes = Uint8List.fromList(commandString.codeUnits);

    // Append the command string
    buf = Uint8List.fromList(buf + commandStringBytes);

    // Calculate checksum
    Uint8List checksum = createChkSum(buf);

    // Update the checksum in the buffer
    ByteData updatedByteData = ByteData.view(buf.buffer);
    updatedByteData.setUint16(
        2, (checksum[0] | (checksum[1] << 8)), Endian.little);

    // Increment replyId
    replyId += 1;
    if (replyId >= USHRT_MAX) {
      replyId -= USHRT_MAX;
    }

    // Update replyId in the buffer
    updatedByteData.setUint16(6, replyId, Endian.little);

    return updatedByteData.buffer.asUint8List();
  }

  /// Creates a communication key based on the given key and session ID.
  ///
  /// The [key] parameter is the key to scramble. The [sessionId] parameter is the
  /// session ID to add to the key. The [ticks] parameter is the number of ticks
  /// to use for the XOR operation. The default is 50.
  ///
  /// The method returns a [Uint8List] containing the communication key.
  static Uint8List makeCommKey(int key, int sessionId, {int ticks = 50}) {
    int k = 0;

    // Iterate 32 times to scramble the key
    for (int i = 0; i < 32; i++) {
      if ((key & (1 << i)) != 0) {
        k = (k << 1) | 1;
      } else {
        k = k << 1;
      }
    }

    k += sessionId;

    // Pack and unpack for byte manipulation
    ByteData byteData = ByteData(4);
    byteData.setInt32(0, k, Endian.little);
    List<int> kBytes = byteData.buffer.asUint8List();

    // XOR operation with 'Z', 'K', 'S', 'O'
    kBytes[0] ^= 'Z'.codeUnitAt(0);
    kBytes[1] ^= 'K'.codeUnitAt(0);
    kBytes[2] ^= 'S'.codeUnitAt(0);
    kBytes[3] ^= 'O'.codeUnitAt(0);

    // Swap the first two bytes with the last two
    int temp = kBytes[0];
    kBytes[0] = kBytes[1];
    kBytes[1] = temp;

    // XOR with ticks value
    int B = 0xff & ticks;
    kBytes[0] ^= B;
    kBytes[1] ^= B;
    kBytes[2] = B;
    kBytes[3] ^= B;

    return Uint8List.fromList(kBytes);
  }

  /// Checks if the response from the device is valid.
  ///
  /// The method takes a [Uint8List] as input, which should be the response
  /// from the device. The method returns [true] if the response is valid and
  /// [false] otherwise.
  ///
  /// A valid response is one in which the first byte is either [CMD_ACK_OK]
  /// or [CMD_ACK_UNAUTH].
  static bool checkValid(List<int> reply) {
    String h1 = reply
        .sublist(0, 1)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    String h2 = reply
        .sublist(1, 2)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    // Combine the hex values into a command
    int command = int.parse(h2 + h1, radix: 16);

    // Compare the command with CMD_ACK_OK and CMD_ACK_UNAUTH
    if (command == CMD_ACK_OK || command == CMD_ACK_UNAUTH) {
      return true;
    } else {
      return false;
    }
  }

  /// Converts a user role to a string.
  ///
  /// The method takes a [int] as input, which should be one of the
  /// following values:
  ///
  /// * [LEVEL_USER]
  /// * [LEVEL_ADMIN]
  ///
  /// The method returns a [String] containing one of the following values:
  ///
  /// * 'User'
  /// * 'Admin'
  /// * 'Unknown'
  static String getUserRole(int role) {
    switch (role) {
      case LEVEL_USER:
        return 'User';
      case LEVEL_ADMIN:
        return 'Admin';
      default:
        return 'Unknown';
    }
  }

  /// Converts an attendance state to a string.
  ///
  /// The method takes a [int] as input, which should be one of the
  /// following values:
  ///
  /// * [ATT_STATE_FINGERPRINT]
  /// * [ATT_STATE_PASSWORD]
  /// * [ATT_STATE_CARD]
  ///
  /// The method returns a [String] containing one of the following values:
  ///
  /// * 'Fingerprint'
  /// * 'Password'
  /// * 'Card'
  /// * 'Unknown'
  static String getAttState(int state) {
    switch (state) {
      case ATT_STATE_FINGERPRINT:
        return 'Fingerprint';
      case ATT_STATE_PASSWORD:
        return 'Password';
      case ATT_STATE_CARD:
        return 'Card';
      default:
        return 'Unknown';
    }
  }

  /// Converts an attendance type to a string.
  ///
  /// The method takes a [int] as input, which should be one of the
  /// following values:
  ///
  /// * [ATT_TYPE_CHECK_IN]
  /// * [ATT_TYPE_CHECK_OUT]
  /// * [ATT_TYPE_OVERTIME_IN]
  /// * [ATT_TYPE_OVERTIME_OUT]
  ///
  /// The method returns a [String] containing one of the following values:
  ///
  /// * 'Check-in'
  /// * 'Check-out'
  /// * 'Overtime-in'
  /// * 'Overtime-out'
  /// * 'Undefined'
  static String getAttType(int type) {
    switch (type) {
      case ATT_TYPE_CHECK_IN:
        return 'Check-in';
      case ATT_TYPE_CHECK_OUT:
        return 'Check-out';
      case ATT_TYPE_OVERTIME_IN:
        return 'Overtime-in';
      case ATT_TYPE_OVERTIME_OUT:
        return 'Overtime-out';
      default:
        return 'Undefined';
    }
  }

  /// Receives data from the device.
  ///
  /// The method sends a command to the device to receive data. The device
  /// must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [Uint8List] containing
  /// the received data, or [null] if no data was received or if the device
  /// could not be queried.
  ///
  /// The [first] parameter is a [bool] indicating if this is the first time
  /// this method is called for the current command. If [first] is [true],
  /// the method sends a command to the device to receive data. If [first] is
  /// [false], the method does not send a command to the device and instead
  /// waits for the device to send data. The default value of [first] is
  /// [true].
  static Future<Uint8List?> recData(ZKTeco self, {bool first = true}) async {
    int attempt = 0;
    int delayMs = 500; // 0.5 seconds delay
    List<Uint8List> packetBuffer = [];

    while (attempt < self.retry) {
      attempt++;
      if (self.debug) {
        debugPrint('Attempt $attempt to receive data...');
      }
      int? bytes = getSize(self);

      if (bytes == null || bytes <= 0) {
        if (self.debug) {
          debugPrint(
              '❌ getSize(self) returned an invalid size: $bytes. Retrying...');
        }
        await Future.delayed(Duration(milliseconds: delayMs));
        delayMs *= 2; // Double delay each retry (exponential backoff)
        continue;
      }

      if (self.debug) {
        debugPrint('📦 Expected packet size: $bytes bytes');
      }

      try {
        Uint8List data = await _parseData(self, bytes, first);
        if (data.isNotEmpty) {
          packetBuffer.add(data);
          if (self.debug) {
            debugPrint(
                'Received packet ${packetBuffer.length}, size: ${data.length}');
          }
          break;
        } else {
          if (self.debug) {
            debugPrint('Received an empty packet, retrying...');
          }
        }
      } catch (e) {
        if (self.debug) {
          debugPrint('Error receiving data: $e. Retrying in ${delayMs}ms...');
        }
      }

      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs *= 2; // Increase delay before next retry
    }

    if (packetBuffer.isEmpty) {
      if (self.debug) {
        debugPrint(
            '❌ Failed to receive valid data after ${self.retry} attempts.');
      }
      return null;
    }

    Uint8List fullData =
        Uint8List.fromList(packetBuffer.expand((x) => x).toList());

    if (self.debug) {
      debugPrint(
          '✅ Successfully reconstructed ${fullData.length} bytes of data.');
    }
    return fullData;
  }

  /// Parses the received data from the device.
  ///
  /// The method takes a [ZKTeco] object, the number of bytes to receive, and
  /// a [bool] indicating if this is the first time this method is called for
  /// the current command as parameters. If [first] is [true], the method
  /// expects the first 8 bytes of the received data to be a header, and
  /// skips the header. If [first] is [false], the method does not skip the
  /// header.
  ///
  /// The method returns a [Future] that completes with a [Uint8List]
  /// containing the received data. The [Future] completes when all expected
  /// data has been received, or when the device stops sending data. If the
  /// device stops sending data before all expected data has been received,
  /// the [Future] completes with the data that has been received so far.
  static Future<Uint8List> _parseData(
      ZKTeco self, int bytes, bool first) async {
    BytesBuilder data = BytesBuilder();
    int received = 0;

    // Choose stream depending on connection type
    Stream<dynamic> stream;
    if (self.tcp) {
      stream = self.streamController.stream.timeout(self.timeout);
    } else {
      stream = self.streamController.stream
          .timeout(self.timeout)
          .map((datagram) => datagram.data);
    }

    await for (var bytesData in stream) {
      if (first && self.tcp) {
        // Skip the first 8 bytes
        bytesData = Uint8List.sublistView(bytesData, 8);
      }

      data.add(bytesData);
      received += bytesData.length as int;
      first = false;

      if (self.debug) {
        Util.logReceived(received, bytes);
      }

      if (received >= bytes) {
        break; // End the loop
      }
    }

    return data.takeBytes();
  }

  /// Prints a debug message indicating how many bytes have been received so
  /// far, out of the total number of bytes expected.
  ///
  /// The method takes a [ZKTeco] object, the number of bytes received so far,
  /// and the total number of bytes expected as parameters. The method
  /// prints a message to the console in the format "Received $received bytes
  /// out of $total bytes".
  static void logReceived(int received, int total) {
    debugPrint('Received $received bytes out of $total bytes');
  }

  /// Converts a hexadecimal string to a [Uint8List] of bytes.
  ///
  /// The method takes a [String] as input, which must have an even length.
  /// The method throws an [ArgumentError] if the input string has an odd
  /// length. The method returns a [Uint8List] containing the bytes equivalent
  /// to the input hexadecimal string.
  static Uint8List hex2bin(String hex) {
    if (hex.length % 2 != 0) {
      throw ArgumentError("Hex string must have an even length.");
    }

    // Convert hex string to bytes
    Uint8List bytes = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }

    return bytes;
  }

  /// Converts a [Uint8List] of bytes to a hexadecimal string.
  ///
  /// The method takes a [Uint8List] as input and returns a string in which
  /// each byte is converted to a 2-character hexadecimal string using
  /// [int.toRadixString] with radix 16, and then padded with leading zeros
  /// to a length of 2 characters. The resulting strings are then joined
  /// together into a single string with no separator. For example, if
  /// [bytes] is `Uint8List.fromList([1, 2, 3, 4])`, this method returns
  /// `"01020304"`.
  static String byteToHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Extracts a UTF-8 encoded string from a hexadecimal string.
  ///
  /// The method takes a [hexString] and extracts a substring from the given
  /// [start] index to the [end] index, then converts it into binary data.
  /// The binary data is decoded using UTF-8, allowing malformed sequences,
  /// and the result is split at the first null character (`\x00`). The
  /// leading and trailing whitespace is removed from the resulting string,
  /// which is then returned.

  static String? extractString(String hexString, int start, int end) {
    // Ensure that the end doesn't exceed the length of the string
    end = end > hexString.length ? hexString.length : end;

    Uint8List binaryData = Util.hex2bin(hexString.substring(start, end));

    String decodedString =
        utf8.decode(binaryData, allowMalformed: true).split('\x00')[0].trim();

    // If decodedString is empty, return a default or handle accordingly
    return decodedString.isNotEmpty ? decodedString : null;
  }

  /// Creates a TCP packet with a header and appends the given data.
  ///
  /// The method constructs a TCP packet header consisting of two predefined
  /// machine data identifiers and the length of the packet data. It then
  /// appends the provided [packet] data to this header.
  ///
  /// The header is an 8-byte structure where:
  /// - The first 2 bytes represent [MACHINE_PREPARE_DATA_1].
  /// - The next 2 bytes represent [MACHINE_PREPARE_DATA_2].
  /// - The last 4 bytes represent the length of the [packet] in little-endian
  ///   format.
  ///
  /// Returns a [Uint8List] containing the header followed by the original
  /// packet data.

  static Uint8List createTcpTop(List<int> packet) {
    int length = packet.length;
    ByteData header = ByteData(8);
    header.setUint16(0, MACHINE_PREPARE_DATA_1, Endian.little);
    header.setUint16(2, MACHINE_PREPARE_DATA_2, Endian.little);
    header.setUint32(4, length, Endian.little);

    return Uint8List.fromList(header.buffer.asUint8List() + packet);
  }

  /// Tests the TCP packet header and extracts the data size.
  ///
  /// The method takes a [List<int>] representing a packet and checks if the
  /// packet's length is greater than 8. If not, it returns 0. It then reads
  /// the first 8 bytes of the packet as a [ByteData] view to extract two
  /// headers and a size. If the headers match [MACHINE_PREPARE_DATA_1] and
  /// [MACHINE_PREPARE_DATA_2], it returns the size. Otherwise, it returns 0.

  static int testTcpTop(List<int> packet) {
    if (packet.length <= 8) {
      return 0;
    }

    ByteData data = ByteData.sublistView(Uint8List.fromList(packet), 0, 8);
    int header1 = data.getUint16(0, Endian.little);
    int header2 = data.getUint16(2, Endian.little);
    int size = data.getUint32(4, Endian.little);

    if (header1 == MACHINE_PREPARE_DATA_1 &&
        header2 == MACHINE_PREPARE_DATA_2) {
      return size;
    }

    return 0;
  }

  /// Tests if a device is reachable by pinging it.
  ///
  /// The method takes an IP address as input and returns a [Future] that
  /// completes with [true] if the device was reachable and [false] otherwise.
  ///
  /// The method uses the `ping` command to send a single packet to the
  /// device. The device is considered reachable if the command returns an
  /// exit code of 0. If the command fails or returns a non-zero exit code,
  /// the device is considered unreachable.
  ///
  /// The method uses the Windows version of the `ping` command on Windows
  /// and the Unix version on other platforms.
  static Future<bool> testPing(String ip) async {
    List<String> args;
    bool useShell = false;

    if (Platform.isWindows) {
      args = ['-n', '1', ip];
    } else {
      args = ['-c', '1', '-W', '5', ip];
      useShell = true;
    }

    try {
      ProcessResult result =
          await Process.run('ping', args, runInShell: useShell);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Tests if a TCP connection can be established to [ip] on port [port].
  ///
  /// The method attempts to create a TCP socket connection to the device at
  /// [ip] on port [port]. If the connection is established within 10
  /// seconds, the method returns [true]. If the connection attempt fails or
  /// takes longer than 10 seconds, the method returns [false].
  static Future<bool> testTcp(String ip, int port) async {
    Socket? client;
    try {
      client =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 10));
      client.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Creates a socket connection to the ZKTeco device.
  ///
  /// If the device is set to use TCP, the method creates a TCP socket
  /// connection to the device. If the device is set to use UDP, the method
  /// creates a UDP socket connection to the device. The method takes a
  /// [ZKTeco] object as input and returns a [Future] that completes with a
  /// [void] when the connection is established.
  static Future<void> createSocket(ZKTeco self) async {
    if (self.tcp) {
      self.zkSocket =
          await Socket.connect(self.ip, self.port, timeout: self.timeout);
      self.zkSocket?.encoding = utf8;
      if (self.debug) {
        debugPrint('✅ TCP Socket Initialized on Port ${self.zkSocket?.port}');
      }

      self.zkSocket?.listen((Uint8List data) {
        self.streamController.add(data);
      });
    } else {
      self.zkClient = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (self.debug) {
        debugPrint('✅ UDP Socket Initialized on Port ${self.zkClient?.port}');
      }

      self.zkClient?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = self.zkClient?.receive();
          if (datagram != null) {
            self.streamController.add(datagram);
          }
        }
      });
    }
  }
}

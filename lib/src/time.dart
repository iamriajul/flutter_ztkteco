import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/util.dart';

class Time {
  /// Sets the device's time to the given [DateTime].
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device's time was successfully set, or a [String] containing an error
  /// message if the device could not be queried.
  static dynamic set(ZKTeco self, DateTime $date) async {
    int command = Util.CMD_SET_TIME;
    try {
      int encodedTime = Util.encodeTime($date);

      // Convert encoded time into Uint8List in little-endian format
      Uint8List commandBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, encodedTime, Endian.little);

      // Send command and wait for reply
      dynamic reply =
          await self.command(command, String.fromCharCodes(commandBytes));

      if (reply is bool) {
        return reply;
      }

      return String.fromCharCodes(reply);
    } catch (e, stackTrace) {
      debugPrint('❌ Error setting time: $e');
      debugPrint(stackTrace.toString());
      return false;
    }
  }

  /// Returns the current time of the device as a [String] in the format
  /// "HH:MM:SS DD/MM/YYYY".
  ///
  /// This method sends a command to the device to retrieve its current time.
  /// The device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the current time of the device, or a [bool] indicating if the device
  /// could not be queried.
  static dynamic get(ZKTeco self) async {
    int command = Util.CMD_GET_TIME;
    try {
      dynamic reply = await self.command(command, '');

      if (reply is bool) {
        return reply; // Return early if the command failed
      }

      // Convert binary response to time
      Uint8List reverseHexBytes =
          Util.hex2bin(Util.reverseHex(Util.bin2hex(reply)));

      if (reverseHexBytes.length < 4) {
        debugPrint('❌ Invalid time data received');
        return false;
      }

      int time = reverseHexBytes.buffer.asByteData().getUint32(0, Endian.big);
      return Util.decodeTime(time);
    } catch (e, stackTrace) {
      debugPrint('❌ Error getting time: $e');
      debugPrint(stackTrace.toString());
      return false;
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/util.dart';

class Time {
  /// Sets the device's time to the given [DateTime].
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the device's time was successfully set, or a [String] containing an error
  /// message if the device could not be queried.
  static Future<String?> set(ZKTeco self, DateTime $date) async {
    int command = Util.CMD_SET_TIME;
    try {
      int encodedTime = Util.encodeTime($date);

      // Convert encoded time into Uint8List in little-endian format
      Uint8List commandBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, encodedTime, Endian.little);

      // Send command and wait for reply
      var resp =
          await self.command(command, String.fromCharCodes(commandBytes));

      if (resp['status'] == false) {
        return null;
      }

      return String.fromCharCodes(self.dataRecv);
    } catch (e, stackTrace) {
      if (self.debug) {
        debugPrint('❌ Error setting time: $e');
        debugPrint(stackTrace.toString());
      }
      return null;
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
  static Future<String?> get(ZKTeco self) async {
    int command = Util.CMD_GET_TIME;
    try {
      await self.command(command, '');

      // Convert binary response to time
      Uint8List reverseHexBytes = Util.hex2bin(
          Util.reverseHex(Util.bin2hex(Uint8List.fromList(self.dataRecv))));

      if (reverseHexBytes.length < 4) {
        if (self.debug) {
          debugPrint('❌ Invalid time data received');
        }
        return null;
      }

      int time = reverseHexBytes.buffer.asByteData().getUint32(0, Endian.big);
      return Util.decodeTime(time);
    } catch (e, stackTrace) {
      if (self.debug) {
        debugPrint('❌ Error getting time: $e');
        debugPrint(stackTrace.toString());
      }
      return null;
    }
  }
}

import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/util.dart';

class Platform {
  /// Returns the platform of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its platform. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the platform of the device, or a [bool] indicating if the device could
  /// not be queried.
  static Future<String?> get(ZKTeco self) async {
    int command = Util.CMD_DEVICE;
    String commandString = '~Platform';

    var resp = await self.command(command, commandString);

    if (resp['status'] == false) {
      return null;
    }

    return String.fromCharCodes(self.dataRecv.sublist(8, 28));
  }

  /// Returns the version of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its version. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the version of the device, or a [bool] indicating if the device could not
  /// be queried.
  static Future<dynamic> version(ZKTeco self) async {
    int command = Util.CMD_DEVICE;
    String commandString = '~ZKFPVersion';

    await self.command(command, commandString);

    return String.fromCharCodes(self.dataRecv.sublist(8, 23));
  }
}

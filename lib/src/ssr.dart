import 'dart:convert';

import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/util.dart';

class Ssr {
  /// Returns the SSR (Silicon Serial Number Register) of the device as a [String].
  ///
  /// This method sends a command to the device to retrieve its SSR. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [String] containing
  /// the SSR of the device, or a [bool] indicating if the device could not be
  /// queried.
  static Future<dynamic> get(ZKTeco self) async {
    int command = Util.CMD_DEVICE;
    String commandString = '~SSR';

    await self.command(command, commandString: utf8.encode(commandString));

    return String.fromCharCodes(self.dataRecv);
  }
}

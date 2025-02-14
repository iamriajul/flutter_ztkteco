import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/util.dart';

class User {
  /// Retrieves all users from the device.
  ///
  /// This method sends a command to the device to retrieve all users. The
  /// device must be connected and authenticated before this method can be
  /// used.
  ///
  /// The method returns a [Future] that completes with a [Map] containing all
  /// users, or a [bool] indicating if the device could not be queried. The
  /// map has the user ID as the key, and the value is another [Map] containing
  /// the user ID, name, role, password, and card number. If the user name is
  /// empty, the user ID is used instead.
  static Future<List<UserInfo>> get(ZKTeco self) async {
    try {
      int command = Util.CMD_USER_TEMP_RRQ;
      String commandString = String.fromCharCode(Util.FCT_USER);

      dynamic session = await self.command(command, commandString,
          type: Util.COMMAND_TYPE_DATA);

      if (session == false) {
        return [];
      }
      Uint8List? userData = await Util.recData(self, first: true);

      if (userData == null || userData.length <= 11) {
        debugPrint('⚠️ No user data received.');
        return [];
      }

      List<UserInfo> users = [];
      Uint8List user = userData.sublist(11);
      int chunkSize = 72;

      while (user.length >= chunkSize) {
        String u =
            Util.byteToHex(Uint8List.fromList(user.sublist(0, chunkSize)));
        int? u1 = int.tryParse(u.substring(2, 4), radix: 16);
        int? u2 = int.tryParse(u.substring(4, 6), radix: 16);
        int? uid = (u1 != null && u2 != null) ? u1 + (u2 * 256) : null;

        int? cardNo = int.tryParse(
          u.substring(78, 80) +
              u.substring(76, 78) +
              u.substring(74, 76) +
              u.substring(72, 74),
          radix: 16,
        );

        int role = int.tryParse(u.substring(6, 8), radix: 16) ?? 0;

        String password = Util.extractString(u, 8, 24);
        String name = Util.extractString(u, 24, 74);
        String userId = Util.extractString(u, 98, 144);

        name = name.isNotEmpty ? name : userId;

        final Map<String, dynamic> data = {
          'uid': uid,
          'userid': userId,
          'name': name,
          'role': role,
          'password': password,
          'cardno': cardNo,
        };

        users.add(UserInfo.fromJson(data));

        user = user.sublist(chunkSize);
      }
      debugPrint('✅ Successfully retrieved ${users.length} users.');
      return users;
    } catch (e, stackTrace) {
      debugPrint('❌ Error retrieving users: $e');
      debugPrint(stackTrace.toString());
      return [];
    }
  }

  /// Sets a user in the device.
  ///
  /// This method sends a command to the device to set a user. The device must
  /// be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the user was successfully set, or a [String] containing an error message
  /// if the device could not be queried.
  ///
  /// The [uid] parameter is the user ID of the user to set. The user ID must
  /// be between 1 and [Util.USHRT_MAX], inclusive.
  ///
  /// The [userid] parameter is the user ID of the user to set as a string.
  /// The string should not be longer than 9 characters.
  ///
  /// The [name] parameter is the name of the user to set. The string should not
  /// be longer than 24 characters.
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
  static Future<dynamic> setUser(
    ZKTeco self, {
    required int uid,
    required String userid,
    required String name,
    required String password,
    int cardNo = 0,
    int role = Util.LEVEL_USER,
  }) async {
    // Validate input parameters
    if (_isInvalidUserInput(uid, userid, name, password, cardNo)) {
      debugPrint('❌ Invalid user input. Check constraints.');
      return false;
    }

    int command = Util.CMD_SET_USER;

    // Convert UID to bytes (low and high parts)
    String byte1 = String.fromCharCode((uid % 0xff));
    String byte2 = String.fromCharCode((uid >> 8) & 0xff);

    // Convert card number to binary string
    String cardno = String.fromCharCodes(
        Util.hex2bin(Util.reverseHex(cardNo.toRadixString(16))));

    String roleUser = String.fromCharCode(role);

    String commandString = byte1 +
        byte2 +
        roleUser +
        password.padRight(8, '\x00') +
        name.padRight(24, '\x00') +
        cardno.padRight(4, '\x00') +
        String.fromCharCode(1).padRight(9, '\x00') +
        userid.padRight(9, '\x00') +
        ''.padRight(15, '\x00');

    try {
      dynamic response = await self.command(command, commandString);
      if (response == false) {
        debugPrint('❌ Failed to set user.');
        return false;
      }

      debugPrint('✅ User set successfully: $userid');
      return response;
    } catch (e, stackTrace) {
      debugPrint('❌ Error setting user: $e');
      debugPrint(stackTrace.toString());
      return false;
    }
  }

  static bool _isInvalidUserInput(
      int uid, String userid, String name, String password, int cardNo) {
    return uid == 0 ||
        uid > Util.USHRT_MAX ||
        userid.length > 9 ||
        name.length > 24 ||
        password.length > 8 ||
        cardNo > 10;
  }

  /// Clears a user from the device.
  ///
  /// This method sends a command to the device to clear a user. The device must
  /// be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the user was successfully cleared, or a [String] containing an error
  /// message if the device could not be queried.
  static Future<dynamic> clear(ZKTeco self) async {
    int command = Util.CMD_CLEAR_DATA;
    String commandString = '';

    return await self.command(command, commandString);
  }

  /// Clears an administrator from the device.
  ///
  /// This method sends a command to the device to clear an administrator. The
  /// device must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the administrator was successfully cleared, or a [String] containing an
  /// error message if the device could not be queried.
  static Future<dynamic> clearAdmin(ZKTeco self) async {
    int command = Util.CMD_CLEAR_ADMIN;
    String commandString = '';

    return await self.command(command, commandString);
  }

  /// Removes a user from the device.
  ///
  /// This method sends a command to the device to remove a user. The device must
  /// be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the user was successfully removed, or a [String] containing an error
  /// message if the device could not be queried.
  ///
  /// The [uid] parameter is the user ID of the user to remove. The user ID must
  /// be between 1 and [Util.USHRT_MAX], inclusive.
  static Future<dynamic> remove(ZKTeco self, int uid) async {
    if (uid <= 0 || uid > Util.USHRT_MAX) {
      debugPrint('❌ Invalid UID: $uid');
      return false;
    }

    int command = Util.CMD_DELETE_USER;

    // Convert UID to byte representation
    String commandString = String.fromCharCode(uid & 0xFF) +
        String.fromCharCode((uid >> 8) & 0xFF);

    try {
      dynamic response = await self.command(command, commandString);

      if (response == false) {
        debugPrint('❌ Failed to remove user: UID $uid');
        return false;
      }

      debugPrint('✅ User removed successfully: UID $uid');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error removing user: $e');
      debugPrint(stackTrace.toString());
      return false;
    }
  }
}

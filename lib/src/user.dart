import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/finger_bridge.dart';
import 'package:flutter_zkteco/src/model/memory_reader.dart';
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
    // try {
    MemoryReader? sizes = await Util.readSizes(self);

    if (sizes?.users == 0) {
      self.nextUid = 1;
      self.nextUserId = '1';
      return [];
    }

    List<UserInfo> users = [];
    int maxUid = 0;

    final results = await FingerBridge.readWithBuffer(
        self, Util.CMD_USER_TEMP_RRQ,
        fct: Util.FCT_USER);

    final Uint8List userData = results.data;
    final int size = results.size;

    if (self.debug) debugPrint("user size $size (= ${userData.length})");

    if (size <= 4) {
      debugPrint("WRN: missing user data");
      return [];
    }

    final totalSize =
        ByteData.sublistView(userData, 0, 4).getUint32(0, Endian.little);
    final int userPacketSize = (totalSize / sizes!.users!).round();
    self.userPacketSize = userPacketSize;

    if (![28, 72].contains(userPacketSize)) {
      if (self.debug) debugPrint("WRN packet size would be $userPacketSize");
    }

    Uint8List data = userData.sublist(4);

    while (data.length >= userPacketSize) {
      if (userPacketSize == 28) {
        final bd =
            ByteData.sublistView(data.sublist(0, 28).buffer.asUint8List());

        int uid = bd.getUint16(0, Endian.little);
        int privilege = bd.getUint8(2);
        String password = Util.extractString(data.sublist(3, 8));
        String name = Util.extractString(data.sublist(8, 16), trim: true);
        int card = bd.getUint32(16, Endian.little);
        int groupId = bd.getUint8(20);
        // int timezone = bd.getUint8(21);
        int userId = bd.getUint32(24, Endian.little);

        if (uid > maxUid) maxUid = uid;
        if (name.isEmpty) name = "NN-$userId";

        users.add(UserInfo(
            uid: uid,
            name: name,
            role: privilege == 14 ? UserType.admin : UserType.user,
            password: password,
            groupId: groupId.toString(),
            userId: userId.toString(),
            cardNo: card));

        data = data.sublist(28);
      } else if (userPacketSize == 72) {
        final bd = ByteData.sublistView(data.sublist(0, 72));

        int uid = bd.getUint16(0, Endian.little);
        int privilege = bd.getUint8(2);
        String password = Util.extractString(data.sublist(3, 11));
        String name = Util.extractString(data.sublist(11, 35), trim: true);
        int card = bd.getUint32(35, Endian.little);
        String groupId = Util.extractString(data.sublist(44, 68), trim: true);
        String userId = Util.extractString(data.sublist(68, 72));

        if (uid > maxUid) maxUid = uid;
        if (name.isEmpty) name = "NN-$userId";

        users.add(UserInfo(
            uid: uid,
            name: name,
            role: privilege == 14 ? UserType.admin : UserType.user,
            password: password,
            groupId: groupId.toString(),
            userId: userId.toString(),
            cardNo: card));
        data = data.sublist(72);
      } else {
        // Unexpected packet size
        break;
      }
    }

    maxUid += 1;
    self.nextUid = maxUid;
    self.nextUserId = maxUid.toString();

    while (users.any((u) => u.userId == self.nextUserId)) {
      maxUid += 1;
      self.nextUserId = maxUid.toString();
    }

    if (self.debug) {
      debugPrint('✅ Successfully retrieved ${users.length} users.');
    }

    await FingerBridge.freeData(self);

    return users;
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
      dynamic response = await self.command(command,
          commandString: Uint8List.fromList(commandString.codeUnits));
      if (response['status'] == false) {
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

    return await self.command(command);
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

    return await self.command(command);
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
      dynamic response = await self.command(command,
          commandString: Uint8List.fromList(commandString.codeUnits));

      if (response['status'] == false) {
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

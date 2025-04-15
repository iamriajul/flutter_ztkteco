import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';
import 'package:flutter_zkteco/src/error/zk_error_connection.dart';
import 'package:flutter_zkteco/src/model/read_buffer_result.dart';
import 'package:flutter_zkteco/src/util.dart';

class FingerBridge {
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
      }).onDone(() {
        if (self.debug) {
          debugPrint('❌ TCP Socket Disconnected');
        }
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
            self.streamController.add(datagram.data);
          }
        }
      }).onDone(() {
        if (self.debug) {
          debugPrint('❌ UDP Socket Disconnected');
        }
      });
    }
  }

  static Future<ReadBufferResult> readWithBuffer(ZKTeco self, int command,
      {int fct = 0, int ext = 0}) async {
    int maxChunk = self.tcp ? 0xffc0 : (16 * 1024);

    final ByteData commandString = ByteData(11);
    commandString.setInt8(0, 1);
    commandString.setInt16(1, command, Endian.little);
    commandString.setInt32(3, fct, Endian.little);
    commandString.setInt32(7, ext, Endian.little);

    if (self.debug) {
      debugPrint("rwb cs: ${commandString.buffer.asUint8List()}");
    }

    List<int> data = [];
    int start = 0;

    final Map<String, dynamic> cmdResponse = await self.command(
        Util.CMD_PREPARE_BUFFER,
        commandString: commandString.buffer.asUint8List());

    if (cmdResponse['status'] == false) {
      throw ZKNetworkError("RWB Not supported");
    }

    if (cmdResponse['code'] == Util.CMD_DATA) {
      if (self.tcp) {
        if (self.debug) {
          debugPrint(
              "DATA! is ${self.data.length} bytes, tcp length is ${self.tcpLength}");
        }
        if (self.data.length < (self.tcpLength - 8)) {
          int need = (self.tcpLength - 8) - self.data.length;
          if (self.debug) {
            debugPrint("need more data: $need");
          }
          List<int> moreData = await receiveRawData(self, need);
          final fullData = Uint8List.fromList([...self.data, ...moreData]);
          return ReadBufferResult(data: fullData, size: fullData.length);
        } else {
          if (self.debug) {
            debugPrint("Enough data");
          }
          return ReadBufferResult(
              data: Uint8List.fromList(self.data), size: self.data.length);
        }
      } else {
        return ReadBufferResult(
            data: Uint8List.fromList(self.data), size: self.data.length);
      }
    }

    final int size = ByteData.sublistView(Uint8List.fromList(self.data), 1, 5)
        .getUint32(0, Endian.little);

    if (self.debug) {
      debugPrint("Size will be $size");
    }

    final int remain = size % maxChunk;
    final int packets = (size - remain) ~/ maxChunk;

    if (self.debug) {
      debugPrint(
          "rwb: #$packets packets of max $maxChunk bytes, and extra $remain bytes remain");
    }

    for (int i = 0; i < packets; i++) {
      final chunk = await readChunk(self, start, maxChunk);
      data.addAll(chunk);
      start += maxChunk;
    }

    if (remain > 0) {
      final chunk = await readChunk(self, start, remain);
      data.addAll(chunk);
      start += remain;
    }

    // freeData(self);

    if (self.debug) {
      debugPrint("_read w/chunk $start bytes");
    }

    return ReadBufferResult(data: Uint8List.fromList(data), size: start);
  }

  /// Receives a specified number of bytes of raw data from the device.
  ///
  /// The method listens to the stream controller associated with the [ZKTeco]
  /// object to receive data packets. It continues to accumulate data until
  /// the specified [size] is reached. If running in debug mode, the method
  /// outputs the received data and the number of bytes still needed at each
  /// step.
  ///
  /// Returns a [Future] that completes with a [Uint8List] containing all
  /// the received data once the specified size is fulfilled.
  static Future<Uint8List> receiveRawData(ZKTeco self, int size) async {
    List<int> data = [];

    if (self.debug) {
      debugPrint("Expecting $size bytes of raw data");
    }

    while (size > 0) {
      Uint8List dataReceived = await self.streamController.stream.first;
      int received = dataReceived.length;

      if (self.debug) {
        debugPrint("Total: $received/$size bytes received");
        if (received < 100) {
          debugPrint(
              "   recv: ${dataReceived.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
        }
      }

      data.addAll(dataReceived);
      size -= dataReceived.length;
      if (self.debug) debugPrint("Still need $size bytes");
    }

    return Uint8List.fromList(data);
  }

  /// Reads a chunk of bytes from the device's memory.
  ///
  /// The [start] parameter is the starting offset of the chunk to read.
  ///
  /// The [size] parameter is the number of bytes to read.
  ///
  /// The method sends a command to the device to read the specified chunk
  /// of bytes from its memory. The device must be connected and authenticated
  /// before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [Uint8List] containing
  /// the read chunk of bytes, or throws a [ZKErrorConnection] if the device
  /// could not be queried.
  static Future<List<int>> readChunk(ZKTeco self, int start, int size) async {
    const int maxRetries = 3;
    Uint8List? data;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      ByteData commandString = ByteData(8)
        ..setInt32(0, start, Endian.little)
        ..setInt32(4, size, Endian.little);

      final Map<String, dynamic> cmdResponse = await self.command(
          Util.CMD_READ_BUFFER,
          commandString: commandString.buffer.asUint8List());

      if (cmdResponse['status'] == true) {
        data = await receiveChunk(self, cmdResponse);
        if (data != null) {
          return data;
        }
      }
    }

    throw ZKErrorConnection("Can't read chunk $start:[$size]");
  }

  /// Receives a chunk of data from the device.
  ///
  /// This method processes the response from the device and retrieves the
  /// data chunk based on the response code. If the response code is
  /// [Util.CMD_DATA], it checks the connection type and the amount of data
  /// received, requesting more data if necessary. If the response code is
  /// [Util.CMD_PREPARE_DATA], it prepares to receive a larger chunk of data
  /// and handles TCP acknowledgment. The device must be connected and
  /// authenticated before this method can be used.
  ///
  /// Returns a [Future] that completes with a [Uint8List] containing the
  /// received data chunk, or [null] if the response is invalid or an error
  /// occurs.
  static Future<Uint8List?> receiveChunk(
      ZKTeco self, Map<String, dynamic> response) async {
    if (response['code'] == Util.CMD_DATA) {
      if (self.tcp) {
        if (self.debug) {
          debugPrint(
              "_rc_DATA! is ${self.data.length} bytes, tcp length is ${self.tcpLength}");
        }

        if (self.dataRecv.length < (self.tcpLength - 8)) {
          int need = (self.tcpLength - 8) - self.data.length;
          if (self.debug) debugPrint("Need more data: $need");

          List<int> moreData = await receiveRawData(self, need);
          return Uint8List.fromList([...self.data, ...moreData]);
        } else {
          if (self.debug) debugPrint("Enough data");
          return Uint8List.fromList(self.data);
        }
      } else {
        if (self.debug) debugPrint("_rc len is ${self.data.length}");
        return Uint8List.fromList(self.data);
      }
    } else if (response['code'] == Util.CMD_PREPARE_DATA) {
      List<int> data = [];
      int size = Util.getSize(self) ?? 0;

      if (size == 0) {
        throw ZKNetworkError('Could not get size');
      }

      if (self.debug) debugPrint("Receive chunk: prepare data size is $size");

      if (self.tcp) {
        List<int> dataRecv = self.data.length >= (8 + size)
            ? self.data.sublist(8)
            : [
                ...self.data.sublist(8),
                ...(await receiveRawData(self, (size + 32))),
              ];
        final result = await receiveTcpData(self, dataRecv, size);
        final List<int> resp = result.$1 ?? [];
        final Uint8List brokenHeader = result.$2;

        data.addAll(resp);

        late Uint8List ackRecv;
        if (brokenHeader.length < 16) {
          ackRecv = Uint8List.fromList([
            ...brokenHeader,
            ...await receiveRawData(self, 16 - brokenHeader.length)
          ]);
        } else {
          ackRecv = brokenHeader;
        }

        if (ackRecv.length < 16) {
          if (self.debug) {
            debugPrint("trying to complete broken ACK ${ackRecv.length}/16");
          }
          ackRecv = Uint8List.fromList([
            ...ackRecv,
            ...await receiveRawData(self, 16 - ackRecv.length),
          ]);
        }

        if (Util.testTcpTop(dataRecv) == 0) {
          if (self.debug) debugPrint("Invalid chunk TCP ACK OK");
          return null;
        }

        final response =
            ByteData.sublistView(ackRecv).getUint16(8, Endian.little);

        if (response == Util.CMD_ACK_OK) {
          if (self.debug) debugPrint("Chunk TCP ACK OK!");
          return Uint8List.fromList(data);
        }

        if (self.debug) debugPrint("Bad response ${utf8.decode(data)}");
        return null;
      }

      while (true) {
        final Uint8List dataRecv = (await receiveRawData(self, 1024 + 8));
        final int response =
            ByteData.sublistView(dataRecv).getUint16(0, Endian.little);

        if (self.debug) {
          debugPrint("# packet response is: $response");
        }

        if (response == Util.CMD_DATA) {
          data.addAll(dataRecv.sublist(8));
          size -= 1024;
        } else if (response == Util.CMD_ACK_OK) {
          break;
        } else {
          if (self.debug) {
            debugPrint("Broken!");
          }
          break;
        }

        if (self.debug) {
          debugPrint("Still needs $size");
        }
      }

      return Uint8List.fromList(data);
    } else {
      if (self.debug) debugPrint("Invalid response $response");
      return null;
    }
  }

  static Future<(Uint8List?, Uint8List)> receiveTcpData(
      ZKTeco self, List<int> dataRecv, int size) async {
    /// dataRecv: raw TCP packet
    /// Must analyze `tcpLength`
    /// Returns: `[data, broken]`

    List<int> data = [];
    int tcpLength = Util.testTcpTop(dataRecv);

    if (self.debug) {
      debugPrint("TCP Length: $tcpLength, Size: $size");
    }

    if (tcpLength <= 0) {
      if (self.debug) debugPrint("Incorrect TCP packet");
      return (null, Uint8List(0));
    }

    if ((tcpLength - 8) < size) {
      if (self.debug) debugPrint("TCP length too small... retrying");

      var (resp1, bh1) = await receiveTcpData(self, dataRecv, tcpLength - 8);
      if (resp1 != null) data.addAll(resp1);
      size -= resp1?.length ?? 0;

      if (self.debug) debugPrint("new tcp DATA packet to fill missing $size");

      Uint8List moreRecv = await receiveRawData(self, size + 16);

      if (self.debug) {
        debugPrint("new tcp DATA starting with ${moreRecv.length} bytes");
      }

      var (resp2, bh2) = await receiveTcpData(
          self, Uint8List.fromList([...bh1, ...moreRecv]), size);
      if (resp2 != null) data.addAll(resp2);

      if (self.debug) {
        debugPrint(
            "for missing $size received ${resp2?.length ?? 0} with extra ${bh2.length}");
      }
      return (Uint8List.fromList(data), bh2);
    }

    int received = dataRecv.length;

    if (self.debug) debugPrint("Received: $received, Size: $size");

    int response = ByteData.sublistView(Uint8List.fromList(dataRecv), 8)
        .getUint16(0, Endian.little);

    if (received >= (size + 32)) {
      if (response == Util.CMD_DATA) {
        List<int> resp = dataRecv.sublist(16, size + 16);

        if (self.debug) debugPrint("Resp complete len: ${resp.length}");

        return (
          Uint8List.fromList(resp),
          Uint8List.fromList(dataRecv.sublist(size + 16))
        );
      } else {
        if (self.debug) debugPrint("Incorrect response!!! $response");
        return (null, Uint8List(0));
      }
    } else {
      if (self.debug) {
        debugPrint("Try DATA incomplete (actual valid ${received - 16})");
      }

      data.addAll(dataRecv.sublist(16, size + 16));
      size -= (received - 16);

      Uint8List brokenHeader = Uint8List(0);
      if (size < 0) {
        brokenHeader =
            Uint8List.fromList(dataRecv.sublist(dataRecv.length + size));
        if (self.debug) {
          debugPrint(
              "broken ${brokenHeader.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}");
        }
      }

      if (size > 0) {
        List<int> moreData = await receiveRawData(self, size);
        data.addAll(moreData);
      }

      return (Uint8List.fromList(data), brokenHeader);
    }
  }

  /// Frees the data buffer on the device.
  ///
  /// This method sends a command to the device to free the data buffer. The
  /// device must be connected and authenticated before this method can be used.
  ///
  /// The method returns a [Future] that completes with a [bool] indicating if
  /// the data buffer was successfully freed. If the data cannot be freed, a
  /// [ZKNetworkError] is thrown.
  static Future<bool> freeData(ZKTeco self) async {
    Map<String, dynamic> cmdResponse = await self.command(
      Util.CMD_FREE_DATA,
    );

    if (cmdResponse['status'] == true) {
      return true;
    } else {
      throw ZKNetworkError("Can't free data");
    }
  }
}

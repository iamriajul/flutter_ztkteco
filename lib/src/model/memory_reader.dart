import 'package:copy_with_extension/copy_with_extension.dart';

part 'memory_reader.g.dart';

@CopyWith()
class MemoryReader {
  final int? users;
  final int? fingers;
  final int? records;
  final int? dummy;
  final int? cards;
  final int? fingersCap;
  final int? usersCap;
  final int? recCap;
  final int? fingersAv;
  final int? usersAv;
  final int? recAv;
  final int? faces;
  final int? facesCap;

  MemoryReader({
    this.users,
    this.fingers,
    this.records,
    this.dummy,
    this.cards,
    this.fingersCap,
    this.usersCap,
    this.recCap,
    this.fingersAv,
    this.usersAv,
    this.recAv,
    this.faces,
    this.facesCap,
  });

  factory MemoryReader.fromJson(Map<String, dynamic> json) {
    return MemoryReader(
      users: json['users'],
      fingers: json['fingers'],
      records: json['records'],
      dummy: json['dummy'],
      cards: json['cards'],
      fingersCap: json['fingersCap'],
      usersCap: json['usersCap'],
      recCap: json['recCap'],
      fingersAv: json['fingersAv'],
      usersAv: json['usersAv'],
      recAv: json['recAv'],
      faces: json['faces'],
      facesCap: json['facesCap'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'users': users,
      'fingers': fingers,
      'records': records,
      'dummy': dummy,
      'cards': cards,
      'fingersCap': fingersCap,
      'usersCap': usersCap,
      'recCap': recCap,
      'fingersAv': fingersAv,
      'usersAv': usersAv,
      'recAv': recAv,
      'faces': faces,
      'facesCap': facesCap,
    };
  }

  @override
  String toString() => toJson().toString();
}

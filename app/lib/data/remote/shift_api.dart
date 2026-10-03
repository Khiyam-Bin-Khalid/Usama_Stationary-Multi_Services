import 'api_client.dart';
import 'guarded.dart';
import '../models/shift.dart';

class ShiftApi {
  final ApiClient client;
  ShiftApi(this.client);

  Future<ShiftReport?> current() => guarded(() async {
        final res = await client.dio.get('/shifts/current');
        if (res.data['shift'] == null) return null;
        return ShiftReport.fromJson(Map<String, dynamic>.from(res.data));
      });

  Future<Shift> open({required double openingCash, String? note}) => guarded(() async {
        final res = await client.dio.post('/shifts/open', data: {
          'openingCash': openingCash,
          if (note != null && note.isNotEmpty) 'note': note,
        });
        return Shift.fromJson(res.data['shift']);
      });

  Future<Shift> close({required double closingCashActual, String? note}) => guarded(() async {
        final res = await client.dio.post('/shifts/close', data: {
          'closingCashActual': closingCashActual,
          if (note != null && note.isNotEmpty) 'note': note,
        });
        return Shift.fromJson(res.data['shift']);
      });

  Future<List<Shift>> list() => guarded(() async {
        final res = await client.dio.get('/shifts');
        return (res.data['shifts'] as List).map((e) => Shift.fromJson(e)).toList();
      });
}

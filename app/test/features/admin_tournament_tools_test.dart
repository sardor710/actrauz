import 'package:actra/core/localized_text.dart';
import 'package:actra/core/markets.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:actra/features/admin/tournament_editor_screen.dart';
import 'package:actra/features/admin/tournament_participants_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the date picker range', () {
    final today = DateTime.utc(2026, 11, 22);

    test('a year back and two years ahead of today by default', () {
      final r = pickerRange(DateTime.utc(2026, 12, 10), today);
      expect(r.first, DateTime.utc(2025, 11, 22));
      expect(r.last, DateTime.utc(2028, 11, 21));
    });

    test('widened to take in an old or far-off initial day, so the picker never asserts', () {
      final old = DateTime.utc(2024, 3, 1);
      expect(pickerRange(old, today).first, old);
      final far = DateTime.utc(2030, 1, 1);
      expect(pickerRange(far, today).last, far);
      // The end day's picker starts at the first day, unless the end is before it.
      expect(pickerRange(DateTime.utc(2026, 12, 12), today, first: DateTime.utc(2026, 12, 10)).first, DateTime.utc(2026, 12, 10));
      expect(pickerRange(old, today, first: DateTime.utc(2026, 12, 10)).first, old);
    });
  });

  test('the CSV created column is the tournament city\'s local time', () {
    final entry = AdminRegistration(
      registration: Registration(
        id: 'r1',
        tournamentId: 't1',
        categoryId: 'c1',
        categoryName: const LocalizedText.all('Open'),
        kind: CategoryKind.singles,
        status: RegistrationStatus.registered,
        registrant: const PlayerRef(id: 'p1', name: 'Aziz'),
        fee: 100000,
        currency: Currency.uzs,
        // 21:30 UTC is 02:30 the next day in Tashkent (UTC+5).
        createdAt: DateTime.utc(2026, 11, 22, 21, 30),
      ),
      registrantPhone: '+998901000001',
    );
    final lines = registrationsCsv([entry], 'en', utcOffsetMinutes: 300).trim().split('\n');
    expect(lines[1], 'Open,registered,Aziz,+998901000001,,,100000,UZS,no,2026-11-23 02:30');
  });
}

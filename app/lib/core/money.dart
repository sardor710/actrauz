/// Groups an amount in thousands with non-breaking spaces: 250000 → "250 000".
///
/// UZS and KZT amounts are whole units; there is no decimal part to show.
String groupThousands(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return amount < 0 ? '-$buffer' : buffer.toString();
}

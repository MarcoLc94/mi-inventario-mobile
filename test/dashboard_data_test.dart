import 'package:flutter_test/flutter_test.dart';
import 'package:mi_inventario_mobile/features/home/dashboard_data.dart';

void main() {
  test('stock states follow the web thresholds', () {
    expect(stockState({'stock': null}), StockState.unknown);
    expect(stockState({'stock': '0.0'}), StockState.out);
    expect(stockState({'stock': 4.5}), StockState.low);
    expect(stockState({'stock': '5'}), StockState.healthy);
    final summary = InventorySummary([{'stock': 0}, {'stock': 2}, {'stock': 10}, {'stock': null}]);
    expect(summary.total, 4);
    expect(summary.attention, 2);
  });

  test('due dates use calendar days', () {
    final today = DateTime(2026, 10, 15, 23, 30);
    expect(daysUntil('2026-10-15', today), 0);
    expect(daysUntil('2026-10-16T00:00:00Z', today), 1);
    expect(daysUntil('2026-10-12', today), -3);
    expect(daysUntil(null, today), isNull);
    expect(dueLabel(-3), '3 d de atraso');
    expect(dueLabel(1), 'Mañana');
  });

  test('tasks are sorted by due date with undated last', () {
    final tasks = buildTasks([
      {'id': 1, 'order_number': 'OC-1', 'status': 'approved', 'expected_delivery_date': null},
    ], [
      {'id': 2, 'order_number': 'OV-2', 'expected_delivery_date': '2000-01-01', 'client': {'name': 'Ana'}},
    ]);
    expect(tasks.map((t) => t.title), ['Venta #OV-2', 'Compra #OC-1']);
    expect(tasks.first.path, '/clients/orders/2');
    expect(tasks.last.subtitle, 'Proveedor sin nombre');
  });
}

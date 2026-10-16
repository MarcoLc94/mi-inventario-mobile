import '../../core/formatters.dart';
import '../../core/user_profile.dart';

/// Mismas reglas que la web (src/pages/Home/dashboardData.ts).
const lowStockLimit = 5;

enum StockState { healthy, low, out, unknown }

const stockLabels = {
  StockState.healthy: 'Con existencias',
  StockState.low: 'Stock bajo',
  StockState.out: 'Sin existencias',
  StockState.unknown: 'Revisar dato',
};

StockState stockState(Map<String, dynamic> product) {
  final stock = toNum(product['stock']);
  if (stock == null) return StockState.unknown;
  if (stock <= 0) return StockState.out;
  return stock < lowStockLimit ? StockState.low : StockState.healthy;
}

class InventorySummary {
  InventorySummary(List<Map<String, dynamic>> products) : total = products.length {
    for (final product in products) {
      counts[stockState(product)] = (counts[stockState(product)] ?? 0) + 1;
    }
  }
  final int total;
  final counts = <StockState, int>{};
  int get low => counts[StockState.low] ?? 0;
  int get out => counts[StockState.out] ?? 0;
  int get attention => low + out;
}

/// Días de calendario entre hoy y la fecha (sin desfases por zona horaria).
int? daysUntil(dynamic value, [DateTime? today]) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value?.toString() ?? '');
  if (match == null) return null;
  final date = DateTime.utc(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
  final now = today ?? DateTime.now();
  return date.difference(DateTime.utc(now.year, now.month, now.day)).inDays;
}

String dueLabel(int? days) {
  if (days == null) return 'Sin fecha';
  if (days < 0) return '${-days} d de atraso';
  if (days == 0) return 'Hoy';
  if (days == 1) return 'Mañana';
  return 'En $days días';
}

enum TaskKind { purchase, sale }

class DashboardTask {
  DashboardTask(this.kind, this.title, this.subtitle, this.days, this.path, this.status);
  final TaskKind kind;
  final String title;
  final String subtitle;
  final int? days;
  final String path;
  final String status;
}

List<DashboardTask> buildTasks(List<Map<String, dynamic>> purchases, List<Map<String, dynamic>> sales) {
  final tasks = [
    for (final order in purchases)
      DashboardTask(
        TaskKind.purchase,
        'Compra #${order['order_number'] ?? order['id']}',
        asMap(order['supplier'])['name']?.toString() ?? 'Proveedor sin nombre',
        daysUntil(order['expected_delivery_date']),
        '/suppliers/orders/${order['id']}',
        order['status'] == 'partially_received' ? 'Recepción parcial' : 'Por recibir',
      ),
    for (final order in sales)
      DashboardTask(
        TaskKind.sale,
        'Venta #${order['order_number'] ?? order['id']}',
        asMap(order['client'])['name']?.toString() ?? 'Cliente sin nombre',
        daysUntil(order['expected_delivery_date']),
        '/clients/orders/${order['id']}',
        'Por entregar',
      ),
  ];
  tasks.sort((a, b) {
    final byDays = (a.days ?? 1 << 30).compareTo(b.days ?? 1 << 30);
    return byDays != 0 ? byDays : a.title.compareTo(b.title);
  });
  return tasks;
}

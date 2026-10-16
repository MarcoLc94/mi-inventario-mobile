import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/formatters.dart';

final _isoDate = DateFormat('yyyy-MM-dd');
String isoDate(DateTime date) => _isoDate.format(date);

/// Campo de fecha (yyyy-MM-dd) con selector.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.firstDate, this.lastDate, this.clearable = false});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(value ?? '') ?? now,
          firstDate: firstDate ?? DateTime(now.year - 5),
          lastDate: lastDate ?? DateTime(now.year + 10),
        );
        if (picked != null) onChanged(isoDate(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: clearable && value != null
              ? IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close), onPressed: () => onChanged(null))
              : null,
        ),
        child: Text(value == null || value!.isEmpty ? 'Sin fecha' : formatDate(value)),
      ),
    );
  }
}

/// Lista desplegable de mapas `{id, name}` (almacenes, categorías, proveedores).
class RecordDropdown extends StatelessWidget {
  const RecordDropdown({super.key, required this.label, required this.records, required this.value, required this.onChanged, this.icon, this.emptyLabel, this.validator});
  final String label;
  final List<Map<String, dynamic>> records;
  final int? value;
  final ValueChanged<int?> onChanged;
  final IconData? icon;
  final String? emptyLabel;
  final String? Function(int?)? validator;

  @override
  Widget build(BuildContext context) {
    final ids = records.map((r) => (r['id'] as num).toInt()).toSet();
    return DropdownButtonFormField<int?>(
      initialValue: ids.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
      validator: validator,
      items: [
        if (emptyLabel != null) DropdownMenuItem<int?>(value: null, child: Text(emptyLabel!)),
        for (final r in records)
          DropdownMenuItem<int?>(value: (r['id'] as num).toInt(), child: Text(r['name']?.toString() ?? '', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Etiqueta de estado con color.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Fila "etiqueta: valor" para tarjetas de detalle.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: theme.textTheme.bodySmall)),
        Expanded(child: Text(value!, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                ?trailing,
              ]),
            ),
            ...children,
          ]),
        ),
      );
}

/// Diálogo de confirmación; devuelve true si el usuario acepta.
Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'Aceptar', bool destructive = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result == true;
}

/// Pide un texto (p. ej. motivo de bloqueo). Null si se cancela.
Future<String?> promptText(BuildContext context, {required String title, required String label, String action = 'Aceptar', bool required = true}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (required && controller.text.trim().isEmpty) return;
            Navigator.pop(context, controller.text.trim());
          },
          child: Text(action),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

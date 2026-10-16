import 'package:flutter/material.dart';

import 'form_fields.dart';

/// Estados de documentos (compras, ventas, devoluciones) con su etiqueta y color.
class DocStatus {
  const DocStatus(this.labels);
  final Map<String, String> labels;

  String label(dynamic status) => labels[status?.toString()] ?? status?.toString() ?? '';

  Color color(BuildContext context, dynamic status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status?.toString()) {
      'draft' || 'pending' => Colors.orange.shade800,
      'approved' || 'processing' || 'in_transit' => scheme.primary,
      'partially_received' => Colors.blue.shade700,
      'received' || 'completed' || 'processed' || 'shipped' || 'delivered' || 'active' => Colors.green.shade700,
      'cancelled' || 'rejected' || 'suspended' || 'discontinued' || 'inactive' => scheme.error,
      _ => scheme.outline,
    };
  }

  Widget chip(BuildContext context, dynamic status) => StatusChip(label(status), color: color(context, status));
}

const purchaseStatus = DocStatus({
  'draft': 'Borrador',
  'pending': 'Pendiente',
  'approved': 'Aprobada',
  'partially_received': 'Recepción parcial',
  'received': 'Recibida',
  'cancelled': 'Cancelada',
  'closed': 'Cerrada',
});

const saleStatus = DocStatus({
  'draft': 'Borrador',
  'pending': 'Pendiente',
  'approved': 'Aprobada',
  'shipped': 'Enviada',
  'completed': 'Completada',
  'cancelled': 'Cancelada',
});

const returnStatus = DocStatus({
  'pending': 'Pendiente',
  'approved': 'Aprobada',
  'processed': 'Procesada',
  'rejected': 'Rechazada',
});

const partnerStatus = DocStatus({
  'active': 'Activo',
  'inactive': 'Inactivo',
  'suspended': 'Suspendido',
  'discontinued': 'Descontinuado',
});

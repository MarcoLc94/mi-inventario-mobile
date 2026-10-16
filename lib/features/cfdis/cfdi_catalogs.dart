import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/user_profile.dart';
import '../../widgets/form_fields.dart';

/// Catálogos del SAT y etiquetas del módulo CFDIs (mismos que la web:
/// interfaces/saleInvoiceData.ts y interfaces/cfdiDocuments.ts).
const invoicePaymentForms = {
  '01': '01 - Efectivo',
  '02': '02 - Cheque nominativo',
  '03': '03 - Transferencia electrónica de fondos',
  '04': '04 - Tarjeta de crédito',
  '28': '28 - Tarjeta de débito',
  '99': '99 - Por definir',
};

/// c_FormaPago sin "99 Por definir" (un pago siempre tiene forma).
const satPaymentForms = {
  '01': '01 - Efectivo',
  '02': '02 - Cheque nominativo',
  '03': '03 - Transferencia electrónica de fondos',
  '04': '04 - Tarjeta de crédito',
  '28': '28 - Tarjeta de débito',
  '05': '05 - Monedero electrónico',
  '06': '06 - Dinero electrónico',
  '08': '08 - Vales de despensa',
  '12': '12 - Dación en pago',
  '13': '13 - Pago por subrogación',
  '14': '14 - Pago por consignación',
  '15': '15 - Condonación',
  '17': '17 - Compensación',
  '23': '23 - Novación',
  '24': '24 - Confusión',
  '25': '25 - Remisión de deuda',
  '26': '26 - Prescripción o caducidad',
  '27': '27 - A satisfacción del acreedor',
  '29': '29 - Tarjeta de servicios',
  '30': '30 - Aplicación de anticipos',
  '31': '31 - Intermediario pagos',
};

const paymentMethods = {'PUE': 'PUE - Pago en una sola exhibición', 'PPD': 'PPD - Pago en parcialidades o diferido'};

const cfdiUses = {
  'G01': 'G01 - Adquisición de mercancías',
  'G02': 'G02 - Devoluciones, descuentos o bonificaciones',
  'G03': 'G03 - Gastos en general',
  'I01': 'I01 - Construcciones',
  'I04': 'I04 - Equipo de cómputo y accesorios',
  'I08': 'I08 - Otra maquinaria y equipo',
  'P01': 'P01 - Por definir',
  'S01': 'S01 - Sin efectos fiscales',
};

const fiscalRegimes = {
  '601': '601 - General de Ley Personas Morales',
  '603': '603 - Personas Morales con Fines no Lucrativos',
  '605': '605 - Sueldos y Salarios e Ingresos Asimilados a Salarios',
  '606': '606 - Arrendamiento',
  '607': '607 - Régimen de Enajenación o Adquisición de Bienes',
  '608': '608 - Demás ingresos',
  '610': '610 - Residentes en el Extranjero sin Establecimiento Permanente en México',
  '611': '611 - Ingresos por Dividendos (socios y accionistas)',
  '612': '612 - Personas Físicas con Actividades Empresariales y Profesionales',
  '614': '614 - Ingresos por intereses',
  '615': '615 - Régimen de los ingresos por obtención de premios',
  '616': '616 - Sin obligaciones fiscales',
  '620': '620 - Sociedades Cooperativas de Producción que optan por diferir sus ingresos',
  '621': '621 - Incorporación Fiscal',
  '622': '622 - Actividades Agrícolas, Ganaderas, Silvícolas y Pesqueras',
  '623': '623 - Opcional para Grupos de Sociedades',
  '624': '624 - Coordinados',
  '625': '625 - Régimen de las Actividades Empresariales con ingresos a través de Plataformas Tecnológicas',
  '626': '626 - Régimen Simplificado de Confianza',
};

const cfdiStatusLabels = {
  'draft': 'Borrador (sin timbrar)',
  'stamping': 'Timbrando…',
  'stamped': 'Timbrada',
  'error': 'Error de timbrado',
  'cancellation_pending': 'Cancelación en proceso',
  'cancelled': 'Cancelada',
};

const cancellationMotives = {
  '01': ('01 - Comprobante emitido con errores con relación', 'Ya emitiste el comprobante que lo sustituye: indica su UUID.'),
  '02': ('02 - Comprobante emitido con errores sin relación', 'Datos erróneos y no habrá comprobante que lo sustituya.'),
  '03': ('03 - No se llevó a cabo la operación', 'La venta no se concretó.'),
  '04': ('04 - Operación nominativa relacionada en factura global', 'La venta ya estaba incluida en una factura global.'),
};

const creditRelations = {
  '01': ('Descuento o bonificación', 'Rebaja sobre una factura ya emitida.'),
  '03': ('Devolución de mercancía', 'El cliente regresó productos de la factura.'),
};

const globalPeriodicities = {'01': 'Diaria', '02': 'Semanal', '03': 'Quincenal', '04': 'Mensual', '05': 'Bimestral (solo RIF)'};

/// Tipos de comprobante además de las facturas de venta.
enum CfdiKind {
  payment('invoice_payments', '/cfdis/complementos-pago', 'Complemento de pago', 'Complementos de pago',
      'Cada pago que recibes de una factura PPD se ampara con un complemento de pago. Se registran desde el detalle de la factura.'),
  creditNote('credit_notes', '/cfdis/notas-credito', 'Nota de crédito', 'Notas de crédito',
      'Descuentos, bonificaciones y devoluciones sobre facturas ya emitidas. Se emiten desde el detalle de la factura.'),
  globalInvoice('global_invoices', '/cfdis/factura-global', 'Factura global', 'Facturas globales',
      'Agrupa las ventas del punto de venta que no se facturaron. El SAT pide emitirla al cierre de cada periodo.');

  const CfdiKind(this.apiPath, this.route, this.singular, this.plural, this.intro);
  final String apiPath;
  final String route;
  final String singular;
  final String plural;
  final String intro;
}

Color cfdiStatusColor(BuildContext context, String? status) => switch (status) {
      'stamped' => Colors.green.shade700,
      'draft' || 'stamping' => Colors.orange.shade800,
      'cancellation_pending' => Colors.blue.shade700,
      'error' || 'cancelled' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };

Widget cfdiStatusChip(BuildContext context, dynamic status) =>
    StatusChip(cfdiStatusLabels[status?.toString()] ?? status?.toString() ?? '', color: cfdiStatusColor(context, status?.toString()));

String cfdiFolio(Map<String, dynamic> doc) => '${doc['series'] ?? ''}-${doc['folio'] ?? ''}';

/// Aviso visible mientras el servidor timbra contra el sandbox de Facturama.
class CfdiSandboxBanner extends StatefulWidget {
  const CfdiSandboxBanner({super.key});

  static Future<String?>? _mode;

  @override
  State<CfdiSandboxBanner> createState() => _CfdiSandboxBannerState();
}

class _CfdiSandboxBannerState extends State<CfdiSandboxBanner> {
  String? _mode;

  @override
  void initState() {
    super.initState();
    CfdiSandboxBanner._mode ??= context
        .read<ApiClient>()
        .get('/fiscal_profile')
        .then((data) => asMap(data)['service_mode']?.toString())
        .catchError((Object _) {
      CfdiSandboxBanner._mode = null;
      return null;
    });
    CfdiSandboxBanner._mode!.then((mode) {
      if (mounted) setState(() => _mode = mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_mode != 'sandbox') return const SizedBox.shrink();
    return Card(
      color: Colors.amber.shade100,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Modo pruebas: los comprobantes se timbran en el ambiente de pruebas de Facturama y no tienen validez ante el SAT. '
            'Usa el RFC de pruebas EKU9003173C9 y su CSD.', style: TextStyle(color: Colors.black87)),
      ),
    );
  }
}

/// Hoja para cancelar un CFDI: motivo del SAT y, con motivo 01, el UUID que lo sustituye.
Future<(String, String?)?> askCancellation(BuildContext context) => showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CancelSheet(),
    );

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  String _motive = '02';
  final _uuid = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Cancelar comprobante', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _motive,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Motivo de cancelación'),
            items: [for (final e in cancellationMotives.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _motive = v ?? '02'),
          ),
          const SizedBox(height: 4),
          Text(cancellationMotives[_motive]!.$2, style: Theme.of(context).textTheme.bodySmall),
          if (_motive == '01') ...[
            const SizedBox(height: 12),
            TextField(controller: _uuid, decoration: const InputDecoration(labelText: 'UUID que lo sustituye', hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx')),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              if (_motive == '01' && !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(_uuid.text.trim())) {
                setState(() => _error = 'Con el motivo 01 escribe el UUID del comprobante que sustituye a este.');
                return;
              }
              Navigator.pop(context, (_motive, _motive == '01' ? _uuid.text.trim() : null));
            },
            child: const Text('Confirmar cancelación'),
          ),
        ]),
      );
}

/// Pide el correo al que se envían el PDF y el XML.
Future<String?> askEmail(BuildContext context, String? initial) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Enviar por correo'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: controller, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo del destinatario')),
        const SizedBox(height: 8),
        const Text('Se envían el PDF y el XML.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => controller.text.trim().contains('@') ? Navigator.pop(context, controller.text.trim()) : null, child: const Text('Enviar')),
      ],
    ),
  );
  controller.dispose();
  return result;
}

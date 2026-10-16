/// Recorridos de Boxy (mismo texto que la web: components/inventoryGuide).
class TutorialStep {
  const TutorialStep(this.title, this.text, [this.path]);
  final String title;
  final String text;

  /// Pantalla donde se hace el paso (misma ruta que la web).
  final String? path;
}

class Tutorial {
  const Tutorial({required this.id, required this.title, required this.description, required this.steps});
  final String id;
  final String title;
  final String description;
  final List<TutorialStep> steps;
}

const tutorials = [
  Tutorial(
    id: 'inventory',
    title: 'Inventario',
    description: 'Almacenes, productos, entradas, salidas y comprobantes.',
    steps: [
      TutorialStep('¡Hola! Soy tu compañero de inventario.', 'Te acompañaré en tus primeros pasos. Vamos a preparar tu almacén, mover tus primeros productos y descargar un comprobante. ¿Empezamos?'),
      TutorialStep('Primero, un lugar para tus productos.', 'Aquí están tus almacenes. Crea uno con nombre y ubicación, o usa el que ya tienes activo. Cuando esté listo, pulsa Continuar.', '/warehouses'),
      TutorialStep('Conozcamos tu primer producto.', 'Pulsa Nuevo producto y completa sus datos. Puedes dejar el stock inicial en cero: lo registraremos juntos en el siguiente paso.', '/products'),
      TutorialStep('¡Vamos a registrar una entrada!', 'Elige almacén y producto, escribe una cantidad y el motivo, y confirma la entrada. Estos datos se guardan en tu cuenta y sí cambian tus existencias.', '/inventory/manual?type=IN'),
      TutorialStep('Mira cómo creció tu inventario.', 'Aquí puedes consultar el stock de tus productos. El círculo señala las existencias actuales. Revisa el producto de tu entrada y después continuemos con una salida.', '/products'),
      TutorialStep('Ahora registremos una salida.', 'Usa el mismo almacén y producto. Captura una cantidad disponible, indica el motivo y confirma. Las unidades reservadas no se pueden retirar.', '/inventory/manual?type=OUT'),
      TutorialStep('Cada movimiento tiene su comprobante.', 'En Comprobantes, pulsa PDF en una entrada o salida. Es un documento de control interno: no necesitas activar Facturación.', '/inventory/receipts'),
      TutorialStep('¡Ya estás listo para empezar!', 'Ya conoces el recorrido básico. También puedes explorar Compras y Ventas; la facturación electrónica es un módulo adicional. Si me necesitas, puedes volver a abrir esta guía.'),
    ],
  ),
  Tutorial(
    id: 'pos',
    title: 'Punto de venta',
    description: 'Apertura de caja, cobro de productos, tickets y cierre.',
    steps: [
      TutorialStep('Conoce tu caja', 'Soy Boxy. Te mostraré cómo cobrar productos y cerrar tu caja. El recorrido explica el proceso sin registrar ventas automáticamente.', '/pos'),
      TutorialStep('Abre una sesión', 'Selecciona el almacén y captura el fondo inicial de efectivo. Abre tu caja cuando estés listo para operar; estos datos quedarán registrados.', '/pos'),
      TutorialStep('Prepara el cobro', 'Busca por nombre o código, añade productos disponibles al carrito y selecciona al cliente. Revisa cantidades, impuestos y total antes de cobrar.', '/pos'),
      TutorialStep('Confirma el pago', 'Elige efectivo, tarjeta o transferencia. Con efectivo registra lo recibido y verifica el cambio. Tarjeta y transferencia registran un pago realizado por fuera del sistema; no cobran una tarjeta automáticamente. Confirmar la venta descuenta existencias.', '/pos'),
      TutorialStep('Tickets', 'En Tickets consulta ventas y descarga el comprobante. El ticket es de venta; la factura fiscal requiere activar Facturación.', '/pos/tickets'),
      TutorialStep('Cierra tu caja', 'En Cortes revisa los totales, cuenta el efectivo y registra lo contado al cerrar. El sistema muestra la diferencia. Puedes repetir este tutorial desde Ayuda.', '/pos/cortes'),
    ],
  ),
];

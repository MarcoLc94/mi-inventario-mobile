# Mi Inventario (Android)

App Flutter de Mi Inventario. Usa el mismo backend y los mismos endpoints que
la web (`ats-inventory-backend` / `ats-inventory-frontend`, rama
`product/general-saas`), así que el usuario puede trabajar indistintamente en
la web o en el teléfono.

- `applicationId`: `space.miinventario.app` (no se puede cambiar después de publicar en Play Store).
- Solo Android.

## Cómo correrla

```bash
flutter pub get
flutter run                                   # contra producción (api.mi-inventario.space)
flutter run --dart-define=API_BASE_URL=https://staging.ejemplo.com \
            --dart-define=WEB_BASE_URL=https://app-staging.ejemplo.com
flutter analyze && flutter test
flutter build apk --release                   # requiere configurar la firma de release
```

Necesita un backend con la API móvil (`/api/mobile/v1/session`), incluida en
`product/general-saas` a partir de la migración `20261015120000_create_mobile_refresh_tokens`.

## Sesión y seguridad

- Login con correo y contraseña → el backend devuelve un **access token** de
  15 min (se manda como `Authorization: Bearer`) y un **refresh token** opaco de
  30 días que rota en cada uso.
- El refresh token vive en el almacenamiento cifrado de Android
  (`flutter_secure_storage`); el access token solo en memoria.
- Si un refresh token ya usado vuelve a presentarse, el backend cierra toda
  esa sesión (protección contra robo).
- **Huella o rostro** (opcional, en *Mi perfil y ajustes*): la app arranca
  bloqueada y vuelve a bloquearse tras 3 min en segundo plano. El token solo se
  renueva después de verificar la biometría.
- La web no cambia: sigue usando su cookie http-only. Un token de la web no
  sirve como Bearer ni al revés.

## Estructura

```
lib/
  core/        config, cliente HTTP (renovación automática del token), sesión,
               tema, menú con las reglas de permisos de la web, formatos
  widgets/     menú lateral, estados de carga/error
  features/    una carpeta por módulo (auth, home, products, settings, …)
  router.dart  rutas con las mismas direcciones que la web
```

El menú (`core/modules.dart`) replica `src/data/menuModules.ts` de la web:
mismos módulos, mismos candados por módulo no contratado (Compras, Ventas,
CFDIs, Punto de venta) y mismos permisos (Administración solo admin, CFDIs
según permiso de facturas, Backoffice según permiso).

## Avance por fases

| Fase | Módulos | Estado |
|------|---------|--------|
| 1 | Login, biometría, tema, menú con permisos, Inicio, Productos (catálogo y detalle), Mi perfil | ✅ |
| 2 | Inventario: alta/edición/borrado de productos con fotos y presentaciones, categorías, ajustes (aprobar/rechazar, PDF), transferencias, lotes y caducidades, movimientos, entradas/salidas manuales con comprobante PDF, escáner de código de barras | ✅ |
| 3 | Compras y Ventas: proveedores, órdenes de compra (alta, edición, aprobación, recepción parcial o total con lotes, PDF), devoluciones a proveedor, clientes, órdenes de venta (aprobar, enviar, cancelar, PDF y remisión), devoluciones de clientes | ✅ |
| 4 | Punto de venta: abrir caja, catálogo con escáner (también códigos de presentaciones), venta con total calculado por el servidor, cobro en efectivo/tarjeta/transferencia sin cobros duplicados, ticket PDF, cierre de caja, tickets y cortes | ✅ |
| 5 | CFDIs: facturar ventas enviadas, timbrar, cancelar, PDF/XML, envío por correo, complementos de pago, notas de crédito, factura global, configuración fiscal con carga de CSD | ✅ |
| 6 | Administración y Ayuda: usuarios, permisos, almacenes, ajustes de cuenta, tutoriales, Boxy, sugerencias, Backoffice | Pendiente |

Mientras un módulo no está en la app, su pantalla ofrece **Abrir en la web**.
Elegir plan y pagar la suscripción se hace en la web (Stripe).

## Pendiente antes de publicar

- Firma de release (keystore) en `android/app/build.gradle.kts`.
- Ícono y splash nativos con el logo.
- Probar en un Android real: login, huella, renovación del token tras 15 min,
  bloqueo al volver de segundo plano y cierre de sesión.
- "Continuar con Google" en Android requiere un OAuth Client ID de tipo
  Android (con el SHA-1 de la firma) y un endpoint móvil en el backend.

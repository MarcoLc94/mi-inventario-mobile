import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'api_client.dart';
import 'user_profile.dart';

/// Suscripciones de Google Play (dar de alta en Play Console con estos IDs,
/// un plan base de renovación automática cada uno). Deben coincidir con
/// GooglePlayBilling::PRODUCT_PLANS del backend.
const playProductIds = {'mi_inventario_mensual', 'mi_inventario_anual'};
const playPackage = 'space.miinventario.app';

/// Compra con Google Play Billing. Cada compra se manda al backend
/// (POST /billing/google_play), que la verifica con Google, activa el plan y
/// la reconoce; después se marca como completada en el teléfono.
class PlayBilling extends ChangeNotifier {
  PlayBilling(this.api);

  final ApiClient api;
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool available = false;
  bool loading = false;
  bool busy = false;
  String? message;
  String? error;
  Map<String, GooglePlayProductDetails> products = {};

  /// Se llama cuando el backend confirmó una compra (para recargar el plan).
  VoidCallback? onVerified;

  Future<void> start() async {
    _subscription ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      error = 'Google Play no pudo completar la compra.';
      busy = false;
      notifyListeners();
    });
    loading = true;
    notifyListeners();
    try {
      available = await _iap.isAvailable();
      if (!available) {
        error = 'Google Play no está disponible en este teléfono.';
        return;
      }
      final response = await _iap.queryProductDetails(playProductIds);
      products = {
        for (final id in playProductIds)
          if (_bestOffer(response.productDetails, id) != null) id: _bestOffer(response.productDetails, id)!,
      };
      if (products.isEmpty) error = 'Los planes todavía no están disponibles en Google Play.';
    } catch (_) {
      error = 'No se pudieron consultar los planes de Google Play.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// De las ofertas que Google devuelve para un producto (plan base y ofertas
  /// para las que el usuario califica), la de menor precio inicial: así se
  /// aprovecha una prueba gratis o un precio de introducción si existe.
  GooglePlayProductDetails? _bestOffer(List<ProductDetails> all, String id) {
    final offers = all.whereType<GooglePlayProductDetails>().where((p) => p.id == id).toList()
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    return offers.firstOrNull;
  }

  /// Precio recurrente (última fase) y, si hay, aviso de la fase inicial.
  ({String price, String? intro}) priceOf(GooglePlayProductDetails product) {
    final index = product.subscriptionIndex;
    final phases = index == null ? null : product.productDetails.subscriptionOfferDetails?[index].pricingPhases;
    if (phases == null || phases.isEmpty) return (price: product.price, intro: null);
    final recurring = phases.last.formattedPrice;
    final first = phases.first;
    if (phases.length == 1) return (price: recurring, intro: null);
    return (price: recurring, intro: first.priceAmountMicros == 0 ? 'Prueba gratis al inicio' : 'Precio de introducción: ${first.formattedPrice}');
  }

  Future<void> buy(GooglePlayProductDetails product, {required int accountId}) async {
    error = null;
    message = null;
    busy = true;
    notifyListeners();
    try {
      // applicationUserName = obfuscatedAccountId: el backend comprueba que la
      // compra sea de esta cuenta.
      final started = await _iap.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(productDetails: product, applicationUserName: '$accountId', offerToken: product.offerToken),
      );
      if (!started) {
        busy = false;
        notifyListeners();
      }
    } catch (e) {
      busy = false;
      error = 'No se pudo iniciar la compra en Google Play.';
      notifyListeners();
    }
  }

  /// Vuelve a enviar al backend las suscripciones activas de esta cuenta de Google.
  Future<void> restore({required int accountId}) async {
    error = null;
    message = 'Buscando tus compras en Google Play…';
    busy = true;
    notifyListeners();
    try {
      await _iap.restorePurchases(applicationUserName: '$accountId');
    } catch (_) {
      error = 'No se pudieron consultar tus compras.';
    }
    // Si no hay compras, Google no emite nada: se libera el estado tras un momento.
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (busy && message == 'Buscando tus compras en Google Play…') {
        busy = false;
        message = 'No encontramos suscripciones activas en esta cuenta de Google.';
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          message = 'Pago en proceso. Te avisaremos cuando Google lo confirme.';
          busy = true;
        case PurchaseStatus.canceled:
          busy = false;
          message = null;
        case PurchaseStatus.error:
          busy = false;
          error = purchase.error?.message ?? 'Google Play rechazó la compra.';
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(purchase);
      }
      notifyListeners();
    }
  }

  Future<void> _verify(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData;
    try {
      final result = asMap(await api.post('/billing/google_play', {'purchase_token': token}));
      message = result['subscription_active'] == true ? '¡Listo! Tu suscripción está activa.' : 'Compra registrada. Esperando confirmación de Google.';
      error = null;
      if (purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (_) {
          // El backend ya la reconoció con Google.
        }
      }
      onVerified?.call();
    } on ApiException catch (e) {
      // Sin confirmar no se completa: Google la reembolsa si nunca se reconoce.
      error = e.message;
    } finally {
      busy = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Datos de sesión que devuelve el backend (mismo JSON que el login web):
/// el menú los usa para mostrar, ocultar o bloquear módulos.
class UserProfile {
  UserProfile(this.raw, {this.account = const {}, this.permissions = const {}});

  final Map<String, dynamic> raw;
  final Map<String, dynamic> account;
  final Map<String, dynamic> permissions;

  factory UserProfile.fromSession(Map<String, dynamic> json) => UserProfile(
        asMap(json['user']),
        account: asMap(json['account']),
        permissions: asMap(json['permissions']),
      );

  Map<String, dynamic> toJson() => {'user': raw, 'account': account, 'permissions': permissions};

  int? get id => (raw['id'] as num?)?.toInt();
  String get email => raw['email']?.toString() ?? '';
  String get firstName => raw['first_name']?.toString() ?? '';
  String get lastName => raw['last_name']?.toString() ?? '';
  String get role => raw['role']?.toString() ?? '';
  bool get isAdmin => role == 'admin';
  String? get profilePictureUrl => raw['profile_picture_url']?.toString();
  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? email : name;
  }

  bool get backofficePermission => raw['backoffice_permission'] == true;
  bool get invoicingActive => raw['account_invoicing_active'] == true;
  bool get inventoryActive => raw['account_inventory_active'] == true;
  bool get posActive => raw['account_pos_active'] == true;
  List<String> get enabledModules =>
      (raw['account_enabled_modules'] as List?)?.map((e) => e.toString()).toList() ?? const [];
  bool get canReadSaleInvoices => asMap(raw['sale_invoices_permission'])['read'] == true;
  bool get canReadPos => asMap(raw['pos_permission'])['read'] == true;

  String get accountName => account['name']?.toString() ?? '';
  String get accountStatus => account['status']?.toString() ?? '';
  String? get accountPlan => account['plan']?.toString();
  DateTime? get trialEndsAt => DateTime.tryParse(account['trial_ends_at']?.toString() ?? '');
}

Map<String, dynamic> asMap(dynamic value) =>
    value is Map ? value.map((key, val) => MapEntry(key.toString(), val)) : <String, dynamic>{};

List<Map<String, dynamic>> asMapList(dynamic value) =>
    value is List ? value.map(asMap).toList() : <Map<String, dynamic>>[];

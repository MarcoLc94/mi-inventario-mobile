import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

/// Descarga un PDF de la API y lo abre con el visor del teléfono.
Future<void> openRemotePdf(ApiClient api, String path, String fileName) async {
  final bytes = await api.download(path);
  final dir = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path, type: 'application/pdf');
  if (result.type != ResultType.done) {
    throw ApiException(0, 'No hay una app para abrir PDF en este teléfono. El archivo se guardó en ${file.path}.');
  }
}

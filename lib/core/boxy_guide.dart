import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/help/tutorials_data.dart';
import 'api_client.dart';
import 'config.dart';
import 'session.dart';
import 'user_profile.dart';

// Mismo texto que InventoryGuide.tsx y SCRIPT en guide_speech_synthesizer.rb:
// el backend solo genera voz para esas frases.
const boxyWelcome =
    '¡Hola! Soy Boxy, tu asistente de Mi Inventario. Puedo enseñarte lo básico con un tutorial rápido o ayudarte a resolver tus dudas. ¿Qué prefieres?';
const boxyReturning = '¡Hola de nuevo! Soy Boxy. ¿Qué necesitas? Podemos repasar el tutorial básico o conversar sobre tu inventario.';
const boxyPending =
    'Todavía falta completar este paso. Hazlo en la pantalla y después pulsa Continuar. También puedes saltar el tutorial cuando quieras.';
const boxyCheckFailed = 'No pude comprobar el paso. Pulsa Continuar para reintentar.';

/// Pantallas donde Boxy no aparece (igual que la web).
const _hiddenPaths = ['/account-settings', '/billing', '/settings/delete-account'];

enum BoxyVoice { idle, loading, playing, failed }

/// Boxy en la app, con las mismas reglas que la guía de la web: bienvenida la
/// primera vez, el tutorial de cada módulo se abre al llegar a su pantalla y
/// el avance se guarda por usuario en el teléfono.
class BoxyGuide extends ChangeNotifier {
  BoxyGuide(this.api, this.session) {
    session.addListener(_sessionChanged);
    unawaited(_sessionChanged());
  }

  final ApiClient api;
  final SessionController session;
  AudioPlayer? _playerInstance;

  /// El reproductor se crea la primera vez que Boxy habla.
  AudioPlayer get _player => _playerInstance ??= AudioPlayer()..onPlayerComplete.listen((_) => _finishSpeech());
  SharedPreferences? _prefs;
  int? _userId;

  Tutorial? tutorial;
  int step = 0;
  String status = 'skipped';
  bool helpOpen = false;
  bool welcome = false;
  bool visible = true;
  bool minimized = false;
  bool muted = false;
  bool busy = false;
  bool checkFailed = false;
  String notice = '';
  String _path = '/';
  String _query = '';

  /// Voz y "karaoke": cuántos caracteres del diálogo van leídos.
  BoxyVoice voice = BoxyVoice.idle;
  int revealed = 0;
  bool speaking = false;
  String _spoken = '';
  List<({int end, Duration start})> _marks = const [];
  List<int> _letterTimes = const [];
  Timer? _typing;
  Timer? _karaoke;
  int _attempt = 0;

  UserProfile? get user => session.profile;
  bool get guiding => tutorial != null && status == 'open';
  TutorialStep get current => tutorial!.steps[step.clamp(0, tutorial!.steps.length - 1)];
  bool get isLast => tutorial != null && step >= tutorial!.steps.length - 1;
  bool get hiddenHere => _hiddenPaths.contains(_path);
  bool get showing => visible && !hiddenHere && (helpOpen || guiding);

  /// Lo que Boxy dice ahora.
  String get dialogue => helpOpen ? (welcome ? boxyWelcome : boxyReturning) : (notice.isNotEmpty ? notice : (guiding ? current.text : ''));

  /// ¿Está el usuario en la pantalla del paso actual?
  bool get onStepScreen {
    final target = guiding ? current.path : null;
    if (target == null) return true;
    final uri = Uri.parse(target);
    return uri.path == _path && (uri.query.isEmpty || uri.query == _query);
  }

  String _key(String id) => id == 'inventory' ? 'inventory-guide-v1:$_userId' : 'boxy-guide-v1:$_userId:$id';

  bool allowed(String id) {
    final profile = user;
    if (profile == null || !profile.enabledModules.contains(id)) return false;
    return id != 'pos' || profile.canReadPos;
  }

  Future<void> _sessionChanged() async {
    final id = user?.id;
    if (id == _userId) return;
    _userId = id;
    _stopSpeech();
    tutorial = null;
    status = 'skipped';
    helpOpen = welcome = false;
    notice = '';
    if (id == null) {
      notifyListeners();
      return;
    }
    _prefs ??= await SharedPreferences.getInstance();
    visible = _prefs!.getBool('boxy-visible:$id') ?? true;
    muted = _prefs!.getBool('boxy-muted:$id') ?? false;
    if (!(_prefs!.getBool('boxy-welcome-v1:$id') ?? false)) {
      welcome = helpOpen = true;
      await _prefs!.setBool('boxy-welcome-v1:$id', true);
    }
    onLocation(Uri(path: _path, query: _query.isEmpty ? null : _query));
  }

  /// Al cambiar de pantalla: retoma el tutorial del módulo o lo abre si nunca se vio.
  void onLocation(Uri location) {
    _path = location.path;
    _query = location.query;
    if (_userId == null || _prefs == null) return;
    if (guiding && tutorial!.steps.any((s) => s.path != null && Uri.parse(s.path!).path == _path)) {
      _changed();
      return;
    }
    final id = tutorialForPath(_path);
    if (id == null || !allowed(id)) {
      if (tutorial != null && status == 'open') status = 'skipped';
      _changed();
      return;
    }
    var next = (step: 0, status: 'open');
    final saved = _prefs!.getString(_key(id));
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        final value = (data['step'] as num?)?.toInt() ?? 0;
        final state = data['status']?.toString() ?? 'open';
        if (value >= 0 && value < tutorialById(id)!.steps.length && ['open', 'skipped', 'finished'].contains(state)) {
          next = (step: value, status: state);
        }
      } catch (_) {}
    } else {
      _prefs!.setString(_key(id), jsonEncode({'step': 0, 'status': 'open'}));
    }
    tutorial = tutorialById(id);
    step = next.step;
    status = next.status;
    notice = '';
    if (guiding && !welcome) helpOpen = false;
    _changed();
  }

  void _save(int value, String state) {
    step = value;
    status = state;
    if (tutorial != null) _prefs?.setString(_key(tutorial!.id), jsonEncode({'step': value, 'status': state}));
  }

  /// Abre la ayuda de Boxy (botón de la barra superior).
  void openHelp() {
    notice = '';
    welcome = false;
    helpOpen = true;
    minimized = false;
    setVisible(true);
  }

  /// Cierra la burbuja: si había tutorial abierto, queda como saltado.
  void close() {
    helpOpen = welcome = false;
    notice = '';
    if (guiding) _save(step, 'skipped');
    _stopSpeech();
    _changed();
  }

  void skip() {
    notice = '';
    _save(step, 'skipped');
    _stopSpeech();
    _changed();
  }

  void setMinimized(bool value) {
    minimized = value;
    if (value) _stopSpeech();
    _changed();
  }

  void setVisible(bool value) {
    visible = value;
    _prefs?.setBool('boxy-visible:$_userId', value);
    if (!value) _stopSpeech();
    _changed();
  }

  void toggleMuted() {
    muted = !muted;
    _prefs?.setBool('boxy-muted:$_userId', muted);
    _playerInstance?.setVolume(muted ? 0 : 1);
    notifyListeners();
  }

  /// Empieza un tutorial; devuelve la pantalla que hay que abrir.
  String? start(String id) {
    final found = tutorialById(id);
    if (found == null || !allowed(id)) return null;
    tutorial = found;
    _save(0, 'open');
    helpOpen = welcome = minimized = false;
    notice = '';
    setVisible(true);
    return found.steps.first.path ?? (id == 'inventory' ? '/products' : '/pos');
  }

  /// Continuar: lleva a la pantalla del paso, comprueba su requisito y avanza.
  /// Devuelve la ruta a abrir, si hay que navegar.
  Future<String?> advance() async {
    if (busy || !guiding) return null;
    busy = true;
    notice = '';
    checkFailed = false;
    _changed();
    try {
      final target = current;
      if (!onStepScreen) return target.path;
      if (target.requirement != null) {
        final progress = asMap(await api.get('/inventory_tutorial'));
        if (progress[target.requirement] != true) {
          notice = boxyPending;
          return null;
        }
      }
      if (isLast) {
        _save(step, 'finished');
        return null;
      }
      _save(step + 1, 'open');
      return current.path;
    } catch (_) {
      checkFailed = true;
      notice = boxyCheckFailed;
      return null;
    } finally {
      busy = false;
      _changed();
    }
  }

  /// Vuelve a decir el diálogo actual.
  void replay() {
    _spoken = '';
    _changed();
  }

  void _changed() {
    notifyListeners();
    _syncSpeech();
  }

  // ---- Voz -----------------------------------------------------------------

  void _syncSpeech() {
    final text = showing && !minimized ? dialogue : '';
    if (text == _spoken) return;
    _spoken = text;
    _stopSpeech(keepText: true);
    if (text.isNotEmpty) unawaited(_speak(text));
  }

  Future<void> _speak(String text) async {
    final attempt = ++_attempt;
    revealed = 0;
    voice = BoxyVoice.loading;
    notifyListeners();
    try {
      final clip = asMap(await api.post('/guide_speech', {'text': text}).timeout(const Duration(seconds: 45)));
      if (attempt != _attempt) return;
      var url = clip['audio_url']?.toString() ?? '';
      if (url.isEmpty) throw StateError('sin audio');
      if (url.startsWith('/')) url = '${AppConfig.apiBaseUrl}$url';
      _marks = _wordMarks(text, asMapList(clip['words']));
      await _player.setVolume(muted ? 0 : 1);
      await _player.play(UrlSource(url));
      if (attempt != _attempt) return;
      voice = BoxyVoice.playing;
      speaking = true;
      notifyListeners();
      await _followAudio(text, attempt);
    } catch (_) {
      if (attempt != _attempt) return;
      // Sin voz: Boxy sigue escribiendo el texto letra por letra.
      voice = BoxyVoice.failed;
      _typeText(text);
    }
  }

  void _typeText(String text) {
    speaking = true;
    _typing?.cancel();
    _typing = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      revealed += 1;
      if (revealed >= text.length) {
        _finishSpeech();
      } else {
        notifyListeners();
      }
    });
  }

  /// Ilumina las letras al ritmo del audio: con marcas por palabra si el
  /// proveedor las da; si no, con tiempos estimados por letra ajustados a la
  /// duración real (letterTimings + scaleTimings de la web).
  Future<void> _followAudio(String text, int attempt) async {
    Duration? duration;
    for (var i = 0; i < 20 && duration == null && attempt == _attempt; i++) {
      duration = await _player.getDuration();
      if (duration == null) await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (attempt != _attempt) return;
    _letterTimes = _scaledLetterTimes(text, duration);
    _karaoke?.cancel();
    _karaoke = Timer.periodic(const Duration(milliseconds: 40), (timer) async {
      if (attempt != _attempt || voice != BoxyVoice.playing) {
        timer.cancel();
        return;
      }
      final position = await _player.getCurrentPosition();
      if (position == null || attempt != _attempt) return;
      final count = _countAt(position);
      if (count != revealed) {
        revealed = count;
        notifyListeners();
      }
    });
  }

  int _countAt(Duration position) {
    if (_marks.isNotEmpty) {
      var count = 0;
      for (final mark in _marks) {
        if (mark.start <= position) count = mark.end;
      }
      return count;
    }
    final ms = position.inMilliseconds;
    final next = _letterTimes.indexWhere((time) => time > ms);
    return next == -1 ? _letterTimes.length : next;
  }

  static List<int> _scaledLetterTimes(String text, Duration? duration) {
    var elapsed = 0;
    final times = [
      for (final letter in text.split(''))
        elapsed += RegExp(r'[.!?…]').hasMatch(letter)
            ? 240
            : RegExp(r'[,;:]').hasMatch(letter)
                ? 140
                : letter.trim().isEmpty
                    ? 35
                    : 55,
    ];
    final total = duration?.inMilliseconds ?? 0;
    if (times.isEmpty || total <= 0) return times;
    final scale = total / times.last;
    return [for (final time in times) (time * scale).round()];
  }

  void _finishSpeech() {
    _typing?.cancel();
    _karaoke?.cancel();
    speaking = false;
    revealed = _spoken.length;
    notifyListeners();
  }

  void _stopSpeech({bool keepText = false}) {
    _attempt++;
    _typing?.cancel();
    _karaoke?.cancel();
    unawaited(_playerInstance?.stop());
    speaking = false;
    if (!keepText) _spoken = '';
    voice = BoxyVoice.idle;
  }

  /// Une cada palabra con timestamps a su posición en el texto.
  static List<({int end, Duration start})> _wordMarks(String text, List<Map<String, dynamic>> words) {
    final marks = <({int end, Duration start})>[];
    var cursor = 0;
    for (final word in words) {
      final token = word['text']?.toString().trim() ?? '';
      if (token.isEmpty) continue;
      final index = text.indexOf(token, cursor);
      if (index < 0) continue;
      cursor = index + token.length;
      final seconds = (word['start'] as num?)?.toDouble() ?? 0;
      marks.add((end: cursor, start: Duration(milliseconds: (seconds * 1000).round())));
    }
    return marks;
  }

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    _typing?.cancel();
    _karaoke?.cancel();
    _playerInstance?.dispose();
    super.dispose();
  }
}

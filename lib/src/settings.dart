// Настройки и прогресс. Ключи JSON совпадают с Go-версией (settings.go),
// поэтому опыт и уровень сохраняются при переходе на Dart.

import 'dart:convert';
import 'dart:io';

import 'content.dart';

class Settings {
  int size = 1; // 0..3
  bool dnd = false;
  bool clickThrough = false;
  bool autostart = true;
  bool walk = true;
  bool windowHop = true;
  bool appReact = true;
  bool chatter = true;
  bool bugs = true;
  bool water = true;
  int waterMin = 45;
  bool stretch = true;
  bool night = true;
  int pomoFocus = 25;
  int pomoBreak = 5;
  int pomoLong = 15;

  int xp = 0;
  double codingSeconds = 0;
  int bugsDefeated = 0;
  int bugsEscaped = 0;
  int pomosDone = 0;
  String lastTipDate = '';
  int tipIndex = 0;
  bool firstRunDone = false;
  double posX = 0;
  double posY = 0;
  bool hasPos = false;

  Settings();

  factory Settings.fromJson(Map<String, dynamic> j) {
    final s = Settings();
    int i(String k, int d) => j[k] is num ? (j[k] as num).toInt() : d;
    double f(String k, double d) => j[k] is num ? (j[k] as num).toDouble() : d;
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    String str(String k, String d) => j[k] is String ? j[k] as String : d;
    s
      ..size = i('size', s.size)
      ..dnd = b('dnd', s.dnd)
      ..clickThrough = b('clickThrough', s.clickThrough)
      ..autostart = b('autostart', s.autostart)
      ..walk = b('walk', s.walk)
      ..windowHop = b('windowHop', s.windowHop)
      ..appReact = b('appReact', s.appReact)
      ..chatter = b('chatter', s.chatter)
      ..bugs = b('bugs', s.bugs)
      ..water = b('water', s.water)
      ..waterMin = i('waterMin', s.waterMin)
      ..stretch = b('stretch', s.stretch)
      ..night = b('night', s.night)
      ..pomoFocus = i('pomoFocus', s.pomoFocus)
      ..pomoBreak = i('pomoBreak', s.pomoBreak)
      ..pomoLong = i('pomoLong', s.pomoLong)
      ..xp = i('xp', s.xp)
      ..codingSeconds = f('codingSeconds', s.codingSeconds)
      ..bugsDefeated = i('bugsDefeated', s.bugsDefeated)
      ..bugsEscaped = i('bugsEscaped', s.bugsEscaped)
      ..pomosDone = i('pomosDone', s.pomosDone)
      ..lastTipDate = str('lastTipDate', s.lastTipDate)
      ..tipIndex = i('tipIndex', s.tipIndex)
      ..firstRunDone = b('firstRunDone', s.firstRunDone)
      ..posX = f('posX', s.posX)
      ..posY = f('posY', s.posY)
      ..hasPos = b('hasPos', s.hasPos);
    return s;
  }

  Map<String, Object> toJson() => {
        'size': size,
        'dnd': dnd,
        'clickThrough': clickThrough,
        'autostart': autostart,
        'walk': walk,
        'windowHop': windowHop,
        'appReact': appReact,
        'chatter': chatter,
        'bugs': bugs,
        'water': water,
        'waterMin': waterMin,
        'stretch': stretch,
        'night': night,
        'pomoFocus': pomoFocus,
        'pomoBreak': pomoBreak,
        'pomoLong': pomoLong,
        'xp': xp,
        'codingSeconds': codingSeconds,
        'bugsDefeated': bugsDefeated,
        'bugsEscaped': bugsEscaped,
        'pomosDone': pomosDone,
        'lastTipDate': lastTipDate,
        'tipIndex': tipIndex,
        'firstRunDone': firstRunDone,
        'posX': posX,
        'posY': posY,
        'hasPos': hasPos,
      };

  void _sanitize() {
    if (size < 0 || size >= sizeFactors.length) size = 1;
    if (waterMin < 10) waterMin = 45;
    if (pomoFocus < 1) pomoFocus = 25;
    if (pomoBreak < 1) pomoBreak = 5;
    if (pomoLong < 1) pomoLong = 15;
  }
}

const sizeFactors = [0.30, 0.40, 0.52, 0.68];
const sizeNames = ['Маленький', 'Средний', 'Большой', 'Огромный'];

/// %APPDATA%\Dartty — как os.UserConfigDir() в Go.
String configDir() {
  final env = Platform.environment;
  final base = env['APPDATA'] ?? (env['XDG_CONFIG_HOME'] ?? (env['HOME'] != null ? '${env['HOME']}/.config' : '.'));
  return '$base${Platform.pathSeparator}Dartty';
}

String settingsPath() => '${configDir()}${Platform.pathSeparator}settings.json';

Settings loadSettings() {
  var s = Settings();
  try {
    final f = File(settingsPath());
    if (f.existsSync()) {
      final j = jsonDecode(f.readAsStringSync());
      if (j is Map<String, dynamic>) s = Settings.fromJson(j);
    }
  } catch (_) {
    // испорченный файл — начинаем с настроек по умолчанию
  }
  s._sanitize();
  return s;
}

void saveSettings(Settings s) {
  try {
    final p = settingsPath();
    Directory(configDir()).createSync(recursive: true);
    final tmp = File('$p.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(s.toJson()));
    tmp.renameSync(p);
  } catch (_) {
    // не удалось сохранить — попробуем в следующий раз
  }
}

/// Уровень L → L+1 стоит 60·L XP (1 XP = минута кода).
({int level, int into, int need, String title}) levelInfo(int xp) {
  var level = 1, need = 60, start = 0;
  while (xp >= start + need) {
    start += need;
    level++;
    need = 60 * level;
  }
  return (level: level, into: xp - start, need: need, title: levelTitle(level));
}

String levelTitle(int level) => level <= levelTitles.length ? levelTitles[level - 1] : 'Легенда pub.dev';

import 'package:flutter/material.dart';

class EchoColors {
  static const background = Color(0xFF0A0A1A);
  static const primary = Color(0xFF7C3AED);
  static const primaryLight = Color(0xFFA78BFA);
  static const danger = Color(0xFFEF4444);
  static const dangerDark = Color(0xFFDC2626);
  static const dangerDarker = Color(0xFF7F1D1D);
  static const success = Color(0xFF22C55E);
  static const info = Color(0xFF3B82F6);
  static const surface = Color(0xFF1A1A2E);
  static const textDim = Color(0xFF666666);
  static const textMid = Color(0xFFA0A0C0);
}

class EchoText {
  static const title = TextStyle(
    fontSize: 68,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    letterSpacing: 8,
  );

  static const titleAccent = TextStyle(
    fontSize: 68,
    fontWeight: FontWeight.w900,
    color: EchoColors.primary,
    letterSpacing: 8,
  );

  static const subtitle = TextStyle(
    fontSize: 14,
    color: EchoColors.textMid,
    letterSpacing: 4,
    fontStyle: FontStyle.italic,
  );

  static const button = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 3,
  );
}
class Enemy {
  final int id;
  double x;
  double y;
  final double speed;

  Enemy({
    required this.id,
    required this.x,
    required this.y,
    required this.speed,
  });

  void update() {
    y += speed;
  }
}
class Shockwave {
  final int id;
  final double x;
  final double y;
  double radius;
  final double power;
  final double maxRadius;

  Shockwave({
    required this.id,
    required this.x,
    required this.y,
    this.radius = 0,
    required this.power,
    this.maxRadius = 400,
  });

  bool get isDead => radius >= maxRadius;

  double get opacity {
    final v = 1.0 - (radius / maxRadius);
    return v.clamp(0.0, 1.0);
  }
}
import 'enemy.dart';
import 'shockwave.dart';

class GameState {
  double health;
  double energy;
  int score;
  int level;
  int combo;
  double time;
  List<Enemy> enemies;
  List<Shockwave> shockwaves;
  bool isGameOver;

  GameState({
    this.health = 100,
    this.energy = 100,
    this.score = 0,
    this.level = 1,
    this.combo = 0,
    this.time = 0,
    List<Enemy>? enemies,
    List<Shockwave>? shockwaves,
    this.isGameOver = false,
  })  : enemies = enemies ?? [],
        shockwaves = shockwaves ?? [];

  void reset() {
    health = 100;
    energy = 100;
    score = 0;
    level = 1;
    combo = 0;
    time = 0;
    enemies.clear();
    shockwaves.clear();
    isGameOver = false;
  }
}
import 'dart:async';
import 'dart:math';
import 'package:record/record.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _sub;
  final _volumeController = StreamController<double>.broadcast();

  Stream<double> get volumeStream => _volumeController.stream;
  double _volume = 0;
  double get volume => _volume;

  bool _isListening = false;
  bool get isListening => _isListening;

  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) return false;

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );

      _isListening = true;

      // Listen to amplitude stream via record package
      _sub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        // amp.current is in dB (negative). Typical range: -50..0
        // Convert to 0..100
        final db = amp.current;
        final normalized = ((db + 50) * 2).clamp(0, 100).toDouble();
        _volume = normalized;
        _volumeController.add(normalized);
      });

      return true;
    } catch (e) {
      // ignore
      return false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (_recorder.isRecording()) {
      await _recorder.stop();
    }
    _isListening = false;
    _volume = 0;
  }

  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
    _volumeController.close();
  }
}
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../models/enemy.dart';
import '../models/game_state.dart';
import '../models/shockwave.dart';

class GameEngine extends ChangeNotifier {
  static const double _width = 400;
  static const double _height = 800;

  GameState _state = GameState();
  GameState get state => _state;

  double _volume = 0;
  double get volume => _volume;

  Size _screenSize = const Size(_width, _height);
  Offset _playerPos = const Offset(200, 650);

  Offset get playerPos => _playerPos;
  Size get screenSize => _screenSize;

  Timer? _loop;
  Timer? _spawnTimer;
  DateTime _lastFrame = DateTime.now();
  int _spawnCount = 0;
  double _lastVolume = 0;
  DateTime _lastHeal = DateTime.now();
  DateTime _lastShockwave = DateTime.now();

  bool _running = false;
  bool get running => _running;

  void init(Size screenSize) {
    _screenSize = screenSize;
    _playerPos = Offset(screenSize.width / 2, screenSize.height - 150);
  }

  void start() {
    _running = true;
    _state.reset();
    _lastFrame = DateTime.now();
    _loop = Timer.periodic(const Duration(milliseconds: 16), _tick);
    _scheduleSpawn();
  }

  void _scheduleSpawn() {
    _spawnTimer?.cancel();
    final interval = max(800, 2000 - _state.level * 100);
    _spawnTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
      if (!_running) return;
      _spawnEnemy();
    });
  }

  void _spawnEnemy() {
    final rand = Random();
    _spawnCount++;
    _state.enemies.add(Enemy(
      id: DateTime.now().microsecondsSinceEpoch + _spawnCount,
      x: rand.nextDouble() * (_screenSize.width - 60) + 30,
      y: -30,
      speed: 1 + rand.nextDouble() * 2 + _state.level * 0.3,
    ));
    notifyListeners();
  }

  void _tick(Timer timer) {
    if (!_running) return;
    final now = DateTime.now();
    final dt = now.difference(_lastFrame).inMilliseconds / 16.67;
    _lastFrame = now;
    _state.time += dt;

    // Move enemies
    final enemiesToRemove = <int>[];
    for (final enemy in _state.enemies) {
      enemy.y += enemy.speed * dt;

      // Off-screen → damage player
      if (enemy.y > _screenSize.height + 40) {
        enemiesToRemove.add(enemy.id);
        _state.health = (_state.health - 10).clamp(0, 100);
        _vibrate(30);
        continue;
      }

      // Collision with player
      final dist = (Offset(enemy.x, enemy.y) - _playerPos).distance;
      if (dist < 45) {
        enemiesToRemove.add(enemy.id);
        _state.health = (_state.health - 15).clamp(0, 100);
        _vibrate(60);
      }
    }
    _state.enemies.removeWhere((e) => enemiesToRemove.contains(e.id));

    // Update shockwaves
    for (final sw in _state.shockwaves) {
      sw.radius += 15 * dt;
    }
    _state.shockwaves.removeWhere((sw) => sw.isDead);

    // Update level
    final newLevel = (_state.score / 1000).floor() + 1;
    if (newLevel != _state.level) {
      _state.level = newLevel;
      _scheduleSpawn();
    }

    if (_state.health <= 0 && !_state.isGameOver) {
      _state.isGameOver = true;
      _running = false;
      _loop?.cancel();
      _spawnTimer?.cancel();
    }

    notifyListeners();
  }

  // Volume → Action
  void onVolume(double v) {
    _volume = v;
    notifyListeners();
    if (!_running) return;

    final now = DateTime.now();

    // SHOUT → shockwave
    if (v > 60 && now.difference(_lastShockwave).inMilliseconds > 350) {
      _lastShockwave = now;
      _triggerShockwave(v);
    } else if (v > 20 && v < 40) {
      // WHISPER → slow heal
      if (now.difference(_lastHeal).inMilliseconds > 200) {
        _lastHeal = now;
        _state.health = (_state.health + 0.3).clamp(0, 100);
      }
    }
    _lastVolume = v;
  }

  void _triggerShockwave(double power) {
    final sw = Shockwave(
      id: DateTime.now().microsecondsSinceEpoch,
      x: _playerPos.dx,
      y: _playerPos.dy,
      power: power,
      maxRadius: 400,
    );
    _state.shockwaves.add(sw);

    // Damage enemies in range
    final toRemove = <int>[];
    for (final enemy in _state.enemies) {
      final dist = (Offset(enemy.x, enemy.y) - _playerPos).distance;
      if (dist < 200) {
        toRemove.add(enemy.id);
        _state.score += 100;
        _state.combo++;
      }
    }
    if (toRemove.isNotEmpty) {
      _state.enemies.removeWhere((e) => toRemove.contains(e.id));
      _vibrate(80);
    }
    notifyListeners();
  }

  void movePlayer(double dx) {
    final x = dx.clamp(30.0, _screenSize.width - 30);
    _playerPos = Offset(x, _playerPos.dy);
    notifyListeners();
  }

  void _vibrate(int duration) {
    Vibration.hasVibrator().then((has) {
      if (has == true) Vibration.vibrate(duration: duration);
    });
  }

  void disposeEngine() {
    _loop?.cancel();
    _spawnTimer?.cancel();
    _running = false;
  }

  @override
  void dispose() {
    disposeEngine();
    super.dispose();
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'screens/main_menu.dart';
import 'services/game_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const EchoRealmApp());
}

class EchoRealmApp extends StatelessWidget {
  const EchoRealmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echo Realm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: EchoColors.background,
        primaryColor: EchoColors.primary,
        fontFamily: 'Roboto',
      ),
      home: const _RootNavigator(),
    );
  }
}

class _RootNavigator extends StatefulWidget {
  const _RootNavigator();
  @override
  State<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<_RootNavigator> {
  String _screen = 'menu';
  int _finalScore = 0;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameEngine(),
      child: switch (_screen) {
        'game' => GameScreenWrapper(
            onGameOver: (score) => setState(() {
              _finalScore = score;
              _screen = 'over';
            }),
          ),
        'over' => GameOverScreen(
            score: _finalScore,
            onRestart: () => setState(() => _screen = 'game'),
            onMenu: () => setState(() => _screen = 'menu'),
          ),
        _ => MainMenuScreen(
            onStart: () => setState(() => _screen = 'game'),
          ),
      },
    );
  }
}

// Wrapper so GameEngine is recreated fresh each new game
class GameScreenWrapper extends StatelessWidget {
  final ValueChanged<int> onGameOver;
  const GameScreenWrapper({super.key, required this.onGameOver});

  @override
  Widget build(BuildContext context) {
    // Rebuild engine when wrapper remounts
    return _GameHost(onGameOver: onGameOver);
  }
}

class _GameHost extends StatefulWidget {
  final ValueChanged<int> onGameOver;
  const _GameHost({required this.onGameOver});

  @override
  State<_GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<_GameHost> {
  @override
  Widget build(BuildContext context) {
    return GameScreen(onGameOver: widget.onGameOver);
  }
}

// Re-export screens
import 'screens/game_screen.dart' show GameScreen;
import 'screens/game_over.dart' show GameOverScreen;
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class MainMenuScreen extends StatefulWidget {
  final VoidCallback onStart;
  const MainMenuScreen({super.key, required this.onStart});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _floatCtrl;
  late final Animation<double> _pulse;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _float = Tween<double>(begin: 0, end: -20).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: EchoColors.background,
      body: Stack(
        children: [
          // Radial glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    EchoColors.primary.withOpacity(0.6),
                    EchoColors.background.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
          // Starfield
          Positioned.fill(
            child: CustomPaint(painter: _StarfieldPainter()),
          ),
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _float,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, _float.value),
                    child: Column(
                      children: [
                        const Text('ECHO', style: EchoText.title),
                        Transform.translate(
                          offset: const Offset(0, -20),
                          child: const Text('REALM',
                              style: EchoText.titleAccent),
                        ),
                        const SizedBox(height: 20),
                        const Text('Speak. Shout. Survive.',
                            style: EchoText.subtitle),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 60),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Transform.scale(
                    scale: _pulse.value,
                    child: child,
                  ),
                  child: _NeonButton(
                    label: '▶  BEGIN',
                    onTap: widget.onStart,
                  ),
                ),
              ],
            ),
          ),
          // Hint
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              '🎤 Uses microphone for gameplay',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: EchoColors.textDim,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeonButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NeonButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
        decoration: BoxDecoration(
          color: EchoColors.primary,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: EchoColors.primaryLight, width: 2),
          boxShadow: [
            BoxShadow(
              color: EchoColors.primary.withOpacity(0.8),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Text('▶  BEGIN', style: EchoText.button),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> stars = List.generate(80, (i) {
    final r = Random(i);
    return _Star(
      Offset(r.nextDouble(), r.nextDouble()),
      0.5 + r.nextDouble() * 1.5,
      0.3 + r.nextDouble() * 0.5,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in stars) {
      paint.color = Colors.white.withOpacity(s.opacity);
      canvas.drawCircle(
        Offset(s.pos.dx * size.width, s.pos.dy * size.height),
        s.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Star {
  final Offset pos;
  final double radius;
  final double opacity;
  _Star(this.pos, this.radius, this.opacity);
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enemy.dart';
import '../models/shockwave.dart';
import '../services/audio_service.dart';
import '../services/game_engine.dart';
import '../theme.dart';

class GameScreen extends StatefulWidget {
  final ValueChanged<int> onGameOver;
  const GameScreen({super.key, required this.onGameOver});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final AudioService _audio = AudioService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final engine = context.read<GameEngine>();
      final size = MediaQuery.of(context).size;
      engine.init(size);
      engine.start();

      // Start audio
      final ok = await _audio.start();
      _audio.volumeStream.listen((v) {
        if (!mounted) return;
        context.read<GameEngine>().onVolume(v);
      });
      _initialized = ok;
    });
  }

  @override
  void dispose() {
    _audio.stop();
    _audio.dispose();
    context.read<GameEngine>().disposeEngine();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EchoColors.background,
      body: Consumer<GameEngine>(
        builder: (context, engine, _) {
          final state = engine.state;

          // Fire game over
          if (state.isGameOver) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onGameOver(state.score);
            });
          }

          return GestureDetector(
            onPanUpdate: (d) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(d.globalPosition);
              engine.movePlayer(local.dx);
            },
            onPanStart: (d) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(d.globalPosition);
              engine.movePlayer(local.dx);
            },
            child: Stack(
              children: [
                // Starfield
                Positioned.fill(
                  child: CustomPaint(painter: _GameStarfieldPainter()),
                ),
                // Game layer (SVG-like, done in CustomPainter)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GamePainter(
                      enemies: state.enemies,
                      shockwaves: state.shockwaves,
                      playerPos: engine.playerPos,
                    ),
                  ),
                ),
                // HUD
                _Hud(engine: engine),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  final GameEngine engine;
  const _Hud({required this.engine});

  @override
  Widget build(BuildContext context) {
    final state = engine.state;
    final v = engine.volume;
    final vColor = v > 60
        ? EchoColors.danger
        : v > 20
            ? EchoColors.success
            : EchoColors.info;
    final vLabel = v > 60
        ? '🔥 SHOUT!'
        : v > 20
            ? '💚 WHISPER'
            : '🎤 SPEAK';

    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: EchoColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (state.health / 100).clamp(0, 1),
                          child: Container(
                            decoration: BoxDecoration(
                              color: EchoColors.success,
                              boxShadow: [
                                BoxShadow(
                                  color: EchoColors.success.withOpacity(0.6),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Text('⚡ ${state.score}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(width: 15),
                Text('LV ${state.level}',
                    style: const TextStyle(
                      color: EchoColors.primaryLight,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    )),
              ],
            ),
          ),
          Positioned(
            bottom: 30,
            left: 30,
            right: 30,
            child: Column(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: EchoColors.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (v / 100).clamp(0, 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          color: vColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  vLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  final List<Enemy> enemies;
  final List<Shockwave> shockwaves;
  final Offset playerPos;

  _GamePainter({
    required this.enemies,
    required this.shockwaves,
    required this.playerPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Enemies
    for (final e in enemies) {
      final center = Offset(e.x, e.y);
      canvas.drawCircle(center, 25,
          Paint()..color = EchoColors.danger.withOpacity(0.4));
      canvas.drawCircle(center, 18, Paint()..color = EchoColors.dangerDark);
      canvas.drawCircle(center, 8, Paint()..color = EchoColors.dangerDarker);
      canvas.drawCircle(center + const Offset(-5, -3), 3,
          Paint()..color = Colors.white);
      canvas.drawCircle(center + const Offset(5, -3), 3,
          Paint()..color = Colors.white);
    }

    // Player glow
    canvas.drawCircle(
      playerPos,
      30,
      Paint()..color = EchoColors.primary.withOpacity(0.3),
    );
    canvas.drawCircle(playerPos, 20, Paint()..color = EchoColors.primaryLight);
    canvas.drawCircle(playerPos, 10, Paint()..color = Colors.white);

    // Shockwaves
    for (final sw in shockwaves) {
      final center = Offset(sw.x, sw.y);
      final paint1 = Paint()
        ..color = EchoColors.primary.withOpacity(sw.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      final paint2 = Paint()
        ..color = EchoColors.primaryLight.withOpacity(sw.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, sw.radius, paint1);
      canvas.drawCircle(center, sw.radius * 0.7, paint2);
    }
  }

  @override
  bool shouldRepaint(covariant _GamePainter old) => true;
}

class _GameStarfieldPainter extends CustomPainter {
  final List<Offset> stars = List.generate(60, (i) {
    // Deterministic pseudo-random
    final x = ((i * 137.5) % 1.0);
    final y = ((i * 73.3) % 1.0);
    return Offset(x, y);
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < stars.length; i++) {
      paint.color = Colors.white.withOpacity(0.3 + (i % 5) * 0.1);
      canvas.drawCircle(
        Offset(stars[i].dx * size.width, stars[i].dy * size.height),
        1 + (i % 3) * 0.5,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
import 'package:flutter/material.dart';
import '../theme.dart';

class GameOverScreen extends StatefulWidget {
  final int score;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  const GameOverScreen({
    super.key,
    required this.score,
    required this.onRestart,
    required this.onMenu,
  });

  @override
  State<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends State<GameOverScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _rank {
    if (widget.score > 5000) return '🏆 LEGEND';
    if (widget.score > 2000) return '⭐ MASTER';
    if (widget.score > 500) return '✨ ADEPT';
    return '🌱 NOVICE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EchoColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'GAME OVER',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: EchoColors.danger,
                    letterSpacing: 6,
                    shadows: [
                      Shadow(color: EchoColors.dangerDarker, blurRadius: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'FINAL SCORE',
                  style: TextStyle(
                    color: EchoColors.textDim,
                    fontSize: 14,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  '${widget.score}',
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: EchoColors.primary, blurRadius: 30),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _rank,
                  style: const TextStyle(
                    fontSize: 20,
                    color: EchoColors.primaryLight,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 40),
                _PillButton(
                  label: '🔄  RETRY',
                  onTap: widget.onRestart,
                ),
                const SizedBox(height: 16),
                _PillButton(
                  label: '🏠  MENU',
                  onTap: widget.onMenu,
                  secondary: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool secondary;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
        decoration: BoxDecoration(
          color: secondary ? EchoColors.surface : EchoColors.primary,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: secondary ? Colors.white24 : EchoColors.primaryLight,
            width: 2,
          ),
        ),
        child: Text(label, style: EchoText.button),
      ),
    );
  }
}
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cloth_effect/cloth_effect.dart';

void main() => runApp(const ClothExampleApp());

class ClothExampleApp extends StatelessWidget {
  const ClothExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloth Effect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF060606),
        fontFamily: 'Roboto',
      ),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final ClothController _cloth = ClothController();
  bool _photo = false;

  @override
  void dispose() {
    _cloth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Align(
              alignment: Alignment(0, -0.1),
              child: Text(
                'You tore the screen\noff the wall.',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.25,
                  color: Color(0xFFE8E8E8),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          Cloth(
            controller: _cloth,
            child: SafeArea(
              child: _NowPlaying(
                photo: _photo,
                onToggleArt: () => setState(() => _photo = !_photo),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: AnimatedBuilder(
                  animation: _cloth,
                  builder: (BuildContext context, _) {
                    return _PillButton(
                      label: 'RESET',
                      onPressed: _cloth.pinsIn ? null : _cloth.reset,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Material(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.white : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.photo, required this.onToggleArt});

  final bool photo;
  final VoidCallback onToggleArt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const <Widget>[
              Text(
                'NOW PLAYING',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2.4,
                  color: Color(0xFF6E6E73),
                ),
              ),
              Icon(Icons.more_horiz, size: 18, color: Color(0xFF6E6E73)),
            ],
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onToggleArt,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: photo
                    ? Image.asset('assets/cover.jpg', fit: BoxFit.cover)
                    : const CustomPaint(painter: _CoverPainter()),
              ),
            ),
          ),
          const SizedBox(height: 22),
          InkWell(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: Duration(milliseconds: 900),
                content: Text('Still a live widget while it hangs flat'),
              ),
            ),
            child: const Text(
              'Slow Tide',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Vera Lune — Ganymede EP',
            style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                flex: 42,
                child: Container(height: 2, color: const Color(0xFFE2552B)),
              ),
              Expanded(
                flex: 58,
                child: Container(height: 2, color: const Color(0xFF2A2A2D)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const <Widget>[
              Text(
                '1:44',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
              Text(
                '4:12',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Text(
            'UP NEXT',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2.4,
              color: Color(0xFF6E6E73),
            ),
          ),
          const SizedBox(height: 6),
          const Expanded(
            child: _UpNext(
              tracks: <_Track>[
                _Track('Paper Weather', 'Oyster Club', '3:38'),
                _Track('Thread Count', 'Marlow', '5:01'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Track {
  const _Track(this.title, this.artist, this.duration);
  final String title;
  final String artist;
  final String duration;
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.tracks});

  final List<_Track> tracks;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      itemBuilder: (BuildContext context, int index) {
        final _Track track = tracks[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      track.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A7A7E),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                track.duration,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7E)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CoverPainter extends CustomPainter {
  const _CoverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF12304A),
            Color(0xFF1B5566),
            Color(0xFF2D8478),
            Color(0xFF0B2233),
          ],
          stops: <double>[0.0, 0.34, 0.62, 1.0],
        ).createShader(rect),
    );

    final Offset moon = Offset(size.width * 0.68, size.height * 0.27);
    final double moonRadius = size.width * 0.115;

    canvas.drawCircle(
      moon,
      moonRadius * 3.4,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFF6E9CC).withValues(alpha: 0.26),
            const Color(0xFFF6E9CC).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: moon, radius: moonRadius * 3.4)),
    );
    canvas.drawCircle(
      moon,
      moonRadius,
      Paint()..color = const Color(0xFFF4E7CB),
    );
    canvas.drawCircle(
      moon.translate(-moonRadius * 0.34, -moonRadius * 0.28),
      moonRadius * 0.22,
      Paint()..color = const Color(0xFFE2D2B0).withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      moon.translate(moonRadius * 0.3, moonRadius * 0.36),
      moonRadius * 0.14,
      Paint()..color = const Color(0xFFE2D2B0).withValues(alpha: 0.42),
    );

    final Paint wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 18; i++) {
      final double t = i / 17;
      final double y = size.height * (0.48 + 0.5 * t * t);
      final double amplitude = size.height * 0.012 * (1 - t * 0.55);
      final double phase = i * 0.9;
      wave
        ..strokeWidth = 1.1 + t * 1.9
        ..color = const Color(0xFFDCF2EE).withValues(alpha: 0.30 - 0.2 * t);

      final Path path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 6) {
        final double k = x / size.width;
        path.lineTo(
          x,
          y +
              math.sin(k * math.pi * 3 + phase) * amplitude +
              math.sin(k * math.pi * 7.3 + phase * 1.7) * amplitude * 0.35,
        );
      }
      canvas.drawPath(path, wave);
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.05),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.22),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) => false;
}

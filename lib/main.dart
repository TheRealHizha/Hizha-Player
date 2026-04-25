import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'dart:io';

// ==================== ENUMS ====================
enum ThemeMode {
  dark,
  transparent,
}

// ==================== MAIN ====================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await Window.initialize();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(900, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      color: const Color(0x00000000),
    );
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const LiquidGlassPlayer());
}

// ==================== THEME PROVIDER ====================
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  
  ThemeMode get themeMode => _themeMode;
  
  void setTheme(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
  
  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.transparent : ThemeMode.dark;
    notifyListeners();
  }
}

// ==================== APP ====================
class LiquidGlassPlayer extends StatelessWidget {
  const LiquidGlassPlayer({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => EqualizerProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Hizha Player',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.themeMode == ThemeMode.dark 
                ? GlassTheme.darkTheme 
                : GlassTheme.transparentTheme,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

// ==================== MODELS ====================
class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String path;
  final Duration duration;
  final Color accentColor;
  final int colorIndex;
  final Uint8List? coverArt;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    required this.duration,
    required this.accentColor,
    required this.colorIndex,
    this.coverArt,
  });

  factory Song.fromFile(String filePath, int index, {Uint8List? coverArt, Map<String, dynamic>? metadata}) {
    String title = 'Unknown Title';
    String artist = 'Unknown Artist';
    String album = 'Unknown Album';
    Duration duration = Duration.zero;

    if (metadata != null) {
      title = metadata['trackName'] ?? 'Unknown Title';
      artist = metadata['trackArtistNames'] != null && metadata['trackArtistNames'].isNotEmpty 
          ? metadata['trackArtistNames'][0] 
          : 'Unknown Artist';
      album = metadata['albumName'] ?? 'Unknown Album';
      final int? trackDuration = metadata['trackDuration'];
      if (trackDuration != null) {
        duration = Duration(milliseconds: trackDuration);
      }
    } else {
      final fileName = filePath.split('\\').last.split('/').last;
      final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      
      title = name;
      artist = 'Unknown Artist';
      if (name.contains(' - ')) {
        final parts = name.split(' - ');
        artist = parts[0].trim();
        title = parts.sublist(1).join(' - ').trim();
      }
    }
    
    final colors = GlassTheme.accentColors;
    final colorIndex = index % colors.length;
    
    return Song(
      id: '${DateTime.now().millisecondsSinceEpoch}_$index',
      title: title,
      artist: artist,
      album: album,
      path: filePath,
      duration: duration,
      accentColor: colors[colorIndex],
      colorIndex: colorIndex,
      coverArt: coverArt,
    );
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  PositionData(this.position, this.bufferedPosition, this.duration);
  double get progress => duration.inMilliseconds > 0
      ? position.inMilliseconds / duration.inMilliseconds
      : 0.0;
}

// ==================== EQUALIZER PRESET ENUM ====================
enum EqualizerPreset {
  normal,
  bassBoost,
  bassReducer,
  trebleBoost,
  trebleReducer,
  vocal,
  classical,
  dance,
  rock,
  pop,
  jazz,
  lounge,
  custom,
}

// ==================== EQUALIZER PROVIDER ====================
class EqualizerProvider extends ChangeNotifier {
  final List<double> _bands = List.filled(10, 0.0);
  double _preAmp = 0.0;
  double _bassBoost = 0.0;
  EqualizerPreset _currentPreset = EqualizerPreset.normal;
  bool _isEnabled = true;

  List<double> get bands => List.unmodifiable(_bands);
  double get preAmp => _preAmp;
  double get bassBoost => _bassBoost;
  EqualizerPreset get currentPreset => _currentPreset;
  bool get isEnabled => _isEnabled;

  static const List<double> bandFrequencies = [
    32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
  ];

  void setBand(int index, double value) {
    _bands[index] = value.clamp(-12.0, 12.0);
    _currentPreset = EqualizerPreset.custom;
    _applyEqualizer();
    notifyListeners();
  }

  void setPreAmp(double value) {
    _preAmp = value.clamp(-12.0, 12.0);
    _applyEqualizer();
    notifyListeners();
  }

  void setBassBoost(double value) {
    _bassBoost = value.clamp(0.0, 1.0);
    _applyEqualizer();
    notifyListeners();
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _applyEqualizer();
    notifyListeners();
  }

  void resetBands() {
    for (int i = 0; i < _bands.length; i++) {
      _bands[i] = 0.0;
    }
    _preAmp = 0.0;
    _bassBoost = 0.0;
    _currentPreset = EqualizerPreset.normal;
    _applyEqualizer();
    notifyListeners();
  }

  void applyPreset(EqualizerPreset preset) {
    _currentPreset = preset;
    final values = presetValues[preset]!;
    for (int i = 0; i < _bands.length && i < values.length; i++) {
      _bands[i] = values[i];
    }
    _bassBoost = preset == EqualizerPreset.bassBoost ? 0.8 : 0.0;
    _applyEqualizer();
    notifyListeners();
  }

  void _applyEqualizer() {
    debugPrint('EQ Applied: $_bands, PreAmp: $_preAmp, BassBoost: $_bassBoost');
  }

  static const Map<EqualizerPreset, List<double>> presetValues = {
    EqualizerPreset.normal: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    EqualizerPreset.bassBoost: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
    EqualizerPreset.bassReducer: [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0],
    EqualizerPreset.trebleBoost: [0, 0, 0, 0, 0, 2, 4, 5, 6, 7],
    EqualizerPreset.trebleReducer: [0, 0, 0, 0, 0, -2, -4, -5, -6, -7],
    EqualizerPreset.vocal: [0, 0, -2, -1, 1, 3, 2, 0, -1, -2],
    EqualizerPreset.classical: [5, 4, 3, 1, -1, -2, -1, 1, 3, 4],
    EqualizerPreset.dance: [7, 6, 3, 0, 0, -2, -4, -2, 0, 2],
    EqualizerPreset.rock: [5, 4, 0, -2, -3, -2, 0, 2, 4, 5],
    EqualizerPreset.pop: [-2, -1, 0, 2, 3, 2, 0, -1, -1, 0],
    EqualizerPreset.jazz: [3, 2, 0, -1, -2, -1, 0, 1, 2, 3],
    EqualizerPreset.lounge: [-3, -2, 0, 2, 3, 2, 0, -1, -2, -3],
    EqualizerPreset.custom: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  };
}

// ==================== THEME ====================
class GlassTheme {
  // Glass Colors
  static const Color glassPrimary = Color(0x18FFFFFF);
  static const Color glassSecondary = Color(0x0DFFFFFF);
  static const Color glassBorder = Color(0x20FFFFFF);
  static const Color glassBorderLight = Color(0x35FFFFFF);
  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF);
  static const Color textTertiary = Color(0x66FFFFFF);
  // Accent Colors Palette
  static const List<Color> accentColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Violet
    Color(0xFFEC4899), // Pink
    Color(0xFFF43F5E), // Rose
    Color(0xFFF97316), // Orange
    Color(0xFFEAB308), // Yellow
    Color(0xFF22C55E), // Green
    Color(0xFF14B8A6), // Teal
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Blue
  ];
  static const Color defaultAccent = Color(0xFF8B5CF6);
  // Background Colors
  static const Color bgDark = Color(0xFF0A0A0F);
  static const Color bgCard = Color(0xFF12121A);
  
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -1,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textTertiary,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: defaultAccent,
        secondary: defaultAccent,
        surface: glassPrimary,
      ),
    );
  }
  
  static ThemeData get transparentTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -1,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textPrimary.withOpacity(0.9),
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textPrimary.withOpacity(0.8),
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: defaultAccent,
        secondary: defaultAccent,
        surface: Color(0x10FFFFFF),
      ),
    );
  }
}

// ==================== PROVIDER ====================
class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<Song> _playlist = [];
  int _currentIndex = -1;
  bool _isShuffled = false;
  LoopMode _loopMode = LoopMode.off;
  double _volume = 0.7;
  bool _isMuted = false;
  double _previousVolume = 0.7;

  PlayerProvider() {
    _init();
  }

  void _init() {
    _audioPlayer.setVolume(_volume);
    _audioPlayer.playerStateStream.listen((state) {
      notifyListeners();
    });
    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex) {
        _currentIndex = index;
        notifyListeners();
      }
    });
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (_loopMode == LoopMode.off && _currentIndex >= _playlist.length - 1) {
          // Playlist ended
        }
      }
    });
  }

  // Getters
  AudioPlayer get audioPlayer => _audioPlayer;
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  Song? get currentSong => _currentIndex >= 0 && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;
  bool get isPlaying => _audioPlayer.playing;
  bool get isShuffled => _isShuffled;
  LoopMode get loopMode => _loopMode;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  Color get accentColor => currentSong?.accentColor ?? GlassTheme.defaultAccent;
  bool get hasPrevious => _currentIndex > 0;
  bool get hasNext => _currentIndex < _playlist.length - 1;

  Stream<PositionData> get positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _audioPlayer.positionStream,
        _audioPlayer.bufferedPositionStream,
        _audioPlayer.durationStream,
        (position, bufferedPosition, duration) => PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        ),
      );

  Future<void> pickAndAddFiles() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      dialogTitle: 'Select Music Files',
    );
    
    if (result != null && result.files.isNotEmpty) {
      final startIndex = _playlist.length;
      for (int i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        if (file.path != null) {
          try {
            final coverArt = await _extractCoverArt(file.path!);
            final song = Song.fromFile(
              file.path!, 
              startIndex + i, 
              coverArt: coverArt,
            );
            _playlist.add(song);
          } catch (e) {
            debugPrint('Error processing file ${file.path}: $e');
            final song = Song.fromFile(file.path!, startIndex + i);
            _playlist.add(song);
          }
        }
      }
      
      if (_playlist.isNotEmpty && _currentIndex == -1) {
        await _loadPlaylist();
        _currentIndex = 0;
      } else if (_playlist.isNotEmpty) {
        await _reloadPlaylist();
      }
      notifyListeners();
    }
  } catch (e) {
    debugPrint('Error picking files: $e');
  }
}

  Future<Uint8List?> _extractCoverArt(String filePath) async {
    try {
      final metadata = await MetadataRetriever.fromFile(File(filePath));
      
      if (metadata.albumArt != null && metadata.albumArt!.isNotEmpty) {
        return Uint8List.fromList(metadata.albumArt!);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error extracting cover art: $e');
      return null;
    }
  }

  Future<void> _loadPlaylist() async {
    if (_playlist.isEmpty) return;
    final audioSources = _playlist.map((song) => AudioSource.file(song.path, tag: song)).toList();
    await _audioPlayer.setAudioSource(
      ConcatenatingAudioSource(children: audioSources),
      initialIndex: 0,
    );
  }

  Future<void> _reloadPlaylist() async {
    if (_playlist.isEmpty) return;
    final currentPosition = _audioPlayer.position;
    final wasPlaying = isPlaying;
    final audioSources = _playlist.map((song) => AudioSource.file(song.path, tag: song)).toList();
    await _audioPlayer.setAudioSource(
      ConcatenatingAudioSource(children: audioSources),
      initialIndex: _currentIndex >= 0 ? _currentIndex : 0,
      initialPosition: currentPosition,
    );
    if (wasPlaying) {
      await play();
    }
  }

  Future<void> play() async {
    if (_playlist.isEmpty) return;
    await _audioPlayer.play();
  }

  Future<void> pause() async => await _audioPlayer.pause();

  Future<void> togglePlayPause() async {
    if (_playlist.isEmpty) {
      await pickAndAddFiles();
      return;
    }
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex < _playlist.length - 1) {
      await _audioPlayer.seekToNext();
    } else if (_loopMode == LoopMode.all) {
      await _audioPlayer.seek(Duration.zero, index: 0);
    }
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    if (_audioPlayer.position.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
    } else if (_currentIndex > 0) {
      await _audioPlayer.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    await _audioPlayer.setVolume(_volume);
    notifyListeners();
  }

  void toggleMute() {
    if (_isMuted) {
      _volume = _previousVolume > 0 ? _previousVolume : 0.7;
      _isMuted = false;
    } else {
      _previousVolume = _volume;
      _volume = 0;
      _isMuted = true;
    }
    _audioPlayer.setVolume(_volume);
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    await _audioPlayer.seek(Duration.zero, index: index);
    await play();
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    _audioPlayer.setShuffleModeEnabled(_isShuffled);
    notifyListeners();
  }

  void cycleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        break;
    }
    _audioPlayer.setLoopMode(_loopMode);
    notifyListeners();
  }

  void removeFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    _playlist.removeAt(index);
    if (_playlist.isEmpty) {
      _currentIndex = -1;
      _audioPlayer.stop();
    } else if (index == _currentIndex) {
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
      _reloadPlaylist();
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    notifyListeners();
  }

  void clearPlaylist() {
    _playlist.clear();
    _currentIndex = -1;
    _audioPlayer.stop();
    notifyListeners();
  }

  void reorderPlaylist(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

// ==================== GLASS WIDGETS ====================
class GlassContainer extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final bool enableHover;
  final bool animate;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final bool forceTransparent;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 24,
    this.blur = 40,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.enableHover = true,
    this.animate = true,
    this.onTap,
    this.gradient,
    this.boxShadow,
    this.forceTransparent = false,
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = provider.accentColor;
    
    final bool isTransparentTheme = themeProvider.themeMode == ThemeMode.transparent || widget.forceTransparent;
    
    final bgColor = isTransparentTheme 
        ? Colors.black.withOpacity(0.15)
        : (widget.backgroundColor ?? GlassTheme.glassPrimary);
        
    final bdColor = isTransparentTheme
        ? Colors.white.withOpacity(0.2)
        : (widget.borderColor ?? GlassTheme.glassBorder);

    final double blurAmount = isTransparentTheme ? 3 : widget.blur;

    Widget container = MouseRegion(
      onEnter: widget.enableHover ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enableHover ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: widget.boxShadow ?? [
              if (!isTransparentTheme)
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              if (_isHovered && widget.enableHover)
                BoxShadow(
                  color: accent.withOpacity(isTransparentTheme ? 0.1 : 0.15),
                  blurRadius: 50,
                  spreadRadius: 5,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurAmount,
                sigmaY: blurAmount,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: widget.gradient ?? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isTransparentTheme
                        ? [
                            Colors.white.withOpacity(_isHovered ? 0.12 : 0.08),
                            Colors.white.withOpacity(_isHovered ? 0.08 : 0.05),
                          ]
                        : [
                            bgColor.withOpacity(_isHovered ? 0.22 : 0.15),
                            bgColor.withOpacity(_isHovered ? 0.12 : 0.08),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: _isHovered ? accent.withOpacity(isTransparentTheme ? 0.2 : 0.3) : bdColor,
                    width: widget.borderWidth,
                  ),
                ),
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.animate) {
      container = container
          .animate()
          .fadeIn(duration: 500.ms, curve: Curves.easeOut)
          .scale(
            begin: const Offset(0.95, 0.95),
            duration: 500.ms,
            curve: Curves.easeOut,
          );
    }

    return container;
  }
}

class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final String? tooltip;
  final bool isActive;
  final bool showBackground;
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 22,
    this.color,
    this.tooltip,
    this.isActive = false,
    this.showBackground = true,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = provider.accentColor;
    final color = widget.color ?? GlassTheme.textPrimary;
    final isTransparentTheme = themeProvider.themeMode == ThemeMode.transparent;

    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _controller.forward();
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.showBackground
                      ? (widget.isActive
                          ? accent.withOpacity(isTransparentTheme ? 0.2 : 0.25)
                          : (_isHovered ? Colors.white.withOpacity(isTransparentTheme ? 0.08 : 0.1) : Colors.white.withOpacity(isTransparentTheme ? 0.04 : 0.05)))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(widget.size / 3),
                  border: widget.showBackground
                      ? Border.all(
                          color: widget.isActive
                              ? accent.withOpacity(isTransparentTheme ? 0.3 : 0.4)
                              : (_isHovered ? Colors.white.withOpacity(isTransparentTheme ? 0.12 : 0.15) : Colors.transparent),
                          width: 1,
                        )
                      : null,
                  boxShadow: widget.isActive
                      ? [
                          BoxShadow(
                            color: accent.withOpacity(isTransparentTheme ? 0.2 : 0.3),
                            blurRadius: 12,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: widget.isActive ? accent : (_isHovered ? Colors.white : color.withOpacity(isTransparentTheme ? 0.9 : 0.8)),
                ),
              ),
            );
          },
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        preferBelow: false,
        decoration: BoxDecoration(
          color: GlassTheme.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GlassTheme.glassBorder),
        ),
        textStyle: const TextStyle(
          color: GlassTheme.textPrimary,
          fontSize: 12,
        ),
        child: button,
      );
    }

    return button;
  }
}

// ==================== ANIMATED BACKGROUND ====================
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _colorController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    _colorController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = playerProvider.accentColor;
    
    if (themeProvider.themeMode == ThemeMode.transparent) {
      return Container(
        color: Colors.transparent,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Container(
            color: Colors.black.withOpacity(0.25),
          ),
        ),
      );
    }
    
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _colorController]),
      builder: (context, child) {
        return CustomPaint(
          painter: _BackgroundPainter(
            animation: _controller.value,
            colorAnimation: _colorController.value,
            accentColor: accent,
            isPlaying: playerProvider.isPlaying,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double animation;
  final double colorAnimation;
  final Color accentColor;
  final bool isPlaying;

  _BackgroundPainter({
    required this.animation,
    required this.colorAnimation,
    required this.accentColor,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0D0D12),
        const Color(0xFF0A0A0F),
        Color.lerp(const Color(0xFF0F0F18), accentColor.withOpacity(0.05), colorAnimation)!,
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = bgGradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      ),
    );

    final orbs = [
      _Orb(
        baseX: 0.15,
        baseY: 0.2,
        radius: size.width * 0.35,
        color: accentColor.withOpacity(isPlaying ? 0.08 : 0.04),
        speed: 1.0,
        amplitude: 0.05,
      ),
      _Orb(
        baseX: 0.85,
        baseY: 0.75,
        radius: size.width * 0.4,
        color: Color.lerp(accentColor, const Color(0xFF06B6D4), 0.5)!.withOpacity(isPlaying ? 0.06 : 0.03),
        speed: 0.7,
        amplitude: 0.04,
      ),
      _Orb(
        baseX: 0.5,
        baseY: 0.5,
        radius: size.width * 0.3,
        color: Color.lerp(accentColor, const Color(0xFFEC4899), 0.5)!.withOpacity(isPlaying ? 0.05 : 0.025),
        speed: 1.3,
        amplitude: 0.06,
      ),
      _Orb(
        baseX: 0.75,
        baseY: 0.15,
        radius: size.width * 0.25,
        color: accentColor.withOpacity(isPlaying ? 0.04 : 0.02),
        speed: 0.9,
        amplitude: 0.03,
      ),
    ];

    for (var orb in orbs) {
      final offsetX = math.sin(animation * 2 * math.pi * orb.speed) * size.width * orb.amplitude;
      final offsetY = math.cos(animation * 2 * math.pi * orb.speed * 0.7) * size.height * orb.amplitude;
      final center = Offset(
        size.width * orb.baseX + offsetX,
        size.height * orb.baseY + offsetY,
      );
      final gradient = RadialGradient(
        colors: [
          orb.color,
          orb.color.withOpacity(0),
        ],
        stops: const [0.0, 1.0],
      );
      final rect = Rect.fromCircle(center: center, radius: orb.radius);
      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(center, orb.radius, paint);
    }

    final noisePaint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..blendMode = BlendMode.overlay;
    final random = math.Random(42);
    for (int i = 0; i < 100; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * 2,
        noisePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isPlaying != isPlaying;
  }
}

class _Orb {
  final double baseX;
  final double baseY;
  final double radius;
  final Color color;
  final double speed;
  final double amplitude;

  _Orb({
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.color,
    required this.speed,
    required this.amplitude,
  });
}

// ==================== ALBUM ART ====================
class AlbumArt extends StatefulWidget {
  final bool isPlaying;
  final Color accentColor;
  final double size;
  final Uint8List? coverArt;
  const AlbumArt({
    super.key,
    required this.isPlaying,
    required this.accentColor,
    this.size = 280,
    this.coverArt,
  });

  @override
  State<AlbumArt> createState() => _AlbumArtState();
}

class _AlbumArtState extends State<AlbumArt> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _rotationController,
        _pulseController,
        _glowController,
      ]),
      builder: (context, child) {
        final glowIntensity = widget.isPlaying ? 0.3 + (_glowController.value * 0.2) : 0.15;
        final pulseScale = widget.isPlaying ? 1.0 + (_pulseController.value * 0.02) : 1.0;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: pulseScale * 1.3,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor.withOpacity(glowIntensity),
                        blurRadius: 80,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              
              ...List.generate(3, (index) {
                final ringScale = 1.0 + (index * 0.12) + (_pulseController.value * 0.03 * (index + 1));
                return Transform.scale(
                  scale: ringScale,
                  child: Transform.rotate(
                    angle: _rotationController.value * 2 * math.pi * (index.isEven ? 1 : -1) * (0.5 + index * 0.2),
                    child: Container(
                      width: widget.size * 0.85,
                      height: widget.size * 0.85,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.accentColor.withOpacity(0.15 - (index * 0.04)),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),

              Transform.rotate(
                angle: widget.coverArt == null ? _rotationController.value * 2 * math.pi : 0,
                child: Container(
                  width: widget.size * 0.8,
                  height: widget.size * 0.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.coverArt == null 
                      ? RadialGradient(
                          colors: [
                            widget.accentColor.withOpacity(0.4),
                            widget.accentColor.withOpacity(0.2),
                            const Color(0xFF1a1a2e).withOpacity(0.9),
                            Colors.black.withOpacity(0.95),
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0],
                        )
                      : null,
                    image: widget.coverArt != null 
                      ? DecorationImage(
                          image: MemoryImage(widget.coverArt!),
                          fit: BoxFit.cover,
                        )
                      : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                      BoxShadow(
                        color: widget.accentColor.withOpacity(0.2),
                        blurRadius: 40,
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: widget.coverArt == null 
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          ...List.generate(12, (index) {
                            return Container(
                              margin: EdgeInsets.all(15.0 + (index * 8)),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.03 + (index.isEven ? 0.02 : 0)),
                                  width: 0.5,
                                ),
                              ),
                            );
                          }),
                          Container(
                            width: widget.size * 0.25,
                            height: widget.size * 0.25,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  widget.accentColor.withOpacity(0.9),
                                  widget.accentColor.withOpacity(0.6),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accentColor.withOpacity(0.5),
                                  blurRadius: 25,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: widget.size * 0.05,
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white.withOpacity(0.9),
                                    size: widget.size * 0.08,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==================== NOW PLAYING ====================
class NowPlayingSection extends StatelessWidget {
  const NowPlayingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final song = provider.currentSong;
        final accent = provider.accentColor;
        return GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = math.min(
                        constraints.maxWidth * 0.85,
                        constraints.maxHeight * 0.9,
                      );
                      return AlbumArt(
                        isPlaying: provider.isPlaying,
                        accentColor: accent,
                        size: size.clamp(200.0, 350.0),
                        coverArt: song?.coverArt,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.3),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        song?.title ?? 'No song playing',
                        key: ValueKey(song?.id ?? 'empty'),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: GlassTheme.textPrimary,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: accent.withOpacity(0.5),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        song?.artist ?? 'Add music to get started',
                        key: ValueKey('${song?.id ?? 'empty'}_artist'),
                        style: TextStyle(
                          fontSize: 16,
                          color: GlassTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==================== PLAYER CONTROLS ====================
class PlayerControlsSection extends StatelessWidget {
  const PlayerControlsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        return GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          borderRadius: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProgressBarWidget(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassIconButton(
                    icon: Icons.shuffle_rounded,
                    onPressed: provider.toggleShuffle,
                    isActive: provider.isShuffled,
                    tooltip: provider.isShuffled ? 'Shuffle On' : 'Shuffle Off',
                    size: 44,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: Icons.skip_previous_rounded,
                    onPressed: provider.previous,
                    tooltip: 'Previous',
                    size: 52,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 16),
                  PlayPauseButton(
                    isPlaying: provider.isPlaying,
                    onPressed: provider.togglePlayPause,
                    accentColor: provider.accentColor,
                  ),
                  const SizedBox(width: 16),
                  GlassIconButton(
                    icon: Icons.skip_next_rounded,
                    onPressed: provider.next,
                    tooltip: 'Next',
                    size: 52,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: _getLoopIcon(provider.loopMode),
                    onPressed: provider.cycleLoopMode,
                    isActive: provider.loopMode != LoopMode.off,
                    tooltip: _getLoopTooltip(provider.loopMode),
                    size: 44,
                    iconSize: 20,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const VolumeControlWidget(),
            ],
          ),
        );
      },
    );
  }

  IconData _getLoopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.one:
        return Icons.repeat_one_rounded;
      default:
        return Icons.repeat_rounded;
    }
  }

  String _getLoopTooltip(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return 'Repeat Off';
      case LoopMode.all:
        return 'Repeat All';
      case LoopMode.one:
        return 'Repeat One';
    }
  }
}

class PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final Color accentColor;
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    required this.accentColor,
  });

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton> with TickerProviderStateMixin {
  late AnimationController _iconController;
  late AnimationController _scaleController;
  late AnimationController _glowController;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    if (widget.isPlaying) {
      _iconController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _iconController.forward();
      } else {
        _iconController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _iconController.dispose();
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _scaleController.forward();
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _scaleController.reverse();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _scaleController.reverse();
        },
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onPressed();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleController, _glowController]),
          builder: (context, child) {
            final scale = 1.0 - (_scaleController.value * 0.08);
            final glowOpacity = widget.isPlaying ? 0.4 + (_glowController.value * 0.2) : 0.3;
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.accentColor.withOpacity(_isHovered ? 1.0 : 0.9),
                      Color.lerp(widget.accentColor, Colors.black, 0.3)!.withOpacity(_isHovered ? 0.95 : 0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(glowOpacity),
                      blurRadius: _isHovered ? 35 : 25,
                      spreadRadius: _isHovered ? 3 : 0,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _iconController,
                    size: 38,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ProgressBarWidget extends StatelessWidget {
  const ProgressBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return StreamBuilder<PositionData>(
      stream: provider.positionDataStream,
      builder: (context, snapshot) {
        final positionData = snapshot.data;
        final accent = provider.accentColor;
        return Column(
          children: [
            ProgressBar(
              progress: positionData?.position ?? Duration.zero,
              buffered: positionData?.bufferedPosition ?? Duration.zero,
              total: positionData?.duration ?? Duration.zero,
              onSeek: provider.seek,
              barHeight: 5,
              baseBarColor: Colors.white.withOpacity(0.1),
              progressBarColor: accent,
              bufferedBarColor: accent.withOpacity(0.3),
              thumbColor: Colors.white,
              thumbGlowColor: accent.withOpacity(0.4),
              thumbRadius: 8,
              thumbGlowRadius: 18,
              timeLabelLocation: TimeLabelLocation.sides,
              timeLabelTextStyle: TextStyle(
                color: GlassTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              ),
              timeLabelPadding: 8,
            ),
          ],
        );
      },
    );
  }
}

class VolumeControlWidget extends StatefulWidget {
  const VolumeControlWidget({super.key});

  @override
  State<VolumeControlWidget> createState() => _VolumeControlWidgetState();
}

class _VolumeControlWidgetState extends State<VolumeControlWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final accent = provider.accentColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _isExpanded = true),
      onExit: (_) => setState(() => _isExpanded = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(_isExpanded ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(_isExpanded ? 0.15 : 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIconButton(
              icon: _getVolumeIcon(provider.volume, provider.isMuted),
              onPressed: provider.toggleMute,
              tooltip: provider.isMuted ? 'Unmute' : 'Mute',
              size: 36,
              iconSize: 20,
              showBackground: false,
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isExpanded ? 140 : 100,
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white.withOpacity(0.15),
                  thumbColor: Colors.white,
                  overlayColor: accent.withOpacity(0.2),
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    elevation: 4,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: provider.volume,
                  onChanged: provider.setVolume,
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isExpanded ? 1.0 : 0.0,
              child: SizedBox(
                width: 36,
                child: Text(
                  '${(provider.volume * 100).round()}%',
                  style: TextStyle(
                    color: GlassTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getVolumeIcon(double volume, bool isMuted) {
    if (isMuted || volume == 0) return Icons.volume_off_rounded;
    if (volume < 0.3) return Icons.volume_mute_rounded;
    if (volume < 0.7) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }
}

// ==================== PLAYLIST ====================
class PlaylistSection extends StatefulWidget {
  const PlaylistSection({super.key});

  @override
  State<PlaylistSection> createState() => _PlaylistSectionState();
}

class _PlaylistSectionState extends State<PlaylistSection> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final filteredPlaylist = _searchQuery.isEmpty
            ? provider.playlist
            : provider.playlist.where((song) =>
                song.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                song.artist.toLowerCase().contains(_searchQuery.toLowerCase())
              ).toList();

        return GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlaylistHeader(
                songCount: provider.playlist.length,
                onAddMusic: provider.pickAndAddFiles,
                onClear: provider.playlist.isNotEmpty ? provider.clearPlaylist : null,
                showSearch: _showSearch,
                onToggleSearch: () => setState(() => _showSearch = !_showSearch),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: _showSearch ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: _SearchBar(
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                secondChild: const SizedBox(height: 12),
              ),
              Expanded(
                child: provider.playlist.isEmpty
                    ? _EmptyPlaylist(onAddMusic: provider.pickAndAddFiles)
                    : filteredPlaylist.isEmpty
                        ? _NoResults()
                        : _PlaylistContent(
                            playlist: filteredPlaylist,
                            allPlaylist: provider.playlist,
                            currentIndex: provider.currentIndex,
                            isPlaying: provider.isPlaying,
                            accentColor: provider.accentColor,
                            scrollController: _scrollController,
                            onPlay: provider.playAt,
                            onRemove: provider.removeFromPlaylist,
                            onReorder: provider.reorderPlaylist,
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final int songCount;
  final VoidCallback onAddMusic;
  final VoidCallback? onClear;
  final bool showSearch;
  final VoidCallback onToggleSearch;
  const _PlaylistHeader({
    required this.songCount,
    required this.onAddMusic,
    required this.onClear,
    required this.showSearch,
    required this.onToggleSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Playlist',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: GlassTheme.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$songCount ${songCount == 1 ? 'song' : 'songs'}',
              style: const TextStyle(
                color: GlassTheme.textTertiary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (songCount > 3)
          GlassIconButton(
            icon: Icons.search_rounded,
            onPressed: onToggleSearch,
            isActive: showSearch,
            tooltip: 'Search',
            size: 40,
            iconSize: 18,
          ),
        const SizedBox(width: 8),
        if (onClear != null)
          GlassIconButton(
            icon: Icons.clear_all_rounded,
            onPressed: onClear!,
            tooltip: 'Clear All',
            size: 40,
            iconSize: 18,
          ),
        const SizedBox(width: 8),
        _AddMusicButton(onPressed: onAddMusic),
      ],
    );
  }
}

class _AddMusicButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _AddMusicButton({required this.onPressed});

  @override
  State<_AddMusicButton> createState() => _AddMusicButtonState();
}

class _AddMusicButtonState extends State<_AddMusicButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final accent = provider.accentColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withOpacity(_isHovered ? 0.9 : 0.8),
                accent.withOpacity(_isHovered ? 0.7 : 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(_isHovered ? 0.4 : 0.2),
                blurRadius: _isHovered ? 16 : 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                'Add',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(
          color: GlassTheme.textPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Search songs...',
          hintStyle: TextStyle(
            color: GlassTheme.textTertiary,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: GlassTheme.textTertiary,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2);
  }
}

class _PlaylistContent extends StatelessWidget {
  final List<Song> playlist;
  final List<Song> allPlaylist;
  final int currentIndex;
  final bool isPlaying;
  final Color accentColor;
  final ScrollController scrollController;
  final Function(int) onPlay;
  final Function(int) onRemove;
  final Function(int, int) onReorder;
  const _PlaylistContent({
    required this.playlist,
    required this.allPlaylist,
    required this.currentIndex,
    required this.isPlaying,
    required this.accentColor,
    required this.scrollController,
    required this.onPlay,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      scrollController: scrollController,
      itemCount: playlist.length,
      onReorder: (oldIndex, newIndex) {
        final oldActualIndex = allPlaylist.indexOf(playlist[oldIndex]);
        final newActualIndex = oldIndex < newIndex
            ? allPlaylist.indexOf(playlist[newIndex - 1])
            : allPlaylist.indexOf(playlist[newIndex]);
        onReorder(oldActualIndex, newActualIndex + (oldIndex < newIndex ? 1 : 0));
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Material(
              color: Colors.transparent,
              child: Transform.scale(
                scale: 1.02,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final song = playlist[index];
        final actualIndex = allPlaylist.indexOf(song);
        final isCurrentSong = actualIndex == currentIndex;
        return _PlaylistItem(
          key: ValueKey(song.id),
          index: index,
          song: song,
          isPlaying: isCurrentSong && isPlaying,
          isSelected: isCurrentSong,
          accentColor: song.accentColor,
          coverArt: song.coverArt,
          onTap: () => onPlay(actualIndex),
          onDelete: () => onRemove(actualIndex),
        );
      },
    );
  }
}

class _PlaylistItem extends StatefulWidget {
  final int index;
  final Song song;
  final bool isPlaying;
  final bool isSelected;
  final Color accentColor;
  final Uint8List? coverArt;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PlaylistItem({
    super.key,
    required this.index,
    required this.song,
    required this.isPlaying,
    required this.isSelected,
    required this.accentColor,
    this.coverArt,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_PlaylistItem> createState() => _PlaylistItemState();
}

class _PlaylistItemState extends State<_PlaylistItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.isSelected
                ? LinearGradient(
                    colors: [
                      widget.accentColor.withOpacity(0.2),
                      widget.accentColor.withOpacity(0.08),
                    ],
                  )
                : null,
            color: !widget.isSelected
                ? (_isHovered ? Colors.white.withOpacity(0.06) : Colors.transparent)
                : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected
                  ? widget.accentColor.withOpacity(0.35)
                  : (_isHovered ? Colors.white.withOpacity(0.12) : Colors.transparent),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              _SongThumbnail(
                isPlaying: widget.isPlaying,
                isSelected: widget.isSelected,
                accentColor: widget.accentColor,
                colorIndex: widget.song.colorIndex,
                coverArt: widget.coverArt,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.song.title,
                      style: TextStyle(
                        color: widget.isSelected ? widget.accentColor : GlassTheme.textPrimary,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.song.artist,
                      style: TextStyle(
                        color: widget.isSelected ? widget.accentColor.withOpacity(0.7) : GlassTheme.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _isHovered ? 1.0 : 0.0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: GlassTheme.textTertiary,
                      ),
                      onPressed: widget.onDelete,
                      splashRadius: 18,
                      tooltip: 'Remove',
                    ),
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        size: 20,
                        color: GlassTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: (30 * widget.index).ms).fadeIn(duration: 300.ms).slideX(
      begin: 0.05,
      duration: 300.ms,
      curve: Curves.easeOut,
    );
  }
}

class _SongThumbnail extends StatefulWidget {
  final bool isPlaying;
  final bool isSelected;
  final Color accentColor;
  final int colorIndex;
  final Uint8List? coverArt;
  const _SongThumbnail({
    required this.isPlaying,
    required this.isSelected,
    required this.accentColor,
    required this.colorIndex,
    this.coverArt,
  });

  @override
  State<_SongThumbnail> createState() => _SongThumbnailState();
}

class _SongThumbnailState extends State<_SongThumbnail> with TickerProviderStateMixin {
  late List<AnimationController> _barControllers;

  @override
  void initState() {
    super.initState();
    _barControllers = List.generate(
      4,
      (index) => AnimationController(
        duration: Duration(milliseconds: 300 + (index * 80)),
        vsync: this,
      ),
    );
    if (widget.isPlaying) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant _SongThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _startAnimation();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _stopAnimation();
    }
  }

  void _startAnimation() {
    for (var controller in _barControllers) {
      controller.repeat(reverse: true);
    }
  }

  void _stopAnimation() {
    for (var controller in _barControllers) {
      controller.stop();
      controller.animateTo(0.3);
    }
  }

  @override
  void dispose() {
    for (var controller in _barControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: widget.coverArt == null 
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.accentColor.withOpacity(widget.isSelected ? 0.4 : 0.25),
                widget.accentColor.withOpacity(widget.isSelected ? 0.2 : 0.1),
              ],
            )
          : null,
        image: widget.coverArt != null 
          ? DecorationImage(
              image: MemoryImage(widget.coverArt!),
              fit: BoxFit.cover,
            )
          : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.accentColor.withOpacity(0.2),
        ),
      ),
      child: widget.coverArt == null 
        ? (widget.isPlaying
            ? _buildPlayingIndicator()
            : Icon(
                Icons.music_note_rounded,
                color: widget.isSelected ? widget.accentColor : widget.accentColor.withOpacity(0.7),
                size: 20,
              ))
        : null,
    );
  }

  Widget _buildPlayingIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        return AnimatedBuilder(
          animation: _barControllers[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 8 + (_barControllers[index].value * 14),
              decoration: BoxDecoration(
                color: widget.accentColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  final VoidCallback onAddMusic;
  const _EmptyPlaylist({required this.onAddMusic});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final accent = provider.accentColor;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        accent.withOpacity(0.15),
                        accent.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: accent.withOpacity(0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.1),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.library_music_rounded,
                    size: 52,
                    color: accent,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          const Text(
            'Your playlist is empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: GlassTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Add some music to start your journey',
            style: TextStyle(
              color: GlassTheme.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 28),
          _AddMusicButtonLarge(onPressed: onAddMusic, accent: accent),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scale(
      begin: const Offset(0.9, 0.9),
      duration: 500.ms,
      curve: Curves.easeOut,
    );
  }
}

class _AddMusicButtonLarge extends StatefulWidget {
  final VoidCallback onPressed;
  final Color accent;
  const _AddMusicButtonLarge({required this.onPressed, required this.accent});

  @override
  State<_AddMusicButtonLarge> createState() => _AddMusicButtonLargeState();
}

class _AddMusicButtonLargeState extends State<_AddMusicButtonLarge> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.accent.withOpacity(_isHovered ? 1.0 : 0.85),
                widget.accent.withOpacity(_isHovered ? 0.85 : 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withOpacity(_isHovered ? 0.5 : 0.3),
                blurRadius: _isHovered ? 25 : 15,
                spreadRadius: _isHovered ? 2 : 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'Add Music',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: GlassTheme.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            'No songs found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: GlassTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different search term',
            style: TextStyle(
              color: GlassTheme.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}

// ==================== EQUALIZER TAB ====================
class EqualizerTab extends StatefulWidget {
  const EqualizerTab({super.key});

  @override
  State<EqualizerTab> createState() => _EqualizerTabState();
}

class _EqualizerTabState extends State<EqualizerTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EqualizerProvider>(
      builder: (context, provider, _) {
        return GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withOpacity(0.3),
                          const Color(0xFF8B5CF6).withOpacity(0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.equalizer_rounded,
                      color: Color(0xFF6366F1),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Equalizer',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: GlassTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  _PowerButton(
                    isEnabled: provider.isEnabled,
                    onToggle: () => provider.setEnabled(!provider.isEnabled),
                  ),
                  const SizedBox(width: 16),
                  GlassIconButton(
                    icon: Icons.refresh_rounded,
                    onPressed: () {
                      provider.resetBands();
                      HapticFeedback.lightImpact();
                    },
                    tooltip: 'Reset Equalizer',
                    size: 44,
                    iconSize: 22,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF6366F1),
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: GlassTheme.textPrimary,
                unselectedLabelColor: GlassTheme.textTertiary,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'GRAPHIC EQUALIZER'),
                  Tab(text: 'BASS BOOST'),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _GraphicEqualizerView(),
                    _BassBoostView(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PowerButton extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onToggle;

  const _PowerButton({required this.isEnabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onToggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isEnabled
                ? [
                    const Color(0xFF6366F1).withOpacity(0.9),
                    const Color(0xFF8B5CF6).withOpacity(0.8),
                  ]
                : [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEnabled
                ? const Color(0xFF6366F1).withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEnabled ? Icons.power_settings_new_rounded : Icons.power_off_rounded,
              color: isEnabled ? Colors.white : GlassTheme.textTertiary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              isEnabled ? 'ON' : 'OFF',
              style: TextStyle(
                color: isEnabled ? Colors.white : GlassTheme.textTertiary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphicEqualizerView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<EqualizerProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PresetChip(
                    label: 'Normal',
                    preset: EqualizerPreset.normal,
                    isSelected: provider.currentPreset == EqualizerPreset.normal,
                  ),
                  _PresetChip(
                    label: 'Bass Boost',
                    preset: EqualizerPreset.bassBoost,
                    isSelected: provider.currentPreset == EqualizerPreset.bassBoost,
                  ),
                  _PresetChip(
                    label: 'Treble Boost',
                    preset: EqualizerPreset.trebleBoost,
                    isSelected: provider.currentPreset == EqualizerPreset.trebleBoost,
                  ),
                  _PresetChip(
                    label: 'Vocal',
                    preset: EqualizerPreset.vocal,
                    isSelected: provider.currentPreset == EqualizerPreset.vocal,
                  ),
                  _PresetChip(
                    label: 'Classical',
                    preset: EqualizerPreset.classical,
                    isSelected: provider.currentPreset == EqualizerPreset.classical,
                  ),
                  _PresetChip(
                    label: 'Dance',
                    preset: EqualizerPreset.dance,
                    isSelected: provider.currentPreset == EqualizerPreset.dance,
                  ),
                  _PresetChip(
                    label: 'Rock',
                    preset: EqualizerPreset.rock,
                    isSelected: provider.currentPreset == EqualizerPreset.rock,
                  ),
                  _PresetChip(
                    label: 'Pop',
                    preset: EqualizerPreset.pop,
                    isSelected: provider.currentPreset == EqualizerPreset.pop,
                  ),
                  _PresetChip(
                    label: 'Jazz',
                    preset: EqualizerPreset.jazz,
                    isSelected: provider.currentPreset == EqualizerPreset.jazz,
                  ),
                  _PresetChip(
                    label: 'Lounge',
                    preset: EqualizerPreset.lounge,
                    isSelected: provider.currentPreset == EqualizerPreset.lounge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _PreAmpSlider(preAmp: provider.preAmp, onChanged: provider.setPreAmp),
            const SizedBox(height: 24),
            Expanded(
              child: _EqualizerBands(
                bands: provider.bands,
                onBandChanged: provider.setBand,
                isEnabled: provider.isEnabled,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final EqualizerPreset preset;
  final bool isSelected;

  const _PresetChip({
    required this.label,
    required this.preset,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<EqualizerProvider>();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          provider.applyPreset(preset);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      const Color(0xFF6366F1).withOpacity(0.3),
                      const Color(0xFF8B5CF6).withOpacity(0.15),
                    ],
                  )
                : null,
            color: isSelected ? null : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF6366F1).withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF6366F1) : GlassTheme.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreAmpSlider extends StatelessWidget {
  final double preAmp;
  final ValueChanged<double> onChanged;

  const _PreAmpSlider({required this.preAmp, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Pre-Amplifier',
              style: TextStyle(
                color: GlassTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${preAmp.toStringAsFixed(1)} dB',
              style: TextStyle(
                color: GlassTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF6366F1),
            inactiveTrackColor: Colors.white.withOpacity(0.1),
            thumbColor: Colors.white,
            overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: preAmp,
            min: -12.0,
            max: 12.0,
            divisions: 48,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _EqualizerBands extends StatelessWidget {
  final List<double> bands;
  final Function(int, double) onBandChanged;
  final bool isEnabled;

  const _EqualizerBands({
    required this.bands,
    required this.onBandChanged,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bandWidth = (constraints.maxWidth - 40) / bands.length;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('+12', style: _labelStyle),
                  const Text('0', style: _labelStyle),
                  const Text('-12', style: _labelStyle),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ...List.generate(bands.length, (index) {
              return _BandSlider(
                index: index,
                value: bands[index],
                frequency: EqualizerProvider.bandFrequencies[index],
                width: bandWidth - 8,
                onChanged: (value) => onBandChanged(index, value),
                isEnabled: isEnabled,
              );
            }),
          ],
        );
      },
    );
  }

  static const TextStyle _labelStyle = TextStyle(
    color: GlassTheme.textTertiary,
    fontSize: 10,
    fontFamily: 'JetBrainsMono',
  );
}

class _BandSlider extends StatefulWidget {
  final int index;
  final double value;
  final double frequency;
  final double width;
  final ValueChanged<double> onChanged;
  final bool isEnabled;

  const _BandSlider({
    required this.index,
    required this.value,
    required this.frequency,
    required this.width,
    required this.onChanged,
    required this.isEnabled,
  });

  @override
  State<_BandSlider> createState() => _BandSliderState();
}

class _BandSliderState extends State<_BandSlider> {
  bool _isHovered = false;

  String _formatFrequency(double freq) {
    if (freq >= 1000) {
      return '${(freq / 1000).toStringAsFixed(freq == 16000 ? 0 : 1)}k';
    }
    return freq.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final Color accentColor = const Color(0xFF6366F1);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _isHovered ? 1.0 : 0.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.value.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: widget.isEnabled ? accentColor : GlassTheme.textTertiary,
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor: widget.isEnabled ? Colors.white : GlassTheme.textTertiary,
                    overlayColor: accentColor.withOpacity(0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: widget.value,
                    min: -12.0,
                    max: 12.0,
                    onChanged: widget.isEnabled ? widget.onChanged : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatFrequency(widget.frequency),
              style: TextStyle(
                color: _isHovered ? GlassTheme.textPrimary : GlassTheme.textTertiary,
                fontSize: 11,
                fontWeight: _isHovered ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BassBoostView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<EqualizerProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bass Boost',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: GlassTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enhance low frequencies for a deeper, richer sound',
              style: TextStyle(
                color: GlassTheme.textTertiary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Container(
                width: 300,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: CustomPaint(
                  painter: _BassBoostVisualizerPainter(
                    boost: provider.bassBoost,
                    color: const Color(0xFF6366F1),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Icon(
                  Icons.speaker_rounded,
                  color: GlassTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFF6366F1),
                      inactiveTrackColor: Colors.white.withOpacity(0.1),
                      thumbColor: Colors.white,
                      overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                    ),
                    child: Slider(
                      value: provider.bassBoost,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: provider.isEnabled ? provider.setBassBoost : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.speaker_group_rounded,
                  color: GlassTheme.textTertiary,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${(provider.bassBoost * 100).round()}%',
                style: TextStyle(
                  color: const Color(0xFF6366F1),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                ),
              ),
            ),
            const Spacer(),
            const SizedBox(height: 20),
            const Text(
              'Quick Presets',
              style: TextStyle(
                color: GlassTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _BassPresetButton(
                  label: 'Subtle',
                  value: 0.3,
                  currentValue: provider.bassBoost,
                  onPressed: () => provider.setBassBoost(0.3),
                ),
                const SizedBox(width: 12),
                _BassPresetButton(
                  label: 'Medium',
                  value: 0.6,
                  currentValue: provider.bassBoost,
                  onPressed: () => provider.setBassBoost(0.6),
                ),
                const SizedBox(width: 12),
                _BassPresetButton(
                  label: 'Heavy',
                  value: 0.9,
                  currentValue: provider.bassBoost,
                  onPressed: () => provider.setBassBoost(0.9),
                ),
                const SizedBox(width: 12),
                _BassPresetButton(
                  label: 'Max',
                  value: 1.0,
                  currentValue: provider.bassBoost,
                  onPressed: () => provider.setBassBoost(1.0),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BassPresetButton extends StatelessWidget {
  final String label;
  final double value;
  final double currentValue;
  final VoidCallback onPressed;

  const _BassPresetButton({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = (currentValue - value).abs() < 0.05;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      const Color(0xFF6366F1).withOpacity(0.3),
                      const Color(0xFF8B5CF6).withOpacity(0.15),
                    ],
                  )
                : null,
            color: isSelected ? null : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF6366F1).withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF6366F1) : GlassTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BassBoostVisualizerPainter extends CustomPainter {
  final double boost;
  final Color color;

  _BassBoostVisualizerPainter({required this.boost, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;
    
    final path = Path();
    final width = size.width;
    final height = size.height;
    
    path.moveTo(0, height);
    
    for (double x = 0; x <= width; x += 2) {
      final freq = (x / width) * 20000;
      double gain = 0;
      
      if (freq < 100) {
        gain = boost * 15;
      } else if (freq < 200) {
        gain = boost * 12;
      } else if (freq < 500) {
        gain = boost * 8;
      } else if (freq < 1000) {
        gain = boost * 4;
      } else if (freq < 2000) {
        gain = boost * 1;
      } else {
        gain = 0;
      }
      
      final y = height - (gain / 15) * (height * 0.7);
      path.lineTo(x, y);
    }
    
    path.lineTo(width, height);
    path.close();
    
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        color.withOpacity(0.5),
        color.withOpacity(0.1),
      ],
    );
    
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, width, height));
    canvas.drawPath(path, paint);
    
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _BassBoostVisualizerPainter oldDelegate) {
    return oldDelegate.boost != boost;
  }
}

// ==================== VISUALIZER ====================
class AudioVisualizerWidget extends StatefulWidget {
  const AudioVisualizerWidget({super.key});

  @override
  State<AudioVisualizerWidget> createState() => _AudioVisualizerWidgetState();
}

class _AudioVisualizerWidgetState extends State<AudioVisualizerWidget> with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _bars = List.generate(48, (_) => 0.15);
  final math.Random _random = math.Random();
  double _smoothness = 0.85;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    )..addListener(_updateBars);

    final provider = context.read<PlayerProvider>();
    provider.audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (mounted) {
          setState(() {
            for (int i = 0; i < _bars.length; i++) {
              _bars[i] = 0.15;
            }
          });
        }
      }
    });
  }

  void _updateBars() {
    if (mounted) {
      setState(() {
        for (int i = 0; i < _bars.length; i++) {
          final target = 0.1 + _random.nextDouble() * 0.8;
          _bars[i] = _bars[i] * _smoothness + target * (1 - _smoothness);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    if (provider.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!provider.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: provider.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.equalizer_rounded,
                  color: provider.accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Visualizer',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: GlassTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (provider.isPlaying)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: provider.accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: provider.accentColor,
                          boxShadow: [
                            BoxShadow(
                              color: provider.accentColor.withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: provider.accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn()
                    .then()
                    .shimmer(duration: 2000.ms, color: provider.accentColor.withOpacity(0.3)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: _VisualizerPainter(
                  bars: _bars,
                  color: provider.accentColor,
                  isPlaying: provider.isPlaying,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final List<double> bars;
  final Color color;
  final bool isPlaying;

  _VisualizerPainter({
    required this.bars,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / bars.length;
    final maxHeight = size.height;

    final reflectionGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.05),
        Colors.transparent,
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, maxHeight * 0.7, size.width, maxHeight * 0.3),
      Paint()..shader = reflectionGradient.createShader(
        Rect.fromLTWH(0, maxHeight * 0.7, size.width, maxHeight * 0.3),
      ),
    );

    for (int i = 0; i < bars.length; i++) {
      final barHeight = isPlaying ? bars[i] * maxHeight * 0.7 : maxHeight * 0.05;
      final x = i * barWidth;
      final y = (maxHeight * 0.7 - barHeight) / 2 + maxHeight * 0.05;

      final barGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          color.withOpacity(0.4),
          color.withOpacity(0.9),
          Color.lerp(color, Colors.white, 0.3)!.withOpacity(0.95),
        ],
        stops: const [0.0, 0.6, 1.0],
      );
      final rect = Rect.fromLTWH(
        x + barWidth * 0.15,
        y,
        barWidth * 0.7,
        barHeight,
      );
      final paint = Paint()
        ..shader = barGradient.createShader(rect)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.35)),
        paint,
      );

      if (bars[i] > 0.5 && isPlaying) {
        final glowPaint = Paint()
          ..color = color.withOpacity(0.3 * bars[i])
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.35)),
          glowPaint,
        );
      }

      final reflectionRect = Rect.fromLTWH(
        x + barWidth * 0.15,
        maxHeight * 0.7 + 4,
        barWidth * 0.7,
        barHeight * 0.25,
      );
      final reflectionPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.0),
          ],
        ).createShader(reflectionRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(reflectionRect, Radius.circular(barWidth * 0.35)),
        reflectionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) {
    return true;
  }
}

// ==================== CUSTOM TITLE BAR ====================
class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = playerProvider.accentColor;
    
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.4),
              Colors.black.withOpacity(0.2),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(0.3),
                    accent.withOpacity(0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accent.withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.2),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                Icons.waves_rounded,
                color: accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hizha Player',
                  style: TextStyle(
                    color: GlassTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'enjoy (:',
                  style: TextStyle(
                    color: GlassTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            GlassIconButton(
              icon: themeProvider.themeMode == ThemeMode.dark 
                  ? Icons.light_mode_rounded 
                  : Icons.dark_mode_rounded,
              onPressed: () => themeProvider.toggleTheme(),
              tooltip: themeProvider.themeMode == ThemeMode.dark 
                  ? 'Switch to Transparent Theme' 
                  : 'Switch to Dark Theme',
              size: 36,
              iconSize: 18,
            ),
            const SizedBox(width: 8),
            if (playerProvider.currentSong != null)
              _MiniNowPlaying(
                title: playerProvider.currentSong!.title,
                isPlaying: playerProvider.isPlaying,
                accent: accent,
              ),
            const Spacer(),
            _WindowControls(),
          ],
        ),
      ),
    );
  }
}

class _MiniNowPlaying extends StatelessWidget {
  final String title;
  final bool isPlaying;
  final Color accent;
  const _MiniNowPlaying({
    required this.title,
    required this.isPlaying,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPlaying) ...[
            _MiniPlayingIndicator(color: accent),
            const SizedBox(width: 10),
          ] else
            Icon(
              Icons.music_note_rounded,
              color: GlassTheme.textTertiary,
              size: 14,
            ),
          if (!isPlaying) const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              title,
              style: TextStyle(
                color: isPlaying ? accent : GlassTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayingIndicator extends StatefulWidget {
  final Color color;
  const _MiniPlayingIndicator({required this.color});

  @override
  State<_MiniPlayingIndicator> createState() => _MiniPlayingIndicatorState();
}

class _MiniPlayingIndicatorState extends State<_MiniPlayingIndicator> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: Duration(milliseconds: 400 + (index * 100)),
        vsync: this,
      )..repeat(reverse: true),
    );
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 2.5,
              height: 6 + (_controllers[index].value * 8),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }
}

class _WindowControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: Icons.remove_rounded,
          onPressed: () => windowManager.minimize(),
          hoverColor: Colors.white.withOpacity(0.1),
        ),
        _WindowButton(
          icon: Icons.crop_square_rounded,
          iconSize: 14,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
          hoverColor: Colors.white.withOpacity(0.1),
        ),
        _WindowButton(
          icon: Icons.close_rounded,
          onPressed: () => windowManager.close(),
          hoverColor: const Color(0xFFE81123),
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final Color hoverColor;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    this.iconSize = 16,
    required this.onPressed,
    required this.hoverColor,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _hoverController;
  late Animation<double> _hoverAnimation;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _hoverAnimation = CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        _hoverController.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _hoverController.reverse();
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: _hoverAnimation,
          builder: (context, child) {
            final scale = _isHovered ? 1.1 : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 46,
                height: 52,
                decoration: BoxDecoration(
                  color: _isHovered ? widget.hoverColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  widget.icon,
                  color: _isHovered && widget.isClose
                      ? Colors.white
                      : Colors.white.withOpacity(_isHovered ? 1 : 0.7),
                  size: widget.iconSize,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== KEYBOARD SHORTCUTS ====================
class KeyboardShortcuts extends StatelessWidget {
  final Widget child;
  const KeyboardShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PlayerProvider>();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          provider.togglePlayPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () {
          provider.next();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () {
          provider.previous();
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () {
          provider.setVolume((provider.volume + 0.1).clamp(0.0, 1.0));
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () {
          provider.setVolume((provider.volume - 0.1).clamp(0.0, 1.0));
        },
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () {
          provider.toggleMute();
        },
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
          provider.pickAndAddFiles();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          provider.toggleShuffle();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          provider.cycleLoopMode();
        },
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}

// ==================== HOME SCREEN ====================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener, SingleTickerProviderStateMixin {
  late TabController _mainTabController;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _mainTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _mainTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardShortcuts(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const AnimatedBackground(),
            Column(
              children: [
                const CustomTitleBar(),
                Container(
                  height: 48,
                  margin: const EdgeInsets.only(top: 4),
                  child: TabBar(
                    controller: _mainTabController,
                    indicatorColor: context.watch<PlayerProvider>().accentColor,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: GlassTheme.textPrimary,
                    unselectedLabelColor: GlassTheme.textTertiary,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.library_music_rounded, size: 18),
                        text: 'PLAYER',
                      ),
                      Tab(
                        icon: Icon(Icons.equalizer_rounded, size: 18),
                        text: 'EQUALIZER',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _mainTabController,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth > 1300) {
                            return const _WideLayout();
                          } else if (constraints.maxWidth > 950) {
                            return const _MediumLayout();
                          } else {
                            return const _CompactLayout();
                          }
                        },
                      ),
                      const EqualizerTab(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: NowPlayingSection(),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 4,
            child: Column(
              children: [
                const Expanded(
                  flex: 3,
                  child: AudioVisualizerWidget(),
                ),
                const SizedBox(height: 24),
                const PlayerControlsSection(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          const Expanded(
            flex: 3,
            child: PlaylistSection(),
          ),
        ],
      ),
    );
  }
}

class _MediumLayout extends StatelessWidget {
  const _MediumLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                const Expanded(
                  flex: 4,
                  child: NowPlayingSection(),
                ),
                const SizedBox(height: 20),
                const PlayerControlsSection(),
              ],
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            flex: 4,
            child: PlaylistSection(),
          ),
        ],
      ),
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Expanded(
                  flex: 1,
                  child: _CompactNowPlaying(),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  flex: 1,
                  child: PlaylistSection(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const PlayerControlsSection(),
        ],
      ),
    );
  }
}

class _CompactNowPlaying extends StatelessWidget {
  const _CompactNowPlaying();

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final song = provider.currentSong;
        final accent = provider.accentColor;
        return GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = math.min(
                        constraints.maxWidth * 0.8,
                        constraints.maxHeight * 0.7,
                      );
                      return AlbumArt(
                        isPlaying: provider.isPlaying,
                        accentColor: accent,
                        size: size.clamp(150.0, 250.0),
                        coverArt: song?.coverArt,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                song?.title ?? 'No song playing',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: GlassTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                song?.artist ?? 'Add music to start',
                style: const TextStyle(
                  fontSize: 13,
                  color: GlassTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}  }
}

// ==================== APP ====================
class LiquidGlassPlayer extends StatelessWidget {
  const LiquidGlassPlayer({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Hizha Player',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.themeMode == ThemeMode.dark 
                ? GlassTheme.darkTheme 
                : GlassTheme.transparentTheme,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

// ==================== MODELS ====================
class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String path;
  final Duration duration;
  final Color accentColor;
  final int colorIndex;
  final Uint8List? coverArt;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    required this.duration,
    required this.accentColor,
    required this.colorIndex,
    this.coverArt,
  });

  factory Song.fromFile(String filePath, int index, {Uint8List? coverArt, Map<String, dynamic>? metadata}) {
    String title = 'Unknown Title';
    String artist = 'Unknown Artist';
    String album = 'Unknown Album';
    Duration duration = Duration.zero;

    if (metadata != null) {
      title = metadata['trackName'] ?? 'Unknown Title';
      artist = metadata['trackArtistNames'] != null && metadata['trackArtistNames'].isNotEmpty 
          ? metadata['trackArtistNames'][0] 
          : 'Unknown Artist';
      album = metadata['albumName'] ?? 'Unknown Album';
      final int? trackDuration = metadata['trackDuration'];
      if (trackDuration != null) {
        duration = Duration(milliseconds: trackDuration);
      }
    } else {
      final fileName = filePath.split('\\').last.split('/').last;
      final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      
      title = name;
      artist = 'Unknown Artist';
      if (name.contains(' - ')) {
        final parts = name.split(' - ');
        artist = parts[0].trim();
        title = parts.sublist(1).join(' - ').trim();
      }
    }
    
    final colors = GlassTheme.accentColors;
    final colorIndex = index % colors.length;
    
    return Song(
      id: '${DateTime.now().millisecondsSinceEpoch}_$index',
      title: title,
      artist: artist,
      album: album,
      path: filePath,
      duration: duration,
      accentColor: colors[colorIndex],
      colorIndex: colorIndex,
      coverArt: coverArt,
    );
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  PositionData(this.position, this.bufferedPosition, this.duration);
  double get progress => duration.inMilliseconds > 0
      ? position.inMilliseconds / duration.inMilliseconds
      : 0.0;
}

// ==================== THEME ====================
class GlassTheme {
  // Glass Colors
  static const Color glassPrimary = Color(0x18FFFFFF);
  static const Color glassSecondary = Color(0x0DFFFFFF);
  static const Color glassBorder = Color(0x20FFFFFF);
  static const Color glassBorderLight = Color(0x35FFFFFF);
  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF);
  static const Color textTertiary = Color(0x66FFFFFF);
  // Accent Colors Palette
  static const List<Color> accentColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Violet
    Color(0xFFEC4899), // Pink
    Color(0xFFF43F5E), // Rose
    Color(0xFFF97316), // Orange
    Color(0xFFEAB308), // Yellow
    Color(0xFF22C55E), // Green
    Color(0xFF14B8A6), // Teal
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Blue
  ];
  static const Color defaultAccent = Color(0xFF8B5CF6);
  // Background Colors
  static const Color bgDark = Color(0xFF0A0A0F);
  static const Color bgCard = Color(0xFF12121A);
  
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -1,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textTertiary,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: defaultAccent,
        secondary: defaultAccent,
        surface: glassPrimary,
      ),
    );
  }
  
  static ThemeData get transparentTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -1,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textPrimary.withOpacity(0.9),
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textPrimary.withOpacity(0.8),
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: defaultAccent,
        secondary: defaultAccent,
        surface: Color(0x10FFFFFF),
      ),
    );
  }
}

// ==================== PROVIDER ====================
class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<Song> _playlist = [];
  int _currentIndex = -1;
  bool _isShuffled = false;
  LoopMode _loopMode = LoopMode.off;
  double _volume = 0.7;
  bool _isMuted = false;
  double _previousVolume = 0.7;

  PlayerProvider() {
    _init();
  }

  void _init() {
    _audioPlayer.setVolume(_volume);
    _audioPlayer.playerStateStream.listen((state) {
      notifyListeners();
    });
    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex) {
        _currentIndex = index;
        notifyListeners();
      }
    });
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (_loopMode == LoopMode.off && _currentIndex >= _playlist.length - 1) {
          // Playlist ended
        }
      }
    });
  }

  // Getters
  AudioPlayer get audioPlayer => _audioPlayer;
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  Song? get currentSong => _currentIndex >= 0 && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;
  bool get isPlaying => _audioPlayer.playing;
  bool get isShuffled => _isShuffled;
  LoopMode get loopMode => _loopMode;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  Color get accentColor => currentSong?.accentColor ?? GlassTheme.defaultAccent;
  bool get hasPrevious => _currentIndex > 0;
  bool get hasNext => _currentIndex < _playlist.length - 1;

  Stream<PositionData> get positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _audioPlayer.positionStream,
        _audioPlayer.bufferedPositionStream,
        _audioPlayer.durationStream,
        (position, bufferedPosition, duration) => PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        ),
      );

  Future<void> pickAndAddFiles() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      dialogTitle: 'Select Music Files',
    );
    
    if (result != null && result.files.isNotEmpty) {
      final startIndex = _playlist.length;
      for (int i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        if (file.path != null) {
          try {
            final coverArt = await _extractCoverArt(file.path!);
            final song = Song.fromFile(
              file.path!, 
              startIndex + i, 
              coverArt: coverArt,
            );
            _playlist.add(song);
          } catch (e) {
            debugPrint('Error processing file ${file.path}: $e');
            final song = Song.fromFile(file.path!, startIndex + i);
            _playlist.add(song);
          }
        }
      }
      
      if (_playlist.isNotEmpty && _currentIndex == -1) {
        await _loadPlaylist();
        _currentIndex = 0;
      } else if (_playlist.isNotEmpty) {
        await _reloadPlaylist();
      }
      notifyListeners();
    }
  } catch (e) {
    debugPrint('Error picking files: $e');
  }
}

  Future<Uint8List?> _extractCoverArt(String filePath) async {
    try {
      final metadata = await MetadataRetriever.fromFile(File(filePath));
      
      if (metadata.albumArt != null && metadata.albumArt!.isNotEmpty) {
        return Uint8List.fromList(metadata.albumArt!);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error extracting cover art: $e');
      return null;
    }
  }

  Future<void> _loadPlaylist() async {
    if (_playlist.isEmpty) return;
    final audioSources = _playlist.map((song) => AudioSource.file(song.path, tag: song)).toList();
    await _audioPlayer.setAudioSource(
      ConcatenatingAudioSource(children: audioSources),
      initialIndex: 0,
    );
  }

  Future<void> _reloadPlaylist() async {
    if (_playlist.isEmpty) return;
    final currentPosition = _audioPlayer.position;
    final wasPlaying = isPlaying;
    final audioSources = _playlist.map((song) => AudioSource.file(song.path, tag: song)).toList();
    await _audioPlayer.setAudioSource(
      ConcatenatingAudioSource(children: audioSources),
      initialIndex: _currentIndex >= 0 ? _currentIndex : 0,
      initialPosition: currentPosition,
    );
    if (wasPlaying) {
      await play();
    }
  }

  Future<void> play() async {
    if (_playlist.isEmpty) return;
    await _audioPlayer.play();
  }

  Future<void> pause() async => await _audioPlayer.pause();

  Future<void> togglePlayPause() async {
    if (_playlist.isEmpty) {
      await pickAndAddFiles();
      return;
    }
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex < _playlist.length - 1) {
      await _audioPlayer.seekToNext();
    } else if (_loopMode == LoopMode.all) {
      await _audioPlayer.seek(Duration.zero, index: 0);
    }
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    if (_audioPlayer.position.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
    } else if (_currentIndex > 0) {
      await _audioPlayer.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    await _audioPlayer.setVolume(_volume);
    notifyListeners();
  }

  void toggleMute() {
    if (_isMuted) {
      _volume = _previousVolume > 0 ? _previousVolume : 0.7;
      _isMuted = false;
    } else {
      _previousVolume = _volume;
      _volume = 0;
      _isMuted = true;
    }
    _audioPlayer.setVolume(_volume);
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    await _audioPlayer.seek(Duration.zero, index: index);
    await play();
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    _audioPlayer.setShuffleModeEnabled(_isShuffled);
    notifyListeners();
  }

  void cycleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        break;
    }
    _audioPlayer.setLoopMode(_loopMode);
    notifyListeners();
  }

  void removeFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    _playlist.removeAt(index);
    if (_playlist.isEmpty) {
      _currentIndex = -1;
      _audioPlayer.stop();
    } else if (index == _currentIndex) {
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
      _reloadPlaylist();
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    notifyListeners();
  }

  void clearPlaylist() {
    _playlist.clear();
    _currentIndex = -1;
    _audioPlayer.stop();
    notifyListeners();
  }

  void reorderPlaylist(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

// ==================== GLASS WIDGETS ====================
class GlassContainer extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final bool enableHover;
  final bool animate;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final bool forceTransparent;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 24,
    this.blur = 40,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.enableHover = true,
    this.animate = true,
    this.onTap,
    this.gradient,
    this.boxShadow,
    this.forceTransparent = false,
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = provider.accentColor;
    
    final bool isTransparentTheme = themeProvider.themeMode == ThemeMode.transparent || widget.forceTransparent;
    
    final bgColor = isTransparentTheme 
        ? Colors.black.withOpacity(0.15)
        : (widget.backgroundColor ?? GlassTheme.glassPrimary);
        
    final bdColor = isTransparentTheme
        ? Colors.white.withOpacity(0.2)
        : (widget.borderColor ?? GlassTheme.glassBorder);

    final double blurAmount = isTransparentTheme ? 3 : widget.blur;

    Widget container = MouseRegion(
      onEnter: widget.enableHover ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enableHover ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: widget.boxShadow ?? [
              if (!isTransparentTheme)
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              if (_isHovered && widget.enableHover)
                BoxShadow(
                  color: accent.withOpacity(isTransparentTheme ? 0.1 : 0.15),
                  blurRadius: 50,
                  spreadRadius: 5,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurAmount,
                sigmaY: blurAmount,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: widget.gradient ?? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isTransparentTheme
                        ? [
                            Colors.white.withOpacity(_isHovered ? 0.12 : 0.08),
                            Colors.white.withOpacity(_isHovered ? 0.08 : 0.05),
                          ]
                        : [
                            bgColor.withOpacity(_isHovered ? 0.22 : 0.15),
                            bgColor.withOpacity(_isHovered ? 0.12 : 0.08),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: _isHovered ? accent.withOpacity(isTransparentTheme ? 0.2 : 0.3) : bdColor,
                    width: widget.borderWidth,
                  ),
                ),
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.animate) {
      container = container
          .animate()
          .fadeIn(duration: 500.ms, curve: Curves.easeOut)
          .scale(
            begin: const Offset(0.95, 0.95),
            duration: 500.ms,
            curve: Curves.easeOut,
          );
    }

    return container;
  }
}

class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final String? tooltip;
  final bool isActive;
  final bool showBackground;
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 22,
    this.color,
    this.tooltip,
    this.isActive = false,
    this.showBackground = true,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = provider.accentColor;
    final color = widget.color ?? GlassTheme.textPrimary;
    final isTransparentTheme = themeProvider.themeMode == ThemeMode.transparent;

    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _controller.forward();
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.showBackground
                      ? (widget.isActive
                          ? accent.withOpacity(isTransparentTheme ? 0.2 : 0.25)
                          : (_isHovered ? Colors.white.withOpacity(isTransparentTheme ? 0.08 : 0.1) : Colors.white.withOpacity(isTransparentTheme ? 0.04 : 0.05)))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(widget.size / 3),
                  border: widget.showBackground
                      ? Border.all(
                          color: widget.isActive
                              ? accent.withOpacity(isTransparentTheme ? 0.3 : 0.4)
                              : (_isHovered ? Colors.white.withOpacity(isTransparentTheme ? 0.12 : 0.15) : Colors.transparent),
                          width: 1,
                        )
                      : null,
                  boxShadow: widget.isActive
                      ? [
                          BoxShadow(
                            color: accent.withOpacity(isTransparentTheme ? 0.2 : 0.3),
                            blurRadius: 12,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: widget.isActive ? accent : (_isHovered ? Colors.white : color.withOpacity(isTransparentTheme ? 0.9 : 0.8)),
                ),
              ),
            );
          },
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        preferBelow: false,
        decoration: BoxDecoration(
          color: GlassTheme.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GlassTheme.glassBorder),
        ),
        textStyle: const TextStyle(
          color: GlassTheme.textPrimary,
          fontSize: 12,
        ),
        child: button,
      );
    }

    return button;
  }
}

// ==================== ANIMATED BACKGROUND ====================
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _colorController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    _colorController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = playerProvider.accentColor;
    
    if (themeProvider.themeMode == ThemeMode.transparent) {
      return Container(
        color: Colors.transparent,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Container(
            color: Colors.black.withOpacity(0.25),
          ),
        ),
      );
    }
    
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _colorController]),
      builder: (context, child) {
        return CustomPaint(
          painter: _BackgroundPainter(
            animation: _controller.value,
            colorAnimation: _colorController.value,
            accentColor: accent,
            isPlaying: playerProvider.isPlaying,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double animation;
  final double colorAnimation;
  final Color accentColor;
  final bool isPlaying;

  _BackgroundPainter({
    required this.animation,
    required this.colorAnimation,
    required this.accentColor,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0D0D12),
        const Color(0xFF0A0A0F),
        Color.lerp(const Color(0xFF0F0F18), accentColor.withOpacity(0.05), colorAnimation)!,
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = bgGradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      ),
    );

    final orbs = [
      _Orb(
        baseX: 0.15,
        baseY: 0.2,
        radius: size.width * 0.35,
        color: accentColor.withOpacity(isPlaying ? 0.08 : 0.04),
        speed: 1.0,
        amplitude: 0.05,
      ),
      _Orb(
        baseX: 0.85,
        baseY: 0.75,
        radius: size.width * 0.4,
        color: Color.lerp(accentColor, const Color(0xFF06B6D4), 0.5)!.withOpacity(isPlaying ? 0.06 : 0.03),
        speed: 0.7,
        amplitude: 0.04,
      ),
      _Orb(
        baseX: 0.5,
        baseY: 0.5,
        radius: size.width * 0.3,
        color: Color.lerp(accentColor, const Color(0xFFEC4899), 0.5)!.withOpacity(isPlaying ? 0.05 : 0.025),
        speed: 1.3,
        amplitude: 0.06,
      ),
      _Orb(
        baseX: 0.75,
        baseY: 0.15,
        radius: size.width * 0.25,
        color: accentColor.withOpacity(isPlaying ? 0.04 : 0.02),
        speed: 0.9,
        amplitude: 0.03,
      ),
    ];

    for (var orb in orbs) {
      final offsetX = math.sin(animation * 2 * math.pi * orb.speed) * size.width * orb.amplitude;
      final offsetY = math.cos(animation * 2 * math.pi * orb.speed * 0.7) * size.height * orb.amplitude;
      final center = Offset(
        size.width * orb.baseX + offsetX,
        size.height * orb.baseY + offsetY,
      );
      final gradient = RadialGradient(
        colors: [
          orb.color,
          orb.color.withOpacity(0),
        ],
        stops: const [0.0, 1.0],
      );
      final rect = Rect.fromCircle(center: center, radius: orb.radius);
      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(center, orb.radius, paint);
    }

    final noisePaint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..blendMode = BlendMode.overlay;
    final random = math.Random(42);
    for (int i = 0; i < 100; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * 2,
        noisePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isPlaying != isPlaying;
  }
}

class _Orb {
  final double baseX;
  final double baseY;
  final double radius;
  final Color color;
  final double speed;
  final double amplitude;

  _Orb({
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.color,
    required this.speed,
    required this.amplitude,
  });
}

// ==================== ALBUM ART ====================
class AlbumArt extends StatefulWidget {
  final bool isPlaying;
  final Color accentColor;
  final double size;
  final Uint8List? coverArt;
  const AlbumArt({
    super.key,
    required this.isPlaying,
    required this.accentColor,
    this.size = 280,
    this.coverArt,
  });

  @override
  State<AlbumArt> createState() => _AlbumArtState();
}

class _AlbumArtState extends State<AlbumArt> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _rotationController,
        _pulseController,
        _glowController,
      ]),
      builder: (context, child) {
        final glowIntensity = widget.isPlaying ? 0.3 + (_glowController.value * 0.2) : 0.15;
        final pulseScale = widget.isPlaying ? 1.0 + (_pulseController.value * 0.02) : 1.0;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: pulseScale * 1.3,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor.withOpacity(glowIntensity),
                        blurRadius: 80,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              
              ...List.generate(3, (index) {
                final ringScale = 1.0 + (index * 0.12) + (_pulseController.value * 0.03 * (index + 1));
                return Transform.scale(
                  scale: ringScale,
                  child: Transform.rotate(
                    angle: _rotationController.value * 2 * math.pi * (index.isEven ? 1 : -1) * (0.5 + index * 0.2),
                    child: Container(
                      width: widget.size * 0.85,
                      height: widget.size * 0.85,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.accentColor.withOpacity(0.15 - (index * 0.04)),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),

              Transform.rotate(
                angle: widget.coverArt == null ? _rotationController.value * 2 * math.pi : 0,
                child: Container(
                  width: widget.size * 0.8,
                  height: widget.size * 0.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.coverArt == null 
                      ? RadialGradient(
                          colors: [
                            widget.accentColor.withOpacity(0.4),
                            widget.accentColor.withOpacity(0.2),
                            const Color(0xFF1a1a2e).withOpacity(0.9),
                            Colors.black.withOpacity(0.95),
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0],
                        )
                      : null,
                    image: widget.coverArt != null 
                      ? DecorationImage(
                          image: MemoryImage(widget.coverArt!),
                          fit: BoxFit.cover,
                        )
                      : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                      BoxShadow(
                        color: widget.accentColor.withOpacity(0.2),
                        blurRadius: 40,
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: widget.coverArt == null 
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          ...List.generate(12, (index) {
                            return Container(
                              margin: EdgeInsets.all(15.0 + (index * 8)),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.03 + (index.isEven ? 0.02 : 0)),
                                  width: 0.5,
                                ),
                              ),
                            );
                          }),
                          Container(
                            width: widget.size * 0.25,
                            height: widget.size * 0.25,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  widget.accentColor.withOpacity(0.9),
                                  widget.accentColor.withOpacity(0.6),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accentColor.withOpacity(0.5),
                                  blurRadius: 25,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: widget.size * 0.05,
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white.withOpacity(0.9),
                                    size: widget.size * 0.08,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==================== NOW PLAYING ====================
class NowPlayingSection extends StatelessWidget {
  const NowPlayingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final song = provider.currentSong;
        final accent = provider.accentColor;
        return GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = math.min(
                        constraints.maxWidth * 0.85,
                        constraints.maxHeight * 0.9,
                      );
                      return AlbumArt(
                        isPlaying: provider.isPlaying,
                        accentColor: accent,
                        size: size.clamp(200.0, 350.0),
                        coverArt: song?.coverArt,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.3),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        song?.title ?? 'No song playing',
                        key: ValueKey(song?.id ?? 'empty'),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: GlassTheme.textPrimary,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: accent.withOpacity(0.5),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        song?.artist ?? 'Add music to get started',
                        key: ValueKey('${song?.id ?? 'empty'}_artist'),
                        style: TextStyle(
                          fontSize: 16,
                          color: GlassTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==================== PLAYER CONTROLS ====================
class PlayerControlsSection extends StatelessWidget {
  const PlayerControlsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        return GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          borderRadius: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProgressBarWidget(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassIconButton(
                    icon: Icons.shuffle_rounded,
                    onPressed: provider.toggleShuffle,
                    isActive: provider.isShuffled,
                    tooltip: provider.isShuffled ? 'Shuffle On' : 'Shuffle Off',
                    size: 44,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: Icons.skip_previous_rounded,
                    onPressed: provider.previous,
                    tooltip: 'Previous',
                    size: 52,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 16),
                  PlayPauseButton(
                    isPlaying: provider.isPlaying,
                    onPressed: provider.togglePlayPause,
                    accentColor: provider.accentColor,
                  ),
                  const SizedBox(width: 16),
                  GlassIconButton(
                    icon: Icons.skip_next_rounded,
                    onPressed: provider.next,
                    tooltip: 'Next',
                    size: 52,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: _getLoopIcon(provider.loopMode),
                    onPressed: provider.cycleLoopMode,
                    isActive: provider.loopMode != LoopMode.off,
                    tooltip: _getLoopTooltip(provider.loopMode),
                    size: 44,
                    iconSize: 20,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const VolumeControlWidget(),
            ],
          ),
        );
      },
    );
  }

  IconData _getLoopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.one:
        return Icons.repeat_one_rounded;
      default:
        return Icons.repeat_rounded;
    }
  }

  String _getLoopTooltip(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return 'Repeat Off';
      case LoopMode.all:
        return 'Repeat All';
      case LoopMode.one:
        return 'Repeat One';
    }
  }
}

class PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final Color accentColor;
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    required this.accentColor,
  });

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton> with TickerProviderStateMixin {
  late AnimationController _iconController;
  late AnimationController _scaleController;
  late AnimationController _glowController;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    if (widget.isPlaying) {
      _iconController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _iconController.forward();
      } else {
        _iconController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _iconController.dispose();
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _scaleController.forward();
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _scaleController.reverse();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _scaleController.reverse();
        },
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onPressed();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleController, _glowController]),
          builder: (context, child) {
            final scale = 1.0 - (_scaleController.value * 0.08);
            final glowOpacity = widget.isPlaying ? 0.4 + (_glowController.value * 0.2) : 0.3;
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.accentColor.withOpacity(_isHovered ? 1.0 : 0.9),
                      Color.lerp(widget.accentColor, Colors.black, 0.3)!.withOpacity(_isHovered ? 0.95 : 0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(glowOpacity),
                      blurRadius: _isHovered ? 35 : 25,
                      spreadRadius: _isHovered ? 3 : 0,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _iconController,
                    size: 38,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ProgressBarWidget extends StatelessWidget {
  const ProgressBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return StreamBuilder<PositionData>(
      stream: provider.positionDataStream,
      builder: (context, snapshot) {
        final positionData = snapshot.data;
        final accent = provider.accentColor;
        return Column(
          children: [
            ProgressBar(
              progress: positionData?.position ?? Duration.zero,
              buffered: positionData?.bufferedPosition ?? Duration.zero,
              total: positionData?.duration ?? Duration.zero,
              onSeek: provider.seek,
              barHeight: 5,
              baseBarColor: Colors.white.withOpacity(0.1),
              progressBarColor: accent,
              bufferedBarColor: accent.withOpacity(0.3),
              thumbColor: Colors.white,
              thumbGlowColor: accent.withOpacity(0.4),
              thumbRadius: 8,
              thumbGlowRadius: 18,
              timeLabelLocation: TimeLabelLocation.sides,
              timeLabelTextStyle: TextStyle(
                color: GlassTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              ),
              timeLabelPadding: 8,
            ),
          ],
        );
      },
    );
  }
}

class VolumeControlWidget extends StatefulWidget {
  const VolumeControlWidget({super.key});

  @override
  State<VolumeControlWidget> createState() => _VolumeControlWidgetState();
}

class _VolumeControlWidgetState extends State<VolumeControlWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final accent = provider.accentColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _isExpanded = true),
      onExit: (_) => setState(() => _isExpanded = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(_isExpanded ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(_isExpanded ? 0.15 : 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIconButton(
              icon: _getVolumeIcon(provider.volume, provider.isMuted),
              onPressed: provider.toggleMute,
              tooltip: provider.isMuted ? 'Unmute' : 'Mute',
              size: 36,
              iconSize: 20,
              showBackground: false,
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isExpanded ? 140 : 100,
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white.withOpacity(0.15),
                  thumbColor: Colors.white,
                  overlayColor: accent.withOpacity(0.2),
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    elevation: 4,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: provider.volume,
                  onChanged: provider.setVolume,
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isExpanded ? 1.0 : 0.0,
              child: SizedBox(
                width: 36,
                child: Text(
                  '${(provider.volume * 100).round()}%',
                  style: TextStyle(
                    color: GlassTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getVolumeIcon(double volume, bool isMuted) {
    if (isMuted || volume == 0) return Icons.volume_off_rounded;
    if (volume < 0.3) return Icons.volume_mute_rounded;
    if (volume < 0.7) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }
}

// ==================== PLAYLIST ====================
class PlaylistSection extends StatefulWidget {
  const PlaylistSection({super.key});

  @override
  State<PlaylistSection> createState() => _PlaylistSectionState();
}

class _PlaylistSectionState extends State<PlaylistSection> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final filteredPlaylist = _searchQuery.isEmpty
            ? provider.playlist
            : provider.playlist.where((song) =>
                song.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                song.artist.toLowerCase().contains(_searchQuery.toLowerCase())
              ).toList();

        return GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlaylistHeader(
                songCount: provider.playlist.length,
                onAddMusic: provider.pickAndAddFiles,
                onClear: provider.playlist.isNotEmpty ? provider.clearPlaylist : null,
                showSearch: _showSearch,
                onToggleSearch: () => setState(() => _showSearch = !_showSearch),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: _showSearch ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: _SearchBar(
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                secondChild: const SizedBox(height: 12),
              ),
              Expanded(
                child: provider.playlist.isEmpty
                    ? _EmptyPlaylist(onAddMusic: provider.pickAndAddFiles)
                    : filteredPlaylist.isEmpty
                        ? _NoResults()
                        : _PlaylistContent(
                            playlist: filteredPlaylist,
                            allPlaylist: provider.playlist,
                            currentIndex: provider.currentIndex,
                            isPlaying: provider.isPlaying,
                            accentColor: provider.accentColor,
                            scrollController: _scrollController,
                            onPlay: provider.playAt,
                            onRemove: provider.removeFromPlaylist,
                            onReorder: provider.reorderPlaylist,
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final int songCount;
  final VoidCallback onAddMusic;
  final VoidCallback? onClear;
  final bool showSearch;
  final VoidCallback onToggleSearch;
  const _PlaylistHeader({
    required this.songCount,
    required this.onAddMusic,
    required this.onClear,
    required this.showSearch,
    required this.onToggleSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Playlist',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: GlassTheme.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$songCount ${songCount == 1 ? 'song' : 'songs'}',
              style: const TextStyle(
                color: GlassTheme.textTertiary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (songCount > 3)
          GlassIconButton(
            icon: Icons.search_rounded,
            onPressed: onToggleSearch,
            isActive: showSearch,
            tooltip: 'Search',
            size: 40,
            iconSize: 18,
          ),
        const SizedBox(width: 8),
        if (onClear != null)
          GlassIconButton(
            icon: Icons.clear_all_rounded,
            onPressed: onClear!,
            tooltip: 'Clear All',
            size: 40,
            iconSize: 18,
          ),
        const SizedBox(width: 8),
        _AddMusicButton(onPressed: onAddMusic),
      ],
    );
  }
}

class _AddMusicButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _AddMusicButton({required this.onPressed});

  @override
  State<_AddMusicButton> createState() => _AddMusicButtonState();
}

class _AddMusicButtonState extends State<_AddMusicButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final accent = provider.accentColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withOpacity(_isHovered ? 0.9 : 0.8),
                accent.withOpacity(_isHovered ? 0.7 : 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(_isHovered ? 0.4 : 0.2),
                blurRadius: _isHovered ? 16 : 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                'Add',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(
          color: GlassTheme.textPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Search songs...',
          hintStyle: TextStyle(
            color: GlassTheme.textTertiary,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: GlassTheme.textTertiary,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2);
  }
}

class _PlaylistContent extends StatelessWidget {
  final List<Song> playlist;
  final List<Song> allPlaylist;
  final int currentIndex;
  final bool isPlaying;
  final Color accentColor;
  final ScrollController scrollController;
  final Function(int) onPlay;
  final Function(int) onRemove;
  final Function(int, int) onReorder;
  const _PlaylistContent({
    required this.playlist,
    required this.allPlaylist,
    required this.currentIndex,
    required this.isPlaying,
    required this.accentColor,
    required this.scrollController,
    required this.onPlay,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      scrollController: scrollController,
      itemCount: playlist.length,
      onReorder: (oldIndex, newIndex) {
        final oldActualIndex = allPlaylist.indexOf(playlist[oldIndex]);
        final newActualIndex = oldIndex < newIndex
            ? allPlaylist.indexOf(playlist[newIndex - 1])
            : allPlaylist.indexOf(playlist[newIndex]);
        onReorder(oldActualIndex, newActualIndex + (oldIndex < newIndex ? 1 : 0));
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Material(
              color: Colors.transparent,
              child: Transform.scale(
                scale: 1.02,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final song = playlist[index];
        final actualIndex = allPlaylist.indexOf(song);
        final isCurrentSong = actualIndex == currentIndex;
        return _PlaylistItem(
          key: ValueKey(song.id),
          index: index,
          song: song,
          isPlaying: isCurrentSong && isPlaying,
          isSelected: isCurrentSong,
          accentColor: song.accentColor,
          coverArt: song.coverArt,
          onTap: () => onPlay(actualIndex),
          onDelete: () => onRemove(actualIndex),
        );
      },
    );
  }
}

class _PlaylistItem extends StatefulWidget {
  final int index;
  final Song song;
  final bool isPlaying;
  final bool isSelected;
  final Color accentColor;
  final Uint8List? coverArt;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PlaylistItem({
    super.key,
    required this.index,
    required this.song,
    required this.isPlaying,
    required this.isSelected,
    required this.accentColor,
    this.coverArt,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_PlaylistItem> createState() => _PlaylistItemState();
}

class _PlaylistItemState extends State<_PlaylistItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.isSelected
                ? LinearGradient(
                    colors: [
                      widget.accentColor.withOpacity(0.2),
                      widget.accentColor.withOpacity(0.08),
                    ],
                  )
                : null,
            color: !widget.isSelected
                ? (_isHovered ? Colors.white.withOpacity(0.06) : Colors.transparent)
                : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected
                  ? widget.accentColor.withOpacity(0.35)
                  : (_isHovered ? Colors.white.withOpacity(0.12) : Colors.transparent),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              _SongThumbnail(
                isPlaying: widget.isPlaying,
                isSelected: widget.isSelected,
                accentColor: widget.accentColor,
                colorIndex: widget.song.colorIndex,
                coverArt: widget.coverArt,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.song.title,
                      style: TextStyle(
                        color: widget.isSelected ? widget.accentColor : GlassTheme.textPrimary,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.song.artist,
                      style: TextStyle(
                        color: widget.isSelected ? widget.accentColor.withOpacity(0.7) : GlassTheme.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _isHovered ? 1.0 : 0.0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: GlassTheme.textTertiary,
                      ),
                      onPressed: widget.onDelete,
                      splashRadius: 18,
                      tooltip: 'Remove',
                    ),
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        size: 20,
                        color: GlassTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: (30 * widget.index).ms).fadeIn(duration: 300.ms).slideX(
      begin: 0.05,
      duration: 300.ms,
      curve: Curves.easeOut,
    );
  }
}

class _SongThumbnail extends StatefulWidget {
  final bool isPlaying;
  final bool isSelected;
  final Color accentColor;
  final int colorIndex;
  final Uint8List? coverArt;
  const _SongThumbnail({
    required this.isPlaying,
    required this.isSelected,
    required this.accentColor,
    required this.colorIndex,
    this.coverArt,
  });

  @override
  State<_SongThumbnail> createState() => _SongThumbnailState();
}

class _SongThumbnailState extends State<_SongThumbnail> with TickerProviderStateMixin {
  late List<AnimationController> _barControllers;

  @override
  void initState() {
    super.initState();
    _barControllers = List.generate(
      4,
      (index) => AnimationController(
        duration: Duration(milliseconds: 300 + (index * 80)),
        vsync: this,
      ),
    );
    if (widget.isPlaying) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant _SongThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _startAnimation();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _stopAnimation();
    }
  }

  void _startAnimation() {
    for (var controller in _barControllers) {
      controller.repeat(reverse: true);
    }
  }

  void _stopAnimation() {
    for (var controller in _barControllers) {
      controller.stop();
      controller.animateTo(0.3);
    }
  }

  @override
  void dispose() {
    for (var controller in _barControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: widget.coverArt == null 
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.accentColor.withOpacity(widget.isSelected ? 0.4 : 0.25),
                widget.accentColor.withOpacity(widget.isSelected ? 0.2 : 0.1),
              ],
            )
          : null,
        image: widget.coverArt != null 
          ? DecorationImage(
              image: MemoryImage(widget.coverArt!),
              fit: BoxFit.cover,
            )
          : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.accentColor.withOpacity(0.2),
        ),
      ),
      child: widget.coverArt == null 
        ? (widget.isPlaying
            ? _buildPlayingIndicator()
            : Icon(
                Icons.music_note_rounded,
                color: widget.isSelected ? widget.accentColor : widget.accentColor.withOpacity(0.7),
                size: 20,
              ))
        : null,
    );
  }

  Widget _buildPlayingIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        return AnimatedBuilder(
          animation: _barControllers[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 8 + (_barControllers[index].value * 14),
              decoration: BoxDecoration(
                color: widget.accentColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  final VoidCallback onAddMusic;
  const _EmptyPlaylist({required this.onAddMusic});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final accent = provider.accentColor;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        accent.withOpacity(0.15),
                        accent.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: accent.withOpacity(0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.1),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.library_music_rounded,
                    size: 52,
                    color: accent,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          const Text(
            'Your playlist is empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: GlassTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Add some music to start your journey',
            style: TextStyle(
              color: GlassTheme.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 28),
          _AddMusicButtonLarge(onPressed: onAddMusic, accent: accent),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scale(
      begin: const Offset(0.9, 0.9),
      duration: 500.ms,
      curve: Curves.easeOut,
    );
  }
}

class _AddMusicButtonLarge extends StatefulWidget {
  final VoidCallback onPressed;
  final Color accent;
  const _AddMusicButtonLarge({required this.onPressed, required this.accent});

  @override
  State<_AddMusicButtonLarge> createState() => _AddMusicButtonLargeState();
}

class _AddMusicButtonLargeState extends State<_AddMusicButtonLarge> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.accent.withOpacity(_isHovered ? 1.0 : 0.85),
                widget.accent.withOpacity(_isHovered ? 0.85 : 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withOpacity(_isHovered ? 0.5 : 0.3),
                blurRadius: _isHovered ? 25 : 15,
                spreadRadius: _isHovered ? 2 : 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'Add Music',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: GlassTheme.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            'No songs found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: GlassTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different search term',
            style: TextStyle(
              color: GlassTheme.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}

// ==================== VISUALIZER ====================
class AudioVisualizerWidget extends StatefulWidget {
  const AudioVisualizerWidget({super.key});

  @override
  State<AudioVisualizerWidget> createState() => _AudioVisualizerWidgetState();
}

class _AudioVisualizerWidgetState extends State<AudioVisualizerWidget> with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _bars = List.generate(48, (_) => 0.15);
  final math.Random _random = math.Random();
  double _smoothness = 0.85;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    )..addListener(_updateBars);

    final provider = context.read<PlayerProvider>();
    provider.audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (mounted) {
          setState(() {
            for (int i = 0; i < _bars.length; i++) {
              _bars[i] = 0.15;
            }
          });
        }
      }
    });
  }

  void _updateBars() {
    if (mounted) {
      setState(() {
        for (int i = 0; i < _bars.length; i++) {
          final target = 0.1 + _random.nextDouble() * 0.8;
          _bars[i] = _bars[i] * _smoothness + target * (1 - _smoothness);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    if (provider.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!provider.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: provider.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.equalizer_rounded,
                  color: provider.accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Visualizer',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: GlassTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (provider.isPlaying)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: provider.accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: provider.accentColor,
                          boxShadow: [
                            BoxShadow(
                              color: provider.accentColor.withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: provider.accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn()
                    .then()
                    .shimmer(duration: 2000.ms, color: provider.accentColor.withOpacity(0.3)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: _VisualizerPainter(
                  bars: _bars,
                  color: provider.accentColor,
                  isPlaying: provider.isPlaying,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final List<double> bars;
  final Color color;
  final bool isPlaying;

  _VisualizerPainter({
    required this.bars,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / bars.length;
    final maxHeight = size.height;

    final reflectionGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.05),
        Colors.transparent,
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, maxHeight * 0.7, size.width, maxHeight * 0.3),
      Paint()..shader = reflectionGradient.createShader(
        Rect.fromLTWH(0, maxHeight * 0.7, size.width, maxHeight * 0.3),
      ),
    );

    for (int i = 0; i < bars.length; i++) {
      final barHeight = isPlaying ? bars[i] * maxHeight * 0.7 : maxHeight * 0.05;
      final x = i * barWidth;
      final y = (maxHeight * 0.7 - barHeight) / 2 + maxHeight * 0.05;

      final barGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          color.withOpacity(0.4),
          color.withOpacity(0.9),
          Color.lerp(color, Colors.white, 0.3)!.withOpacity(0.95),
        ],
        stops: const [0.0, 0.6, 1.0],
      );
      final rect = Rect.fromLTWH(
        x + barWidth * 0.15,
        y,
        barWidth * 0.7,
        barHeight,
      );
      final paint = Paint()
        ..shader = barGradient.createShader(rect)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.35)),
        paint,
      );

      if (bars[i] > 0.5 && isPlaying) {
        final glowPaint = Paint()
          ..color = color.withOpacity(0.3 * bars[i])
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.35)),
          glowPaint,
        );
      }

      final reflectionRect = Rect.fromLTWH(
        x + barWidth * 0.15,
        maxHeight * 0.7 + 4,
        barWidth * 0.7,
        barHeight * 0.25,
      );
      final reflectionPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.0),
          ],
        ).createShader(reflectionRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(reflectionRect, Radius.circular(barWidth * 0.35)),
        reflectionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) {
    return true;
  }
}

// ==================== CUSTOM TITLE BAR ====================
class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.watch<PlayerProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accent = playerProvider.accentColor;
    
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.4),
              Colors.black.withOpacity(0.2),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(0.3),
                    accent.withOpacity(0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accent.withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.2),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                Icons.waves_rounded,
                color: accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hizha Player',
                  style: TextStyle(
                    color: GlassTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'enjoy (:',
                  style: TextStyle(
                    color: GlassTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            
            // دکمه سوییچ تم
            GlassIconButton(
              icon: themeProvider.themeMode == ThemeMode.dark 
                  ? Icons.light_mode_rounded 
                  : Icons.dark_mode_rounded,
              onPressed: () => themeProvider.toggleTheme(),
              tooltip: themeProvider.themeMode == ThemeMode.dark 
                  ? 'Switch to Transparent Theme' 
                  : 'Switch to Dark Theme',
              size: 36,
              iconSize: 18,
            ),
            const SizedBox(width: 8),
            
            if (playerProvider.currentSong != null)
              _MiniNowPlaying(
                title: playerProvider.currentSong!.title,
                isPlaying: playerProvider.isPlaying,
                accent: accent,
              ),
            const Spacer(),
            _WindowControls(),
          ],
        ),
      ),
    );
  }
}

class _MiniNowPlaying extends StatelessWidget {
  final String title;
  final bool isPlaying;
  final Color accent;
  const _MiniNowPlaying({
    required this.title,
    required this.isPlaying,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPlaying) ...[
            _MiniPlayingIndicator(color: accent),
            const SizedBox(width: 10),
          ] else
            Icon(
              Icons.music_note_rounded,
              color: GlassTheme.textTertiary,
              size: 14,
            ),
          if (!isPlaying) const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              title,
              style: TextStyle(
                color: isPlaying ? accent : GlassTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayingIndicator extends StatefulWidget {
  final Color color;
  const _MiniPlayingIndicator({required this.color});

  @override
  State<_MiniPlayingIndicator> createState() => _MiniPlayingIndicatorState();
}

class _MiniPlayingIndicatorState extends State<_MiniPlayingIndicator> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: Duration(milliseconds: 400 + (index * 100)),
        vsync: this,
      )..repeat(reverse: true),
    );
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 2.5,
              height: 6 + (_controllers[index].value * 8),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }
}

class _WindowControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: Icons.remove_rounded,
          onPressed: () => windowManager.minimize(),
          hoverColor: Colors.white.withOpacity(0.1),
        ),
        _WindowButton(
          icon: Icons.crop_square_rounded,
          iconSize: 14,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
          hoverColor: Colors.white.withOpacity(0.1),
        ),
        _WindowButton(
          icon: Icons.close_rounded,
          onPressed: () => windowManager.close(),
          hoverColor: const Color(0xFFE81123),
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final Color hoverColor;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    this.iconSize = 16,
    required this.onPressed,
    required this.hoverColor,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _hoverController;
  late Animation<double> _hoverAnimation;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _hoverAnimation = CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        _hoverController.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _hoverController.reverse();
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: _hoverAnimation,
          builder: (context, child) {
            final scale = _isHovered ? 1.1 : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 46,
                height: 52,
                decoration: BoxDecoration(
                  color: _isHovered ? widget.hoverColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  widget.icon,
                  color: _isHovered && widget.isClose
                      ? Colors.white
                      : Colors.white.withOpacity(_isHovered ? 1 : 0.7),
                  size: widget.iconSize,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== KEYBOARD SHORTCUTS ====================
class KeyboardShortcuts extends StatelessWidget {
  final Widget child;
  const KeyboardShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PlayerProvider>();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          provider.togglePlayPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () {
          provider.next();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () {
          provider.previous();
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () {
          provider.setVolume((provider.volume + 0.1).clamp(0.0, 1.0));
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () {
          provider.setVolume((provider.volume - 0.1).clamp(0.0, 1.0));
        },
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () {
          provider.toggleMute();
        },
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
          provider.pickAndAddFiles();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          provider.toggleShuffle();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          provider.cycleLoopMode();
        },
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}

// ==================== HOME SCREEN ====================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardShortcuts(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const AnimatedBackground(),
            Column(
              children: [
                const CustomTitleBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 1300) {
                        return const _WideLayout();
                      } else if (constraints.maxWidth > 950) {
                        return const _MediumLayout();
                      } else {
                        return const _CompactLayout();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: NowPlayingSection(),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 4,
            child: Column(
              children: [
                const Expanded(
                  flex: 3,
                  child: AudioVisualizerWidget(),
                ),
                const SizedBox(height: 24),
                const PlayerControlsSection(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          const Expanded(
            flex: 3,
            child: PlaylistSection(),
          ),
        ],
      ),
    );
  }
}

class _MediumLayout extends StatelessWidget {
  const _MediumLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                const Expanded(
                  flex: 4,
                  child: NowPlayingSection(),
                ),
                const SizedBox(height: 20),
                const PlayerControlsSection(),
              ],
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            flex: 4,
            child: PlaylistSection(),
          ),
        ],
      ),
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Expanded(
                  flex: 1,
                  child: _CompactNowPlaying(),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  flex: 1,
                  child: PlaylistSection(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const PlayerControlsSection(),
        ],
      ),
    );
  }
}

class _CompactNowPlaying extends StatelessWidget {
  const _CompactNowPlaying();

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final song = provider.currentSong;
        final accent = provider.accentColor;
        return GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = math.min(
                        constraints.maxWidth * 0.8,
                        constraints.maxHeight * 0.7,
                      );
                      return AlbumArt(
                        isPlaying: provider.isPlaying,
                        accentColor: accent,
                        size: size.clamp(150.0, 250.0),
                        coverArt: song?.coverArt,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                song?.title ?? 'No song playing',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: GlassTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                song?.artist ?? 'Add music to start',
                style: const TextStyle(
                  fontSize: 13,
                  color: GlassTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

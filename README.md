# 🎵 Liquid Glass Player
A stunning, modern music player built with Flutter that combines sleek glassmorphism design with powerful audio playback capabilities. Experience your music like never before with this visually immersive audio player.

<img src="https://i.postimg.cc/J0TCP148/Screenshot-2025-11-30-062129.png" alt="appscreenshot" width="600" height="300">

✨ Features

🎨 Visual Excellence

Glassmorphism UI: Beautiful frosted glass effects with dynamic acrylic backgrounds

Dynamic Color System: Automatic accent color extraction from album art

Animated Backgrounds: Fluid, responsive background animations that react to music

Smooth Animations: Elegant transitions and micro-interactions throughout the app

🎵 Audio Capabilities

High-Quality Playback: Support for various audio formats

Smart Playlist Management: Drag & drop reordering, search, and filtering

Audio Visualization: Real-time visualizer that responds to your music

Cover Art Extraction: Automatic metadata and artwork retrieval

⌨️ User Experience
Keyboard Shortcuts: Comprehensive hotkey support for power users

Responsive Design: Adapts beautifully to different screen sizes

Custom Title Bar: Platform-agnostic window controls

Haptic Feedback: Tactile responses for key interactions

🚀 Installation

Prerequisites

Flutter SDK (3.0.0 or higher)

Dart (2.17.0 or higher)

For Windows: Visual Studio with C++ support

Steps

Clone the repository:

``` bash
git clone https://github.com/your-username/liquid-glass-player.git
cd liquid-glass-player
```
Install dependencies:
``` bash
flutter pub get
```
Run the application:
``` bash
flutter run
```

------------------------------------------------------
🎮 Usage
Basic Controls
Space: Play/Pause

Ctrl + →: Next track

Ctrl + ←: Previous track

Ctrl + ↑/↓: Volume control

Ctrl + M: Mute/Unmute

Ctrl + O: Open music files

Ctrl + S: Toggle shuffle

Ctrl + R: Cycle repeat modes

Playlist Management
Drag & Drop: Reorder songs in playlist

Search: Use the search bar to filter songs

Right-click: Remove songs from playlist

Clear All: Remove all songs with one click

-----------------------------------------------
🛠️ Technical Details

Architecture

Provider Pattern: State management using Flutter's Provider

Clean Architecture: Separation of concerns with models, providers, and widgets

Reactive Programming: RxDart for streamlined audio state management

Key Packages
just_audio: Core audio playback

window_manager: Custom window controls

flutter_acrylic: Acrylic background effects

file_picker: Music file selection

flutter_animate: Advanced animations

flutter_media_metadata: Audio metadata extraction

Performance
Optimized Rendering: Efficient rebuilds with selective listening

Memory Management: Proper disposal of controllers and streams

Smooth Animations: 60fps animations even during heavy audio processing

🎨 Customization

Theme System

The app features a comprehensive theming system with:

10 curated accent colors

Dynamic color adaptation

Glass effect intensity controls

Typography scaling

Layout Modes

Wide Layout: Full-featured with visualizer (1300px+)

Medium Layout: Balanced experience (950px-1300px)

Compact Layout: Space-efficient (900px-950px)

📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

<div align="center">
  
Made with ❤️ and Flutter

Hizha Karimnezhad 

</div>

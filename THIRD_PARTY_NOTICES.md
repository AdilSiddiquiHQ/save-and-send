# Third-party notices

Save & Send is built on the work of several open-source projects. This file
records the components that are bundled in, linked by, or used to build the
application. The notices below are provided for attribution and compliance;
they do not replace the full license texts shipped by each project.

## Bundled at runtime

| Component | Version | License | Source |
| --- | --- | --- | --- |
| [youtubedl-android](https://github.com/JunkFood02/youtubedl-android) (`library`, `ffmpeg`, `common`) | 0.18.1 | GPL-3.0 | https://github.com/JunkFood02/youtubedl-android |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 2026.10.21 | Unlicense | https://github.com/yt-dlp/yt-dlp |
| [FFmpeg](https://ffmpeg.org/) (build distributed by youtubedl-android) | bundled with youtubedl-android 0.18.1 | GPL-3.0 | https://github.com/JunkFood02/youtubedl-android |
| [CPython](https://www.python.org/) (runtime distributed by youtubedl-android) | bundled with youtubedl-android 0.18.1 | PSF-2.0 | https://www.python.org/ |
| [libc++](https://libcxx.llvm.org/) (`libc++_shared.so`) | Android NDK build | Apache-2.0 with LLVM exception | https://libcxx.llvm.org/ |

The bundled yt-dlp executable is the official 2026.10.21 release
(`8cdf4fea48ecf4064387375301d7f294ebdb17c1`), stored at
`android/app/src/main/res/raw/ytdlp` and extracted on first launch. It is
unmodified apart from being stored as an Android raw resource.

## Application stack

| Component | License | Source |
| --- | --- | --- |
| [Flutter](https://flutter.dev/) and the Dart SDK | BSD-3-Clause | https://github.com/flutter/flutter |
| [video_player](https://pub.dev/packages/video_player) | BSD-3-Clause | https://pub.dev/packages/video_player |
| [lucide_icons_lite](https://pub.dev/packages/lucide_icons_lite) / [Lucide](https://lucide.dev/) | ISC | https://github.com/lucide-icons/lucide |
| [AndroidX / Jetpack](https://developer.android.com/jetpack) | Apache-2.0 | https://github.com/androidx/androidx |
| [Kotlin](https://kotlinlang.org/) | Apache-2.0 | https://github.com/JetBrains/kotlin |

## Fonts

The font files are redistributed under the SIL Open Font License 1.1. The full
license texts are included next to the fonts in `assets/fonts/`.

| Font | License | Source | License file |
| --- | --- | --- | --- |
| [Manrope](https://fonts.google.com/specimen/Manrope) | OFL-1.1 | https://github.com/sharanda/manrope | `assets/fonts/OFL-Manrope.txt` |
| [Plus Jakarta Sans](https://fonts.google.com/specimen/Plus+Jakarta+Sans) | OFL-1.1 | https://github.com/tokotype/PlusJakartaSans | `assets/fonts/OFL-PlusJakartaSans.txt` |
| [Noto Sans Arabic](https://fonts.google.com/noto/specimen/Noto+Sans+Arabic) | OFL-1.1 | https://github.com/notofonts/arabic | `assets/fonts/OFL-NotoSansArabic.txt` |

## GPL-3.0 components and source availability

Save & Send links against and redistributes GPL-3.0 components
(youtubedl-android and its FFmpeg build). Those components keep their licenses,
and a distributed APK carries the GPL-3.0 obligations for them, including the
source offer. The original application code is source-available under the
[Save & Send Personal Use License](LICENSE), which adds no restriction on the
rights the GPL grants for those components.

This repository is the corresponding source for the application code. The
third-party components are used as published upstream at the versions listed
above, without private modifications. If you redistribute a built APK, keep
this notice, the GPL license, and the source links with it, and comply with the
GPL's source-offer requirements for the bundled components. You still may not
use the project's name, icon, or package name for that copy.

## Downloaded media

Save & Send does not claim ownership of videos downloaded with the app. Videos
remain the property of their respective owners and are subject to the terms of
the platform they came from. The licenses above apply to the software, not to
downloaded content.

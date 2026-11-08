# Third-Party Notices

Remlark's own source code is licensed under the [MIT License](LICENSE). Binary
releases also contain the third-party components listed below, each under its
own license. None of them requires Remlark itself to use a different license.

## Native libraries (statically linked)

These are downloaded and built from source by `native/rdp/scripts/` and
`native/ssh_crypto/scripts/`, then statically linked into the RDP and SSH
crypto glue libraries.

| Component | Version | License | Notes |
| --- | --- | --- | --- |
| [FreeRDP](https://github.com/FreeRDP/FreeRDP) | 3.32.2 | Apache-2.0 | RDP protocol stack |
| [OpenSSL](https://www.openssl.org/) | 3.6.5 | Apache-2.0 | TLS for RDP, AES-GCM for SSH |
| [FFmpeg](https://ffmpeg.org/) | 8.1.3 | LGPL-2.1-or-later | H.264 decoder only, see below |
| [zlib](https://zlib.net/) (Windows) | 1.3.1 | zlib | |

### FFmpeg (LGPL)

FFmpeg is configured **without** `--enable-gpl` and `--enable-nonfree`, so the
build stays under the LGPL-2.1-or-later. Only the H.264 decoder, parser,
swscale and platform hardware acceleration are compiled in.

Because FFmpeg is linked statically, the LGPL requires that users can relink
Remlark against a modified FFmpeg. This is satisfied by the complete Remlark
source code and build scripts in this repository: change `FFMPEG_VERSION` or
the FFmpeg source in `native/rdp/scripts/`, run `make native-lib`, then rebuild
the application. The unmodified FFmpeg source is available at
<https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.gz>.

## Dart / Flutter packages

All packages resolved in `pubspec.lock` use permissive licenses (BSD, MIT,
Apache-2.0), except:

| Package | License | Notes |
| --- | --- | --- |
| [dbus](https://pub.dev/packages/dbus) | MPL-2.0 | Indirect dependency of `desktop_drop`, used unmodified. Source is available on pub.dev. |
| [dartssh2](https://pub.dev/packages/dartssh2) | MIT | Vendored in `third_party/dartssh2` with an AES-GCM native backend patch; original license kept in that directory. |

The Flutter engine and framework are BSD-3-Clause.

## Icons

- Operating system icons in `assets/os_icons/` come from
  [Dashboard Icons](https://github.com/homarr-labs/dashboard-icons)
  (Apache-2.0) and [Simple Icons](https://simpleicons.org/) (CC0-1.0). Sources
  are listed in `assets/os_icons/sources.json`, and the license texts sit next
  to the icons.
- Distribution and vendor logos are trademarks of their respective owners and
  are used only to identify the operating system of a host.
- Material Icons are Apache-2.0.

## Software installed at runtime

AI agent runtimes such as DeepSeek Harness (with Node.js) or Codex are not
bundled. When the user chooses to install them, the application downloads them
from their official sources, under their own licenses.

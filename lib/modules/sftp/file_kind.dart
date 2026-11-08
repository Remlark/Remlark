import 'package:flutter/foundation.dart';

import 'sftp_service.dart';

/// 文件类型分类，每一类对应 assets/file_icons/ 下同名的 SVG 图标。
/// 目录仍使用主题色文件夹图标，不在此分类中
enum FileKind {
  /// 未识别的普通文件
  generic,

  /// 指向文件的符号链接
  symlink,

  /// 纯文本与日志
  text,

  /// Markdown / reStructuredText 等标记文本
  markdown,

  /// 源代码
  code,

  /// Shell / PowerShell / 批处理脚本
  script,

  /// 网页与样式表
  web,

  /// 配置与结构化数据（JSON / YAML / TOML / XML 等）
  config,

  /// 数据库与 SQL
  database,

  /// 表格
  spreadsheet,

  /// 文字处理文档
  document,

  /// 演示文稿
  presentation,

  /// PDF
  pdf,

  /// 图片
  image,

  /// 音频
  audio,

  /// 视频
  video,

  /// 压缩包
  archive,

  /// 安装包 / 软件包
  package,

  /// 光盘与虚拟磁盘镜像
  diskImage,

  /// 可执行文件与二进制库
  executable,

  /// 密钥与证书
  key,

  /// 字体
  font;

  /// 对应的 SVG 资源路径
  String get asset => 'assets/file_icons/$name.svg';

  /// 根据文件条目判断类型：符号链接优先，其次按文件名 / 扩展名，
  /// 最后对无法识别但带执行权限的文件归为可执行文件
  static FileKind of(FileEntry f) {
    if (f.isLink) return FileKind.symlink;
    final kind = fromName(f.name);
    if (kind == FileKind.generic && _isExecutable(f.permissions)) return FileKind.executable;
    return kind;
  }

  /// 仅根据文件名判断类型（大小写不敏感）
  static FileKind fromName(String name) {
    final lower = name.toLowerCase();
    final byName = _byFileName[lower];
    if (byName != null) return byName;
    // SSH 私钥 / 公钥：id_rsa、id_ed25519.pub 等
    if (lower.startsWith('id_') && !lower.contains('.')) return FileKind.key;
    // 末尾为数字段的文件（轮转日志 app.log.2、动态库 libssl.so.3）按去掉数字段后的名称判断；
    // 去掉后仍无法识别（如 python3.11）则继续按原名处理
    final numbered = RegExp(r'^(.+)\.\d+$').firstMatch(lower);
    if (numbered != null) {
      final base = fromName(numbered.group(1)!);
      if (base != FileKind.generic) return base;
    }
    final dot = lower.lastIndexOf('.');
    // 无扩展名或仅以点开头（如 .bashrc 已在文件名表中处理）
    if (dot <= 0 || dot == lower.length - 1) return FileKind.generic;
    return _byExtension[lower.substring(dot + 1)] ?? FileKind.generic;
  }

  /// 权限字符串（如 -rwxr-xr-x）中任意一位执行位为 x 则视为可执行
  static bool _isExecutable(String permissions) {
    if (permissions.length < 10) return false;
    return permissions[3] == 'x' || permissions[6] == 'x' || permissions[9] == 'x';
  }
}

/// 扩展名映射表，由各分类的扩展名列表展开
final Map<String, FileKind> _byExtension = {
  for (final e in fileKindExtensions.entries)
    for (final ext in e.value) ext: e.key,
};

/// 各分类包含的扩展名（不含点、小写）；同一扩展名只能出现在一个分类中，由单元测试保证
@visibleForTesting
const Map<FileKind, List<String>> fileKindExtensions = {
  FileKind.text: ['txt', 'text', 'log', 'nfo', 'diff', 'patch'],
  FileKind.markdown: ['md', 'markdown', 'mdx', 'rst', 'adoc', 'org', 'tex'],
  FileKind.code: [
    'c', 'h', 'cc', 'cpp', 'cxx', 'hpp', 'hh', 'm', 'mm', 'cs', 'java', 'kt', 'kts', 'scala', 'groovy', //
    'go', 'rs', 'swift', 'dart', 'py', 'pyw', 'rb', 'php', 'pl', 'pm', 'lua', 'r', 'jl', 'ex', 'exs', //
    'erl', 'hs', 'clj', 'elm', 'zig', 'nim', 'v', 'sv', 'vhdl', 'asm', 's', 'js', 'mjs', 'cjs', 'ts', //
    'jsx', 'tsx', 'vue', 'svelte', 'proto', 'graphql', 'gradle', 'cmake', 'mk', 'tf', 'nix',
  ],
  FileKind.script: ['sh', 'bash', 'zsh', 'fish', 'ksh', 'csh', 'ps1', 'psm1', 'bat', 'cmd', 'command', 'awk'],
  FileKind.web: ['html', 'htm', 'xhtml', 'css', 'scss', 'sass', 'less', 'wasm'],
  FileKind.config: [
    'json', 'jsonc', 'json5', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'config', 'env', 'properties', //
    'xml', 'plist', 'service', 'socket', 'timer', 'desktop', 'reg', 'lock', 'editorconfig',
  ],
  FileKind.database: ['db', 'sqlite', 'sqlite3', 'db3', 'sql', 'mdb', 'accdb', 'dump', 'rdb', 'frm', 'ibd'],
  FileKind.spreadsheet: ['csv', 'tsv', 'xls', 'xlsx', 'xlsm', 'ods', 'numbers'],
  FileKind.document: ['doc', 'docx', 'odt', 'rtf', 'pages', 'wpd', 'epub', 'mobi'],
  // key 在服务器上多为私钥，不归入 Keynote 演示文稿
  FileKind.presentation: ['ppt', 'pptx', 'odp'],
  FileKind.pdf: ['pdf'],
  FileKind.image: [
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'ico', 'icns', 'tif', 'tiff', 'heic', 'heif', 'avif', //
    'psd', 'ai', 'sketch', 'fig', 'xcf', 'raw', 'cr2', 'nef', 'dng',
  ],
  FileKind.audio: ['mp3', 'wav', 'flac', 'aac', 'ogg', 'oga', 'opus', 'm4a', 'wma', 'aiff', 'aif', 'mid', 'midi', 'ape'],
  FileKind.video: ['mp4', 'm4v', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'mpg', 'mpeg', '3gp', 'rmvb', 'vob'],
  FileKind.archive: [
    'zip', 'tar', 'gz', 'tgz', 'bz2', 'tbz', 'tbz2', 'xz', 'txz', 'zst', 'tzst', 'lz', 'lz4', 'lzma', '7z', //
    'rar', 'z', 'cab', 'arj', 'cpio',
  ],
  FileKind.package: ['deb', 'rpm', 'apk', 'aab', 'ipa', 'pkg', 'mpkg', 'msi', 'msix', 'appimage', 'snap', 'flatpak', 'jar', 'war', 'whl', 'gem', 'crate', 'nupkg', 'vsix'],
  FileKind.diskImage: ['iso', 'img', 'dmg', 'vmdk', 'vdi', 'vhd', 'vhdx', 'qcow', 'qcow2', 'ova', 'ovf'],
  FileKind.executable: ['exe', 'com', 'dll', 'so', 'dylib', 'bin', 'elf', 'o', 'obj', 'a', 'lib', 'ko', 'sys', 'app', 'class', 'pyc'],
  FileKind.key: [
    'pem', 'key', 'pub', 'crt', 'cer', 'der', 'csr', 'p12', 'pfx', 'p7b', 'jks', 'keystore', 'gpg', 'pgp', //
    'asc', 'sig', 'ppk', 'kdbx',
  ],
  FileKind.font: ['ttf', 'otf', 'ttc', 'woff', 'woff2', 'eot', 'fon', 'pfb'],
};

/// 无扩展名或惯用固定名称的文件（小写完整文件名）
const Map<String, FileKind> _byFileName = {
  'makefile': FileKind.code,
  'gnumakefile': FileKind.code,
  'dockerfile': FileKind.code,
  'containerfile': FileKind.code,
  'jenkinsfile': FileKind.code,
  'vagrantfile': FileKind.code,
  'gemfile': FileKind.code,
  'rakefile': FileKind.code,
  'cmakelists.txt': FileKind.code,
  'readme': FileKind.markdown,
  'license': FileKind.text,
  'licence': FileKind.text,
  'copying': FileKind.text,
  'changelog': FileKind.text,
  'authors': FileKind.text,
  'notice': FileKind.text,
  'todo': FileKind.text,
  '.bashrc': FileKind.script,
  '.bash_profile': FileKind.script,
  '.bash_logout': FileKind.script,
  '.profile': FileKind.script,
  '.zshrc': FileKind.script,
  '.zprofile': FileKind.script,
  '.zshenv': FileKind.script,
  '.bash_history': FileKind.text,
  '.zsh_history': FileKind.text,
  '.gitignore': FileKind.config,
  '.gitattributes': FileKind.config,
  '.gitmodules': FileKind.config,
  '.gitconfig': FileKind.config,
  '.dockerignore': FileKind.config,
  '.npmrc': FileKind.config,
  '.vimrc': FileKind.config,
  '.inputrc': FileKind.config,
  '.tmux.conf': FileKind.config,
  '.env': FileKind.config,
  'crontab': FileKind.config,
  'fstab': FileKind.config,
  'hosts': FileKind.config,
  'passwd': FileKind.config,
  'group': FileKind.config,
  'sudoers': FileKind.config,
  'config': FileKind.config,
  'authorized_keys': FileKind.key,
  'known_hosts': FileKind.key,
  'shadow': FileKind.key,
};

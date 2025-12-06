/// Maps platform IDs to their full display names
class PlatformNames {
  static const Map<String, String> _names = {
    // Nintendo
    'nes': 'NES',
    'famicom': 'Famicom',
    'fds': 'Famicom Disk System',
    'snes': 'SNES',
    'sfc': 'Super Famicom',
    'n64': 'Nintendo 64',
    'ndd': 'Nintendo 64DD',
    'gc': 'GameCube',
    'wii': 'Wii',
    'wiiu': 'Wii U',
    'switch': 'Switch',
    'gb': 'Game Boy',
    'gbc': 'Game Boy Color',
    'gba': 'Game Boy Advance',
    'vb': 'Virtual Boy',
    'nds': 'Nintendo DS',
    'ds': 'Nintendo DS',
    '3ds': 'Nintendo 3DS',
    'n3ds': 'Nintendo 3DS',
    'min': 'Pokemon Mini',

    // Sony
    'ps1': 'PlayStation',
    'psx': 'PlayStation',
    'ps2': 'PlayStation 2',
    'ps3': 'PlayStation 3',
    'ps4': 'PlayStation 4',
    'ps5': 'PlayStation 5',
    'psp': 'PSP',
    'psv': 'PS Vita',
    'vita': 'PS Vita',
    'psvita': 'PS Vita',

    // Microsoft
    'xbox': 'Xbox',
    'x360': 'Xbox 360',
    'xboxone': 'Xbox One',
    'xboxsx': 'Xbox Series X',

    // Sega
    'sms': 'Master System',
    'sg1000': 'SG-1000',
    'genesis': 'Genesis',
    'smd': 'Genesis',
    'megadrive': 'Mega Drive',
    'md': 'Mega Drive',
    'scd': 'Sega CD',
    'segacd': 'Sega CD',
    '32x': 'Sega 32X',
    'saturn': 'Saturn',
    'sat': 'Saturn',
    'dc': 'Dreamcast',
    'dreamcast': 'Dreamcast',
    'gg': 'Game Gear',
    'gamegear': 'Game Gear',

    // Atari
    '2600': 'Atari 2600',
    'a26': 'Atari 2600',
    'atari2600': 'Atari 2600',
    'a52': 'Atari 5200',
    'atari5200': 'Atari 5200',
    'a78': 'Atari 7800',
    'atari7800': 'Atari 7800',
    'jag': 'Atari Jaguar',
    'jcd': 'Atari Jaguar CD',
    'lynx': 'Atari Lynx',

    // NEC
    'pce': 'PC Engine',
    'tg16': 'TurboGrafx-16',
    'pcfx': 'PC-FX',
    'pc98': 'PC-98',
    'tgcd': 'TurboGrafx-CD',
    'sgx': 'SuperGrafx',

    // SNK
    'neogeo': 'Neo Geo',
    'ng': 'Neo Geo',
    'ngp': 'Neo Geo Pocket',
    'ngpc': 'Neo Geo Pocket Color',
    'ngcd': 'Neo Geo CD',

    // Other
    '3do': '3DO',
    'cdi': 'CD-i',
    'cv': 'ColecoVision',
    'intv': 'Intellivision',
    'msx': 'MSX',
    'msx2': 'MSX2',
    'wonderswan': 'WonderSwan',
    'ws': 'WonderSwan',
    'wsc': 'WonderSwan Color',
    'amiga': 'Amiga',
    'fmt': 'FM Towns',
    'pip': 'Pippin',
    'c64': 'Commodore 64',
    'dos': 'DOS',
    'pc': 'PC',
    'arcade': 'MAME',
    'mame': 'MAME',
    'fbneo': 'MAME',
  };

  static String getDisplayName(String platformId) {
    final lowerId = platformId.toLowerCase();
    return _names[lowerId] ?? platformId.toUpperCase();
  }

  static bool hasCustomName(String platformId) {
    return _names.containsKey(platformId.toLowerCase());
  }
}

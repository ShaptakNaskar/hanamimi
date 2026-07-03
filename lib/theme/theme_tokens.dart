/// Design tokens from DESIGN.md — the only spacing/radius/type values
/// allowed in the app. Never invent values outside these scales.
library;

abstract final class Radii {
  /// Tags, genre badges.
  static const double sm = 6;

  /// Cards, inputs, bottom sheets, mini player.
  static const double md = 12;

  /// Album art, mascot frame, featured elements.
  static const double lg = 20;

  /// Buttons, pills, nav indicator.
  static const double pill = 999;
}

abstract final class Space {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s12 = 48;
  static const double s16 = 64;
}

abstract final class Sizes {
  static const double bottomNavHeight = 60;
  static const double miniPlayerHeight = 68;
  static const double trackRowHeight = 64;
  static const double pillTabBarHeight = 40;
  static const double pillTabHeight = 32;
  static const double playButton = 56;
  static const double secondaryButton = 40;
  static const double tertiaryButton = 32;
  static const double inputHeight = 44;
  static const double genreTagHeight = 26;
  static const double trackRowArt = 48;
  static const double miniPlayerArt = 44;
  static const double minTouchTarget = 44;
}

abstract final class TypeScale {
  static const double hero = 36; // w800
  static const double screenTitle = 24; // w700
  static const double npSongTitle = 20; // w700
  static const double rowSongTitle = 15; // w600
  static const double npArtist = 15; // w400
  static const double rowArtist = 13; // w400
  static const double sectionLabel = 11; // w600, +0.08em, uppercase
  static const double body = 16; // w400, lyrics at rest
  static const double activeLyric = 18; // w600
  static const double caption = 12; // w400
  static const double timestamp = 11; // w400 mono
  static const double button = 14; // w600
}

abstract final class Anim {
  /// Minimum for any state change — nothing is instant.
  static const minTransition = Duration(milliseconds: 150);
  static const tabSlide = Duration(milliseconds: 280);
  static const themeCrossfade = Duration(milliseconds: 300);
  static const heartPulse = Duration(milliseconds: 300);
  static const sheetSpring = Duration(milliseconds: 400);
}

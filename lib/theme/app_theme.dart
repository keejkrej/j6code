import 'package:flutter/material.dart';
import '../services/ui_settings.dart';

/// Semantic color tokens mirrored 1:1 from t3code's default theme
/// (apps/web/src/index.css: `:root`, `@variant dark` and the
/// `[data-app-sidebar]` overrides). Names follow the CSS custom properties.
@immutable
class T3Colors extends ThemeExtension<T3Colors> {
  // Canvas & text
  final Color background; // --background
  final Color foreground; // --foreground
  final Color foregroundSubtle; // secondary body text (between fg and muted)
  final Color card; // --card
  final Color popover; // --popover
  final Color primary; // --primary
  final Color primaryForeground; // --primary-foreground
  final Color secondary; // --secondary
  final Color muted; // --muted
  final Color mutedForeground; // --muted-foreground (also --placeholder)
  final Color faint; // --icon-muted mixed toward the canvas
  final Color accent; // --accent (hover / active fills)
  final Color border; // --border
  final Color input; // --input

  // Status
  final Color error; // --error
  final Color errorForeground; // --error-foreground
  final Color toolErrorIcon; // --tool-error-icon
  final Color success; // --success
  final Color warning; // --warning
  final Color info; // --info
  final Color link; // --info-foreground

  // Chat
  final Color messageSurface; // --message-surface (user bubble)
  final Color codeBackground; // --code-background
  final Color composerShadow; // --shadow-composer(-dark)

  // Sidebar ([data-app-sidebar])
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarMutedForeground;
  final Color sidebarIcon; // --sidebar-icon-color
  final Color sidebarAccent; // sidebar-scoped --accent
  final Color sidebarBorder;
  final Color sidebarRowHover;
  final Color sidebarRowActive;
  final Color sidebarRowSelected;

  // Terminal
  final Color terminalBackground;
  final Color terminalForeground;
  final Color terminalCursor;
  final Color terminalSelection;

  // Scrollbar
  final Color scrollbarThumb;
  final Color scrollbarThumbHover;

  const T3Colors({
    required this.background,
    required this.foreground,
    required this.foregroundSubtle,
    required this.card,
    required this.popover,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.muted,
    required this.mutedForeground,
    required this.faint,
    required this.accent,
    required this.border,
    required this.input,
    required this.error,
    required this.errorForeground,
    required this.toolErrorIcon,
    required this.success,
    required this.warning,
    required this.info,
    required this.link,
    required this.messageSurface,
    required this.codeBackground,
    required this.composerShadow,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarMutedForeground,
    required this.sidebarIcon,
    required this.sidebarAccent,
    required this.sidebarBorder,
    required this.sidebarRowHover,
    required this.sidebarRowActive,
    required this.sidebarRowSelected,
    required this.terminalBackground,
    required this.terminalForeground,
    required this.terminalCursor,
    required this.terminalSelection,
    required this.scrollbarThumb,
    required this.scrollbarThumbHover,
  });

  /// `:root` (light) — zinc scale.
  static const light = T3Colors(
    background: Color(0xFFFCFCFC), // zinc-25  oklch(99.2% 0 0)
    foreground: Color(0xFF27272A), // zinc-800
    foregroundSubtle: Color(0xFF52525B), // zinc-600
    card: Color(0xFFFFFFFF),
    popover: Color(0xFFFFFFFF),
    primary: Color(0xFF1B4ED8), // oklch(0.488 0.217 264)
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFFAFAFA), // zinc-50
    muted: Color(0xFFFAFAFA), // zinc-50
    mutedForeground: Color(0xFF71717A), // zinc-500
    faint: Color(0xFFA1A1AA), // zinc-400
    accent: Color(0xFFF4F4F5), // zinc-100
    border: Color(0xFFE4E4E7), // zinc-200
    input: Color(0xFFD4D4D8), // zinc-300
    error: Color(0xFFEF4444), // red-500
    errorForeground: Color(0xFFB91C1C), // red-700
    toolErrorIcon: Color(0xFFEF4444),
    success: Color(0xFF10B981), // emerald-500
    warning: Color(0xFFF59E0B), // amber-500
    info: Color(0xFF3B82F6), // blue-500
    link: Color(0xFF1D4ED8), // blue-700
    messageSurface: Color(0xFFF4F4F5), // = accent
    codeBackground: Color(0xFFFEFEFE), // card 90% / background
    composerShadow: Color(0x66000000), // rgb(0 0 0 / 40%)
    sidebar: Color(0xFFFAFAFA), // zinc-50
    sidebarForeground: Color(0xFF27272A), // zinc-800
    sidebarMutedForeground: Color(0xFF71717A), // zinc-500
    sidebarIcon: Color(0xFFA8A8AD), // muted-fg 60% / sidebar
    sidebarAccent: Color(0xFFF4F4F5), // zinc-100
    sidebarBorder: Color(0xFFE4E4E7), // zinc-200
    sidebarRowHover: Color(0xFFFCFCFC), // zinc-25
    sidebarRowActive: Color(0xFFFFFFFF),
    sidebarRowSelected: Color(0xFFFFFFFF),
    terminalBackground: Color(0xFFFCFCFC),
    terminalForeground: Color(0xFF27272A),
    terminalCursor: Color(0xFF26384E), // rgb(38 56 78)
    terminalSelection: Color(0x33253F63), // rgb(37 63 99 / 20%)
    scrollbarThumb: Color(0xFFD9D9D9),
    scrollbarThumbHover: Color(0xFFBFBFBF),
  );

  /// `@variant dark` — neutral-black canvas with white-alpha separation.
  static const dark = T3Colors(
    background: Color(0xFF0A0A0A), // neutral-950
    foreground: Color(0xFFF5F5F5), // neutral-100
    foregroundSubtle: Color(0xFFD4D4D4), // neutral-300
    card: Color(0xFF111111), // background 97% / white
    popover: Color(0xFF111111),
    primary: Color(0xFF346BF1), // oklch(0.571 0.21 264)
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0x08FFFFFF), // white / 3%
    muted: Color(0x08FFFFFF), // white / 3%
    mutedForeground: Color(0xFF818181), // neutral-500 90% / white
    faint: Color(0xFF5A5A5A),
    accent: Color(0x0AFFFFFF), // white / 4%
    border: Color(0x0FFFFFFF), // white / 6%
    input: Color(0x14FFFFFF), // white / 8%
    error: Color(0xFFF15757), // red-500 90% / white
    errorForeground: Color(0xFFF87171), // red-400
    toolErrorIcon: Color(0xFFFCA5A5),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF3B82F6),
    link: Color(0xFF60A5FA), // blue-400
    messageSurface: Color(0x0AFFFFFF), // = accent
    codeBackground: Color(0xFF101010), // card 90% / background
    composerShadow: Color(0xBF000000), // rgb(0 0 0 / 75%)
    sidebar: Color(0xFF000000), // [data-app-sidebar] dark
    sidebarForeground: Color(0xFFF1F3F7),
    sidebarMutedForeground: Color(0xFFA3A3A3),
    sidebarIcon: Color(0xFF626262), // muted-fg 60% / sidebar
    sidebarAccent: Color(0xFF191A1D),
    sidebarBorder: Color(0x14FFFFFF), // white / 8%
    sidebarRowHover: Color(0x14FFFFFF), // contrast-fg 8%
    sidebarRowActive: Color(0x1CFFFFFF), // contrast-fg 11%
    sidebarRowSelected: Color(0x12FFFFFF), // contrast-fg 7%
    terminalBackground: Color(0xFF0A0A0A),
    terminalForeground: Color(0xFFF5F5F5),
    terminalCursor: Color(0xFFB4CBFF), // rgb(180 203 255)
    terminalSelection: Color(0x40B4CBFF), // / 25%
    scrollbarThumb: Color(0x14FFFFFF),
    scrollbarThumbHover: Color(0x1FFFFFFF),
  );

  @override
  T3Colors copyWith() => this;

  @override
  T3Colors lerp(ThemeExtension<T3Colors>? other, double t) {
    if (other is! T3Colors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return T3Colors(
      background: l(background, other.background),
      foreground: l(foreground, other.foreground),
      foregroundSubtle: l(foregroundSubtle, other.foregroundSubtle),
      card: l(card, other.card),
      popover: l(popover, other.popover),
      primary: l(primary, other.primary),
      primaryForeground: l(primaryForeground, other.primaryForeground),
      secondary: l(secondary, other.secondary),
      muted: l(muted, other.muted),
      mutedForeground: l(mutedForeground, other.mutedForeground),
      faint: l(faint, other.faint),
      accent: l(accent, other.accent),
      border: l(border, other.border),
      input: l(input, other.input),
      error: l(error, other.error),
      errorForeground: l(errorForeground, other.errorForeground),
      toolErrorIcon: l(toolErrorIcon, other.toolErrorIcon),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      info: l(info, other.info),
      link: l(link, other.link),
      messageSurface: l(messageSurface, other.messageSurface),
      codeBackground: l(codeBackground, other.codeBackground),
      composerShadow: l(composerShadow, other.composerShadow),
      sidebar: l(sidebar, other.sidebar),
      sidebarForeground: l(sidebarForeground, other.sidebarForeground),
      sidebarMutedForeground: l(sidebarMutedForeground, other.sidebarMutedForeground),
      sidebarIcon: l(sidebarIcon, other.sidebarIcon),
      sidebarAccent: l(sidebarAccent, other.sidebarAccent),
      sidebarBorder: l(sidebarBorder, other.sidebarBorder),
      sidebarRowHover: l(sidebarRowHover, other.sidebarRowHover),
      sidebarRowActive: l(sidebarRowActive, other.sidebarRowActive),
      sidebarRowSelected: l(sidebarRowSelected, other.sidebarRowSelected),
      terminalBackground: l(terminalBackground, other.terminalBackground),
      terminalForeground: l(terminalForeground, other.terminalForeground),
      terminalCursor: l(terminalCursor, other.terminalCursor),
      terminalSelection: l(terminalSelection, other.terminalSelection),
      scrollbarThumb: l(scrollbarThumb, other.scrollbarThumb),
      scrollbarThumbHover: l(scrollbarThumbHover, other.scrollbarThumbHover),
    );
  }
}

extension T3ColorsContext on BuildContext {
  /// Current t3code color tokens for the active brightness.
  T3Colors get t3 => Theme.of(this).extension<T3Colors>()!;
}

class AppTheme {
  static const String monoFont = 'Cascadia Mono';
  static const List<String> monoFallback = ['Consolas', 'monospace'];

  /// User-selected appearance (System / Light / Dark), persisted to
  /// ~/.j6code/ui_settings.json.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(_loadMode());

  static ThemeMode _loadMode() {
    final saved = UiSettings.get<String>('themeMode');
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  static void setMode(ThemeMode m) {
    mode.value = m;
    UiSettings.set('themeMode', m.name);
  }

  static ThemeData get lightTheme => _build(Brightness.light, T3Colors.light);
  static ThemeData get darkTheme => _build(Brightness.dark, T3Colors.dark);

  static ThemeData _build(Brightness brightness, T3Colors c) {
    final base = brightness == Brightness.dark ? ColorScheme.dark : ColorScheme.light;
    return ThemeData(
      brightness: brightness,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      primaryColor: c.primary,
      fontFamily: 'Segoe UI',
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: c.accent,
      focusColor: c.accent,
      colorScheme: base(
        primary: c.primary,
        onPrimary: c.primaryForeground,
        surface: c.card,
        onSurface: c.foreground,
        error: c.error,
        outline: c.border,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.foreground,
        selectionColor: c.primary.withAlpha(0x55),
      ),
      dividerColor: c.border,
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: TextStyle(fontSize: 12, color: c.foreground),
        decoration: BoxDecoration(
          color: c.popover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.input),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.input),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.popover),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: c.input),
          )),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) ? c.scrollbarThumbHover : c.scrollbarThumb,
        ),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}

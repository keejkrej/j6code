import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

/// Compact relative time label, e.g. "now", "43m", "7h", "1d", "3w".
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 30) return '${d.inDays ~/ 7}w';
  if (d.inDays < 365) return '${d.inDays ~/ 30}mo';
  return '${d.inDays ~/ 365}y';
}

/// Two-letter initials for a project name ("lisca" -> "LA", "j6code" -> "J6").
String projectInitials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '?';
  final words = clean.split(RegExp(r'[\s_\-\.]+')).where((w) => w.isNotEmpty).toList();
  if (words.length >= 2) {
    return (words[0][0] + words[1][0]).toUpperCase();
  }
  if (clean.length == 1) return clean.toUpperCase();
  final digit = RegExp(r'\d').firstMatch(clean.substring(1));
  if (digit != null) return (clean[0] + digit.group(0)!).toUpperCase();
  return (clean[0] + clean[clean.length - 1]).toUpperCase();
}

/// Badge hues as (dark: Tailwind 400, light: Tailwind 600) pairs.
const _avatarPalette = <(Color, Color)>[
  (Color(0xFF34D399), Color(0xFF059669)), // emerald
  (Color(0xFFA78BFA), Color(0xFF7C3AED)), // violet
  (Color(0xFF60A5FA), Color(0xFF2563EB)), // blue
  (Color(0xFFF472B6), Color(0xFFDB2777)), // pink
  (Color(0xFFFBBF24), Color(0xFFD97706)), // amber
  (Color(0xFF22D3EE), Color(0xFF0891B2)), // cyan
  (Color(0xFFFB923C), Color(0xFFEA580C)), // orange
  (Color(0xFFA3E635), Color(0xFF65A30D)), // lime
];

Color projectColor(String key, {Brightness brightness = Brightness.dark}) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final (dark, light) = _avatarPalette[h % _avatarPalette.length];
  return brightness == Brightness.dark ? dark : light;
}

/// Small rounded-square project badge with initials (as in the t3code sidebar).
class ProjectAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool muted;

  const ProjectAvatar({super.key, required this.name, this.size = 18, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final color = muted ? context.t3.faint : projectColor(name, brightness: Theme.of(context).brightness);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? context.t3.sidebarAccent : color.withAlpha(36),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Text(
        projectInitials(name),
        style: TextStyle(
          fontSize: size * 0.46,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: color,
        ),
      ),
    );
  }
}

/// Square ghost icon button with hover background and tooltip.
class GhostIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool active;
  final Color? color;

  const GhostIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 28,
    this.iconSize = 18,
    this.active = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: active ? context.t3.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        hoverColor: context.t3.accent,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: color ?? (active ? context.t3.foreground : context.t3.mutedForeground),
          ),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

/// Low-emphasis pill used under the composer and in the header.
class GhostChip extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? color;
  final String? tooltip;

  const GhostChip({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.onTap,
    this.showChevron = false,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.t3.mutedForeground;
    final chip = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: context.t3.accent,
        mouseCursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 6)],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c),
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 3),
                Icon(LucideIcons.chevronDown, size: 14, color: c),
              ],
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

/// Outlined compact button for header actions (e.g. "Open").
class OutlineButtonSmall extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;

  const OutlineButtonSmall({super.key, this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.t3.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: context.t3.input),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: context.t3.accent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: context.t3.foregroundSubtle),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.t3.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small keyboard-shortcut badge.
class KbdBadge extends StatelessWidget {
  final String keys;
  const KbdBadge(this.keys, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.t3.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        keys,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.t3.mutedForeground),
      ),
    );
  }
}

/// iOS-style list tile (Apple HIG standard).
///
/// Features:
/// - 0.5px hairline separator
/// - 44px minimum touch target
/// - Rounded icon with tinted background
/// - Primary text 17px/400
/// - Secondary text 14px/400 in muted color
/// - Chevron trailing icon
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS-style list tile.
class IosListTile extends StatelessWidget {
  const IosListTile({
    super.key,
    this.leading,
    this.leadingIcon,
    this.leadingIconColor = const Color(0xFF0066CC),
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.isSelected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget? leading;
  final IconData? leadingIcon;
  final Color leadingIconColor;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool isSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final subTextColor = isDark ? const Color(0xFFEBEBF5) : const Color(0xFF8E8E93);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0066CC).withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            if (leading != null || leadingIcon != null) ...[
              if (leading != null)
                leading!
              else
                Icon(leadingIcon, size: 22, color: leadingIconColor),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? const Color(0xFF0066CC) : textColor,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (showChevron) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: const Color(0xFFC7C7CC),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// iOS-style list tile with switch.
class IosSwitchListTile extends StatelessWidget {
  const IosSwitchListTile({
    super.key,
    this.leadingIcon,
    this.leadingIconColor = const Color(0xFF0066CC),
    this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final IconData? leadingIcon;
  final Color leadingIconColor;
  final String? title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final subTextColor = isDark ? const Color(0xFFEBEBF5) : const Color(0xFF8E8E93);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 22, color: leadingIconColor),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                      color: textColor,
                    ),
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 14,
                      color: subTextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF34C759),
          ),
        ],
      ),
    );
  }
}

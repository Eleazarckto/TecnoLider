import 'package:flutter/material.dart';
import '../services/database.dart';
import '../services/support_service.dart';
import '../models/models.dart';
import 'design_system.dart';
import 'components.dart';

/// Navigation item for the sidebar / tab bar
class NavItem {
  final String label;
  final IconData icon;
  final Widget body;
  final int? badge;
  const NavItem({
    required this.label,
    required this.icon,
    required this.body,
    this.badge,
  });
}

/// Adaptive scaffold with 3 breakpoints:
/// - Compact (< 600px): bottom navigation bar (mobile phone)
/// - Medium (600-1100px): collapsed rail sidebar (tablet)
/// - Wide (>= 1100px): full sidebar with labels (desktop)
class AppShell extends StatefulWidget {
  final String userName;
  final String userRoleLabel;
  final String userSubtitle;
  final List<NavItem> items;
  final VoidCallback onLogout;
  final Color roleColor;

  const AppShell({
    super.key,
    required this.userName,
    required this.userRoleLabel,
    required this.userSubtitle,
    required this.items,
    required this.onLogout,
    this.roleColor = DS.brandOrange,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1100) return _buildWide();
    if (width >= 600) return _buildMedium();
    return _buildCompact();
  }

  // ============ WIDE (desktop, >= 1100px) ============
  Widget _buildWide() {
    return Scaffold(
      backgroundColor: DS.surface,
      body: Row(
        children: [
          _Sidebar(
            userName: widget.userName,
            userRoleLabel: widget.userRoleLabel,
            userSubtitle: widget.userSubtitle,
            items: widget.items,
            selectedIndex: _selected,
            onSelect: (i) => setState(() => _selected = i),
            onLogout: widget.onLogout,
            roleColor: widget.roleColor,
          ),
          Expanded(
            child: Column(
              children: [
                _DesktopTopbar(title: widget.items[_selected].label),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(_selected),
                      child: widget.items[_selected].body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ MEDIUM (tablet, 600-1099px) ============
  Widget _buildMedium() {
    return Scaffold(
      backgroundColor: DS.surface,
      body: Row(
        children: [
          _RailSidebar(
            userName: widget.userName,
            userRoleLabel: widget.userRoleLabel,
            items: widget.items,
            selectedIndex: _selected,
            onSelect: (i) => setState(() => _selected = i),
            onLogout: widget.onLogout,
            roleColor: widget.roleColor,
          ),
          Expanded(
            child: Column(
              children: [
                _DesktopTopbar(title: widget.items[_selected].label),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(_selected),
                      child: widget.items[_selected].body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ COMPACT (phone, < 600px) ============
  Widget _buildCompact() {
    final hasMany = widget.items.length > 4;
    return Scaffold(
      backgroundColor: DS.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: _MobileTopbar(
          title: widget.items[_selected].label,
          userName: widget.userName,
          userRoleLabel: widget.userRoleLabel,
          onLogout: widget.onLogout,
          roleColor: widget.roleColor,
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_selected),
          child: widget.items[_selected].body,
        ),
      ),
      bottomNavigationBar: hasMany
          ? _buildScrollableBottomNav()
          : _buildFixedBottomNav(),
    );
  }

  Widget _buildFixedBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: DS.surfaceRaised,
        border: Border(top: BorderSide(color: DS.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(widget.items.length, (i) {
              return Expanded(
                child: _BottomNavItem(
                  item: widget.items[i],
                  selected: i == _selected,
                  roleColor: widget.roleColor,
                  onTap: () => setState(() => _selected = i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: DS.surfaceRaised,
        border: Border(top: BorderSide(color: DS.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              return SizedBox(
                width: 84,
                child: _BottomNavItem(
                  item: widget.items[i],
                  selected: i == _selected,
                  roleColor: widget.roleColor,
                  onTap: () => setState(() => _selected = i),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============ FULL SIDEBAR (desktop) ============
class _Sidebar extends StatelessWidget {
  final String userName;
  final String userRoleLabel;
  final String userSubtitle;
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final Color roleColor;

  const _Sidebar({
    required this.userName,
    required this.userRoleLabel,
    required this.userSubtitle,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      decoration: const BoxDecoration(
        color: DS.surfaceRaised,
        border: Border(right: BorderSide(color: DS.border, width: 1)),
      ),
      child: Column(
        children: [
          // Brand header
          Padding(
            padding: const EdgeInsets.fromLTRB(
                DS.space5, DS.space5, DS.space5, DS.space4),
            child: Row(
              children: [
                const YjLogo(size: 40),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YJ DELIVERY', style: DS.eyebrow()),
                      const SizedBox(height: 2),
                      Text(userRoleLabel,
                          style: DS.display(15, weight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DS.border),
          // Nav items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: DS.space3, vertical: DS.space3),
              itemCount: items.length,
              itemBuilder: (context, i) {
                return _NavTile(
                  item: items[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(i),
                  roleColor: roleColor,
                );
              },
            ),
          ),
          const Divider(height: 1, color: DS.border),
          // Botón de SOPORTE - prominente
          Padding(
            padding: const EdgeInsets.fromLTRB(
                DS.space3, DS.space3, DS.space3, 0),
            child: Material(
              color: DS.success,
              borderRadius: BorderRadius.circular(DS.radiusMd),
              child: InkWell(
                borderRadius: BorderRadius.circular(DS.radiusMd),
                onTap: () {
                  final user = Database.instance.currentUser;
                  if (user != null) {
                    SupportService.openSupport(
                      context: context,
                      userRole: user.role.label,
                      userName: user.name,
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(DS.space3),
                  child: Row(
                    children: const [
                      Icon(Icons.support_agent,
                          color: Colors.white, size: 20),
                      SizedBox(width: DS.space2),
                      Expanded(
                        child: Text(
                          'Soporte por WhatsApp',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // User profile footer
          Padding(
            padding: const EdgeInsets.all(DS.space3),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(DS.radiusMd),
              child: InkWell(
                borderRadius: BorderRadius.circular(DS.radiusMd),
                onTap: onLogout,
                child: Padding(
                  padding: const EdgeInsets.all(DS.space3),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(DS.radiusSm),
                        ),
                        child: Center(
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: DS.display(15,
                                color: roleColor, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: DS.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DS.ui(13, weight: FontWeight.w600)),
                            Text(userSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DS.ui(11, color: DS.inkMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.logout_outlined,
                          color: DS.inkMuted, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ COLLAPSED RAIL SIDEBAR (tablet) ============
class _RailSidebar extends StatelessWidget {
  final String userName;
  final String userRoleLabel;
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final Color roleColor;

  const _RailSidebar({
    required this.userName,
    required this.userRoleLabel,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: const BoxDecoration(
        color: DS.surfaceRaised,
        border: Border(right: BorderSide(color: DS.border, width: 1)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DS.space4),
            child: YjLogo(size: 36),
          ),
          const Divider(height: 1, color: DS.border),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: DS.space3),
              itemCount: items.length,
              itemBuilder: (context, i) {
                return _RailTile(
                  item: items[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(i),
                  roleColor: roleColor,
                );
              },
            ),
          ),
          const Divider(height: 1, color: DS.border),
          Padding(
            padding: const EdgeInsets.all(DS.space2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Soporte - prominente
                Tooltip(
                  message: 'Soporte por WhatsApp',
                  child: Material(
                    color: DS.success,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        final user = Database.instance.currentUser;
                        if (user != null) {
                          SupportService.openSupport(
                            context: context,
                            userRole: user.role.label,
                            userName: user.name,
                          );
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.support_agent,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DS.space2),
                Tooltip(
                  message: 'Cerrar sesión ($userName)',
                  child: IconButton(
                    icon: const Icon(Icons.logout_outlined, size: 18),
                    color: DS.inkMuted,
                    onPressed: onLogout,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color roleColor;

  const _RailTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? roleColor : DS.inkMuted;
    return Tooltip(
      message: item.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: DS.space2, vertical: 4),
        child: Material(
          color: selected
              ? roleColor.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DS.radiusMd),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DS.radiusMd),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  if (item.badge != null && item.badge! > 0)
                    Positioned(
                      top: 4,
                      right: 14,
                      child: Container(
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: DS.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${item.badge}',
                          textAlign: TextAlign.center,
                          style: DS.numeric(10,
                              color: Colors.white,
                              weight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============ NAV TILE (full sidebar) ============
class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color roleColor;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? roleColor : DS.inkSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? roleColor.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DS.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(DS.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: DS.space3, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 17, color: fg),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Text(
                    item.label,
                    style: DS.ui(13,
                        color: fg,
                        weight: selected
                            ? FontWeight.w600
                            : FontWeight.w500),
                  ),
                ),
                if (item.badge != null && item.badge! > 0)
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: DS.danger,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${item.badge}',
                      textAlign: TextAlign.center,
                      style: DS.numeric(10,
                          color: Colors.white, weight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ DESKTOP TOPBAR ============
class _DesktopTopbar extends StatelessWidget {
  final String title;
  const _DesktopTopbar({required this.title});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: DS.space6),
      decoration: const BoxDecoration(
        color: DS.surfaceRaised,
        border: Border(bottom: BorderSide(color: DS.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: DS.display(20, weight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  db.config.tiersEnabled
                      ? 'Configuración: Comisión por tramos · ${db.config.currency}'
                      : 'Configuración: ${db.config.commissionType == CommissionType.percentage ? "${db.config.commissionValue.toStringAsFixed(0)}%" : formatMoney(db.config.commissionValue)} para motorizado · ${db.config.currency}',
                  style: DS.ui(11, color: DS.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: DS.space3, vertical: 6),
            decoration: BoxDecoration(
              color: DS.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(DS.radiusSm),
              border: Border.all(
                  color: DS.success.withValues(alpha: 0.20), width: 1),
            ),
            child: const LiveSyncBadge(),
          ),
        ],
      ),
    );
  }
}

// ============ MOBILE TOPBAR ============
class _MobileTopbar extends StatelessWidget {
  final String title;
  final String userName;
  final String userRoleLabel;
  final VoidCallback onLogout;
  final Color roleColor;

  const _MobileTopbar({
    required this.title,
    required this.userName,
    required this.userRoleLabel,
    required this.onLogout,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DS.surfaceRaised,
        border: Border(bottom: BorderSide(color: DS.border, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: DS.space4, vertical: DS.space2),
          child: Row(
            children: [
              const YjLogo(size: 32),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: DS.display(16, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(userRoleLabel,
                        style: DS.ui(11, color: DS.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DS.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: const LiveSyncBadge(),
              ),
              const SizedBox(width: DS.space2),
              // Botón de SOPORTE - prominente
              Material(
                color: DS.success,
                borderRadius: BorderRadius.circular(DS.radiusSm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                  onTap: () {
                    final user = Database.instance.currentUser;
                    if (user != null) {
                      SupportService.openSupport(
                        context: context,
                        userRole: user.role.label,
                        userName: user.name,
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.support_agent,
                            size: 18, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Ayuda',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: DS.space1),
              IconButton(
                icon: const Icon(Icons.logout_outlined, size: 18),
                color: DS.inkMuted,
                onPressed: onLogout,
                tooltip: 'Cerrar sesión',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============ BOTTOM NAV ITEM ============
class _BottomNavItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final Color roleColor;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.item,
    required this.selected,
    required this.roleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? roleColor : DS.inkMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  if (item.badge != null && item.badge! > 0)
                    Positioned(
                      top: -4,
                      right: -10,
                      child: Container(
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: DS.danger,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: DS.surfaceRaised, width: 1.5),
                        ),
                        child: Text(
                          '${item.badge}',
                          textAlign: TextAlign.center,
                          style: DS.numeric(9,
                              color: Colors.white,
                              weight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DS.ui(10,
                    color: color,
                    weight: selected
                        ? FontWeight.w600
                        : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../state/marketplace_controller.dart';

class MarketplaceTeamSelector extends StatelessWidget {
  const MarketplaceTeamSelector({
    super.key,
    required this.controller,
    this.onOpenInvites,
    this.onOpenBilling,
    this.spacing = 8,
  });

  final MarketplaceController controller;
  final VoidCallback? onOpenInvites;
  final VoidCallback? onOpenBilling;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final hasTeams = controller.orgs.isNotEmpty;
    final activeRole = controller.activeOrgRole.toLowerCase();
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: DropdownButtonFormField<String>(
            initialValue: hasTeams ? controller.activeOrgId : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Team',
              border: OutlineInputBorder(),
            ),
            items: controller.orgs
                .map(
                  (org) => DropdownMenuItem<String>(
                    value: org.id,
                    child: Text(org.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(growable: false),
            onChanged: hasTeams
                ? (value) {
                    if (value == null) {
                      return;
                    }
                    controller.selectOrg(value);
                  }
                : null,
          ),
        ),
        Chip(label: Text('Role: $activeRole')),
        if (onOpenBilling != null)
          FilledButton.tonal(
            onPressed: onOpenBilling,
            child: const Text('Billing'),
          ),
        if (onOpenInvites != null)
          FilledButton.tonal(
            onPressed: onOpenInvites,
            child: const Text('Invites'),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../state/marketplace_controller.dart';
import 'team_selector.dart';

class MarketplaceInviteScreen extends StatefulWidget {
  const MarketplaceInviteScreen({
    super.key,
    required this.controller,
    this.initialToken,
  });

  final MarketplaceController controller;
  final String? initialToken;

  @override
  State<MarketplaceInviteScreen> createState() =>
      _MarketplaceInviteScreenState();
}

class _MarketplaceInviteScreenState extends State<MarketplaceInviteScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  String _selectedRole = 'member';
  bool _submittingInvite = false;
  bool _acceptingInvite = false;
  String? _createdToken;

  static const List<String> _roles = <String>[
    'member',
    'viewer',
    'billing',
    'admin',
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _tokenController.text = widget.initialToken?.trim() ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.loadOrgs();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _emailController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _createInvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an email address')));
      return;
    }
    setState(() {
      _submittingInvite = true;
    });
    try {
      final token = await widget.controller.createInvite(
        email: email,
        role: _selectedRole,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _createdToken = token;
      });
      if (token != null && token.isNotEmpty) {
        _tokenController.text = token;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite created')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.infoBanner ?? 'Could not create invite',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingInvite = false;
        });
      }
    }
  }

  Future<void> _acceptInvite() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an invite token')));
      return;
    }
    setState(() {
      _acceptingInvite = true;
    });
    try {
      await widget.controller.acceptInvite(token);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite accepted')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.infoBanner ?? 'Could not accept invite',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _acceptingInvite = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: <Widget>[
          Text(
            'Team Invites',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          MarketplaceTeamSelector(controller: controller),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Send invite',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (!controller.canManageOrgMembers)
                    const Text("You don't have billing permission"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailController,
                    enabled: controller.canManageOrgMembers,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: _roles
                        .map(
                          (role) => DropdownMenuItem<String>(
                            value: role,
                            child: Text(role),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: controller.canManageOrgMembers
                        ? (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedRole = value;
                            });
                          }
                        : null,
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed:
                        controller.canManageOrgMembers && !_submittingInvite
                        ? _createInvite
                        : null,
                    child: _submittingInvite
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send invite'),
                  ),
                  if (_createdToken != null && _createdToken!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SelectableText('Invite token: $_createdToken'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Accept invite',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Invite token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: _acceptingInvite ? null : _acceptInvite,
                    child: _acceptingInvite
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept invite'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

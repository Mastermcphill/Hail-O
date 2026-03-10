import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const <Widget>[
            PremiumSectionHeader(
              eyebrow: 'Internal operations',
              title: 'Hidden administrative workspace.',
              description:
                  'This route remains intentionally separate from the public product. The internal UI can be expanded further without surfacing admin affordances to normal users.',
            ),
            SizedBox(height: HailoSpacing.lg),
            PremiumPanel(
              child: PremiumListItem(
                title: 'Admin access preserved',
                subtitle:
                    'Public landing, login, and signup surfaces no longer expose any admin route or action.',
                leadingIcon: Icons.lock_outline_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

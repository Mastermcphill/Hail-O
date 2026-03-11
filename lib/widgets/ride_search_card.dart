import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../features/rideshare/models/ride_search_draft.dart';
import '../theme/app_tokens.dart';
import 'premium_ui.dart';
import 'seat_class_chip.dart';

class RideSearchCard extends StatefulWidget {
  const RideSearchCard({
    super.key,
    this.initialDraft,
    required this.onSubmit,
    this.primaryLabel = 'Search rides',
    this.caption,
    this.showCharterMode = false,
  });

  final RideSearchDraft? initialDraft;
  final ValueChanged<RideSearchDraft> onSubmit;
  final String primaryLabel;
  final String? caption;
  final bool showCharterMode;

  @override
  State<RideSearchCard> createState() => _RideSearchCardState();
}

class _RideSearchCardState extends State<RideSearchCard> {
  late final TextEditingController _pickupController;
  late final TextEditingController _destinationController;
  late final TextEditingController _luggageController;

  late DateTime _departureAt;
  late int _passengerCount;
  late RideTravelMode _travelMode;
  late RideSeatTier _seatTier;
  late bool _charterMode;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft ?? RideSearchDraft.initial();
    _pickupController = TextEditingController(text: draft.pickup);
    _destinationController = TextEditingController(text: draft.destination);
    _luggageController = TextEditingController(
      text: draft.luggageCount.toString(),
    );
    _departureAt = draft.departureAt;
    _passengerCount = draft.passengerCount;
    _travelMode = draft.travelMode;
    _seatTier = draft.seatTier;
    _charterMode = draft.charterMode;
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _luggageController.dispose();
    super.dispose();
  }

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final initialDate = _departureAt.isBefore(now) ? now : _departureAt;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (selectedDate == null || !mounted) {
      return;
    }
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureAt.toLocal()),
    );
    if (selectedTime == null || !mounted) {
      return;
    }
    setState(() {
      _departureAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      ).toUtc();
    });
  }

  RideSearchDraft _buildDraft() {
    return RideSearchDraft(
      pickup: _pickupController.text.trim(),
      destination: _destinationController.text.trim(),
      departureAt: _departureAt,
      passengerCount: _passengerCount,
      travelMode: _travelMode,
      seatTier: _seatTier,
      luggageCount: int.tryParse(_luggageController.text.trim()) ?? 0,
      charterMode: _charterMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDeparture = DateFormat(
      'EEE, MMM d • h:mm a',
    ).format(_departureAt.toLocal());

    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.caption != null) ...<Widget>[
            Text(
              widget.caption!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: HailoSpacing.sm),
          ],
          TextFormField(
            controller: _pickupController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Pickup location',
              prefixIcon: Icon(Icons.my_location_rounded),
            ),
          ),
          const SizedBox(height: HailoSpacing.md),
          TextFormField(
            controller: _destinationController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Destination',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: HailoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  borderRadius: HailoRadii.sm,
                  onTap: _pickDeparture,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Departure time',
                      prefixIcon: Icon(Icons.schedule_rounded),
                    ),
                    child: Text(formattedDeparture),
                  ),
                ),
              ),
              const SizedBox(width: HailoSpacing.md),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Passengers',
                    prefixIcon: Icon(Icons.people_outline_rounded),
                  ),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: _passengerCount > 1
                            ? () => setState(() => _passengerCount--)
                            : null,
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      Expanded(
                        child: Text(
                          '$_passengerCount',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: _passengerCount < 8
                            ? () => setState(() => _passengerCount++)
                            : null,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HailoSpacing.md),
          TextFormField(
            controller: _luggageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Luggage pieces',
              prefixIcon: Icon(Icons.luggage_rounded),
            ),
          ),
          const SizedBox(height: HailoSpacing.lg),
          Text(
            'Seat tier',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: HailoSpacing.sm),
          Wrap(
            spacing: HailoSpacing.sm,
            runSpacing: HailoSpacing.sm,
            children: <Widget>[
              for (final tier in RideSeatTier.values)
                SizedBox(
                  width: 156,
                  child: SeatClassChip(
                    label: _labelForSeatTier(tier),
                    description: _descriptionForSeatTier(tier),
                    selected: _seatTier == tier,
                    onTap: () => setState(() => _seatTier = tier),
                  ),
                ),
            ],
          ),
          const SizedBox(height: HailoSpacing.lg),
          Text(
            'Ride type',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: HailoSpacing.sm),
          Wrap(
            spacing: HailoSpacing.sm,
            runSpacing: HailoSpacing.sm,
            children: <Widget>[
              for (final mode in RideTravelMode.values)
                ChoiceChip(
                  label: Text(_labelForTravelMode(mode)),
                  selected: _travelMode == mode,
                  onSelected: (_) => setState(() => _travelMode = mode),
                ),
            ],
          ),
          if (widget.showCharterMode) ...<Widget>[
            const SizedBox(height: HailoSpacing.md),
            SwitchListTile.adaptive(
              value: _charterMode,
              onChanged: (value) => setState(() => _charterMode = value),
              contentPadding: EdgeInsets.zero,
              title: const Text('Charter or full-vehicle booking'),
              subtitle: const Text(
                'Best for private premium vans, fleet coaches, and executive travel.',
              ),
            ),
          ],
          const SizedBox(height: HailoSpacing.lg),
          FilledButton.icon(
            onPressed: () => widget.onSubmit(_buildDraft()),
            icon: const Icon(Icons.search_rounded),
            label: Text(widget.primaryLabel),
          ),
        ],
      ),
    );
  }
}

String _labelForSeatTier(RideSeatTier tier) {
  switch (tier) {
    case RideSeatTier.standard:
      return 'Standard';
    case RideSeatTier.comfort:
      return 'Comfort';
    case RideSeatTier.premium:
      return 'Premium';
    case RideSeatTier.executive:
      return 'Executive';
  }
}

String _descriptionForSeatTier(RideSeatTier tier) {
  switch (tier) {
    case RideSeatTier.standard:
      return 'Everyday rides';
    case RideSeatTier.comfort:
      return 'More room';
    case RideSeatTier.premium:
      return 'Priority comfort';
    case RideSeatTier.executive:
      return 'Top-tier cabin';
  }
}

String _labelForTravelMode(RideTravelMode mode) {
  switch (mode) {
    case RideTravelMode.city:
      return 'City rides';
    case RideTravelMode.interCity:
      return 'Inter-city';
    case RideTravelMode.interState:
      return 'Inter-state';
    case RideTravelMode.crossBorder:
      return 'Cross-border';
  }
}

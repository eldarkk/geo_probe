import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../models.dart';

/// Map screen: user-defined regions (long-press to create), today's track,
/// event markers, one-shot locate and continuous foreground tracking.
class MapScreen extends StatefulWidget {
  final AppState state;
  const MapScreen({super.key, required this.state});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentFix;
  double? _currentFixAccuracy;
  // Live radius preview while the creation dialog is open.
  LatLng? _draftPoint;
  double _draftRadius = 150;
  List<GeoEvent> _todayEvents = [];
  int _loadedRevision = -1;
  bool _movedToInitialPosition = false;

  // Astana as a neutral fallback until the first fix arrives.
  static const _fallbackCenter = LatLng(51.169392, 71.449074);

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _reloadEvents();
    _locate(moveCamera: !_movedToInitialPosition);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (widget.state.eventsRevision != _loadedRevision) {
      _reloadEvents();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reloadEvents() async {
    _loadedRevision = widget.state.eventsRevision;
    final events = await widget.state.db.eventsForDay(DateTime.now(), types: {
      EventType.enter,
      EventType.exit,
      EventType.slc,
    });
    if (!mounted) return;
    setState(() => _todayEvents = events);
  }

  Future<void> _locate({bool moveCamera = true}) async {
    final fix = await widget.state.bridge.getCurrentLocation();
    if (fix == null || !mounted) return;
    final point =
        LatLng((fix['lat'] as num).toDouble(), (fix['lng'] as num).toDouble());
    setState(() {
      _currentFix = point;
      _currentFixAccuracy = (fix['accuracy'] as num?)?.toDouble();
    });
    if (moveCamera) {
      _movedToInitialPosition = true;
      _mapController.move(point, 16);
    }
  }

  Future<void> _onLongPress(TapPosition tapPosition, LatLng point) async {
    final state = widget.state;
    final t = AppLocalizations.of(context)!;
    if (state.activeRegionCount >= 20) {
      _snack(t.regionLimitWarning);
      return;
    }
    setState(() {
      _draftPoint = point;
      _draftRadius = 150;
    });
    final result = await showDialog<(String, double)>(
      context: context,
      builder: (context) => _RegionDialog(
        initialName: t.regionDefaultName(state.regions.length + 1),
        onRadiusChanged: (r) => setState(() => _draftRadius = r),
      ),
    );
    setState(() => _draftPoint = null);
    if (result == null) return;
    await state.addRegion(
      name: result.$1,
      lat: point.latitude,
      lng: point.longitude,
      radius: result.$2,
    );
  }

  Future<void> _onRegionTap(Region region) async {
    final state = widget.state;
    final t = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(region.name),
              subtitle: Text(
                  '${region.lat.toStringAsFixed(6)}, ${region.lng.toStringAsFixed(6)} · r=${t.radiusValue(region.radius.round())}'),
            ),
            ListTile(
              leading: Icon(region.active ? Icons.pause_circle : Icons.play_circle),
              title: Text(region.active ? t.deactivate : t.activate),
              onTap: () => Navigator.pop(context, 'toggle'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(t.delete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'toggle') {
      await state.updateRegion(region.copyWith(active: !region.active));
    } else if (action == 'delete') {
      await state.deleteRegion(region.id);
    }
  }

  void _showZonesList() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final t = AppLocalizations.of(context)!;
        // Rebuilds on AppState changes so toggles/deletes reflect instantly.
        return ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) {
            final regions = widget.state.regions;
            if (regions.isEmpty) {
              return SizedBox(
                height: 160,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(t.noZonesYet, textAlign: TextAlign.center),
                  ),
                ),
              );
            }
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(t.zonesTitle,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in regions)
                          ListTile(
                            leading: Icon(Icons.location_on,
                                color: r.active ? Colors.indigo : Colors.grey),
                            title: Text(r.name),
                            subtitle: Text(
                                '${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)} · ${t.radiusValue(r.radius.round())}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: r.active,
                                  onChanged: (v) => widget.state
                                      .updateRegion(r.copyWith(active: v)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () =>
                                      widget.state.deleteRegion(r.id),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _mapController.move(LatLng(r.lat, r.lng), 16);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Color _eventColor(String type) {
    switch (type) {
      case EventType.enter:
        return Colors.green;
      case EventType.exit:
        return Colors.red;
      case EventType.slc:
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final trackPoints = _todayEvents
        .where((e) => e.lat != null && e.lng != null)
        .map((e) => LatLng(e.lat!, e.lng!))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('geo_probe'),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.zonesTitle,
            icon: const Icon(Icons.format_list_bulleted),
            onPressed: _showZonesList,
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _fallbackCenter,
          initialZoom: 13,
          onLongPress: _onLongPress,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.clockster.geo_probe',
          ),
          CircleLayer(
            circles: [
              for (final r in state.regions)
                CircleMarker(
                  point: LatLng(r.lat, r.lng),
                  radius: r.radius,
                  useRadiusInMeter: true,
                  color: (r.active ? Colors.indigo : Colors.grey)
                      .withValues(alpha: 0.28),
                  borderColor: (r.active ? Colors.indigo : Colors.grey)
                      .withValues(alpha: 0.9),
                  borderStrokeWidth: 3,
                ),
              if (_draftPoint != null)
                CircleMarker(
                  point: _draftPoint!,
                  radius: _draftRadius,
                  useRadiusInMeter: true,
                  color: Colors.green.withValues(alpha: 0.25),
                  borderColor: Colors.green,
                  borderStrokeWidth: 3,
                ),
              if (_currentFix != null && _currentFixAccuracy != null)
                CircleMarker(
                  point: _currentFix!,
                  radius: _currentFixAccuracy!,
                  useRadiusInMeter: true,
                  color: Colors.lightBlue.withValues(alpha: 0.2),
                  borderColor: Colors.lightBlue,
                  borderStrokeWidth: 1,
                ),
            ],
          ),
          if (trackPoints.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: trackPoints,
                  strokeWidth: 3,
                  color: Colors.deepPurple.withValues(alpha: 0.7),
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              // Region name pins (tappable).
              for (final r in state.regions)
                Marker(
                  point: LatLng(r.lat, r.lng),
                  width: 120,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => _onRegionTap(r),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on,
                            color: r.active ? Colors.indigo : Colors.grey),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(r.name,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
              // Geofence / SLC event dots.
              for (final e in _todayEvents)
                if (e.lat != null && e.lng != null)
                  Marker(
                    point: LatLng(e.lat!, e.lng!),
                    width: 14,
                    height: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _eventColor(e.type),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              if (_currentFix != null)
                Marker(
                  point: _currentFix!,
                  width: 18,
                  height: 18,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.lightBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
            ],
          ),
          const SimpleAttributionWidget(
            source: Text('© OpenStreetMap contributors'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _locate(),
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

class _RegionDialog extends StatefulWidget {
  final String initialName;
  final ValueChanged<double>? onRadiusChanged;
  const _RegionDialog({required this.initialName, this.onRadiusChanged});

  @override
  State<_RegionDialog> createState() => _RegionDialogState();
}

class _RegionDialogState extends State<_RegionDialog> {
  late final TextEditingController _nameController;
  double _radius = 150;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(t.newRegionTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No autofocus: summoning the keyboard together with the dialog
          // hangs debug sessions on physical iOS devices under the VSCode
          // debugger (flutter/flutter#123021).
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: t.regionNameLabel),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(t.radiusLabel(_radius.round())),
            ],
          ),
          Slider(
            value: _radius,
            min: 100,
            max: 500,
            divisions: 40,
            label: t.radiusValue(_radius.round()),
            onChanged: (v) {
              setState(() => _radius = v);
              widget.onRadiusChanged?.call(v);
            },
          ),
          Text(
            t.radiusHint,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (_nameController.text.trim(), _radius)),
          child: Text(t.create),
        ),
      ],
    );
  }
}

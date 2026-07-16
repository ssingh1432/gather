import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Result of the map picker: a human-readable label plus the coordinates,
/// so a post can show both "📍 Kathmandu, Nepal" in the feed and (later)
/// an actual pin on a map.
class PickedLocation {
  const PickedLocation({required this.label, required this.lat, required this.lng});
  final String label;
  final double lat;
  final double lng;
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial});
  final PickedLocation? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Default to Kathmandu so the map has something sensible to show before
  // the person picks a point or grants location permission.
  static const _defaultCenter = LatLng(27.7172, 85.3240);

  GoogleMapController? _mapController;
  LatLng _selected = _defaultCenter;
  String? _label;
  bool _resolvingLabel = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _selected = LatLng(widget.initial!.lat, widget.initial!.lng);
      _label = widget.initial!.label;
    }
  }

  Future<void> _resolveLabel(LatLng point) async {
    setState(() => _resolvingLabel = true);
    try {
      final placemarks = await placemarkFromCoordinates(point.latitude, point.longitude);
      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.locality, p.administrativeArea, p.country].where((s) => s != null && s.isNotEmpty).toList();
        setState(() => _label = parts.isNotEmpty ? parts.join(', ') : '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}');
      } else {
        setState(() => _label = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}');
      }
    } catch (_) {
      if (mounted) setState(() => _label = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}');
    } finally {
      if (mounted) setState(() => _resolvingLabel = false);
    }
  }

  void _onTapMap(LatLng point) {
    setState(() => _selected = point);
    _resolveLabel(point);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied. You can still tap the map to pick a spot.')),
          );
        }
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Turn on location services to use your current position.')),
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _selected = point);
      _mapController?.animateCamera(CameraUpdate.newLatLng(point));
      await _resolveLabel(point);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get your location: $e')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a location'),
        actions: [
          TextButton(
            onPressed: _label == null
                ? null
                : () => Navigator.pop(
                      context,
                      PickedLocation(label: _label!, lat: _selected.latitude, lng: _selected.longitude),
                    ),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _selected, zoom: 12),
            onMapCreated: (c) => _mapController = c,
            onTap: _onTapMap,
            markers: {Marker(markerId: const MarkerId('picked'), position: _selected)},
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingActionButton(
              onPressed: _locating ? null : _useCurrentLocation,
              child: _locating
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _resolvingLabel ? 'Finding address...' : (_label ?? 'Tap the map or use your location'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

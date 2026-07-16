import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

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
  bool _searching = false;
  String? _lastApiError;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _selected = LatLng(widget.initial!.lat, widget.initial!.lng);
      _label = widget.initial!.label;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _mapsApiKey = 'AIzaSyAEiXDNwVSa_gtvUML_TWeUFMoOiAiZWWo';

  /// Extracts a short "locality, admin area, country" label from a
  /// Geocoding API result, falling back to its full formatted_address.
  String _shortLabel(Map<String, dynamic> result) {
    final components = (result['address_components'] as List).cast<Map<String, dynamic>>();
    String? find(String type) =>
        components.firstWhere((c) => (c['types'] as List).contains(type), orElse: () => const {})['long_name'] as String?;
    final locality = find('locality') ?? find('administrative_area_level_2');
    final admin = find('administrative_area_level_1');
    final country = find('country');
    final parts = [locality, admin, country].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(', ') : result['formatted_address'] as String? ?? '';
  }

  Future<void> _resolveLabel(LatLng point) async {
    setState(() {
      _resolvingLabel = true;
      _lastApiError = null;
    });
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${point.latitude},${point.longitude}&key=$_mapsApiKey',
      );
      final res = await http.get(uri);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String?;
      final results = body['results'] as List?;
      if (status == 'OK' && results != null && results.isNotEmpty) {
        if (mounted) setState(() => _label = _shortLabel(results.first as Map<String, dynamic>));
      } else {
        // Surface the real reason (e.g. REQUEST_DENIED means the API key
        // isn't allowed to call the Geocoding API yet) instead of
        // silently falling back to raw coordinates.
        if (mounted) {
          setState(() {
            _lastApiError = '${status ?? 'unknown error'}${body['error_message'] != null ? ': ${body['error_message']}' : ''}';
            _label = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastApiError = 'Request failed: $e';
          _label = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
        });
      }
    } finally {
      if (mounted) setState(() => _resolvingLabel = false);
    }
  }

  Future<void> _searchPlace(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _lastApiError = null;
    });
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(query.trim())}&key=$_mapsApiKey',
      );
      final res = await http.get(uri);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String?;
      final results = body['results'] as List?;
      if (status == 'OK' && results != null && results.isNotEmpty) {
        final first = results.first as Map<String, dynamic>;
        final loc = (first['geometry'] as Map)['location'] as Map;
        final point = LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
        setState(() {
          _selected = point;
          _label = _shortLabel(first);
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 13));
      } else {
        if (mounted) {
          setState(() => _lastApiError = '${status ?? 'unknown error'}${body['error_message'] != null ? ': ${body['error_message']}' : ''}');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No results for "$query".')));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastApiError = 'Request failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
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
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: _searchPlace,
                decoration: InputDecoration(
                  hintText: 'Search for a place',
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: () => _searchPlace(_searchController.text),
                        ),
                ),
              ),
            ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _resolvingLabel ? 'Finding address...' : (_label ?? 'Tap the map, search, or use your location'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_lastApiError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _lastApiError!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11),
                      ),
                    ],
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

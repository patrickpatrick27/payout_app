import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Clipboard
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAP Box Locator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  
  // Data State
  List<dynamic> _allLcps = [];
  List<dynamic> _searchResults = []; 
  List<Marker> _markers = [];
  dynamic _selectedLcp;

  // Initial Center (Tagaytay)
  final LatLng _initialCenter = const LatLng(14.1153, 120.9621);
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final String response = await rootBundle.loadString('assets/lcp_data.json');
      final List<dynamic> data = json.decode(response);
      setState(() {
        _allLcps = data;
        _resetToOverview(); 
      });
    } catch (e) {
      debugPrint("Error loading data: $e");
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Migrated': return Colors.green;
      case 'Pending': return Colors.red;
      case 'Partially Migrated': return Colors.orange;
      default: return Colors.grey;
    }
  }

  // --- 1. OVERVIEW MODE ---
  void _resetToOverview() {
    _generateOverviewMarkers(_allLcps);
    setState(() {
      _selectedLcp = null;
      _searchResults.clear();
      _isSearching = false;
    });
  }

  void _generateOverviewMarkers(List<dynamic> lcps) {
    List<Marker> markers = [];
    for (var lcp in lcps) {
      if (lcp['nps'] != null && lcp['nps'].isNotEmpty) {
        var firstNp = lcp['nps'][0];
        markers.add(
          Marker(
            point: LatLng(firstNp['lat'], firstNp['lng']),
            width: 45,
            height: 45,
            child: GestureDetector(
              onTap: () => _focusOnLcp(lcp), 
              child: Icon(
                Icons.location_on, 
                color: _getStatusColor(lcp['status']), 
                size: 45
              ),
            ),
          ),
        );
      }
    }
    setState(() => _markers = markers);
  }

  // --- 2. FOCUS MODE (LCP Selected) ---
  void _focusOnLcp(dynamic lcp) {
    FocusScope.of(context).unfocus(); 
    setState(() {
      _isSearching = false;
      _selectedLcp = lcp;
    });

    List<Marker> npMarkers = [];
    List<LatLng> pointsForBounds = [];

    for (var np in lcp['nps']) {
      double lat = np['lat'];
      double lng = np['lng'];
      LatLng pos = LatLng(lat, lng);
      pointsForBounds.add(pos);

      npMarkers.add(
        Marker(
          point: pos,
          width: 80, 
          height: 60,
          child: GestureDetector(
            onTap: () => _showNpDetailsBottomSheet(lcp, np),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    np['name'],
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  Icons.radio_button_checked,
                  color: _getStatusColor(lcp['status']), 
                  size: 30
                ),
              ],
            ),
          ),
        ),
      );
    }

    setState(() => _markers = npMarkers);

    if (pointsForBounds.isNotEmpty) {
       double minLat = pointsForBounds.first.latitude;
       double maxLat = pointsForBounds.first.latitude;
       double minLng = pointsForBounds.first.longitude;
       double maxLng = pointsForBounds.first.longitude;

       for (var p in pointsForBounds) {
         if (p.latitude < minLat) minLat = p.latitude;
         if (p.latitude > maxLat) maxLat = p.latitude;
         if (p.longitude < minLng) minLng = p.longitude;
         if (p.longitude > maxLng) maxLng = p.longitude;
       }
       
       _mapController.fitCamera(
         CameraFit.bounds(
           bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
           padding: const EdgeInsets.all(80), 
         ),
       );
    }
    
    _showLcpListBottomSheet(lcp);
  }

  // --- 3. BOTTOM SHEETS ---

  // A. General List
  void _showLcpListBottomSheet(dynamic lcp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.2,
          maxChildSize: 0.6,
          builder: (context, scrollController) {
            return _buildSheetContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHandle(),
                  const SizedBox(height: 15),
                  Text(lcp['lcp_name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(lcp['site_name'], style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 10),
                  Chip(
                    label: Text(lcp['status'], style: const TextStyle(color: Colors.white)),
                    backgroundColor: _getStatusColor(lcp['status']),
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text("All Network Points:", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: lcp['nps'].length,
                      itemBuilder: (context, index) {
                        var np = lcp['nps'][index];
                        return ListTile(
                          leading: const Icon(Icons.location_on, size: 20),
                          title: Text(np['name']),
                          subtitle: Text("${np['lat']}, ${np['lng']}"),
                          dense: true,
                          onTap: () {
                             Navigator.pop(context); 
                             _showNpDetailsBottomSheet(lcp, np); 
                          },
                        );
                      },
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

  // B. NP Details (With Copy Button)
  void _showNpDetailsBottomSheet(dynamic lcp, dynamic np) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: SafeArea( 
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHandle(),
                const SizedBox(height: 15),
                
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue[50], 
                                borderRadius: BorderRadius.circular(8)
                              ),
                              child: Icon(Icons.radio_button_checked, color: _getStatusColor(lcp['status']), size: 30),
                            ),
                            const SizedBox(width: 15),
                            Expanded( 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(np['name'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                  Text("Part of ${lcp['lcp_name']}", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildInfoRow(Icons.place, "Location", lcp['site_name']),
                        const SizedBox(height: 10),
                        // ENABLE COPYING HERE
                        _buildInfoRow(
                          Icons.map, 
                          "Coordinates", 
                          "${np['lat']}, ${np['lng']}",
                          isCopyable: true
                        ),
                        const SizedBox(height: 10),
                        _buildInfoRow(Icons.info_outline, "Status", lcp['status']),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                       Navigator.pop(context); 
                       _showLcpListBottomSheet(lcp); 
                    },
                    icon: const Icon(Icons.list),
                    label: const Text("View All Points in this LCP"),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetContainer({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(width: 40, height: 4, 
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
    );
  }

  // --- UPDATED UI HELPER WITH COPY BUTTON ---
  Widget _buildInfoRow(IconData icon, String label, String value, {bool isCopyable = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        if (isCopyable)
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: Colors.blueGrey),
            tooltip: "Copy Coordinates",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(), // Removes default padding
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Coordinates copied to clipboard!"),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
      ],
    );
  }

  // --- 4. SEARCH & UI ---
  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      _resetToOverview();
      return;
    }
    setState(() => _isSearching = true);

    final filtered = _allLcps.where((lcp) {
      final name = lcp['lcp_name'].toString().toLowerCase();
      final site = lcp['site_name'].toString().toLowerCase();
      return name.contains(query.toLowerCase()) || site.contains(query.toLowerCase());
    }).toList();

    setState(() => _searchResults = filtered);
    _generateOverviewMarkers(filtered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 13.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onTap: (_, __) {
                 if (_isSearching) setState(() => _isSearching = false);
                 FocusScope.of(context).unfocus();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.davepatrick.napboxlocator',
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          Positioned(
            top: 50, left: 15, right: 15,
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search NAP Box...",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.clear), 
                            onPressed: () {
                              _searchController.clear();
                              _resetToOverview();
                              _mapController.move(_initialCenter, 13.0);
                            },
                          ) 
                        : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(15),
                    ),
                    onChanged: _onSearchChanged,
                    onTap: () {
                       if (_searchController.text.isNotEmpty) setState(() => _isSearching = true);
                    },
                  ),
                ),
                if (_isSearching && _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    height: 250, 
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black26)],
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        var lcp = _searchResults[index];
                        return ListTile(
                          title: Text(lcp['lcp_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(lcp['site_name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                          leading: Icon(Icons.location_on, color: _getStatusColor(lcp['status'])),
                          onTap: () => _focusOnLcp(lcp),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          
          if (_selectedLcp != null && !_isSearching)
            Positioned(
              bottom: 20, right: 20,
              child: FloatingActionButton.extended(
                onPressed: () {
                   _resetToOverview();
                   _mapController.move(_initialCenter, 13.0);
                },
                label: const Text("Reset Map"),
                icon: const Icon(Icons.map),
              ),
            ),
        ],
      ),
    );
  }
}
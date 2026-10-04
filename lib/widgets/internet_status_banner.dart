import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/network_status_service.dart';

class InternetStatusBanner extends StatelessWidget {
  const InternetStatusBanner({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<NetworkStatusService>().isOnline;

    return Column(
      children: [
        if (!isOnline)
          Material(
            color: Colors.red.shade700,
            elevation: 4,
            child: SafeArea(
              bottom: false,
              child: const SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'No internet connection. Live SoilSense data is unavailable.',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: isOnline
              ? child
              : MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                ),
        ),
      ],
    );
  }
}

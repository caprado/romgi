import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/providers.dart';

class InternetArchiveLoginScreen extends ConsumerStatefulWidget {
  const InternetArchiveLoginScreen({super.key});

  @override
  ConsumerState<InternetArchiveLoginScreen> createState() =>
      _InternetArchiveLoginScreenState();
}

class _InternetArchiveLoginScreenState
    extends ConsumerState<InternetArchiveLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentUrl = '';

  static const String _loginUrl = 'https://archive.org/account/login';
  static const String _accountUrl = 'https://archive.org/account/';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });

            // Check if we've reached the account page (successful login)
            if (url.startsWith(_accountUrl) || url == 'https://archive.org/') {
              await _extractAndSaveCookies();
            }
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
  }

  Future<void> _extractAndSaveCookies() async {
    try {
      // Get cookies using JavaScript - document.cookie returns all cookies
      final cookieResult = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );

      // Parse the cookie string (format: "name1=value1; name2=value2")
      final cookieMap = <String, String>{};
      final rawString = cookieResult.toString();
      // Remove quotes if present (JS returns quoted string)
      final cleanString = rawString.startsWith('"') && rawString.endsWith('"')
          ? rawString.substring(1, rawString.length - 1)
          : rawString;

      for (final pair in cleanString.split('; ')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          final name = pair.substring(0, idx);
          final value = pair.substring(idx + 1);
          cookieMap[name] = value;
        }
      }

      // Check if we have the logged-in cookies
      if (cookieMap.containsKey('logged-in-user') &&
          cookieMap['logged-in-user']!.isNotEmpty) {
        final authService = ref.read(internetArchiveAuthProvider);
        await authService.saveCookies(cookieMap);

        // Refresh the auth state
        ref.invalidate(iaLoggedInProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logged in as ${cookieMap['logged-in-user']}'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true); // Return success
        }
      }
    } catch (error) {
      debugPrint('Error extracting cookies: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Internet Archive Login'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Column(
        children: [
          // URL bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.lock,
                  size: 16,
                  color: _currentUrl.startsWith('https')
                      ? Colors.green
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUrl,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // WebView
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

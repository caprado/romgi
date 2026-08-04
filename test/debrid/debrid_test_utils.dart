import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StubAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function(RequestOptions)> routes;
  final List<RequestOptions> calls = [];

  StubAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final handler =
        routes[options.uri.path] ?? routes[options.path] ?? routes['*'];
    if (handler == null) return ResponseBody.fromString('not stubbed', 500);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(String body, [int code = 200]) => ResponseBody.fromString(
      body,
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

ResponseBody textBody(String body, [int code = 200]) => ResponseBody.fromString(
      body,
      code,
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );

Dio stubbedDio(String baseUrl, Map<String, ResponseBody Function(RequestOptions)> routes) {
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    validateStatus: (code) => code != null && code < 500,
  ))
    ..httpClientAdapter = StubAdapter(routes);
}

class InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> store;

  InMemorySecureStorage(this.store) : super();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }
}

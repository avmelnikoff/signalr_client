import 'dart:io';

abstract class AbstractCookieManager {
  // Sets the cookies for specified [url].
  Future<void> setCookies(String url, List<Cookie> cookies);

  /// Gets the cookies for specified [url].
  Future<List<Cookie>> getCookies(String url);

  /// Merge cookies into a Cookie string.
  /// Cookies with longer paths are listed before cookies with shorter paths.
  Future<String?> getCookieHeader(
    String url, [
    String? defaultCookieHeader,
  ]) async {
    final cookies = await getCookies(url);

    cookies.addAll(defaultCookieHeader
            ?.split(';')
            .where((e) => e.isNotEmpty)
            .map((c) => Cookie.fromSetCookieValue(c)) ??
        []);

    // Sort cookies by path (longer path first).
    cookies.sort((a, b) {
      if (a.path == null && b.path == null) {
        return 0;
      } else if (a.path == null) {
        return -1;
      } else if (b.path == null) {
        return 1;
      } else {
        return b.path!.length.compareTo(a.path!.length);
      }
    });

    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }
}

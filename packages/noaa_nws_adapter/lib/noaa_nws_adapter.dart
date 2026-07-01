/// NOAA / National Weather Service direct-consume wrapper.
///
/// Smallest-slice client for `api.weather.gov`. One endpoint
/// (`GET /alerts/active?point={lat},{lon}`); winter alert focus
/// (the 14 winter event types catalogued by `api.weather.gov/alerts/types`).
///
/// API base: `https://api.weather.gov` — National Weather Service public API.
/// Spec: `https://www.weather.gov/documentation/services-web-api`.
///
/// Auth: a `User-Agent` header is required identifying the calling
/// application and a contact path, e.g.
/// `(myappname.com, contact@email.com)`. No API key, no registration.
///
/// Rate limit: not publicly documented. The service notes a generous
/// allowance for typical use and a 5-second retry-after on 429.
///
/// License: U.S. Federal public-domain — the API documentation states
/// the data is "open data, free to use for any purpose." Attribution is
/// not required by the publisher; the User-Agent header is used by the
/// publisher only for rate-limit accounting and security contact.
///
/// Three exported types:
/// - [WinterAlert]: Equatable model of a CAP-class alert relevant to
///   winter driving (event, severity, certainty, urgency, area, effective,
///   expires, headline, description, instruction, status, messageType,
///   senderName).
/// - [NoaaNwsClient]: thin HTTP client around `/alerts/active?point=`.
/// - [NoaaNwsParseException]: thrown on GeoJSON schema-shape mismatch.
///
/// An SNGNav adapter package, published to pub.dev.
///
/// ```dart
/// import 'package:noaa_nws_adapter/noaa_nws_adapter.dart';
///
/// final client = NoaaNwsClient(
///   userAgent: '(sngnav.example, contact@sngnav.example)',
/// );
/// final alerts = await client.fetchActiveWinterAlerts(
///   latitude: 47.9253,
///   longitude: -97.0329,
/// );
/// for (final a in alerts) {
///   print('${a.event}: ${a.headline}');
/// }
/// ```
library;

export 'src/winter_alert.dart'
    show
        WinterAlert,
        WinterAlertArea,
        WinterAlertCircle,
        GeoPoint,
        NoaaNwsParseException,
        AlertSeverity,
        AlertCertainty,
        AlertUrgency,
        AlertMessageType,
        AlertStatus,
        kNwsWinterEventTypes;
export 'src/noaa_nws_client.dart'
    show
        NoaaNwsClient,
        NoaaNwsHttpException,
        NoaaNwsRetryPolicy,
        isWithinNwsCoverage;

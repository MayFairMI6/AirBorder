# Privacy and Security

## Data inventory

The app may process linked flight details, airport location/route progress, accessibility preferences, notification choices, and cached transit/terminal data. Camera processing is local by default. If the user separately enables Cloud Assist and approves a low-confidence still, one cropped/re-encoded image can be sent through the application proxy for scene OCR; continuous frames are never uploaded. No account or analytics SDK is included.

## Permission strategy

- Camera permission is requested only when AR/marker guidance starts.
- Location permission is requested in context and defaults to When In Use.
- Notification permission is requested after a journey is linked and the benefit is explained.
- The map, manual calibration, cached flight, and transit features remain available when permissions are denied.
- Cloud Assist is a distinct default-off consent. Failed images are not queued for later upload, and cloud results are advisory.

## API credentials

- Commercial provider keys are server-side secrets in the backend proxy.
- `Config/Secrets.xcconfig` and backend local secret files are ignored by Git.
- `Secrets.xcconfig.example` contains placeholders only.
- Swift source, Info.plist, app resources, crash logs, and request logs contain no provider keys.
- Proxy logs redact authorization, query details beyond operational need, and provider payloads.

## Network controls

- Production endpoints require HTTPS; arbitrary loads are not enabled.
- The client validates URL construction and accepted status/content type/size.
- Authentication and rate-limit failures are typed and do not trigger unbounded retry.
- Backend input is allow-listed, rate-limited, bounded by date range, and protected against open-proxy behavior.
- Provider responses are normalized server-side and never rendered as HTML.

## Local protection and retention

- Caches use iOS Application Support with complete-until-first-authentication file protection where available.
- Only normalized active-journey fields are retained; raw provider payloads are not stored.
- Users can clear journey and cache data from Settings.
- Completed journeys can be automatically pruned after a documented retention window.
- Accessibility preferences remain local unless the user explicitly enables future sync.

## Model-training controls

- On-device personalization is default-deny for provider payloads. A provider response must match a bundled policy ID, policy version, and exact permitted training purpose before a resolved outcome is forwarded to the learner.
- The current commercial-provider policies permit no training. Permission is enabled only after an operator documents the applicable license; a provider response cannot grant itself permission.
- Eligible flight observations are reduced to aggregate delay residuals. The model stores a deterministic one-way deduplication ID rather than the raw provider record or payload.
- User-owned measurements and explicit feedback are handled separately and remain erasable through Settings.
- Entry and visa requirements have no supported training purpose. Learned preferences can rank equally safe plans but cannot weaken the deterministic safety floor or authorize a city visit.

## Privacy-safe diagnostics

Logs use event categories and redacted identifiers. They exclude full flight queries, precise coordinates, accessibility values, credentials, notification contents, and provider payloads. Debug demo-state flags are not enabled in production builds.

## Threat summary

| Threat | Mitigation |
|---|---|
| Extract provider key from app | key exists only in proxy secret store |
| Abuse proxy as open endpoint | strict routes, validation, quotas, origin/app attestation extension point |
| Mislead user with stale status | source timestamps, stale banner, explicit manual refresh |
| Unsafe route due to outage | closure/elevator state in graph, uncertainty notice, manual fallback |
| Sensitive travel data leakage | minimal cache, file protection, clear-data control, redacted logging |
| Camera/location overcollection | in-context permissions, local processing, no background location |
| Notification disclosure | concise configurable content and system privacy settings |

## Review checklist

- Verify no secret-like string in tracked files or built product.
- Verify ATS remains enabled and proxy URL is HTTPS outside localhost development.
- Test permission denial and revocation for camera, location, and notifications.
- Test cache deletion and retention pruning.
- Review provider license before production caching/display.
- Run static search for unsafe logging and forced URL unwraps.
- Validate App Privacy details and a user-facing privacy policy before distribution.

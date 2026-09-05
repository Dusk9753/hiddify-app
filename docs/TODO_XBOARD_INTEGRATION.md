# XBoard Integration TODO

## Goal

Allow a user to sign in to an XBoard V1 user API from Hiddify, retrieve the user's existing subscription URL, and add it as a standard remote Hiddify profile.

The integration must use the existing XBoard subscription endpoint and the existing Hiddify remote-profile pipeline. It must not implement a second subscription parser or expose XBoard credentials, API bearer tokens, or subscription tokens in UI, analytics, logs, exports, or crash reports.

## Verified Current Contract

The local XBoard backend currently exposes the following user-authenticated API routes:

- `POST /api/v1/passport/auth/login`: authenticate a user. Confirm the exact request and response schema against the deployed backend before implementation.
- `GET /api/v1/user/getSubscribe`: retrieve the authenticated user's subscription data.
- `POST /api/v1/user/changePassword` and `POST /api/v1/user/profile/update`: remain out of scope for the first client integration.

`GET /api/v1/user/getSubscribe` returns user subscription metadata including `subscribe_url`. XBoard generates that URL server-side from the user's subscription token. Hiddify must retain only the returned subscription URL as a normal remote profile after import; it must not derive or reconstruct a subscription URL from account fields.

Hiddify already imports a remote URL through:

- `lib/features/profile/add/add_profile_modal.dart`
- `lib/features/profile/notifier/profile_notifier.dart`
- `lib/features/profile/data/profile_repository.dart`
- `lib/features/profile/data/profile_parser.dart`

That pipeline downloads the profile, reads supported subscription headers, validates the generated configuration, persists the remote profile, and supports later refreshes. Reuse it unchanged.

## Scope Decisions

- Add a dedicated XBoard sign-in/import flow beside the manual remote-profile form.
- Support HTTPS XBoard panel URLs only in the UI. Keep existing generic HTTP manual import behavior unchanged.
- Accept an XBoard panel base URL, email, and password; do not add admin API support.
- Store any short-lived XBoard user API session using the platform secure-storage abstraction only if it is needed to refresh the subscription URL later.
- The first release may discard the XBoard API session immediately after successful import. In that version, regular profile refreshes continue using the saved subscription URL and an expired/revoked subscription is handled by the existing profile-refresh error path.
- Do not add a global default panel URL, hard-coded brand domain, or credentials in source, build configuration, fixtures, tests, screenshots, or documentation.

## Implementation Tasks

### 1. Confirm the deployed XBoard authentication contract

- Read the deployed `Passport/AuthController` and route registration before writing Dart API code.
- Record the login path, request fields, successful response envelope, token location, expiry behavior, and error envelope in this document or a dedicated API adapter comment.
- Confirm the user middleware's accepted authentication header format.
- Verify that a valid user session can call `GET /api/v1/user/getSubscribe` and that its `data.subscribe_url` is an HTTPS URL.
- Verify that the endpoint returns no sensitive fields that need to be persisted by Hiddify.

Acceptance: a redacted HTTP fixture documents login success, rejected credentials, expired session, and a successful `getSubscribe` payload.

### 2. Add an isolated XBoard API client

- Create `lib/features/xboard/data/xboard_api_client.dart` and keep XBoard response-envelope parsing there.
- Add typed request/result models under `lib/features/xboard/model/`; never pass untyped JSON beyond the client boundary.
- Construct URLs with `Uri`, normalize a user-supplied base URL once, and reject non-HTTPS URLs in this flow.
- Send credentials only to the normalized configured origin. Disable redirects that cross origins, or reject cross-origin redirects before forwarding credentials or authorization headers.
- Make the client return domain failures for invalid panel URL, authentication failure, missing `subscribe_url`, malformed subscription URL, and transport failure.
- Redact `Authorization`, passwords, bearer tokens, cookies, `subscribe_url`, and query strings from diagnostic logging.

Acceptance: unit tests cover URL normalization, API-envelope parsing, missing data, 401/403, malformed URLs, and redirect rejection without real credentials.

### 3. Build the XBoard import coordinator

- Create `lib/features/xboard/application/xboard_import_service.dart` (or follow the repository's existing Riverpod service naming pattern after implementation begins).
- Authenticate, call `getSubscribe`, validate `data.subscribe_url`, and hand that URL to `ProfileRepository.upsertRemote`.
- Pass a user-selected profile name using `UserOverride`; never use account email, token, UUID, or raw subscription URL as the default visible profile name.
- Ensure duplicate imports update the existing remote profile via the repository's URL de-duplication behavior rather than creating duplicates.
- Clear in-memory credentials and session values in `finally` blocks. Do not insert a profile when any prior step fails.

Acceptance: coordinator tests prove one successful import invokes `upsertRemote`, failures do not invoke it, and logged exceptions are redacted.

### 4. Add the XBoard user interface

- Add an XBoard option to `lib/features/profile/add/` using the existing add-profile modal navigation and component conventions.
- The form requires panel URL, email, password, and a display name. Use password-field obscuring and proper keyboard/autofill hints where platform support exists.
- Use a single explicit import command with loading and cancellation state. Do not show account tokens, subscription URLs, or raw backend error strings.
- On success, close the modal through the existing add-profile success behavior. On error, show a localized, actionable generic message.
- Add only the required Chinese and existing supported-localization keys using the repository translation workflow. Do not hard-code UI text in Dart.

Acceptance: widget tests cover validation, disabled import during submission, successful close, and redacted friendly errors.

### 5. Decide session persistence before implementing refresh-from-XBoard

- Default first-release behavior: do not persist XBoard API credentials or bearer tokens. Existing remote-profile refresh uses the imported subscription URL.
- If product requirements require re-fetching `subscribe_url` after an XBoard reset-security action, add a separate follow-up task for a secure token store and explicit user consent.
- The secure-store design must define per-platform storage, session expiry, logout/revoke behavior, migration, and recovery if the stored token becomes invalid.
- Never store passwords. Never store the XBoard session in Drift, SharedPreferences, profile JSON export, clipboard, logs, or URL fragments.

Acceptance: the implementation PR explicitly states either "no XBoard session persisted" or includes secure-storage tests and a platform review.

### 6. End-to-end verification against a disposable XBoard account

- Use a non-production XBoard account and an HTTPS staging panel.
- Import a valid subscription, verify it becomes a remote profile, and verify the imported profile can be refreshed with the normal Hiddify flow.
- Test invalid password, unavailable panel, expired XBoard session during import, an account with no usable subscription, and a revoked subscription URL.
- Inspect application logs and exported configuration to confirm no password, bearer token, subscription token, or full subscription URL appears.
- Run the project's formatter, analyzer, focused unit/widget tests, and the platform build targets available in CI.

Acceptance: CI passes and the test record contains only redacted URLs and fixtures.

## Explicit Non-Goals

- XBoard admin login, administration, billing, orders, tickets, or user-profile editing.
- Changing XBoard subscription generation, server selection, traffic accounting, or node protocols.
- Embedding an XBoard webview or sharing browser cookies with the app.
- Replacing Hiddify's existing remote-profile parser, validator, storage, or refresh implementation.
- Exposing upstream panel information in customer-facing UI.

## Security Checklist

- [ ] Credentials are sent only over HTTPS to the exact normalized panel origin.
- [ ] Passwords are never persisted, logged, exported, copied to the clipboard, or included in exceptions.
- [ ] Bearer tokens and subscription URLs are redacted from every log/error/reporting path.
- [ ] `subscribe_url` is obtained only from authenticated XBoard API output and is not synthesized client-side.
- [ ] Imported profile refresh uses existing Hiddify profile handling and reports failures without leaking upstream responses.
- [ ] Automated tests use placeholder hosts and fake tokens only.

## Implementation Order

1. Confirm deployed XBoard login and user-middleware details.
2. Write failing API-client tests and implement the typed API client.
3. Write failing coordinator tests and connect it to `ProfileRepository.upsertRemote`.
4. Add localized UI and widget tests.
5. Run static checks and the focused test suite.
6. Run the disposable-account integration test and review redacted logs/exports.
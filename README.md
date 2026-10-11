# Custom Mattermost Team Edition

A minimally patched Mattermost Team Edition for internal + partner use:
standards-compliant **OIDC single sign-on** (Google, Entra ID, or an identity
broker in front of both), **restricted guest accounts**, **calls with group
calls, recording and transcription**, and no free-tier nag — with the stock
Mattermost interface untouched.

Built from pinned upstream source (`upstream.env`, currently `v11.11.1`
server + calls `v1.12.3`); only the patches in `patches/` are applied. No
Enterprise code, no licence checks touched.

## Patches

| Patch | What | Why |
|---|---|---|
| `0001-generic-oidc-provider` | Standards-compliant OIDC provider (from [Mattermore](https://github.com/dennisklappe/mattermore)) | Team Edition ships no Google/Entra/OpenID provider at all |
| `0002-oidc-login-buttons` | Exposes the OIDC button + text/color to the login page | Otherwise the provider has no visible button |
| `0004/0005-guest-accounts` | Lifts the guest-accounts gate, incl. admin screens | Partner channels with restricted guests |
| `0006-remove-licence-badges` | Removes the “Free Version” label + unsupported-version notice | Cosmetic; display strings only |
| `0007-prepackaged-signature-optional` | Allows installing our unsigned calls bundle | Required to ship our own plugin build |
| `0013-ignore-superseded-plugins` | Server ignores the stale official calls bundle in the base image | Our bundle replaces it without a removal fight |
| `0014-openid-button-adaptive-icon` | Login/signup SSO button shows Google’s “G”, Entra’s mark, or the generic OpenID mark depending on the configured discovery endpoint | One provider serves one IdP at a time; the icon follows it |
| `calls/0001-0009` | Calls plugin: group calls + video, recording, transcription, on-by-default | Partner voice/video; see Calls below |

Deliberately **not** ported: fork branding + branded assets (we ship upstream
artwork), user-limit lift, channel moderation, agents defaults,
empty-category hiding. Unlimited message history needs no patch: an unlicensed
server returns no history limit.

## Calls, recording, transcription

The image ships our calls plugin build (`patches/calls/`, `CALLS_VERSION` in
`upstream.env`): group calls in every channel, call recording to file storage,
and transcription. Recording posts land in the channel; transcription
delivery through an external transcriber worker is a separate deployment step
(tracked as follow-up work, not part of this image).

## Build & release

Every push/PR runs `build.yml`: patches apply to the pinned tag, the Go
server compiles, and a full image is built and smoke-tested (`scripts/e2e.sh`).

```bash
./scripts/build-image.sh custom-mm:dev   # local build (needs go, node 20, docker)
```

Cut a release by pushing a tag:

```bash
git tag v11.11.1-1 && git push origin tag v11.11.1-1
```

`release.yml` publishes `ghcr.io/duartemvix/mattermost-team-custom:<tag>`
(plus `:latest`). Production only ever pulls a finished image.

## Configure

All runtime behaviour is environment, exactly like upstream:

```
MM_SQLSETTINGS_DATASOURCE=postgres://...            # your database
MM_SERVICESETTINGS_SITEURL=https://chat.example.com
MM_EMAILSETTINGS_ENABLESIGNUPWITHEMAIL=false        # SSO-only lockdown
MM_EMAILSETTINGS_ENABLESIGNINWITHEMAIL=false
MM_EMAILSETTINGS_ENABLESIGNINWITHUSERNAME=false
MM_OPENIDSETTINGS_ENABLE=true
MM_OPENIDSETTINGS_DISCOVERYENDPOINT=https://accounts.google.com/.well-known/openid-configuration
MM_OPENIDSETTINGS_ID=<client id>
MM_OPENIDSETTINGS_SECRET=<client secret>
MM_OPENIDSETTINGS_BUTTONTEXT="Continue with Google"
```

Callback: `<site-url>/signup/openid/complete`. For Google + Entra at the same
time, point the discovery endpoint at an identity broker (Authentik/Keycloak)
instead — the button then falls back to the neutral OpenID mark.

## Trademark & licence

Upstream code is © Mattermost, Inc. and contributors, used under AGPL-3.0
(`LICENSE`). “Mattermost” is their trademark; this build ships their artwork
unmodified. Review [Mattermost’s trademark policy](https://mattermost.com/trademark-standards-of-use/)
before publicly redistributing images carrying official branding.

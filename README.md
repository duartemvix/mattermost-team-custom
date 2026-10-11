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
| `0014-openid-button-google-icon` | Login/signup SSO button renders Google’s “G” instead of the generic OpenID mark | Deployment authenticates against Google; matches the plan’s required button |
| `0015-office365-button-without-license` / `0016-matching-sso-button-style` / `0017-google-button-first` | Adds and styles the Microsoft button and orders Google first | Dual-provider SSO on Team Edition |
| `0018-oauth-invitation-only-signup` | Enforces Open Server for OAuth signup: email-bound one-time invitations, verified email matching, and correct Guest provisioning | Stop uninvited OAuth identities bypassing `EnableOpenServer=false` |
| `0019-show-guest-invites-on-team-edition` | Removes the `BuildEnterpriseReady` UI gate from guest invitation controls | Expose the already-enabled guest invite flow in Team Edition |
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
MM_TEAMSETTINGS_ENABLEOPENSERVER=false              # OAuth signup requires a specific invite
MM_TEAMSETTINGS_ENABLEUSERCREATION=true             # required for invited first-time OAuth users
MM_OPENIDSETTINGS_ENABLE=true
MM_OPENIDSETTINGS_DISCOVERYENDPOINT=https://accounts.google.com/.well-known/openid-configuration
MM_OPENIDSETTINGS_ID=<client id>
MM_OPENIDSETTINGS_SECRET=<client secret>
MM_OPENIDSETTINGS_BUTTONTEXT="Continue with Google"
```

Callback: `<site-url>/signup/openid/complete`. For Google + Entra at the same
time, point the discovery endpoint at an identity broker (Authentik/Keycloak)
instead — the button then falls back to the neutral OpenID mark.

When Open Server is disabled, this fork only provisions a new OAuth identity
from an unused, unexpired, email-bound team or guest invitation. A reusable
team invite ID is not sufficient. The invitation token is single-use and
email-bound; the authenticated OAuth email must match it. Providers that assert
`email_verified=false` are rejected, while providers omitting that optional
claim rely on the invitation email as proof of mailbox access. Guest invitations
create Guest accounts and apply their invited channel scope. Existing OAuth users can still sign in. Keep
`EnableUserCreation` enabled to allow invited new users; setting it false is an
emergency blanket block that also prevents invited first-time sign-ins.

To invite a Guest, use the team’s **Invite People** dialog, choose **Guest** in
the **Invite as** selector, and select the channels they may access. With
`EnableGuestMagicLink=true`, the optional “Allow invited guests to log in with
a magic link” checkbox sends a passwordless, one-time link to the invited email.
The Guest account is created when that invitation is redeemed; selecting
Member instead creates a regular team member.

## Trademark & licence

Upstream code is © Mattermost, Inc. and contributors, used under AGPL-3.0
(`LICENSE`). “Mattermost” is their trademark; this build ships their artwork
unmodified. Review [Mattermost’s trademark policy](https://mattermost.com/trademark-standards-of-use/)
before publicly redistributing images carrying official branding.

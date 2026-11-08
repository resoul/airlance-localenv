# Airlance

A messenger for iOS with its own backend. This repository runs the whole thing from one place: `make setup` clones the three
projects below next to this file, and `make up` starts the services in the right order.

| Project | What it does | Where it runs |
| --- | --- | --- |
| [`Airlance`](https://github.com/resoul/Airlance) | The iOS app: chats, channels, stories, calls, a camera and media, several accounts on one device. Written in Swift, built with Bazel | iPhone |
| [`auth`](https://github.com/resoul/auth) | Passwordless sign-in: an emailed code and a passkey, signed tokens, OpenID Connect. Written in Go | `auth.airlance.org` |
| [`airlance-server`](https://github.com/resoul/airlance-server) | The messenger's server: checks tokens from `auth` and talks to the app over an encrypted WebSocket. It serves profiles, direct chats, groups and channels, attachments, stories, contacts, privacy, links, scheduled messages, agents, folders, pinned and muted chats. Written in Go | `api.airlance.org` |

What the server does not hold yet (calls, the On Air tab, most of what a message can carry beyond text and files) stays empty. For test data run `make seed`: it fills the server with people, groups, channels and one sample of every message kind.

## Links

Add the tunnel route `link.airlance.org` -> `http://airlance-server:8080`. The page there offers to open the app. Links go straight to the app only with a paid Apple account: see `docs/server/operations.md`.

## Delete everything and start again

```sh
make reset
```

Asks for confirmation, then deletes the data of both stacks: accounts, passkeys, chats, files and the search index. It brings everything back up, registers the clients again and creates the test people, groups and channels (`make seed`). Settings and secrets stay: `auth/.secrets`, `airlance-server/deploy/.env` and the tunnel token, so tokens signed before the reset still pass until they expire.

Then delete the app from the phone so nothing of the old account is left, install it with `make ios`, sign up and join the test chats:

```sh
make seed TO=@your_username
```

The old passkey stays in the phone's password list and no longer works. Delete it in Settings, Passwords, `auth.airlance.org`.

## From scratch

```sh
make setup
```

Put the Cloudflare tunnel token into `auth/.secrets/production/cloudflared.env`, then:

```sh
make up
make register
```

## Signing in on a phone

1. With no account the app shows the welcome screen. Continue opens the `auth.airlance.org` page in the system window (private
   mode, PKCE, a token for `messenger-api`).
2. On the page: email, the emailed code, then creating or confirming a passkey. A new person saves 10 recovery codes.
3. The app verifies the ID token, keeps the tokens in Keychain per account, and asks for the profile over the WebSocket
   `wss://api.airlance.org/v1/ws`. No profile means the name screen; a profile means straight to the chats.
4. The profile refreshes from the server when an account opens and when the app returns. If the token cannot be refreshed, the
   Session ended screen appears. Sign out revokes the token and erases the account's data on the device.

The passkey is made on the page, not in the app: a native passkey needs Associated Domains, which a free Apple account does not
have.

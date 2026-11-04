# Airlance

| Folder | What is this |
| --- | --- |
| `auth` | email, passkey, OpenID Connect. `auth.airlance.org` |
| `airlance-server` | Server of messenger. `api.airlance.org` |
| `Airlance` | iOS application |

## From scratch

```sh
make setup
```

Put the Cloudflare tunnel token into `auth/.secrets/production/cloudflared.env`, then:

```sh
make up
make register
```

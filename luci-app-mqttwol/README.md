# luci-app-mqttwol

OpenWrt **LuCI** application and **`procd` service** that subscribes to an MQTT topic, treats each MQTT payload as a Wake-on-LAN MAC address string, and runs **`etherwake -i <interface> <mac>`** for valid addresses. Depends on **`mosquitto-client`** (`mosquitto_sub`) and **`etherwake`** as requested.

Compared to the [podkop reference](https://github.com/itdoginfo/podkop) (Lua controller + packaged JavaScript SPA), this package uses **classic Lua CBI forms** alongside the packaged shell worker, matching the MQTT/WoL simplicity of the feature set.

---

## Architecture

```
                    ┌──────────────────────────────┐
                    │ LuCI Lua (mqttwol controller)│
                    │            +                 │
                    │ CBI form (model/cbi/mqttwol) │
                    └────────────────┬─────────────┘
                                     │ edits
                                     ▼
                        /etc/config/mqttwol (uci)
                                     │
                        ┌────────────▼────────────┐
             procd ────► /usr/sbin/mqttwol-sub   │
                        │ mosquitto_sub  ◄ ─ MQTT │
                        └─────────┬────────────────┘
                                  │ parses MAC payloads
                                  ▼
                          etherwake -i iface MAC
                                  │
                                  └──► LAN Magic Packet broadcast
```

- **LuCI**: writes UCI blob `mqttwol.main` (`enabled`, `server`, `port`, optional credentials, `topic`, `interface`).
- **`/etc/init.d/mqttwol`** (`USE_PROCD=1`): when `enabled=1`, spawns **`/usr/sbin/mqttwol-sub`** via `procd` with **`respawn 3600 5 5`**, piping env vars sourced from UCI.
- **`mqttwol-sub`**: indefinite outer loop rebuilding `mosquitto_sub`; inner `while read` handles each payload instantly. If MQTT disconnects, the pipe ends, the shell notices, logs a warning, sleeps 2s, and resumes (defence in depth on top of procd restart policy).
- **Logging**: BusyBox `logger` → `logread`; tag `mqttwol`.

Reload trigger: **`procd_add_reload_trigger mqttwol`** recomputes the service whenever UCI commits (LuCI commits already call restart in `mqttwol.lua`).

---

## File tree

```
luci-app-mqttwol/
├── Makefile                         # feeds/package recipe and install layout
├── README.md                        # operational & maintenance documentation
├── scripts/
│   ├── build-sdk-packages.sh        # SDK docker build for apk+ipk
├── sdk/
│   ├── Dockerfile-sdk-apk-base      # cached SDK base for apk builds
│   ├── Dockerfile-sdk-apk           # package build on apk base
│   ├── Dockerfile-sdk-ipk-base      # cached SDK base for ipk builds
│   └── Dockerfile-sdk-ipk           # package build on ipk base
├── install.sh                       # podkop-style auto-installer from GitHub release
├── luasrc/
│   ├── controller/
│   │   └── mqttwol.lua             # Registers Services → MQTT Wake-on-LAN
│   └── model/
│       └── cbi/
│           └── mqttwol.lua          # CBI bindings for mqttwol.main
└── root/
    ├── etc/
    │   ├── config/
    │   │   └── mqttwol             # authoritative defaults (ship & upgrade safe)
    │   └── init.d/
    │       └── mqttwol             # procd wrapper exporting env vars for worker
    └── usr/
        └── sbin/
            └── mqttwol-sub          # mosquitto_sub ↔ etherwake pipeline
```

On device, staged paths mirror **`root/`** plus LuCI artefacts under **`/usr/lib/lua/luci/`**.

---

## UCI schema (`config mqttwol 'main'`)

| Option       | Meaning                                      |
|-------------|-----------------------------------------------|
| `enabled`   | `1` activates procd-managed subscriber        |
| `server`    | MQTT hostname or IP                           |
| `port`      | MQTT port (defaults to `1883` in bootstrap)    |
| `username`  | Optional (`-u`); blank disables auth block    |
| `password`  | Optional MQTT password (`-P` when username set)|
| `topic`     | Single topic `mosquitto_sub` listens to       |
| `interface` | Network device for `etherwake -i`, default **`br-lan`** |

MQTT payloads must resemble `00:11:22:33:44:55` ; dashed inputs are canonicalised internally but must still encode six octets.

---

## Init-script behaviour (`/etc/init.d/mqttwol`)

`start_service`:

1. `config_load mqttwol`; fetch `enabled` (`main`).
2. Return immediately when `enabled` ≠ `"1"` (no `procd` instance).
3. Validate `server`, `topic`, and `interface` are non-empty; fail fast with syslog error if invalid.
4. `procd_open_instance` executing `/usr/sbin/mqttwol-sub` with exported env mirrors (see Makefile postinst optionally enabling symlink).
5. `procd_close_instance`; `reload_service → restart`; `service_triggers` notifies `pod`.

`mqttwol-sub` honours:

- **`MQTTWOL_SERVER`**, **`MQTTWOL_PORT`**, **`MQTTWOL_TOPIC`**, **`MQTTWOL_INTERFACE`** (mandatory).
- **`MQTTWOL_USERNAME` / `MQTTWOL_PASSWORD`** only when subscribing with credentials.

---

## Building & deploying

Copy the bundle into OpenWrt’s tree (preferred location: `package/luci-app-mqttwol` or feeds clone). Example:

```
cp -a luci-app-mqttwol /path/to/openwrt/package/
./scripts/feeds update
./scripts/feeds install mosquitto-client etherwake luci-base
make menuconfig
# LuCI → 3. Applications → luci-app-mqttwol <M/*>
make package/luci-app-mqttwol/compile V=s
```

On OpenWrt 25+ with APK backend (`CONFIG_USE_APK=y`) output format is:

- `luci-app-mqttwol-<version>.apk`

Typical location:

- `openwrt/bin/packages/<arch>/base/luci-app-mqttwol-<version>.apk`

### SDK build (apk + ipk)

Like podkop, this project now ships SDK docker build files and helper script.

```sh
./scripts/build-sdk-packages.sh
```

First run builds SDK base images (feeds/setup), next runs reuse cache.
To force refresh SDK base layers:

```sh
./scripts/build-sdk-packages.sh ./dist/sdk --rebuild-base
```

Artifacts are exported to:

- `dist/sdk/apk/luci-app-mqttwol-*.apk`
- `dist/sdk/ipk/luci-app-mqttwol-*.ipk`

### Public release workflow (recommended)

1. Build both formats with SDK script:

```sh
./scripts/build-sdk-packages.sh ./dist/sdk
```

2. Upload release assets to GitHub Release:
   - `dist/sdk/apk/luci-app-mqttwol-*.apk`
   - `dist/sdk/ipk/luci-app-mqttwol-*.ipk`

### One-command install script (podkop-style)

After publishing release assets, users can install directly from your repo:

```sh
wget -O - https://raw.githubusercontent.com/altplus255/luci-app-mqttwol/main/install.sh | sh
```

`install.sh` automatically:
- detects `apk` vs `opkg`,
- updates package indexes,
- installs dependencies (`luci-base`, `mosquitto-client`, `etherwake`),
- downloads latest release package,
- for `apk` runs `apk add --allow-untrusted`,
- installs and starts `mqttwol`.

Optional format override:

```sh
PKG_FMT=apk wget -O - https://raw.githubusercontent.com/altplus255/luci-app-mqttwol/main/install.sh | sh
PKG_FMT=ipk wget -O - https://raw.githubusercontent.com/altplus255/luci-app-mqttwol/main/install.sh | sh
```

If your workstation cannot write `/openwrt/package` due to root ownership, relocate with `sudo chown` or build from a user-owned clone.

---

## Testing before / after packaging

**On build host (shell audit):**

- `shellcheck root/usr/sbin/mqttwol-sub root/etc/init.d/mqttwol` (optional but recommended).
- Verify **Makefile** `DEPENDS` covers `+luci-base +mosquitto-client +etherwake`.

**On router (manual smoke, without package install):**

1. Install `mosquitto-client`, `etherwake`, `luci-base`.
2. Copy `root/etc/config/mqttwol`, `root/etc/init.d/mqttwol`, `root/usr/sbin/mqttwol-sub` to matching paths, `chmod +x` scripts.
3. Edit `/etc/config/mqttwol` with your broker & topic; `uci commit mqttwol`.
4. `/etc/init.d/mqttwol enable && /etc/init.d/mqttwol start`.
5. `logread -f | grep mqttwol` to watch events.
6. Publish a test MAC (`mosquitto_pub -h broker -t home/router/wol -m "$(printf '00:11:22:33:44:66')"`).
7. Confirm target NIC toggles WoL LEDs / wakes host; adjust `interface` option if bridging differs.

---

## Operational notes / future tweaks

- **Security**: plaintext MQTT credentials reside in `/etc/config`; consider TLS broker & VPN instead of WAN exposure.
- **Payload validation**: rejects non-mac strings to avoid spawning `etherwake` with nonsense.
- **Multiple targets**: subscribe with wildcards (`#`, `+`) is not wired in; broaden code if needed.
- **IPv6 MQTT**: ensure broker reachable; `datatype "host"` in LuCI accommodates DNS or literal addresses.
- **Scaling**: sequential `etherwake` calls suffice for homelab bursts; offload to queue worker if bursts grow.

Maintain this README when extending features so tooling (and collaborators) regain context instantly.

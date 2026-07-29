# API Reference

All backend functionality is exposed through shell scripts in `/usr/local/bin/trafficctl-*.sh`. The LuCI frontend calls them via JSON-RPC through the rpcd backend at `/usr/libexec/rpcd/luci.trafficctl`.

---

## Common Conventions

- **Input validation**: Every script validates IPs with regex + octet range (0–255) via `tctl_validate_ip`.
- **Error format**: `{"ok":false,"msg":"Human-readable error message"}`
- **Success format (actions)**: `{"ok":true,"msg":"Human-readable success message"}`
- **Rate units**: All rate values are in **kbit/s** (kilobits per second).
- **Exit codes**: 0 on success, 1 on input validation failure.
- **Label sanitization**: All label parameters are stripped to `[a-zA-Z0-9_.-]`.

---

## rpcd Methods

The frontend calls these via `rpc.declare()`:

| Method | Script | Params |
|--------|--------|--------|
| `summary` | `trafficctl-summary.sh` | (none) |
| `device` | `trafficctl-device.sh` | `ip`, `proto` |
| `bytes` | `trafficctl-bytes.sh` | (none) |
| `block` | `trafficctl-block.sh` | `ip`, `label` |
| `unblock` | `trafficctl-unblock.sh` | `ip`, `label` |
| `ratelimit` | `trafficctl-ratelimit.sh` | `ip`, `rate_kbit`, `label` |
| `ratelimit_stats` | `trafficctl-ratelimit-stats.sh` | (none) |
| `shape_add` | `trafficctl-shape.sh add` | `ip`, `rate_kbit`, `label` |
| `shape_remove` | `trafficctl-shape.sh remove` | `ip`, `label` |
| `shape_stats` | `trafficctl-shape-stats.sh` | (none) |
| `macfilter_add` | `trafficctl-macfilter-add.sh` | `ip` |
| `macfilter_remove` | `trafficctl-macfilter-remove.sh` | `ip` |
| `rdns` | `trafficctl-rdns.sh` | `ip` |
| `config_get` | (inline) | (none) — returns `enabled`, `default_mode`, `offload_mode`, `sw`, `hw` |
| `config_set` | (inline) | `enabled`, `default_mode`, `sw`, `hw` (all optional) |
| `telegram_config_get` | (inline) | (none) |
| `telegram_config_set` | (inline) | `enabled`, `bot_token`, `chat_id`, `poll_interval`, `notify_new_device`, `notify_known_device`, `btn_block_inet`, `btn_block_wifi`, `btn_limiter`, `btn_shaper` |
| `telegram_test` | `trafficctl-telegram-test.sh` | `bot_token`, `chat_id` |

---

## Query Scripts

### trafficctl-summary.sh

Returns a summary of all active LAN devices with traffic control status and connection type.

**Arguments:** None

**Output:** JSON array of device objects.

```json
[
  {
    "ip": "192.168.0.111",
    "name": "MacBookPro",
    "mac": "06:2b:92:a8:bd:8c",
    "conn_type": "5G",
    "conns": 42,
    "total": 1958278,
    "tcp": 1900000,
    "udp": 58278,
    "blocked": false,
    "block_bytes": 0,
    "wifi_blocked": false,
    "rate_limit_kbit": 0,
    "shape_kbit": 10000
  }
]
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `ip` | string | Device LAN IP address |
| `name` | string | Hostname from DHCP lease, or `*` if unknown |
| `mac` | string | MAC address (lowercase), empty if not resolved |
| `conn_type` | string | `"2.4G"`, `"5G"`, `"6G"`, `"lan2"`, `"lan3"`, `"lan4"`, or `"ethernet"` |
| `conns` | number | Active connection count (unique dst IPs) |
| `total` | number | Total bytes in conntrack (reply direction = download) |
| `tcp` | number | TCP bytes |
| `udp` | number | UDP bytes |
| `blocked` | boolean | Whether internet is blocked |
| `block_bytes` | number | Bytes matched by the block rule (cumulative) |
| `wifi_blocked` | boolean | Whether MAC is in WiFi deny list |
| `rate_limit_kbit` | number | Active policer rate in kbit/s (0 = not limited) |
| `shape_kbit` | number | Active shaper rate in kbit/s (0 = not shaped) |

---

### trafficctl-device.sh

Returns detailed connection information for a single device.

**Arguments:**

| Position | Required | Description |
|----------|----------|-------------|
| 1 | Yes | IPv4 address |
| 2 | No | Protocol filter: `tcp`, `udp`, or `all` (default: `all`) |

**Output:**

```json
{
  "ip": "192.168.0.111",
  "name": "MacBookPro",
  "mac": "06:2b:92:a8:bd:8c",
  "conn_type": "5G",
  "timestamp": 1779742529,
  "blocked": false,
  "block_packets": 0,
  "block_bytes": 0,
  "wifi_blocked": false,
  "total": 101,
  "protocols": {"tcp": 91, "udp": 10, "other": 0},
  "tcp_states": {"established": 22, "time_wait": 3, "syn_sent": 63, "close_wait": 0},
  "connections": [
    {
      "proto": "tcp",
      "dst": "140.82.121.3",
      "host": "",
      "port": 443,
      "service": "https",
      "wan": "wan",
      "bytes": 17261,
      "state": "ESTABLISHED"
    }
  ],
  "rate_limit_kbit": 0,
  "shape_kbit": 10000
}
```

---

### trafficctl-bytes.sh

Returns raw byte counters from conntrack for bandwidth speed calculation.

**Arguments:** None

**Output:**

```json
[
  {"ip": "192.168.0.111", "bytes_in": 456789012, "bytes_out": 12345678}
]
```

| Field | Type | Description |
|-------|------|-------------|
| `ip` | string | Device IP |
| `bytes_in` | number | Total bytes received (download = conntrack reply direction) |
| `bytes_out` | number | Total bytes sent (upload = conntrack original direction) |

---

### trafficctl-ratelimit-stats.sh

Returns drop counters from the nftables rate-limiter.

**Arguments:** None

**Output:**

```json
[
  {"ip": "192.168.0.100", "rate_kbit": 5000, "packets": 1423, "bytes": 2134567}
]
```

Returns `[]` if no rate limits are active or on iptables backends.

---

### trafficctl-shape-stats.sh

Returns tc/HTB class statistics for all shaped devices.

**Arguments:** None

**Output:**

```json
[
  {"ip": "192.168.0.111", "rate_kbit": 10000, "bytes": 45678901, "packets": 32456, "backlog": 4096}
]
```

Returns `[]` if tc is not installed or no HTB qdisc exists.

---

### trafficctl-rdns.sh

Reverse DNS lookup for a single IP. Used by the Telegram bot and the rpcd `rdns` ubus
method. The LuCI frontend uses `network.rrdns.lookup` directly for batch resolution.

**Arguments:** `<ip>`

**Output:**

```json
{"ip": "140.82.121.3", "host": "lb-140-82-121-3-iad.github.com"}
```

Uses `ubus call network.rrdns lookup` (rpcd-mod-rrdns, ships with rpcd) with BusyBox
`nslookup` as a fallback. No `bind-dig` required.

---

## Action Scripts

### trafficctl-block.sh / trafficctl-unblock.sh

Block/unblock a device's internet access.

**Arguments:** `<ip> [label]`

**Output:**
```json
{"ok": true, "msg": "blocked 192.168.0.100 (label: Kids-iPad)"}
```

**Side effects (block):**
- Inserts drop rule in `inet fw4 forward` (nft) or `FORWARD` chain (iptables).
- Kills existing conntrack entries for the device.

---

### trafficctl-ratelimit.sh

Set or remove a download rate limit (policer).

**Arguments:** `<ip> <rate_kbit> [label]`

Rate of `0` removes the limit.

**Output:**
```json
{"ok": true, "msg": "rate limit set: 5000 kbit/s for 192.168.0.100"}
```

---

### trafficctl-shape.sh

Manage tc/HTB traffic shaping.

**Arguments:** `<add|remove|status> <ip> [rate_kbit] [label]`

**Output (add):**
```json
{"ok": true, "msg": "shape 10000 kbit/s applied to 192.168.0.111 (class 1:6f)"}
```

**Output (status):**
```json
{"ok": true, "ip": "192.168.0.111", "classid": "1:6f", "info": "rate 10000Kbit"}
```

**Persistence:** Writes to `/etc/trafficctl/shapes.json` on every add/remove.

---

### trafficctl-macfilter-add.sh / trafficctl-macfilter-remove.sh

Block/unblock a device from WiFi (MAC filter).

**Arguments:** `<ip>`

**Output:**
```json
{"ok": true, "msg": "wifi blocked for 06:2b:92:a8:bd:8c on 2 interface(s)"}
```

**Side effects:**
- Sets `macfilter=deny` on all wifi-iface sections.
- Adds/removes MAC from `maclist`.
- Applies at runtime via `hostapd_cli deny_acl` + `deauthenticate` (no wifi reload -- only target client affected).

---

## Telegram Bot

### trafficctl-telegram.sh

Bot daemon using Telegram long polling. Runs under procd.

**Commands:**
- `/devices` -- inline keyboard with all active devices
- `/status` -- text summary of blocked/limited devices
- `/help` -- usage

**Callback data format:** `act:<verb>:<ip>[:<param>]`

| Callback | Action |
|----------|--------|
| `act:menu:<ip>` | Show device action buttons |
| `act:block:<ip>` | Block internet |
| `act:unblock:<ip>` | Unblock internet |
| `act:wblock:<ip>` | Block WiFi |
| `act:wunblock:<ip>` | Unblock WiFi |
| `act:limit:<ip>:<rate>` | Apply limiter (rate in kbit/s) |
| `act:unlimit:<ip>` | Remove limiter |
| `act:shape:<ip>:<rate>` | Apply shaper |
| `act:unshape:<ip>` | Remove shaper |
| `act:back` | Return to device list |

**Known devices file:** `/etc/trafficctl/telegram_known.json` -- tracks MACs for new device notifications.

### trafficctl-telegram-test.sh

```
trafficctl-telegram-test.sh <token> <chat_id>
```

Validates token format and chat_id, sends a test message. Returns `{"ok":true,"msg":"..."}`.

---

## rpcd ACL

The ACL file at `/usr/share/rpcd/acl.d/luci-app-trafficctl.json` grants execution permissions. The rpcd backend at `/usr/libexec/rpcd/luci.trafficctl` handles method dispatch and parameter validation.

# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is

`luci-app-trafficctl` is an **OpenWrt LuCI plugin** (shell scripts + single ES5 `status.js` file). There is no `npm run dev`, bundler, or local web server. Development on a Linux VM means lint, unit tests, IPK/APK builds, and (optionally) deploy to a real OpenWrt router or QEMU VM.

See `docs/DEVELOPMENT.md` and `CLAUDE.md` for full conventions.

### Dev VM dependencies

| Tool | Purpose |
|------|---------|
| **Node.js 20+** + `npm ci` | ESLint (`eslint@^8`) |
| **shellcheck** | Shell lint (CI parity) |
| **dash** | POSIX syntax checks in `tests/test_openwrt_compat.sh` |
| **bash** | Test runners under `tests/` |

System packages (`shellcheck`, `dash`) are expected to be present in the Cloud Agent image. They are not installed by the update script.

### Lint

```sh
npm ci
npx eslint --max-warnings 0 luci-app-trafficctl/htdocs/
node --check luci-app-trafficctl/htdocs/luci-static/resources/view/trafficctl/status.js

# ShellCheck (same file list as .github/workflows/shellcheck.yml)
mapfile -t files < <(grep -rlE '^#!.*(sh|bash|dash|ash)' luci-app-trafficctl/root build-ipk.sh build-apk.sh tests | grep -v node_modules | sort -u)
shellcheck -x -e SC1091 -S warning "${files[@]}"
```

Note: `package.json` `"lint"` points at `htdocs/` (wrong path); use `luci-app-trafficctl/htdocs/` as CI does.

### Test

```sh
bash tests/test_fw.sh
bash tests/test_bytes_nft.sh
bash tests/test_telegram.sh
bash tests/test_telegram_mock.sh
bash tests/test_telegram_e2e.sh
bash tests/test_security.sh
bash tests/test_build_ipk.sh
bash tests/test_openwrt_compat.sh
```

Optional (Docker + OpenWrt images): `tests/test_install.sh`, `compat.yml` matrix. Telegram integration needs `TEST_TELEGRAM_TOKEN` / `TEST_TELEGRAM_CHAT_ID` secrets.

### Build

```sh
./build-ipk.sh <version> <release>   # → dist/luci-app-trafficctl_*.ipk
./build-apk.sh <version> <release>   # → dist/luci-app-trafficctl_*.apk
```

### Running the app locally (no router)

The LuCI UI only runs on OpenWrt (`uhttpd` + `rpcd`). On the dev VM you can exercise the **rpcd backend** after installing scripts to `/usr/local/bin` and `/usr/libexec/rpcd/` (paths are hardcoded in the sources):

```sh
sudo cp luci-app-trafficctl/root/usr/local/bin/trafficctl-fw.sh /usr/local/bin/
sudo cp luci-app-trafficctl/root/usr/libexec/rpcd/luci.trafficctl /usr/libexec/rpcd/
sudo chmod +x /usr/local/bin/trafficctl-fw.sh /usr/libexec/rpcd/luci.trafficctl

# List API methods
/usr/libexec/rpcd/luci.trafficctl list

# Summary needs a working trafficctl-summary.sh on the router paths;
# on a dev VM without conntrack, use a mock script or run the test suite instead.
```

For end-to-end UI testing, deploy to a router (`docs/DEVELOPMENT.md`) or use QEMU with port forwards `:2222` (SSH) and `:8080` (HTTP).

### Gotchas

- Shell scripts must be **POSIX sh** (BusyBox ash/dash), not bash.
- Frontend is **ES5 only** — no `let`, arrows, or template literals.
- `rpcd` scripts output JSON **objects**; wrap arrays as `{"result": [...]}`.
- CSS class hidden elements need `style.display = 'block'` (not `''`) to show — see `CLAUDE.md`.

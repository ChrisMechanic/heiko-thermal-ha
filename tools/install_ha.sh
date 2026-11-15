#!/bin/bash
# Instalacja / aktualizacja Heiko Thermal w Home Assistant. Uruchom w terminalu HA (Studio Code Server, SSH):
#
#   curl -sL https://raw.githubusercontent.com/ChrisMechanic/heiko-thermal-ha/main/tools/install_ha.sh | HOST=192.168.1.183 NOTIFY=mobile_app_telefon bash
#
# HOST    IP modułu USR-W600 (potrzebne przy pierwszej instalacji)
# NOTIFY  usługa powiadomień na telefon dla pakietu alarmów (opcjonalnie, np. mobile_app_s25u)
# WRITE   true/false: sterowanie trybem i włącznikiem (domyślnie true)
#
# Co robi: kopiuje integrację do custom_components, pakiety do katalogu packages (nie nadpisuje istniejących),
# panel do /config/heiko_panel.yaml, dopisuje konfigurację do configuration.yaml (kopia: configuration.yaml.bak-heiko),
# sprawdza konfigurację i restartuje HA, jeśli sprawdzenie przejdzie.
set -e
CONFIG=${CONFIG:-/config}
TMP=$(mktemp -d)
echo "== Pobieram heiko-thermal-ha"
curl -fsSL "${URL:-https://github.com/ChrisMechanic/heiko-thermal-ha/archive/refs/heads/main.tar.gz}" | tar xz -C "$TMP"
export SRC="$TMP/heiko-thermal-ha-main" CONFIG HOST NOTIFY WRITE
python3 - <<'PY'
import os, re, shutil, glob
cfg, src = os.environ["CONFIG"], os.environ["SRC"]
host, notify = os.environ.get("HOST", ""), os.environ.get("NOTIFY", "")
write = os.environ.get("WRITE", "true").lower() != "false"
path = os.path.join(cfg, "configuration.yaml")
text = open(path, encoding="utf-8").read()
orig = text

# integration
dst = os.path.join(cfg, "custom_components", "heiko_thermal")
shutil.rmtree(dst, ignore_errors=True)
shutil.copytree(os.path.join(src, "custom_components", "heiko_thermal"), dst)
print("== Integracja ->", dst)

# packages: use the directory already configured, otherwise add packages: !include_dir_named packages
m = re.search(r"^[ \t]+packages:[ \t]*!include_dir_(?:merge_)?named[ \t]+(\S+)", text, re.M)
if m:
    pkg_dir = m.group(1)
elif re.search(r"^[ \t]+packages:", text, re.M):
    raise SystemExit("!! configuration.yaml ma 'packages:' w innej postaci - skopiuj pakiety ręcznie z examples/packages")
else:
    pkg_dir = "packages"
    ha = re.search(r"^homeassistant:[ \t]*\n((?:[ \t]*#.*\n|[ \t]*\n)*)([ \t]+)?", text, re.M)
    if ha:
        indent = ha.group(2) or "  "
        text = text[:ha.end(1)] + f"{indent}packages: !include_dir_named packages\n" + text[ha.end(1):]
    else:
        text = "homeassistant:\n  packages: !include_dir_named packages\n\n" + text
pkg_abs = os.path.join(cfg, pkg_dir)
os.makedirs(pkg_abs, exist_ok=True)
for f in glob.glob(os.path.join(src, "examples", "packages", "*.yaml")):
    target = os.path.join(pkg_abs, os.path.basename(f))
    if os.path.exists(target):
        print("== Pakiet istnieje, zostawiam:", target)
        continue
    body = open(f, encoding="utf-8").read()
    if os.path.basename(f) == "pompa_ciepla_alarmy.yaml":
        if notify:
            body = body.replace("notify.mobile_app_TELEFON_1", f"notify.{notify}")
        body = re.sub(r"      - action: notify\.mobile_app_TELEFON_\d\n        data: \{[^\n]*\}\n        continue_on_error: true\n", "", body)
    open(target, "w", encoding="utf-8").write(body)
    print("== Pakiet ->", target)

# integration config
if not re.search(r"^heiko_thermal:", text, re.M):
    if not host:
        raise SystemExit("!! Podaj HOST=<IP modułu USR-W600>")
    text = text.rstrip("\n") + f"\n\nheiko_thermal:\n  host: {host}\n  allow_write: {'true' if write else 'false'}\n"
    print("== Dopisano heiko_thermal (host", host + ")")
if text != orig:
    shutil.copy(path, path + ".bak-heiko")
    open(path, "w", encoding="utf-8").write(text)
    print("== configuration.yaml zaktualizowany, kopia: configuration.yaml.bak-heiko")

shutil.copy(os.path.join(src, "examples", "dashboard", "pompa_ciepla_panel.yaml"), os.path.join(cfg, "heiko_panel.yaml"))
print("== Panel -> /config/heiko_panel.yaml")
PY
rm -rf "$TMP"
if command -v ha >/dev/null 2>&1; then
  echo "== Sprawdzam konfigurację"
  if ha core check; then echo "== OK, restartuję HA"; ha core restart; else echo "!! Błąd konfiguracji - HA NIE zrestartowany. Kopia: configuration.yaml.bak-heiko"; exit 1; fi
else
  echo "== Gotowe. Sprawdź konfigurację (Narzędzia deweloperskie -> YAML) i zrestartuj HA."
fi

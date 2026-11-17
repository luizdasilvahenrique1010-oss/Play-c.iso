#!/bin/bash
# Monta a ISO do Play Musica. Roda no GitHub (nao precisa mexer).
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$ROOT/build"; mkdir -p "$ROOT/build"; cd "$ROOT/build"

mkdir -p "config/includes.chroot/etc/systemd/system"
cat > "config/includes.chroot/etc/systemd/system/jukebox-server.service" <<'__FIM_DO_ARQUIVO__'
[Unit]
Description=Play Musica - servidor local
After=local-fs.target systemd-udevd.service

[Service]
Environment=PYTHONUTF8=1 LANG=C.UTF-8
ExecStart=/usr/bin/python3 /opt/jukebox/server.py
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
__FIM_DO_ARQUIVO__
mkdir -p "config/includes.chroot/etc/systemd/system/getty@tty1.service.d"
cat > "config/includes.chroot/etc/systemd/system/getty@tty1.service.d/zz-jukebox.conf" <<'__FIM_DO_ARQUIVO__'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM
Type=idle
__FIM_DO_ARQUIVO__
mkdir -p "config/includes.chroot/etc/skel"
cat > "config/includes.chroot/etc/skel/.bash_profile" <<'__FIM_DO_ARQUIVO__'
# Abre o jukebox direto na tela cheia (sem desktop) ao logar no tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx
fi
__FIM_DO_ARQUIVO__
mkdir -p "config/includes.chroot/etc/skel"
cat > "config/includes.chroot/etc/skel/.xinitrc" <<'__FIM_DO_ARQUIVO__'
#!/bin/sh
export LANG=C.UTF-8
xset s off; xset s noblank; xset -dpms
unclutter -idle 1 -root &
openbox &

# som no maximo (ALSA + PulseAudio)
( sleep 4
  for c in Master Speaker Headphone PCM; do amixer -q sset "$c" 100% unmute 2>/dev/null; done
  pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null
  pactl set-sink-volume @DEFAULT_SINK@ 100% 2>/dev/null ) &

# espera o servidor local subir
for i in $(seq 1 40); do
  curl -s -o /dev/null http://127.0.0.1:8765/api/fontes && break
  sleep 0.5
done

# abre em tela cheia e reabre sozinho se fechar/travar
while true; do
  chromium --kiosk --start-fullscreen --no-first-run --noerrdialogs --disable-infobars \
    --disable-session-crashed-bubble --disable-features=Translate --password-store=basic \
    --overscroll-history-navigation=0 --disable-pinch \
    --autoplay-policy=no-user-gesture-required \
    --user-data-dir=/tmp/chromium-jukebox \
    http://127.0.0.1:8765/index.html
  sleep 1
done
__FIM_DO_ARQUIVO__
mkdir -p "config/hooks/normal"
cat > "config/hooks/normal/0100-jukebox.hook.chroot" <<'__FIM_DO_ARQUIVO__'
#!/bin/sh
set -e
systemctl enable jukebox-server.service
mkdir -p /mnt/jukebox
chmod +x /opt/jukebox/server.py
__FIM_DO_ARQUIVO__
mkdir -p "config/hooks/normal"
cat > "config/hooks/normal/0200-boot-rapido.hook.binary" <<'__FIM_DO_ARQUIVO__'
#!/bin/sh
# Faz o menu de boot iniciar sozinho em 3 segundos (maquina de bar liga sem ninguem apertar nada)
for f in binary/isolinux/*.cfg; do
  [ -f "$f" ] && sed -i -E "s/^timeout .*/timeout 30/" "$f"
done
for f in binary/boot/grub/*.cfg; do
  [ -f "$f" ] && sed -i -E "s/^set timeout=.*/set timeout=3/" "$f"
done
exit 0
__FIM_DO_ARQUIVO__
mkdir -p "config/package-lists"
cat > "config/package-lists/jukebox.list.chroot" <<'__FIM_DO_ARQUIVO__'
xserver-xorg
xinit
x11-xserver-utils
openbox
unclutter-xfixes
chromium
libgl1-mesa-dri
python3
curl
dbus-x11
pulseaudio
pulseaudio-utils
alsa-utils
ntfs-3g
exfatprogs
dosfstools
fonts-dejavu
fonts-noto-color-emoji
locales
kbd
console-setup
keyboard-configuration
firmware-misc-nonfree
firmware-realtek
firmware-amd-graphics
firmware-sof-signed
__FIM_DO_ARQUIVO__
mkdir -p "auto"
cat > "auto/config" <<'__FIM_DO_ARQUIVO__'
#!/bin/sh
set -e
lb config noauto \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free non-free-firmware" \
  --apt-recommends false \
  --debian-installer none \
  --iso-volume "PLAYMUSICA" \
  --iso-application "Play Musica" \
  --iso-publisher "Play Musica" \
  --memtest none \
  --bootappend-live "boot=live components quiet loglevel=3 noeject locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Maceio" \
  "${@}"
__FIM_DO_ARQUIVO__

chmod +x auto/config config/hooks/normal/* config/includes.chroot/etc/skel/.xinitrc
mkdir -p config/includes.chroot/opt/jukebox/musicas config/includes.chroot/opt/jukebox/imagem config/includes.chroot/opt/jukebox/som
cp "$ROOT/index.html" "$ROOT/server.py" config/includes.chroot/opt/jukebox/
lb config
lb build
ls -lh *.iso
mv *.iso "$ROOT/PlayMusica.iso"

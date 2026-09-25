#!/bin/bash

# ==============================================================================
# Uygulama Adı : openfortivpn Custom GUI (GNOME Shell Extension)
# Açıklama     : Üst Bar Üzerinden OTP/SMS Destekli Yerleşik GNOME VPN Eklentisi
# ==============================================================================

UUID="openfortivpn-helper@local"
CONFIG_DIR="/etc/openfortivpn"
CONFIG_FILE="${CONFIG_DIR}/config"
SUDOERS_FILE="/etc/sudoers.d/openfortivpn-extension"

CURRENT_USER=${SUDO_USER:-$USER}

install_app() {
    echo "=========================================="
    echo " [+] GNOME Shell VPN Eklentisi Kuruluyor..."
    echo "=========================================="

    if [ "$EUID" -ne 0 ]; then
      echo "[-] Lütfen bu betiği sudo ile çalıştırın: sudo bash $0 install"
      exit 1
    fi

    # 1. Bağımlılıklar
    echo "[1/4] Bağımlılıklar yükleniyor (openfortivpn)..."
    apt update -qq
    apt install -y openfortivpn gnome-shell-extension-prefs > /dev/null

    # 2. Sudoers İzinleri
    echo "[2/4] Sudo yetkileri tanımlanıyor..."
    cat << EOF > "${SUDOERS_FILE}"
${CURRENT_USER} ALL=(ALL) NOPASSWD: /usr/bin/openfortivpn, /usr/bin/pkill -f openfortivpn
EOF
    chmod 0440 "${SUDOERS_FILE}"

    # 3. Eklenti Dizin Yapısı
    echo "[3/4] GNOME Shell Eklentisi oluşturuluyor..."
    ACTUAL_EXT_DIR="/home/${CURRENT_USER}/.local/share/gnome-shell/extensions/${UUID}"
    mkdir -p "${ACTUAL_EXT_DIR}"

    # metadata.json
    cat << EOF > "${ACTUAL_EXT_DIR}/metadata.json"
{
  "uuid": "${UUID}",
  "name": "openfortivpn Custom GUI",
  "description": "SMS/OTP destekli ve canlı terminal loglu OpenFortiVPN eklentisi.",
  "shell-version": [ "45", "46", "47", "48", "49", "50" ]
}
EOF

    # extension.js
    cat << 'EOF' > "${ACTUAL_EXT_DIR}/extension.js"
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

export default class OpenFortiVpnExtension extends Extension {
    enable() {
        this._vpnProcess = null;
        this._stdinStream = null;
        this._logBuffer = [];
        this._decoder = new TextDecoder('utf-8');

        this._indicator = new PanelMenu.Button(0.0, 'OpenFortiVPN', false);
        this._icon = new St.Icon({
            icon_name: 'network-vpn-no-route-symbolic',
            style_class: 'system-status-icon',
            style: 'opacity: 0.6;'
        });
        this._indicator.add_child(this._icon);

        this._toggleItem = new PopupMenu.PopupSwitchMenuItem('VPN Bağlantısı', false);
        this._toggleItem.closeOnActivate = false;

        this._toggleItem.connect('button-press-event', (actor, event) => {
            this._toggleItem.toggle();
            return Clutter.EVENT_STOP;
        });

        this._toggleItem.connect('toggled', (item, state) => {
            if (state) {
                this._startVpn();
            } else {
                this._disconnectVpn();
            }
        });
        this._indicator.menu.addMenuItem(this._toggleItem);

        this._otpMenuItem = new PopupMenu.PopupBaseMenuItem({ 
            reactive: true,
            activate: false 
        });
        this._otpMenuItem.closeOnActivate = false;
        
        let inputBox = new St.BoxLayout({ 
            vertical: false, 
            style: 'padding: 5px; spacing: 5px;' 
        });
        
        this._otpEntry = new St.Entry({
            hint_text: 'SMS Kodunu Girin',
            can_focus: true,
            style: 'width: 150px; font-size: 13px;'
        });

        let sendBtn = new St.Button({
            label: 'Gönder',
            style_class: 'button',
            style: 'padding: 2px 10px; font-size: 12px;'
        });

        sendBtn.connect('clicked', () => this._sendOtp());
        this._otpEntry.clutter_text.connect('activate', () => this._sendOtp());

        inputBox.add_child(this._otpEntry);
        inputBox.add_child(sendBtn);
        this._otpMenuItem.add_child(inputBox);
        this._indicator.menu.addMenuItem(this._otpMenuItem);

        this._otpMenuItem.actor.hide();

        this._logMenuItem = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            activate: false
        });
        this._logMenuItem.closeOnActivate = false;

        let logBox = new St.BoxLayout({
            vertical: true,
            style: 'background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 8px; width: 360px; height: 270px;'
        });

        this._logLabel = new St.Label({
            text: '--- Loglar Bekleniyor ---\n',
            style: 'color: #3fb950; font-family: monospace; font-size: 11px;'
        });

        let clutterText = this._logLabel.get_clutter_text();
        clutterText.set_line_wrap(true);
        clutterText.set_single_line_mode(false);

        logBox.add_child(this._logLabel);
        this._logMenuItem.add_child(logBox);
        this._indicator.menu.addMenuItem(this._logMenuItem);

        Main.panel.addToStatusArea(this.metadata.uuid, this._indicator);
    }

    disable() {
        this._disconnectVpn();
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }

    _appendRawText(text) {
        if (!text) return;

        let cleanText = text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, '');
        let lines = cleanText.split('\n');
        
        for (let i = 0; i < lines.length; i++) {
            if (i === 0 && this._logBuffer.length > 0 && !this._lastWasNewline) {
                this._logBuffer[this._logBuffer.length - 1] += lines[i];
            } else {
                this._logBuffer.push(lines[i]);
            }
        }

        this._lastWasNewline = cleanText.endsWith('\n');

        while (this._logBuffer.length > 30) {
            this._logBuffer.shift();
        }

        let fullText = this._logBuffer.join('\n');

        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            if (this._logLabel) {
                this._logLabel.set_text(fullText);
            }
            return GLib.SOURCE_REMOVE;
        });

        if (cleanText.match(/Two-factor|token:|OTP|SMS|Passcode/i)) {
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                if (this._otpMenuItem) {
                    this._otpMenuItem.actor.show();
                }
                Main.notify('OpenFortiVPN', 'SMS Kodunu Menüye Girin!');
                return GLib.SOURCE_REMOVE;
            });
        }

        if (cleanText.includes('Tunnel is up') || cleanText.includes('Authenticated')) {
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                if (this._otpMenuItem) {
                    this._otpMenuItem.actor.hide();
                }
                this._icon.set_icon_name('network-vpn-symbolic');
                this._icon.set_style('opacity: 1.0; color: #3fb950;');
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    _startVpn() {
        try {
            let configPath = '/etc/openfortivpn/config'; 
            this._logBuffer = [];
            this._lastWasNewline = true;

            let launcher = new Gio.SubprocessLauncher({
                flags: Gio.SubprocessFlags.STDIN_PIPE | 
                       Gio.SubprocessFlags.STDOUT_PIPE | 
                       Gio.SubprocessFlags.STDERR_MERGE
            });

            this._vpnProcess = launcher.spawnv([
                'stdbuf', '-oL', '-eL', 'sudo', 'openfortivpn', '-c', configPath
            ]);

            this._stdinStream = this._vpnProcess.get_stdin_pipe();
            let stdoutPipe = this._vpnProcess.get_stdout_pipe();

            this._appendRawText('[+] VPN başlatılıyor...\n');

            this._readChunks(stdoutPipe);

        } catch (e) {
            this._appendRawText('[-] Hata: ' + e.message + '\n');
            Main.notify('OpenFortiVPN Hata', e.message);
            this._disconnectVpn();
        }
    }

    _sendOtp() {
        let code = this._otpEntry.get_text().trim();
        if (this._stdinStream && code) {
            let bytes = new GLib.Bytes(code + '\n');
            this._stdinStream.write_bytes_async(bytes, GLib.PRIORITY_DEFAULT, null, null);
            this._appendRawText('\n[>] OTP Gönderildi: ' + code + '\n');
            this._otpEntry.set_text('');
        }
    }

    _readChunks(stream) {
        stream.read_bytes_async(4096, GLib.PRIORITY_DEFAULT, null, (source, result) => {
            try {
                let gbytes = source.read_bytes_finish(result);
                if (gbytes && gbytes.get_size() > 0) {
                    let text = this._decoder.decode(gbytes.get_data());
                    this._appendRawText(text);
                    this._readChunks(stream);
                }
            } catch (e) {
            }
        });
    }

    _disconnectVpn() {
        if (this._vpnProcess) {
            this._vpnProcess.force_exit();
            this._vpnProcess = null;
            this._stdinStream = null;
        }

        try {
            let launcher = new Gio.SubprocessLauncher({ flags: Gio.SubprocessFlags.NONE });
            launcher.spawnv(['sudo', 'pkill', '-f', 'openfortivpn']);
        } catch (e) {}

        this._appendRawText('\n[-] VPN Bağlantısı Kesildi.\n');

        if (this._icon) {
            this._icon.set_icon_name('network-vpn-no-route-symbolic');
            this._icon.set_style('opacity: 0.6;');
        }

        if (this._otpMenuItem) {
            this._otpMenuItem.actor.hide();
        }

        if (this._toggleItem && this._toggleItem.state) {
            this._toggleItem.setToggleState(false);
        }
    }
}
EOF

    chown -R "${CURRENT_USER}:${CURRENT_USER}" "${ACTUAL_EXT_DIR}"

    # 4. Konfigürasyon
    echo "[4/4] Konfigürasyon kontrol ediliyor..."
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$CONFIG_DIR"
        cat << EOF > "$CONFIG_FILE"
# openfortivpn Custom GUI Konfigürasyon Dosyası
host = vpn.sirketiniz.com
port = 443
username = kullanici_adiniz
password = sifreniz
# trusted-cert = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF
        chmod 600 "$CONFIG_FILE"
    fi

    echo ""
    echo "=========================================="
    echo " [✔] Kurulum Tamamlandı!"
    echo "=========================================="
    echo "Eklentiyi Etkinleştirmek İçin:"
    echo "gnome-extensions enable ${UUID}"
    echo "=========================================="
}

uninstall_app() {
    echo "=========================================="
    echo " [-] GNOME Shell Eklentisi Kaldırılıyor..."
    echo "=========================================="

    if [ "$EUID" -ne 0 ]; then
      echo "[-] Lütfen bu betiği sudo ile çalıştırın: sudo bash $0 uninstall"
      exit 1
    fi

    ACTUAL_EXT_DIR="/home/${CURRENT_USER}/.local/share/gnome-shell/extensions/${UUID}"

    pkill -f openfortivpn 2>/dev/null

    rm -rf "${ACTUAL_EXT_DIR}"
    rm -f "${SUDOERS_FILE}"

    read -p "[?] /etc/openfortivpn/config dosyası da silinsin mi? (e/H): " choice
    case "$choice" in 
      e|E ) 
        rm -rf "${CONFIG_DIR}"
        echo "[+] Konfigürasyon klasörü silindi."
        ;;
      * ) 
        echo "[!] Konfigürasyon dosyasına dokunulmadı."
        ;;
    esac

    echo "=========================================="
    echo " [✔] Eklenti Başarıyla Kaldırıldı!"
    echo "=========================================="
}

case "$1" in
    install|--install|-i)
        install_app
        ;;
    uninstall|--uninstall|-u)
        uninstall_app
        ;;
    *)
        echo "Kullanım: sudo bash $0 {install|uninstall}"
        exit 1
        ;;
esac

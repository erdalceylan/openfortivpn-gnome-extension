# OpenFortiVPN Custom GUI (GNOME Shell Extension)

GNOME Masaüstü ortamı (Ubuntu 24.04/26.04, GNOME 45 - 50+) için özel olarak geliştirilmiş **OpenFortiVPN** eklentisidir.

Bu eklenti, Fortinet SSL-VPN bağlantılarınızı üst bar üzerinden yönetmenizi sağlar. SMS / OTP (Two-Factor Authentication) doğrulama kodlarını doğrudan GNOME arabiriminde yakalar, anlık canlı terminal loglarını gösterir ve şifresiz geçiş altyapısı sunar.

---

## 🌟 Özellikler

- **Üst Bar Entegrasyonu:** Tek tıkla VPN bağlantısını başlatma ve kesme.
- **Dinamik OTP / SMS Girişi:** Sunucudan 2FA/OTP istendiği anda menü içerisinde otomatik beliren kod giriş kutusu.
- **Canlı Log Ekranı:** `openfortivpn` terminal çıktılarını ansi renk temizliği ve tamponsuz (unbuffered) bayt akışıyla anlık olarak takip edebilme.

---

## 🛠️ Bağımlılıklar (Requirements)

Eklentinin sorunsuz çalışabilmesi için sistemde aşağıdaki paketlerin yüklü olması gerekir:

* **Linux Dağıtımı:** Ubuntu 26.04+ (veya GNOME Shell kullanan herhangi bir Linux dağıtımı)
* **Masaüstü Ortamı:** GNOME Shell 50
* **Sistem Paketleri:**
  * `openfortivpn`
  * `coreutils` (`stdbuf` komutu için)
  * `gnome-shell-extension-prefs` (Uzantı yönetimi için)

---

## 🚀 Hızlı Kurulum

Projeyi klonlayıp kurulum betiğini `sudo` yetkisiyle çalıştırmanız yeterlidir:

```bash
git clone [https://github.com/erdalceylan/openfortivpn-gnome-extension.git](https://github.com/erdalceylan/openfortivpn-gnome-extension.git)
cd openfortivpn-gnome-extension
sudo bash install-uninstall.sh install
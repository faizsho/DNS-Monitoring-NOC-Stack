# Benteng DNS + Monitoring NOC Stack

Solusi DNS Recursive tingkat tinggi yang dirancang untuk ISP/WISP dengan fitur pemblokiran TrustPositif (CDB), Google SafeSearch, dan Monitoring Real-time menggunakan Prometheus & Grafana.

## 🚀 Fitur Utama
* **Layered Defense**: Menggabungkan `dnsdist`, `SmartDNS`, dan `PowerDNS Recursor`.
* **High Performance**: Menggunakan database CDB untuk menangani jutaan domain blokir tanpa beban CPU berlebih.
* **SafeSearch**: Otomatis mengaktifkan Restricted Mode pada Google dan YouTube di level jaringan.
* **NOC Dashboard**: Monitoring trafik QPS, Latency, dan Response Code secara visual.

## 🛠️ Cara Instalasi
Cukup jalankan satu baris perintah di server Ubuntu Fresh Install:
```bash
wget -qO- [https://raw.githubusercontent.com/faizsho/repo/main/install.sh](https://raw.githubusercontent.com/faizsho/repo/main/install.sh) | sudo bash

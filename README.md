# Benteng DNS + Monitoring NOC Stack

Solusi DNS Recursive tingkat tinggi yang dirancang untuk ISP/WISP dengan fitur pemblokiran TrustPositif (CDB), Google SafeSearch, dan Monitoring Real-time menggunakan Prometheus & Grafana.

## 🚀 Fitur Utama
* **Layered Defense**: Menggabungkan `dnsdist`, `SmartDNS`, dan `PowerDNS Recursor`.
* **High Performance**: Menggunakan database CDB untuk menangani jutaan domain blokir tanpa beban CPU berlebih.
* **SafeSearch**: Otomatis mengaktifkan Restricted Mode pada Google dan YouTube di level jaringan.
* **NOC Dashboard**: Monitoring trafik QPS, Latency, dan Response Code secara visual.

![Grafana Dashboard](img/simple dashboard.png)
---

## 🛠️ Cara Instalasi
Cukup jalankan satu baris perintah di server Ubuntu 24 Fresh Install:
```bash
wget -qO- https://raw.githubusercontent.com/faizsho/DNS-Monitoring-NOC-Stack/main/install.sh | sudo bash

wget -qO- https://raw.githubusercontent.com/faizsho/DNS-Monitoring-NOC-Stack/main/install22.sh | sudo bash
```
📊 Dashboard Access
Grafana: http://IP-SERVER:3000 (User/Pass: admin/admin).

dnsdist Web: http://IP-SERVER:8083 (Pass: admin123).

📝 Custom List
Whitelist: Tambahkan domain di  ``/opt/blocklist/custom_whitelist.txt.``

Update Manual: Jalankan bash `` /opt/blocklist/update-blocklist.sh.``

 
# Update Database Blocklist & Whitelist setiap jam 03:00 Pagi
```
sudo crontab -e
0 3 * * * bash /opt/blocklist/update-blocklist.sh >> /var/log/update-blocklist.log 2>&1
```
🤝 Credits
Script ini dikembangkan berdasarkan basis awal dari dnsdist-one-click oleh azhrimzdi dan telah dimodifikasi oleh Saya untuk kebutuhan infrastruktur yang lebih kompleks.


https://github.com/azhrimzdi/dnsdist-one-click

Developed with ❤️ for NOC Indonesia.

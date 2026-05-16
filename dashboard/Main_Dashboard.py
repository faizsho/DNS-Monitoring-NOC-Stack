from flask import Flask, render_template_string, request, jsonify
import subprocess
import json
import os

app = Flask(__name__)
WORKDIR = "/opt/blocklist"
WHITELIST_CDB = os.path.join(WORKDIR, "whitelist.cdb")
BLOCKLIST_CDB = os.path.join(WORKDIR, "domains.cdb")
STATUS_FILE = os.path.join(WORKDIR, "status.json")

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Glosindo Management Systemt</title>
    <style>
        body { font-family: 'Segoe UI', Roboto, sans-serif; background-color: #0f172a; color: #e2e8f0; margin: 0; padding: 40px 20px; display: flex; justify-content: center; }
        .container { max-width: 800px; width: 100%; }
        h1 { color: #f8fafc; font-size: 2rem; margin-bottom: 5px; text-align: center; }
        .subtitle { color: #94a3b8; font-size: 1rem; margin-bottom: 40px; text-align: center; }
        
        /* Grid Status */
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .status-card { background-color: #1e293b; border: 1px solid #334155; border-radius: 10px; padding: 20px; text-align: center; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        .status-label { font-size: 0.8rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 1px; }
        .status-value { font-size: 1.5rem; font-weight: bold; color: #3b82f6; margin-top: 8px; }
        .status-ok { color: #10b981; }
        
        /* Checker Card */
        .checker-card { background-color: #1e293b; border: 1px solid #334155; border-radius: 10px; padding: 30px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        h2 { font-size: 1.25rem; margin-top: 0; margin-bottom: 20px; color: #f8fafc; border-bottom: 1px solid #334155; padding-bottom: 10px; }
        .input-group { display: flex; gap: 10px; margin-bottom: 15px; }
        input[type="text"] { flex: 1; padding: 12px 15px; background-color: #0f172a; border: 1px solid #334155; border-radius: 6px; color: white; font-size: 1rem; }
        input[type="text"]:focus { outline: none; border-color: #3b82f6; }
        button.action-btn { background-color: #3b82f6; color: white; border: none; padding: 0 20px; border-radius: 6px; font-weight: 600; cursor: pointer; transition: 0.2s; }
        button.action-btn:hover { background-color: #2563eb; }
        
        /* Result Box */
        .result-box { display: none; padding: 20px; border-radius: 8px; border-left: 4px solid; margin-top: 20px; background-color: #0f172a; }
        .result-title { font-weight: bold; font-size: 1.1rem; margin-bottom: 15px; }
        .result-label { font-size: 0.8rem; color: #94a3b8; text-transform: uppercase; margin-bottom: 5px; }
        .result-domain { font-weight: bold; font-size: 1rem; color: #e2e8f0; margin-bottom: 15px; }
        .result-desc { font-size: 0.9rem; color: #cbd5e1; line-height: 1.4; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Glosindo Filter</h1>
        <div class="subtitle">Sistem Manajemen & Monitoring DNS Terpadu</div>

        <div class="status-grid">
            <div class="status-card">
                <div class="status-label">Terakhir Update</div>
                <div class="status-value" style="font-size: 1.2rem;">{{ status_data.last_run }}</div>
            </div>
            <div class="status-card">
                <div class="status-label">Total Domain Blokir</div>
                <div class="status-value">{{ "{:,}".format(status_data.total_entries|int) }}</div>
            </div>
            <div class="status-card">
                <div class="status-label">Durasi Proses</div>
                <div class="status-value">{{ status_data.duration }}s</div>
            </div>
            <div class="status-card">
                <div class="status-label">Status Mesin</div>
                <div class="status-value status-ok">{{ status_data.status }}</div>
            </div>
        </div>

        <div class="checker-card">
            <h2>Pengecekan Status Domain</h2>
            <div class="input-group">
                <input type="text" id="domainInput" placeholder="Masukkan nama domain (contoh: slotgacor.com)" onkeypress="if(event.key === 'Enter') checkDomain()">
                <button class="action-btn" onclick="checkDomain()">Cek Status</button>
            </div>
            
            <div id="resultBox" class="result-box">
                <div id="resultTitle" class="result-title"></div>
                <div class="result-label">NAMA DOMAIN</div>
                <div id="resultDomain" class="result-domain"></div>
                <div class="result-label">PENJELASAN SISTEM</div>
                <div id="resultDesc" class="result-desc"></div>
            </div>
        </div>
    </div>

    <script>
        async function checkDomain() {
            const input = document.getElementById('domainInput').value.trim().toLowerCase();
            if (!input) return;
            const btn = document.querySelector('.action-btn');
            btn.textContent = "Mengecek..."; btn.disabled = true;
            try {
                const response = await fetch('/api/check', {
                    method: 'POST', headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ domain: input })
                });
                const data = await response.json();
                const resultBox = document.getElementById('resultBox');
                const title = document.getElementById('resultTitle');
                
                resultBox.style.display = 'block';
                resultBox.style.borderColor = data.color;
                title.textContent = data.title; 
                title.style.color = data.color;
                document.getElementById('resultDomain').textContent = data.domain;
                document.getElementById('resultDesc').textContent = data.message;
            } catch (error) {
                alert("Terjadi kesalahan saat mengecek domain.");
            } finally {
                btn.textContent = "Cek Status"; btn.disabled = false;
            }
        }
    </script>
</body>
</html>
"""

def get_system_status():
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, 'r') as f:
                return json.load(f)
        except Exception:
            pass
    return {"last_run": "-", "total_entries": 0, "duration": "-", "status": "No Data"}

def check_in_cdb(domain, cdb_path):
    if not os.path.exists(cdb_path):
        return False
    try:
        with open(cdb_path, 'rb') as f:
            res = subprocess.run(['cdbget', domain], stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if res.returncode == 0:
                return True
            elif res.returncode == 100:
                return False
    except FileNotFoundError:
        pass
        
    try:
        res = subprocess.run(['cdb', '-q', cdb_path, domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if res.returncode == 0:
            return True
    except FileNotFoundError:
        pass
    return False

@app.route('/')
def index():
    status_data = get_system_status()
    return render_template_string(HTML_TEMPLATE, status_data=status_data)

@app.route('/api/check', methods=['POST'])
def api_check():
    data = request.json
    domain = data.get('domain', '').strip().lower()

    if not domain:
        return jsonify({"error": "Empty domain"}), 400

    if check_in_cdb(domain, WHITELIST_CDB):
        return jsonify({
            "domain": domain, "title": "Akses Aman (Diizinkan)",
            "message": "Domain ada di Whitelist. Akses normal diizinkan.",
            "color": "#10b981" 
        })

    if check_in_cdb(domain, BLOCKLIST_CDB):
        return jsonify({
            "domain": domain, "title": "Akses Diblokir",
            "message": "Domain masuk Database Kominfo/Blocklist. Akses dialihkan.",
            "color": "#ef4444" 
        })

    return jsonify({
        "domain": domain, "title": "Akses Aman (Diizinkan)",
        "message": "Domain bersih, tidak ada di daftar blokir mana pun.",
        "color": "#10b981" 
    })

if __name__ == '__main__':
    # Menjalankan di port 8080. Pastikan UFW allow 8080
    app.run(host='0.0.0.0', port=8080)

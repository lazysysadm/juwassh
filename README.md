# ☀️ Juwassh — Simple SSH Connection Manager

> **JUWA** means **SUN** in Swahili — and with this tool, your SSH workflow should be all sunshine.  
> **HAKUNA MATATA** with your shell and SSH connections 😄

---

## 🌍 Why Juwassh?

One day I wanted to migrate my [Remmina](https://remmina.org/) configuration from computer A to computer B.  
And then… **BOOM!** The whole config got messed up — impossible to use the imported data. I had to manually recreate every single entry on the new machine. 😤

I really like Remmina! But when it comes to **configuration portability**, it's pretty awful.

That's where the idea came from: a simple Bash script that lets you connect to your machines via SSH using tools already available on any Linux system, with a **single portable TOML configuration file** — while prioritizing **security and SSH key authentication**.

No GUI. No database. No bloat. Just a terminal, `fzf`, `tmux`, and your keys.

---

## ✨ Features

- 🗂️ **Group-based server organization** with color labels
- 🔍 **Fuzzy search** powered by `fzf`
- 🖥️ **Multi-select** — open several SSH sessions at once in tmux tabs
- 🏓 **Live ping status** (🟢 ON / 🔴 OFF) at startup
- 🔑 **SSH key authentication** first, password fallback optional
- 📄 **Single TOML config file** — easy to read, edit, backup, and migrate
- 🔌 **Auto-detects `~/.ssh/config`** entries and adds them to the list
- 🎨 Per-server **terminal color** theming inside tmux
- 💡 Runs entirely inside a **tmux session** with mouse support

---

## 📦 Dependencies

| Tool | Purpose |
|------|---------|
| `bash` | Shell interpreter |
| `tmux` | Terminal multiplexer |
| `fzf` | Fuzzy finder UI |
| `python3` | TOML config parsing (uses built-in `tomllib`, Python ≥ 3.11) |
| `ssh` | SSH client |
| `ping` | Server reachability check |

> On Debian/Ubuntu: `sudo apt install tmux fzf`  
> On FEDORA/RHEL Familly : 'sudo dnf install tmux fzf'
> Python 3.11+ is required for the built-in `tomllib` module.

---

## 🚀 Quick Start

```bash
git clone https://codeberg.org/youruser/juwassh.git
cd juwassh
cp hosts.toml.example hosts.toml
# Edit hosts.toml with your servers
chmod +x juwassh.sh
./juwassh.sh
```

---

## ⚙️ Configuration — `hosts.toml`

```toml
[settings]
default_user = "root"
default_port = 22
default_key  = "~/.ssh/id_ed25519"
show_user    = true

[groups.homelab]
label = "Home Lab"
color = "green"

  [groups.homelab.servers.proxmox]
  host = "192.168.1.99"
  user = "admin"
  port = 22
  key  = "~/.ssh/id_ed25519"

  [groups.homelab.servers.nas]
  host = "192.168.1.77"

[groups.vps]
label = "VPS"
color = "blue"

  [groups.vps.servers.web01]
  host = "203.0.113.42"
  user = "deploy"
  port = 2222
  key  = "~/.ssh/vps_key"
```

### Available colors

`green` `blue` `yellow` `orange` `white`

---

## 🖥️ Usage

| Key | Action |
|-----|--------|
| `↑ / ↓` | Navigate |
| `Enter` | Connect / Open group |
| `Space` or `Tab` | Multi-select servers |
| `Esc` | Go back / Quit |
| `\` or `8` | Split pane horizontally |
| `\|` or `6` | Split pane vertically |

---

## 🔒 Security Notes

- Juwassh **never stores passwords**. Authentication relies on SSH keys.
- `password_fallback = true` simply lets `ssh` fall back to its default behavior — no password is stored in the config.
- The TOML file contains **no sensitive credentials** and is safe to version-control (as long as your key paths are correct).

---

## 📁 Project Structure

```
juwassh/
├── juwassh.sh          # Main script
├── hosts.toml          # Your server list (ignored by git)
├── hosts.toml.example  # Example config to get started
├── LICENSE
└── README.md
```

---

## 📜 License

MIT — do whatever you want, just keep the credits. ☀️

---

## 🤝 Contributing

Issues and pull requests are welcome on [Codeberg](https://codeberg.org/youruser/juwassh).  
If Juwassh saved you time, a ⭐ is always appreciated!
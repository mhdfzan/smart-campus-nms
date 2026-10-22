# Setup guide (from scratch)

Follow this top to bottom. You do not need to understand the code. Commands go into a **Linux terminal** (Ubuntu).

## 1. What you need

| | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 6+ cores |
| RAM | 8 GB free for Ubuntu/WSL | 12-16 GB |
| Disk | 25 GB free | 40 GB |
| Internet | yes (downloads about 3 GB of images) | |
| OS | Ubuntu 22.04 / 24.04 (native, VM or **WSL2 on Windows 10/11**) | |

Time: about 20-30 minutes for the first setup, mostly waiting for downloads and OpenNMS to start.

## 2. Install the tools (one time)

### Option A: Ubuntu (native or virtual machine)
```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 git curl python3 unzip
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```
Now **log out and log back in** (or reboot). Then check:
```bash
docker ps
```
You should see a table header (`CONTAINER ID  IMAGE ...`) and no error.

VM users: give the VM 4+ CPUs and 8+ GB RAM, and use **bridged or NAT** networking with internet access.

### Option B: Windows 10/11 with WSL2
1. In **PowerShell as Administrator**: `wsl --install -d Ubuntu`, then restart Windows and finish the Ubuntu first-run (create a username and password).
2. Give WSL enough memory. In PowerShell run `notepad $env:USERPROFILE\.wslconfig`, paste, save:
   ```
   [wsl2]
   memory=8GB
   processors=4
   ```
   (use `memory=6GB` if your PC has only 8 GB in total, and close other programs).
3. In PowerShell run `wsl --shutdown`, then open **Ubuntu** from the Start menu.
4. Inside Ubuntu run the same commands as Option A:
   ```bash
   sudo apt update
   sudo apt install -y docker.io docker-compose-v2 git curl python3 unzip
   sudo usermod -aG docker $USER
   sudo service docker start
   ```
5. In PowerShell run `wsl --shutdown` once more and reopen Ubuntu so the group change applies. Check `docker ps` works.
6. After every Windows restart, run `sudo service docker start` before using the project.

(Docker Desktop for Windows with *WSL integration* enabled for Ubuntu also works; then skip the `docker.io` install.)

> **Important for WSL:** work inside the Linux home folder (`~`), never inside `/mnt/c/...`. Files there are slow and cause permission and line-ending problems.

## 3. Get the project
```bash
cd ~
git clone <REPOSITORY-URL>
cd <REPOSITORY-FOLDER>
```
(Replace the placeholders with the repository URL and folder name you were given.)

## 4. Run the setup
```bash
bash setup.sh
```
What it does, with typical times:
1. checks Docker, memory and free ports (seconds)
2. downloads and builds all containers (5-10 min the first time)
3. waits for OpenNMS and adds the 4 campus devices (3-5 min)
4. switches OpenNMS to 30-second polling and restarts it so alarms appear quickly (3-5 min)
5. runs a health check and prints the web addresses

It is finished when you see **"Setup finished"** and every health-check line says `OK`. If a line says `FAIL`, wait 2 minutes and run `bash scripts/check_stack.sh` again.

Options: `bash setup.sh --no-fast-polling` keeps OpenNMS's default 5-minute polling (alarm tests then take up to about 15 minutes each).
Running `setup.sh` again is safe.

## 5. Look around (2 minutes)
| Service | Address | Login |
|---|---|---|
| Grafana | http://localhost:3000/d/campus-overview | admin / campus123 (skip any "change password" prompt) |
| OpenNMS | http://localhost:8980/opennms | admin / admin |
| Prometheus | http://localhost:9090/targets | none |

On WSL, open these in your normal Windows browser. In Grafana you should see green **UP** boxes and live graphs. In OpenNMS go to **Inventory → Nodes** (left sidebar) to see 4 nodes.

## 6. Run the tests
```bash
bash scripts/run_tests.sh
```
Then follow **[TESTING.md](TESTING.md)**.

## 7. Everyday commands
```bash
docker compose ps                  # what is running
docker compose stop                # pause everything (keeps data)
docker compose up -d               # start again (OpenNMS needs 3-5 min)
docker compose down                # remove containers (keeps data)
docker compose down -v             # remove containers AND all data (clean reset; then run setup.sh again)
```
After a reboot: (WSL: `sudo service docker start`), then `cd` into the project and `docker compose up -d`.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `permission denied ... docker.sock` | Your user is not in the docker group yet: `sudo usermod -aG docker $USER`, then close and reopen the terminal (WSL: `wsl --shutdown` in PowerShell, reopen Ubuntu). |
| `Cannot connect to the Docker daemon` | Docker is not running: `sudo service docker start` (or start Docker Desktop). |
| `docker: 'compose' is not a docker command` | `sudo apt install -y docker-compose-v2` |
| `bad interpreter` / `\r: command not found` | The files have Windows line endings (project was copied from Windows). Re-clone inside Linux with `git clone`, or run `sudo apt install -y dos2unix && find . -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.py" \) -exec dos2unix {} +`. |
| Ports in use (`8980`, `3000`, ...) | Another program uses them. Stop it, or a previous copy of this project: `docker compose down`. |
| `Pool overlaps with other one` / subnet error | Another Docker network uses 172.28.0.0/24: `docker network prune`, or stop the other project. |
| OpenNMS never becomes ready, containers restarting, machine freezes | Not enough RAM. Give Ubuntu/WSL 8 GB+, close other programs, then `docker compose restart opennms`. Look at `docker compose logs opennms \| tail -50`. |
| `manifest unknown` for the OpenNMS image | The pinned version is unavailable. Run `OPENNMS_VERSION=latest bash setup.sh`. |
| Grafana shows "No data" | Wait 2 minutes, press Ctrl+F5, set time range to "Last 30 minutes". Check http://localhost:9090/targets. |
| Setup stops with an error you cannot fix | Run `bash scripts/collect_logs.sh` and send the generated `diagnostics-*.txt` file to the project owner. |

## 9. Security note
This is a lab prototype with default passwords (admin/admin, admin/campus123, labuser/labpass), SNMPv2c community `public`, and plain HTTP. Run it only on a private machine or network and never expose its ports to the internet.

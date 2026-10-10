# Omallama

Run and monitor a local [llama.cpp](https://github.com/ggml-org/llama.cpp) server from the [Omarchy](https://omarchy.org) bar.

![Omallama panel](preview.png)

Click the chip icon in the bar to open a panel where you can start and stop the server, watch the GPU, memory and tokens per second, and manage your local GGUF models. Stopping the server when you are not coding gives the VRAM and RAM straight back.

## Quick start

Omallama controls a local `llama serve` (or standalone `llama-server`), so it needs two things that are not part of the plugin: **llama.cpp** and **a model**. You do those once. The panel's setup screen does the rest (the background service) and walks you through each step.

**1. Install the plugin and put it on the bar**

```bash
omarchy plugin add https://github.com/dexterhere/omallama.git --enable
omarchy bar put dexterhere.omallama
```

Plugins run unsandboxed, so read the code first. See [Install](#install).

**2. Install llama.cpp** (skip this if you already have `llama` or `llama-server`; it is found in your `PATH`, `~/.local/bin`, `~/llama.cpp/build/bin`, `~/Work/llama.cpp/build/bin`, `/usr/local/bin` and a few other places)

Use the [llama.app installer](https://llama.app/docs/installation). It auto-detects your platform and GPU and installs a suitable binary:

```bash
curl -LsSf https://llama.app/install.sh | sh
```

Verify with `llama cli --version`. The setup screen's **Copy install command** copies this same command. Alternatively, use **Copy build command** or the [source-build instructions](#building-llamacpp) below.

**3. Get a model.** Any `.gguf` works. Qwen2.5-Coder 7B (4.4 GB) suits a 6 GB GPU; the setup screen suggests a size that fits your memory:

```bash
mkdir -p ~/models && curl -L -C - -o ~/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf
```

Or add a file you already have from the panel with the folder icon.

**4. Open the panel.** Click the chip icon in the bar. The setup screen checks each step and shows what is missing. Click **Install service**, then the power button to start the server. It listens on `http://localhost:8080/v1`.

## Features

- **Start, stop and restart** the server from the bar. Middle-click the icon to toggle it without opening the panel.
- **Live graphs** for GPU load and temperature, VRAM (or shared memory on integrated graphics), RAM and tokens per second.
- **Model manager**: finds every `.gguf` on the machine, shows size, quantization and whether it fits your hardware, switches the active model, shows it in your file manager, and deletes it after a confirmation.
- **Add a model** with a normal file chooser. The file's GGUF header is verified before it is added.
- **Search**: the list shows three models at a time, with a search box when you have more.
- **Settings**: context windows from 4k to 1M, GPU or CPU offload, compact KV cache, port, extra server arguments (Enter to apply), stop-when-idle, start at login, and one-click Zed and Pi configs.
- **First-run onboarding** that checks llama.cpp, your graphics, the service and your models, and fixes what it can.
- **Hardware aware**: NVIDIA, AMD (discrete and APU), Intel (Arc and integrated) or no GPU at all.

## Requirements

- Omarchy with the Quickshell-based shell.
- A `llama` dispatcher or standalone `llama-server` binary from llama.cpp. If you do not have one, the onboarding copies the llama.app installer command, which auto-detects your GPU.
- `systemd` user services, `curl`, `bash`.

For GPU stats on NVIDIA you need the driver utilities (`nvidia-smi`, package `nvidia-utils`). AMD and Intel stats are read from `/sys`, so nothing extra is needed.

Optional, and the onboarding tells you which are missing:

| Tool (Arch package) | Used for |
| --- | --- |
| `wl-clipboard` | copy and paste buttons |
| `libnotify` | the "stopped after idle" notice |
| `python-gobject` (or `zenity` / `kdialog`) | the file chooser |
| `xdg-utils`, `nautilus` | opening folders and showing a model in the file manager (Nautilus selects the file; other managers just open the folder) |
| `pciutils` | the GPU name |
| `journalctl` (systemd), Omarchy's `omarchy-launch-tui` | the "View logs" button |

## Install

```bash
omarchy plugin add https://github.com/dexterhere/omallama.git --enable
```

Plugins run unsandboxed inside `omarchy-shell`. Read the code before enabling it. Omallama can start a local server and delete model files you confirm.

Then put the widget on your bar:

```bash
omarchy bar put dexterhere.omallama
```

## First run

Open the panel. If anything is missing you land on the setup screen:

| Step | What it checks | If it is red |
| --- | --- | --- |
| llama.cpp server | a `llama` or `llama-server` binary on this machine | **Copy install command** or **Copy build command** |
| Graphics | your GPU and whether your build can use it | **Copy install command** or **Copy build command** |
| Background service | the `omallama` systemd user service | **Install service** |
| A model | at least one `.gguf`, and an active one | **Add from files**, or **Copy download** for a size that fits your memory |
| Helper tools | clipboard, notifications, file chooser | **Copy install command** |

The service file and its settings are generated for you in `~/.config/systemd/user/omallama.service` and `~/.config/omallama/env`. Omallama only writes its own files, and only when you click **Install service** or **Reinstall service**. If you edited the service file by hand, the previous copy is saved as `omallama.service.bak` before it is replaced. It also creates an empty `~/models` folder if you have none.

## Building llama.cpp

As an alternative to the llama.app installer, build a standalone `llama-server` with the commands below (Arch package names). The server and graphics setup steps offer both **Copy install command** and **Copy build command** when action is needed; the build command matches your detected GPU.

**NVIDIA (CUDA)**

```bash
sudo pacman -S --needed cuda cmake git
export NVCC_CCBIN=${NVCC_CCBIN:-/usr/bin/g++-15} PATH=$PATH:/opt/cuda/bin
git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=native -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4 --target llama-server
```

**AMD, Intel or integrated graphics (Vulkan)**

```bash
sudo pacman -S --needed vulkan-headers vulkan-icd-loader shaderc cmake git
git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4 --target llama-server
```

**No GPU (CPU only)**

```bash
sudo pacman -S --needed cmake git
git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4 --target llama-server
```

If `~/llama.cpp` already exists, skip the clone command and use that checkout. On other distributions install the same toolchain with your package manager.

## Integrated graphics

An integrated GPU has no memory of its own, so Omallama shows **shared memory** (how much system RAM the server holds) instead of VRAM, and judges whether a model fits against about half of your RAM. Intel GPUs expose no unprivileged utilization counter, so the GPU card shows `n/a` for load. A Vulkan build of llama.cpp is needed to use an integrated GPU; otherwise models run on the CPU.

## Models

Omallama lists cached models by repository and quantization using `llama cli --cache-list`, and starts a selected cache entry with `llama serve -hf owner/repository:quant`. Cache sizes are read from the Hugging Face revision in `refs/main`: snapshot filenames are matched by quantization, symlinks are followed for file sizes, and split shards are summed. `HF_HUB_CACHE`, `HF_HOME` and `XDG_CACHE_HOME` are respected. Missing revisions/files show unknown size; cache file actions remain hidden. With standalone binaries it uses `llama-server --cache-list` and `-hf` instead.

Local `.gguf` files are scanned in `~/models`, LM Studio, Downloads, Documents, `/opt`, `/srv`, `/mnt`, `/run/media`, a shallow sweep of your home folder, and anything you add yourself. Vision projectors and non-first shards are skipped. Local files still start with `-m`.

After updating, run `omarchy restart shell` if the UI still shows old controls: a plugin rescan may retain cached QML/JavaScript. For an existing installation, click Settings → Tools → **Reinstall service** once to enable dispatcher startup and cached selections. Settings are kept and the previous service is backed up. Larger contexts need more memory and must be supported by the model.

Deleting removes the real file from disk after you confirm in the panel. The active model cannot be deleted.

## Use it from Pi

Settings → Tools → **Copy Pi config** copies a provider snippet for the selected model, port and context window. Merge its `providers.omallama` entry into `~/.pi/agent/models.json` (keep other providers), then select it with Pi's `/model`. The dummy API key is for a local unauthenticated server. Tool calling requires a capable model/chat template; add `--jinja` to Extra arguments if needed. The plugin does not modify Pi's files.

## Use it from Zed

Settings → Tools → **Copy Zed config** copies a ready-made `language_models` snippet for the active model. Paste it into Zed's `settings.json` and add any API key in Zed's agent settings. The server speaks the OpenAI API at `http://localhost:8080/v1`.

## Commands

```bash
omarchy-shell dexterhere.omallama toggle         # open or close the panel
omarchy-shell dexterhere.omallama toggleServer   # start or stop llama-server
omarchy-shell dexterhere.omallama restartServer
omarchy-shell dexterhere.omallama rescan         # rescan for models
omarchy-shell dexterhere.omallama browse         # open the file chooser
omarchy-shell dexterhere.omallama setup          # show or hide the setup screen
```

## Files

| Path | Purpose |
| --- | --- |
| `Panel.qml` | bar icon and panel |
| `Model.js` | parsing and formatting, covered by `tests/run.js` |
| `sample.sh` | one sample of GPU, memory and server state |
| `doctor.sh`, `setup.sh` | environment check, service installer and remover |
| `setmodel.sh` | writes settings and the added-models list |
| `scan.sh` | finds models on the machine |
| `browse.sh`, `pick.py` | file chooser for adding models |
| `lib.sh` | binary lookup and GPU detection |

## Uninstall

Removing a plugin cannot run cleanup code, so stop the service first:

1. Open the panel, then Settings → Tools → **Uninstall service**. It stops the server and deletes the `omallama` systemd user service. Your models and settings are kept.
2. Remove the plugin:

```bash
omarchy plugin remove dexterhere.omallama
```

Everything Omallama created lives in two places. To erase all of it, including your saved settings and added-models list (your model files are never touched):

```bash
systemctl --user disable --now omallama
rm -f ~/.config/systemd/user/omallama.service
rm -rf ~/.config/omallama
systemctl --user daemon-reload
```

## Development

```bash
npm test
```

runs the model tests, GPU detection tests (fake sysfs trees for Intel, AMD, NVIDIA and no GPU), scanner/cache/settings regression tests, and service installation/removal tests. The AMD and Intel paths are tested that way; they have not been run on that hardware yet. Reports from real machines are welcome.

`npm run test:ui` uses Python 3 and Qt's `qmltestrunner` to check the actual port/extra-argument bindings offscreen: drafts survive refreshes and Enter submits them.

After editing QML, `omarchy restart shell` makes the change show reliably.

## License

MIT

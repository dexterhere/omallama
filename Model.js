var HISTORY = 60

var Glyph = { chip: "\uf2db", power: "\uf011", refresh: "\uf021", check: "\uf00c", trash: "\uf1f8", folder: "\uf07b", folderOpen: "\uf07c", copy: "\uf0c5", gear: "\uf013", paste: "\uf0ea", close: "\uf00d" }

function parseSample(raw) {
  var out = {}
  var added = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("=")
    if (lines[i].indexOf("added=") === 0) added.push(lines[i].substring(6))
    else if (idx > 0) out[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  var n = function(k) { var v = parseFloat(out[k]); return isFinite(v) ? v : 0 }
  var memTotal = n("mem_total")
  var integrated = out.gpu_integrated === "1"
  var serverRssMb = Math.round(n("server_rss") / 1024)
  var ramTotalMb = Math.round(memTotal / 1024)
  var hasUtil = out.gpu_util !== undefined && n("gpu_util") >= 0
  return {
    gpuKind: out.gpu_kind || "none",
    integrated: integrated,
    ramTotalMb: ramTotalMb,
    hasUtil: hasUtil,
    state: out.state || "inactive",
    ready: out.health === "ok",
    ramPct: memTotal ? Math.round((1 - n("mem_avail") / memTotal) * 100) : 0,
    ramFreeMb: Math.round(n("mem_avail") / 1024),
    swapMb: Math.round(n("swap_used") / 1024),
    // Integrated GPUs have no memory of their own: show what the server holds of shared system RAM.
    vramUsedMb: integrated ? serverRssMb : n("vram_used"),
    vramTotalMb: integrated ? ramTotalMb : n("vram_total"),
    vramPct: integrated ? (ramTotalMb ? Math.round(serverRssMb / ramTotalMb * 100) : 0)
      : n("vram_total") ? Math.round(n("vram_used") / n("vram_total") * 100) : 0,
    gpuUtil: hasUtil ? n("gpu_util") : 0,
    gpuTemp: Math.max(0, n("gpu_temp")),
    serverRssMb: serverRssMb,
    tps: n("tps"),
    ctx: n("ctx"),
    uptime: n("uptime"),
    activeModel: out.active_model || "",
    busy: n("busy") > 0,
    port: parseInt(out.cfg_PORT, 10) || 8080,
    ngl: out.cfg_NGL === undefined || out.cfg_NGL === "" ? 99 : n("cfg_NGL"),
    compactKv: /q8_0/.test(out.cfg_KV || ""),
    extraArgs: out.cfg_EXTRA || "",
    autoStopMin: n("cfg_AUTOSTOP"),
    atLogin: out.enabled === "enabled",
    added: added
  }
}

// Every word of the query must appear in the model's name, quant, size class or source.
function filterModels(rows, query) {
  var words = String(query || "").toLowerCase().split(/\s+/).filter(function(w) { return w !== "" })
  if (words.length === 0) return rows
  return rows.filter(function(r) {
    var hay = (r.name + " " + r.quant + " " + r.params + " " + r.source + " " + r.file).toLowerCase()
    return words.every(function(w) { return hay.indexOf(w) >= 0 })
  })
}

function activeFirst(rows, activePath) {
  return rows.slice().sort(function(a, b) { return (b.path === activePath) - (a.path === activePath) })
}

function sourceLabel(path, home) {
  var p = String(path)
  if (p.indexOf(home + "/models/") === 0) return "~/models"
  if (p.indexOf("/huggingface/") >= 0) return "Hugging Face cache"
  if (p.indexOf("/.lmstudio/") >= 0) return "LM Studio"
  if (p.indexOf("/llama.cpp/") >= 0 && p.indexOf(home + "/Work/") !== 0) return "llama.cpp cache"
  if (p.indexOf(home + "/") === 0) return "~/" + p.substring(home.length + 1).split("/").slice(0, -1).slice(0, 2).join("/")
  return p.split("/").slice(0, -1).join("/")
}

// One "bytes|path" line per model, as printed by scan.sh.
function parseModels(raw, home) {
  var rows = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("|")
    if (idx < 1) continue
    var r = modelRow(lines[i].substring(idx + 1), parseFloat(lines[i].substring(0, idx)))
    r.source = sourceLabel(r.path, home)
    r.deletable = r.path.indexOf(home + "/models/") === 0
    rows.push(r)
  }
  rows.sort(function(a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0 })
  return rows
}

function modelRow(path, bytes) {
  var file = String(path || "").split("/").pop()
  var name = file.replace(/\.gguf$/i, "")
  var q = /(q\d(?:_[a-z0-9]+)+|iq\d(?:_[a-z0-9]+)*|f16|bf16|f32)/i.exec(name)
  var size = /(\d+(?:\.\d+)?)b(?![a-z])/i.exec(name)
  return {
    path: path, file: file,
    name: name.replace(/[-_.]?(q\d(?:_[a-z0-9]+)+|iq\d(?:_[a-z0-9]+)*|f16|bf16|f32)$/i, ""),
    quant: q ? q[1].toUpperCase() : "",
    params: size ? size[1] + "B" : "",
    sizeMb: Math.round(bytes / 1048576)
  }
}

// Weights plus roughly 1 GB for KV cache and CUDA buffers.
function fitVerdict(sizeMb, vramTotalMb) {
  if (!vramTotalMb) return { text: "?", level: 0 }
  var need = sizeMb + 1024
  if (need <= vramTotalMb) return { text: "Fits GPU", level: 0 }
  if (sizeMb <= vramTotalMb * 1.8) return { text: "Partial offload", level: 1 }
  return { text: "Too large", level: 2 }
}

// Fit of a model on this machine's accelerator: discrete VRAM, half of shared RAM for an iGPU, or CPU only.
function fitFor(sizeMb, s) {
  if (s.gpuKind === "none") return { text: "CPU only", level: 1 }
  if (s.integrated) {
    var v = fitVerdict(sizeMb, s.ramTotalMb / 2)
    return v.level === 0 ? { text: "Fits shared RAM", level: 0 } : v
  }
  return fitVerdict(sizeMb, s.vramTotalMb)
}

function gpuHeading(s) { return s.gpuKind === "none" ? "CPU" : "GPU" }
function memHeading(s) { return s.integrated ? "Shared memory" : "VRAM" }
function gpuText(s) {
  if (s.gpuKind === "none") return "no GPU"
  var load = s.hasUtil ? s.gpuUtil + "%" : "n/a"
  return s.gpuTemp > 0 ? load + "  ·  " + s.gpuTemp + "°C" : load
}

function fmtUptime(sec) {
  var s = Math.floor(sec || 0)
  if (s < 60) return s + "s"
  if (s < 3600) return Math.floor(s / 60) + "m"
  return Math.floor(s / 3600) + "h " + Math.floor(s % 3600 / 60) + "m"
}

function ctxLabel(n) { return n >= 1024 ? (n / 1024) + "k" : String(n) }

function parseDoctor(raw) {
  var o = {}
  String(raw || "").split("\n").forEach(function(l) {
    var i = l.indexOf("=")
    if (i > 0) o[l.substring(0, i)] = l.substring(i + 1).trim()
  })
  var list = function(v) { return v ? v.split(",").filter(function(x) { return x !== "" }) : [] }
  return {
    loaded: true,
    bin: o.bin || "",
    binVersion: o.bin_version || "",
    devices: list(o.devices),
    gpuKind: o.gpu_kind || "none",
    integrated: o.gpu_integrated === "1",
    gpuName: o.gpu_name || "",
    driverMissing: o.gpu_driver === "missing",
    ramTotalMb: parseFloat(o.ram_total_mb) || 0,
    unitInstalled: o.unit === "installed",
    missing: list(o.missing_tools)
  }
}

var EMPTY_DOCTOR = { loaded: false, bin: "", binVersion: "", devices: [], gpuKind: "none", integrated: false, gpuName: "",
  driverMissing: false, ramTotalMb: 0, unitInstalled: false, missing: [] }

// Does this llama.cpp build have a backend for the machine's GPU?
function accelerated(d) {
  var has = function(k) { return d.devices.indexOf(k) >= 0 }
  if (d.gpuKind === "nvidia") return has("cuda")
  if (d.gpuKind === "amd") return has("vulkan") || has("rocm") || has("hip")
  if (d.gpuKind === "intel") return has("vulkan") || has("sycl") || has("opencl")
  return true
}

function needsSetup(d) { return d.loaded && (d.bin === "" || !d.unitInstalled) }

function backendName(kind) { return kind === "nvidia" ? "CUDA" : kind === "none" ? "CPU" : "Vulkan" }

function deviceSummary(d) {
  if (d.gpuKind === "none") return "No GPU found — models will run on the CPU"
  var what = d.gpuName || (d.gpuKind + " graphics")
  if (d.driverMissing) return what + " — NVIDIA driver (nvidia-smi) not installed"
  if (!d.bin) return what + (d.integrated ? " · integrated, shares system RAM" : "")
  if (accelerated(d)) return what + " · " + backendName(d.gpuKind) + (d.integrated ? " · shares system RAM" : "")
  return what + " — your llama.cpp has no " + backendName(d.gpuKind) + " support, so it will use the CPU"
}

// Shell command that builds a llama-server matching the GPU (Arch package names).
function buildCommand(kind) {
  var flag = kind === "nvidia" ? " -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=native" : kind === "none" ? "" : " -DGGML_VULKAN=ON"
  var pkgs = kind === "nvidia" ? "cuda cmake git" : kind === "none" ? "cmake git" : "vulkan-headers vulkan-icd-loader shaderc cmake git"
  var env = kind === "nvidia" ? "export NVCC_CCBIN=${NVCC_CCBIN:-/usr/bin/g++-15} PATH=$PATH:/opt/cuda/bin && " : ""
  return "sudo pacman -S --needed " + pkgs + " && " + env
    + "git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/llama.cpp && cd ~/llama.cpp && "
    + "cmake -B build" + flag + " -DCMAKE_BUILD_TYPE=Release && cmake --build build -j4 --target llama-server"
}

// A starter Qwen2.5-Coder size that fits the machine, as a download command.
function starterModel(budgetMb) {
  var pick = budgetMb >= 5600 ? ["7B", "qwen2.5-coder-7b-instruct-q4_k_m.gguf", "4.4 GB"]
    : budgetMb >= 3500 ? ["3B", "qwen2.5-coder-3b-instruct-q4_k_m.gguf", "2.0 GB"]
    : ["1.5B", "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf", "1.1 GB"]
  var repo = "Qwen/Qwen2.5-Coder-" + pick[0] + "-Instruct-GGUF"
  return { label: "Qwen2.5-Coder " + pick[0] + " (" + pick[2] + ")",
    command: "mkdir -p ~/models && curl -L -C - -o ~/models/" + pick[1] + " https://huggingface.co/" + repo + "/resolve/main/" + pick[1] }
}

var TOOL_PACKAGES = { "wl-copy": "wl-clipboard", "wl-paste": "wl-clipboard", "notify-send": "libnotify", "xdg-open": "xdg-utils",
  lspci: "pciutils", "python-gi": "python-gobject", curl: "curl", systemctl: "systemd", journalctl: "systemd" }

function missingPackages(tools) {
  var seen = {}
  return tools.map(function(t) { return TOOL_PACKAGES[t.replace("!", "")] || t }).filter(function(p) { return !seen[p] && (seen[p] = true) })
}

function zedConfig(port, alias) {
  return JSON.stringify({ language_models: { openai_compatible: { "llama.cpp": {
    api_url: "http://localhost:" + port + "/v1",
    available_models: [{ name: alias, display_name: alias + " (local)", max_tokens: 8192, max_output_tokens: 2048,
      capabilities: { tools: false, images: false, parallel_tool_calls: false, prompt_cache_key: false } }]
  } } } }, null, 2)
}

function validPort(v) { var n = parseInt(v, 10); return /^\d+$/.test(String(v)) && n >= 1024 && n <= 65535 }

function push(history, value) {
  var next = (history || []).concat([value])
  while (next.length > HISTORY) next.shift()
  return next
}

function statusText(s) {
  if (s.state === "active") return s.ready ? "Running · ready" : "Starting…"
  if (s.state === "activating") return "Starting…"
  if (s.state === "failed") return "Failed to start"
  return "Stopped"
}

function isOn(s) { return s.state === "active" || s.state === "activating" }

function gb(mb) { return mb < 1024 ? Math.round(mb) + " MB" : (mb / 1024).toFixed(1) + " GB" }

if (typeof module !== "undefined") module.exports = { fitFor, gpuHeading, memHeading, gpuText, parseDoctor, EMPTY_DOCTOR, accelerated, needsSetup, deviceSummary, buildCommand, starterModel, missingPackages, activeFirst, filterModels, zedConfig, validPort, parseSample, parseModels, sourceLabel, modelRow, fitVerdict, fmtUptime, ctxLabel, push, statusText, isOn, gb, HISTORY }

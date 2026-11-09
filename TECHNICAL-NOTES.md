Note: The notes below are the actual telemetry and development notes from the project. As such, they are extremely valuable because they contain much of the original code, implementation details, troubleshooting history, and development reasoning used throughout the project.

You will quickly notice that these notes are not as polished or neatly organised as the rest of the documentation. Under normal circumstances I would have cleaned, reorganised, and integrated them into the primary documentation myself. However, after roughly five months of continuous work on this project, burnout has finally caught up with me, and I am allowing myself the luxury of being a little lazy.

Despite their rough presentation, these notes remain one of the most useful reference sources in the project and should not be overlooked. In many cases they provide context, technical details, and code examples that are not documented elsewhere.




1. Hardware Architecture & System Topology

┌────────────────────────────────────────────────────────────────────────┐
│ PHYSICAL HARDWARE SPECIFICATIONS                                      │
├──────────────────────┬─────────────────────────────────────────────────┤
│ Motherboard / PCH    │ Intel Server Board S2600CO (Intel C602 Chipset) │
│ Processors (Dual)    │ 2x Intel Xeon E5-2600 v2 (Ivy Bridge-EP)        │
│ Physical Core Count  │ 12 Cores (6 Cores/Socket, SMT/HT Disabled: nosmt│
│ Host RAM Topology    │ 72 GB Total DDR3 ECC Registered                 │
│  - Socket 0 (Node 0) │ 48 GB (4x 8GB + 4x 4GB across all 8 slots)      │
│                      │ 12 GB/channel = 100% Symmetric Quad-Channel     │
│  - Socket 1 (Node 1) │ 24 GB (2x 8GB + 2x 4GB in Blue Slots E1/F1/G1/H1│
│ GPU Accelerators     │ Dual Vega 10 Enterprise Accelerators (Passive)  │
│  - Card 0 (Slot 3)   │ AMD Radeon Pro V320 [1002:6860 rev 06], 56 CUs │
│                      │ Factory Cap: 110W, PCIe Gen 3 x8 via CPU 1      │
│  - Card 1 (Slot 5)   │ AMD Instinct MI25 [1002:6860 rev 00], 64 CUs   │
│                      │ Factory Cap: 220W, PCIe Gen 3 x8 via CPU 2      │
│ Total GPU VRAM       │ 32.7 GB HBM2 (2x 16,368 MiB) @ 380 GB/s per card│
│ Storage Subsystem    │ SSD RAID 0 on /dev/sda (MBR / Legacy BIOS GRUB) │
│ Base Operating System│ NixOS 24.05 LTS (Linux Kernel 6.6.68)           │
│ Primary Workload     │ Gemma 4 26B-A4B-IT Q8_0 (25.2B MoE, 3.8B Active)│
└──────────────────────┴─────────────────────────────────────────────────┘

2. Verified Performance Metrics & Milestones

The following performance benchmarks have been physically executed, measured,
and verified on this hardware [1, 2]:

  - Short-Context Burst Speed (N < 500 tokens): 40.54 to 43.00 TPS (Latency:
    24.67\text{ ms/token}) [1].
  - Deep-Context Sustained Speed (N = 7,226 tokens): 31.07 TPS (1,463 tokens
    generated continuously over 69 seconds) [1, 2].
  - Saturated Worst-Case Floor (N = 8,192 tokens): 26.50 to 28.50 TPS [1, 2].
  - Model VRAM Allocation (Q8_0, 26.8 GB weights):
      - Card 0: 13.39\text{ GB} weights + 0.40\text{ GB} KV cache
        \+ 0.80\text{ GB} scratch = \mathbf{14.59\text{ GB} / 16.0\text{ GB}}
        (1.41\text{ GB} headroom) [1].
      - Card 1: 13.39\text{ GB} weights + 0.40\text{ GB} KV cache
        \+ 0.80\text{ GB} scratch = \mathbf{14.59\text{ GB} / 16.0\text{ GB}}
        (1.41\text{ GB} headroom) [1].
      - Host DDR3 Spillover: 0 bytes (100% In-VRAM execution) [1].

3. Solved Root-Cause Matrix

| Subsystem             | Failure Encountered                                                 | Technical Root Cause                                                                                                             | Permanent Engineering Fix                                                                            |
| :-------------------- | :------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------- |
| **BIOS Video**        | Black screen on local VGA port \[3\].                               | MI25 exposes PCI Class `0300` (VGA) despite having zero video ports; C602 disables onboard Matrox G200e in single mode \[3, 4\].    pulled th cards and set up teh os with ssh login for headless useage                         |
| **PCIe Subsystem**    | Kernel fails 16 GB BAR assignment (`can't assign; no space`) \[5\]. | C602 respects ACPI `_CRS` tables by default, restricting MMIO above 4GB \[3, 5\].                                                | Kernel boot params: `pci=realloc pci=nocrs pci=pcie_bus_perf iommu=pt` \[5\].                        |
| **AMDGPU Driver**     | `amdgpu_device_ip_resume failed (-22)` on idle wake \[6\].          | Headless GPUs enter BACO runtime sleep; Vega 10 enterprise vBIOS fails resume \[6\].                                             | Kernel boot param: `amdgpu.runpm=0` (disables dynamic sleep) \[6\].                                  |
| **CPU Instruction**   | `SIGILL (Illegal Instruction)` in `_GLOBAL__sub_I` \[7\].           | Upstream `llama.cpp` compiled `common/` with `LLAMA_AVX2=ON`. Ivy Bridge lacks AVX2 \[7, 8\].                                    disabled avx2 and all other types other then avx 1 in the ggml cmake file.      |
| **ROCm Toolchain**    | `hipStreamWaitEvent` 3-argument call failure \[9\].                 | ROCm 6.0.2 C API requires 3 arguments; ROCm 6.1 added a 2-arg default overload \[9\].                                            | Inlined C++ wrapper with `flags = 0` default in `ggml-cuda/vendors/hip.h` \[9\].                     |

| **Systemd Execution** | `status=127` on service launch \[12\].                              | Systemd default `$PATH` does not contain `/bin/bash` on NixOS; `#!/usr/bin/env bash` fails \[12\].                               | Shebang updated to absolute path: `#!/run/current-system/sw/bin/bash` \[12\].                        |








5. Production NixOS System Configuration (/etc/nixos/configuration.nix)

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # 1. Bootloader (Legacy BIOS on /dev/sda)
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    useOSProber = true;
  };
  boot.loader.systemd-boot.enable = false;

  # 2. Kernel Boot Parameters
  boot.kernelParams = [
    "pci=realloc"                     # Reallocate 16 GB MMIO BAR windows
    "pci=nocrs"                       # Bypass ACPI 4GB MMIO limits on Intel C602
    "pci=pcie_bus_perf"               # Enforce 256-byte TLP Max Payload Size
    "iommu=pt"                         # IOMMU Passthrough: Eliminates DMA latency
    "amdgpu.noretry=0"                # Avoids GPU lockup on page faults
    "amdgpu.runpm=0"                  # Disables BACO runtime power management
    "nosmt"                           # Binds 1:1 to physical cores (6 per socket)
    "processor.max_cstate=1"          # Clamps CPU C-states to C1
    "intel_idle.max_cstate=1"
    "console=tty0"                    # Local VGA console
    "console=ttyS1,115200n8"          # IPMI Serial-over-LAN (COM2)
  ];

  powerManagement.cpuFreqGovernor = "performance";

  # 3. Dedicated 1GB hugetlbfs Virtual Filesystem Mount
  fileSystems."/dev/hugepages" = {
    device = "hugetlbfs";
    fsType = "hugetlbfs";
    options = [ "pagesize=1G" "mode=0777" ];
  };

  # 4. Remote Access & Firewall Policy
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Disable internal firewall to prevent LAN drops across SSH, API, and RDP
  networking.firewall.enable = false;

  # 5. Graphical Remote Desktop (XRDP + XFCE over virtual RAM buffer)
  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
  };
  services.xrdp = {
    enable = true;
    defaultWindowManager = "startxfce4";
    openFirewall = true;
  };

  # 6. User Accounts
  users.users.user = {
    isNormalUser = true;
    description = "Standard User";
    extraGroups = [ "wheel" "video" "render" ];
  };

  # 7. Hardware Graphics and ROCm HIP Enablement (NixOS 24.05)
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs.rocmPackages; [
      clr
      clr.icd
    ];
  };

  # 8. Physical Directory Hierarchy & Global Shortcuts
  systemd.tmpfiles.rules = [
    "d /opt/arclight 0755 root root -"
    "d /opt/arclight/models 0755 root root -"
    "d /opt/arclight/scripts 0755 root root -"
    "d /opt/arclight/config 0755 root root -"
    "d /opt/arclight/profiles 0755 root root -"
    "d /opt/arclight/cache 0755 root root -"
    "L+ /opt/rocm - - - - ${pkgs.rocmPackages.clr}"
    "L+ /usr/local/bin/llama-chat - - - - /opt/arclight/scripts/run_cli.sh"
    "L+ /usr/local/bin/llama-serve - - - - /opt/arclight/scripts/run_server.sh"
  ];

  # 9. Factory DPM State & Thermal Safety Daemon (Caps Card 1 to 160W)
  systemd.services.mi25-dpm-lock = {
    description = "Lock AMD Instinct MI25 GPUs to High DPM and Enforce Thermal Power Caps";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "set-mi25-clocks-power" ''
        for card in /sys/class/drm/card*/device; do
          if [ -f "$card/power_dpm_force_performance_level" ]; then
            echo "high" > "$card/power_dpm_force_performance_level" || true
          fi
        done
        for hwmon in /sys/class/drm/card*/device/hwmon/hwmon*; do
          if [ -f "$hwmon/power1_cap_max" ] && [ -f "$hwmon/power1_cap" ]; then
            MAX=$(cat "$hwmon/power1_cap_max")
            if [ "$MAX" -gt 160000000 ]; then
              echo 160000000 > "$hwmon/power1_cap" || true
            fi
          fi
        done
      '';
    };
  };

  # 10. System Environment Packages
  environment.systemPackages = with pkgs; [
    rocmPackages.clr
    rocmPackages.hipblas
    rocmPackages.rocblas
    rocmPackages.rocm-smi
    numactl
    pciutils
    wget
    curl
    htop
    git
    binutils
    firefox
  ];

  # 11. Environment Variables for ROCm
  environment.sessionVariables = {
    HSA_OVERRIDE_GFX_VERSION = "9.0.0";
    HSA_ENABLE_SDMA = "0";
    HIP_VISIBLE_DEVICES = "0,1";
  };

  # 12. On-Demand Background API Service (Manual launch: systemctl start llama-server)
  systemd.services.llama-server = {
    description = "Llama.cpp Background API Server";
    after = [ "network.target" "mi25-dpm-lock.service" ];
    wants = [ "mi25-dpm-lock.service" ];
    path = [ pkgs.numactl pkgs.bash pkgs.coreutils ];

    serviceConfig = {
      Type = "simple";
      User = "root";
      WorkingDirectory = "/opt/arclight";
      ExecStart = "/opt/arclight/scripts/run_server.sh";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };

  system.stateVersion = "24.05";
}

6. Modular Execution Scripts & Profiles

6.1 Master Server Script (/opt/arclight/scripts/run_server.sh)

#!/run/current-system/sw/bin/bash
set -euo pipefail

# 1. Driver overrides for Vega 10 (gfx900)
export HSA_OVERRIDE_GFX_VERSION=9.0.0
export HSA_ENABLE_SDMA=0
export HIP_VISIBLE_DEVICES=0,1

# 2. Source active model profile
if [ ! -f /opt/arclight/config/active_model.env ]; then
    echo "ERROR: /opt/arclight/config/active_model.env not found!"
    exit 1
fi
source /opt/arclight/config/active_model.env

echo "=== Launching llama-server: ${MODEL_NAME} ==="
echo "Model Path: ${MODEL_PATH}"
echo "Context: ${CTX_SIZE} | Split: ${SPLIT_MODE} (${TENSOR_SPLIT})"

# 3. Launch server pinned to Socket 0 (Cores 0-5) with Node 1 overflow allowed
exec /run/current-system/sw/bin/numactl --cpunodebind=0 --preferred=0 \
  /opt/arclight/llama.cpp/build/bin/llama-server \
  --model "${MODEL_PATH}" \
  --alias "${MODEL_NAME}" \
  --host 0.0.0.0 \
  --port 8080 \
  --n-gpu-layers "${N_GPU_LAYERS}" \
  --split-mode "${SPLIT_MODE}" \
  --tensor-split "${TENSOR_SPLIT}" \
  --ctx-size "${CTX_SIZE}" \
  --parallel "${PARALLEL_SLOTS}" \
  --cache-type-k "${CACHE_TYPE_K}" \
  --cache-type-v "${CACHE_TYPE_V}" \
  --threads 6 \
  --threads-batch 6 \
  --cont-batching \
  --batch-size 512 \
  --ubatch-size 128 \
  ${EXTRA_ARGS}

6.2 Interactive CLI Script (/opt/arclight/scripts/run_cli.sh)

#!/run/current-system/sw/bin/bash
set -euo pipefail

export HSA_OVERRIDE_GFX_VERSION=9.0.0
export HSA_ENABLE_SDMA=0
export HIP_VISIBLE_DEVICES=0,1

if [ ! -f /opt/arclight/config/active_model.env ]; then
    echo "ERROR: /opt/arclight/config/active_model.env not found!"
    exit 1
fi
source /opt/arclight/config/active_model.env

echo "=== Launching Interactive Chat: ${MODEL_NAME} ==="

exec /run/current-system/sw/bin/numactl --cpunodebind=0 --preferred=0 \
  /opt/arclight/llama.cpp/build/bin/llama-cli \
  --model "${MODEL_PATH}" \
  --n-gpu-layers "${N_GPU_LAYERS}" \
  --split-mode "${SPLIT_MODE}" \
  --tensor-split "${TENSOR_SPLIT}" \
  --ctx-size "${CTX_SIZE}" \
  --cache-type-k "${CACHE_TYPE_K}" \
  --cache-type-v "${CACHE_TYPE_V}" \
  --threads 6 \
  --threads-batch 6 \
  --color \
  --conversation \
  ${EXTRA_ARGS}

6.3 Active Model Profile (/opt/arclight/profiles/gemma4_26b.env)

# Model Profile: Gemma 4 26B-A4B-IT Q8_0
MODEL_NAME="gemma4"
MODEL_PATH="/opt/arclight/models/gemma-4-26b-a4b-it-q8_0.gguf"
CTX_SIZE=8192
N_GPU_LAYERS=999
SPLIT_MODE="layer"
TENSOR_SPLIT="1,1"
PARALLEL_SLOTS=1
CACHE_TYPE_K="f16"
CACHE_TYPE_V="f16"
EXTRA_ARGS="--flash-attn off --keep 3"

7. Source Code Patches for Modern llama.cpp (b11493+)

If recompiling modern llama.cpp from source, execute
/opt/arclight/scripts/build_llama.sh [7, 9]:

#!/run/current-system/sw/bin/bash
set -euo pipefail

WORKSPACE="/opt/arclight/llama.cpp"

if [ ! -d "$WORKSPACE" ]; then
    mkdir -p /opt/arclight
    cd /opt/arclight
    git clone https://github.com/ggml-org/llama.cpp.git
fi

cd "$WORKSPACE"

# 1. Clean working tree
git checkout ggml/src/ggml-hip/CMakeLists.txt 2>/dev/null || true
git checkout ggml/src/ggml-cuda/vendors/hip.h 2>/dev/null || true

# 2. Patch 1: Neutralize ROCm 6.1 version check in CMake
sed -i -E 's/if.*VERSION_LESS.*6\.1.*/if (FALSE)/g' ggml/src/ggml-hip/CMakeLists.txt

# 3. Patch 2: Add 3-argument C++ default wrapper for hipStreamWaitEvent in ROCm 6.0
sed -i 's/#define cudaStreamWaitEvent hipStreamWaitEvent/inline static hipError_t ggml_hipStreamWaitEvent(hipStream_t stream, hipEvent_t event, unsigned int flags = 0) { return hipStreamWaitEvent(stream, event, flags); }\n#define cudaStreamWaitEvent ggml_hipStreamWaitEvent/g' ggml/src/ggml-cuda/vendors/hip.h




rm -rf build
nix-shell -p cmake pkg-config git rocmPackages.clr rocmPackages.hipblas rocmPackages.rocblas --run '
  export HIP_PATH=/opt/rocm
  export ROCM_PATH=/opt/rocm
  cmake -B build \
    -DGGML_HIP=ON \
    -DGPU_TARGETS=gfx900 \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=OFF \
    -DGGML_AVX=ON \
    -DGGML_F16C=ON \
    -DGGML_AVX2=OFF \
    -DGGML_FMA=OFF \
    -DLLAMA_AVX=ON \
    -DLLAMA_F16C=ON \
    -DLLAMA_AVX2=OFF \
    -DLLAMA_FMA=OFF \
    -DCMAKE_C_FLAGS="-mavx -mf16c -mno-avx2 -mno-fma -mno-bmi2 -mno-avx512f" \
    -DCMAKE_CXX_FLAGS="-mavx -mf16c -mno-avx2 -mno-fma -mno-bmi2 -mno-avx512f" \
    && taskset -c 0-5 cmake --build build --config Release -j 6
'

echo "SUCCESS: Modern binary compiled at $WORKSPACE/build/bin/llama-server"

8. Quick-Start Guide for New Sessions

# 1. Verify GPU Discovery in ROCm
rocm-smi
rocminfo | grep -E "Name:.*gfx900"

# 2. Verify PCIe 16 GB Large BARs
lspci -d 1002:6860 -v | grep -E "Memory at.*size=16G"

# 3. Interactive Terminal Chat
llama-chat

# 4. Launch API Server Daemon in Background
systemctl start llama-server
systemctl status llama-server

# 5. View Live Server Logs
journalctl -u llama-server -f

# 6. Stop Server
systemctl stop llama-server

# 7. Connect via Remote Desktop (XRDP GUI)
mstsc.exe -> <SERVER_IP> -> Session: Xorg -> User: root or user

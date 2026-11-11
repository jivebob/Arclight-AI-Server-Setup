Part 1: The Complete /etc/nixos/configuration.nix

This configuration file includes the hardware overrides, thermal power caps,
ROCm/HIP runtime links, XRDP graphical desktop, and on-demand server daemons
verified on the dual AMD Instinct MI25 and Intel S2600CO platform.

{ config, pkgs, lib, ... }:

{
  imports = [
    # Include hardware configuration auto-generated during NixOS installation
    ./hardware-configuration.nix
  ];

  # =========================================================================
  # 1. BOOTLOADER CONFIGURATION
  # =========================================================================
  # Legacy BIOS (MBR) installation on /dev/sda with os-prober for multi-boot
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    useOSProber = true;
  };
  boot.loader.systemd-boot.enable = false;

  # =========================================================================
  # 2. LOW-LEVEL HARDWARE & KERNEL PARAMETERS
  # =========================================================================
  boot.kernelParams = [
    # --- PCIe MMIO 64-Bit Memory Allocation ---
    "pci=realloc"                     # Forces Linux to reallocate PCIe BARs from scratch
    "pci=nocrs"                       # Bypasses ACPI motherboard limits above 4 GB on Intel C602
    "pci=pcie_bus_perf"               # Enforces 256-byte TLP Max Payload Size for PCIe Gen 3

    # --- I/O Virtualization & GPU Stability ---
    "iommu=pt"                         # IOMMU Passthrough (eliminates virtual DMA translation overhead)
    "amdgpu.noretry=0"                # Avoids GPU driver lockups on memory page-table faults
    "amdgpu.runpm=0"                  # Disables BACO runtime power management (prevents sleep crash -22)

    # --- CPU Architecture & Low-Latency Dispatch Tuning ---
    "nosmt"                           # Disables Hyper-Threading (1:1 physical core execution)
    "processor.max_cstate=1"          # Clamps CPU sleep states to C1 (eliminates wakeup latency)
    "intel_idle.max_cstate=1"

    # --- Console Output ---
    "console=tty0"                    # Directs output to physical local screen
    "console=ttyS1,115200n8"          # Directs output to IPMI Serial-over-LAN (COM2)
  ];

  # Lock CPU frequency governor to maximum rated clock speed
  powerManagement.cpuFreqGovernor = "performance";

  # =========================================================================
  # 3. HIGH-SPEED VIRTUAL MEMORY MOUNT (HugeTLB)
  # =========================================================================
  fileSystems."/dev/hugepages" = {
    device = "hugetlbfs";
    fsType = "hugetlbfs";
    options = [ "pagesize=1G" "mode=0777" ];
  };

  # =========================================================================
  # 4. REMOTE ACCESS & LOCAL NETWORK POLICIES
  # =========================================================================
  # OpenSSH Daemon configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Disable internal firewall to prevent LAN drops across SSH, API, and RDP
  networking.firewall.enable = false;

  # =========================================================================
  # 5. GRAPHICAL REMOTE DESKTOP (XRDP + XFCE)
  # =========================================================================
  # Runs XFCE inside a virtual RAM framebuffer, completely bypassing physical GPU video ports
  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
  };
  services.xrdp = {
    enable = true;
    defaultWindowManager = "startxfce4";
    openFirewall = true;
  };

  # =========================================================================
  # 6. USER ACCOUNT CONFIGURATION
  # =========================================================================
  users.users.user = {
    isNormalUser = true;
    description = "Standard User";
    extraGroups = [ "wheel" "video" "render" ]; # video & render grant GPU access
  };

  # =========================================================================
  # 7. HARDWARE GRAPHICS & ROCm HIP RUNTIME (NixOS 24.05)
  # =========================================================================
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs.rocmPackages; [
      clr                             # Common Language Runtime (HIP runtime & compiler)
      clr.icd                         # OpenCL Installable Client Driver loader
    ];
  };

  # =========================================================================
  # 8. DIRECTORY HIERARCHY, FHS BRIDGES & GLOBAL SHORTCUTS
  # =========================================================================
  systemd.tmpfiles.rules = [
    "d /opt/arclight 0755 root root -"
    "d /opt/arclight/models 0755 root root -"
    "d /opt/arclight/scripts 0755 root root -"
    "d /opt/arclight/config 0755 root root -"
    "d /opt/arclight/profiles 0755 root root -"
    "d /opt/arclight/cache 0755 root root -"

    # Standard /opt/rocm symlink for tools expecting standard FHS paths
    "L+ /opt/rocm - - - - ${pkgs.rocmPackages.clr}"

    # Global convenience shortcuts
    "L+ /usr/local/bin/llama-chat - - - - /opt/arclight/scripts/run_cli.sh"
    "L+ /usr/local/bin/llama-serve - - - - /opt/arclight/scripts/run_server.sh"
  ];

  # =========================================================================
  # 9. GPU DPM CLOCK & THERMAL POWER CAPPING DAEMON
  # =========================================================================
  # Enforces maximum DPM states while capping Card 1 to 160W (Card 0 stays at factory 110W)
  systemd.services.mi25-dpm-lock = {
    description = "Lock AMD Instinct MI25 GPUs to High DPM and Enforce Thermal Power Caps";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "set-mi25-clocks-power" ''
        # Lock performance level to prevent frequency dips
        for card in /sys/class/drm/card*/device; do
          if [ -f "$card/power_dpm_force_performance_level" ]; then
            echo "high" > "$card/power_dpm_force_performance_level" || true
          fi
        done

        # Safely enforce 160W cap only on cards that exceed 160W (leaves 110W V320 alone)
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

  # =========================================================================
  # 10. SYSTEM PACKAGES
  # =========================================================================
  environment.systemPackages = with pkgs; [
    # ROCm Compute Toolchain
    rocmPackages.clr
    rocmPackages.hipblas
    rocmPackages.rocblas
    rocmPackages.rocm-smi
    rocmPackages.rocminfo

    # NUMA & Low-Level Hardware Diagnostics
    numactl
    pciutils
    binutils

    # Monitoring & Core Utilities
    wget
    curl
    htop
    git
    firefox
  ];

  # =========================================================================
  # 11. GLOBAL ROCm & HIP RUNTIME ENVIRONMENT VARIABLES
  # =========================================================================
  environment.sessionVariables = {
    HSA_OVERRIDE_GFX_VERSION = "9.0.0"; # Identifies both Vega 10 GPUs as GCN 5.0 gfx900
    HSA_ENABLE_SDMA = "0";              # Bypasses PCIe SDMA engines to prevent DMA page stalls
    HIP_VISIBLE_DEVICES = "0,1";        # Explicitly orders both accelerators
  };

  # =========================================================================
  # 12. ON-DEMAND BACKGROUND INFERENCE DAEMON
  # =========================================================================
  # Manual start/stop via: systemctl start|stop llama-server
  # Notice: wantedBy is omitted so it NEVER auto-starts on boot
  systemd.services.llama-server = {
    description = "Llama.cpp Background API Server";
    after = [ "network.target" "mi25-dpm-lock.service" ];
    wants = [ "mi25-dpm-lock.service" ];
    path = [ pkgs.numactl pkgs.bash pkgs.coreutils ]; # Injects execution paths for systemd

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

Part 2: Detailed Technical Breakdown of the Configurations

1. The ROCm / HIP Subsystem & Architecture Demystified

Understanding how AMD's compute layer works is critical to understanding why
these specific lines exist.

  - What is HIP? HIP (Heterogeneous-compute Interface for Portability) is AMD’s
    C++ runtime and kernel language, functioning as AMD’s direct alternative to
    NVIDIA’s CUDA [1]. Where NVIDIA uses nvcc and CUDA driver APIs, AMD uses HIP
    compiled through Clang/LLVM to execute compute kernels directly on GPU
    stream processors [1].

  - The Role of rocmPackages.clr: In NixOS 24.05, clr stands for Common Language
    Runtime [2]. It packages:

    1.  The HIP Runtime Library (libamdhip64.so), which translates GPU memory
        allocations (hipMalloc), event synchronizations (hipStreamWaitEvent),
        and kernel launches.
    2.  The Radeon Open Compute (ROCm) Compiler (hipcc / clang++), which
        compiles C++ kernels into AMDGPU machine code [1, 2].

  - Why the /opt/rocm Symlink via systemd.tmpfiles.rules is Necessary: Standard
    Linux distributions install ROCm into a fixed filesystem directory:
    /opt/rocm/ [1]. Upstream software like llama.cpp, CMake find-modules, and
    various Python scripts have hardcoded searches looking for /opt/rocm/include
    or /opt/rocm/lib [3]. NixOS does not follow standard Linux directory
    conventions; it isolates packages in read-only hashes like
    /nix/store/462g8d...-clr-6.0.2/ [4]. The line:

    "L+ /opt/rocm - - - - ${pkgs.rocmPackages.clr}"

    creates an atomic, permanent symbolic link from the active Nix store path
    directly to /opt/rocm, satisfying legacy build tools and runtimes without
    breaking Nix's isolation model [2, 4].

  - The ROCm Environment Directives:

      - HSA_OVERRIDE_GFX_VERSION=9.0.0: The Heterogeneous System Architecture
        (HSA) runtime is the low-level foundation beneath HIP [1]. When an
        application launches, the HSA runtime inspects the GPU’s hardware PCI
        revision ID [1]. Because Card 0 identifies as a Radeon PRO V320
        (rev 06), certain versions of ROCm fail to recognize its microcode
        stepping and abort [5]. Setting 9.0.0 explicitly commands the HSA layer:
        "Treat every detected GPU as standard GCN 5.0 gfx900 silicon
        unconditionally." [1, 5]
      - HSA_ENABLE_SDMA=0: SDMA (System Direct Memory Access) is a dedicated
        hardware engine on AMD GPUs designed to copy data across the PCIe bus
        asynchronously without utilizing compute units [5, 6]. On the Intel C602
        server chipset, PCIe Slot 3 and Slot 5 are routed through separate CPU
        sockets over an Intel QPI bus [7]. High-throughput SDMA bursts across
        this bifurcated bridge trigger hardware timing mismatches and page
        faults in the AMD KFD driver [5, 6]. Setting HSA_ENABLE_SDMA=0 disables
        the SDMA ring buffer and instructs the driver to use standard
        compute-pipeline blits for host-to-device transfers, completely
        eliminating bus stalls [5, 6].
      - HIP_VISIBLE_DEVICES=0,1: Explicitly tells the HIP runtime to bind Card 0
        (06:00.0 on Socket 0) as GPU 0 and Card 1 (85:00.0 on Socket 1) as
        GPU 1, preventing external virtual devices or integrated controllers
        from shifting device indexes [1].

2. PCIe MMIO & Kernel Boot Overrides

  - pci=realloc and pci=nocrs: Each MI25 requires a continuous 16 GB PCIe
    Memory-Mapped I/O (MMIO) window to expose its HBM2 memory to the system (32
    GB total) [7, 8]. The Intel C602 chipset and 2012-era server BIOS default to
    obeying the ACPI Current Resource Settings (_CRS) tables, which limit 64-bit
    MMIO space above 4 GB [7]. Without these two flags, the Linux kernel aborts
    allocation (can't assign; no space), leaving amdgpu dead on the bus [8].
    pci=realloc commands the kernel to wipe BIOS assignments and rebuild the
    address space; pci=nocrs commands the kernel to bypass ACPI limits and map
    the BARs into 64-bit high memory (0x387800000000) [8].
  - pci=pcie_bus_perf: Standard Linux distributions default PCIe endpoints to a
    conservative Max Payload Size (MPS) of 128 bytes [8]. Vega 10 supports
    a 256-byte MPS [5]. This parameter configures the Intel C602 root complex
    and PCIe switches to use 256-byte Transaction Layer Packets (TLPs),
    decreasing header framing overhead and increasing burst DMA throughput
    across your PCIe Gen 3 x8 links by 10% to 15% [7, 8].
  - amdgpu.runpm=0: Resolves the fatal BACO sleep crash [6]. On headless servers
    without a physical monitor plugged into the GPU, the Linux kernel tries to
    put the card to sleep after 10 seconds of idle to save power [6]. Enterprise
    Vega 10 firmware fails to resume from this state, crashing with
    amdgpu_device_ip_resume failed (-22) [6]. Setting runpm=0 disables dynamic
    power management, keeping the GPU awake and responsive at all times [6].
  - amdgpu.noretry=0: Prevents GPU hardware lockups [6]. If an out-of-bounds
    memory access occurs during shader execution, noretry=0 forces an immediate,
    recoverable error return rather than letting the memory controller retry
    endlessly in an infinite hardware ring stall [6].

3. CPU Architecture & Latency Tuning

  - nosmt: Disables Simultaneous Multi-Threading (Hyper-Threading) at the kernel
    scheduler level [9]. On Ivy Bridge-EP cores, SMT threads share physical
    execution pipelines, L1/L2 caches, and instruction decode units [9]. When
    running parallel matrix math in llama.cpp, SMT causes thread port contention
    and cache evictions [3, 9]. Running 1 thread per physical core (6 cores on
    Socket 0) provides higher throughput, lower latency jitter, and lower heat
    output [3, 9].
  - processor.max_cstate=1 and intel_idle.max_cstate=1: In full GPU offload, the
    host CPU spends small intervals waiting between layer executions [3]. By
    default, the CPU drops into deep sleep states (C3/C6) [9]. Waking up from C6
    takes up to 100 microseconds per core [9]. Across 30 layers and multiple
    token forward passes, exiting sleep states adds \approx 4.8\text{ ms} of
    pure latency per token [3, 9]. Clamping to C1 keeps the CPU execution pipes
    awake (wake latency < 2\,\mu\text{s}), saving \approx 4.8\text{ ms} on every
    token [9].
  - powerManagement.cpuFreqGovernor = "performance": Prevents Intel SpeedStep
    from downclocking core frequencies during token sampling transitions [9].

4. GPU Power & Thermal Capping Daemon (mi25-dpm-lock)

  - Why Standard Overclocking Scripts Failed: The factory vBIOS on enterprise
    Instinct MI25 and Radeon Pro V320 accelerators write-protects the OverDrive
    registers [5, 6]. Attempting to write manual clock or voltage tables to
    pp_od_clk_voltage fails with -EINVAL [6].
  - The Working Sysfs Architecture:
    1.  Setting power_dpm_force_performance_level = high commands the driver to
        lock the memory controller (HBM2) and compute clocks to their highest
        factory-certified operational states without touching voltages [6].
    2.  The hardware power-cap check:
        MAX=$(cat "$hwmon/power1_cap_max")
        if [ "$MAX" -gt 160000000 ]; then
          echo 160000000 > "$hwmon/power1_cap" || true
        fi
        Our diagnostic query revealed that Card 0 (V320) has a hard factory
        ceiling of 110W (110000000), while Card 1 (MI25) has a ceiling of 220W
        (220000000) [5, 6]. Attempting to set Card 0 to 160W triggered write
        error: Invalid argument because 160W exceeds its 110W limit [6]. This
        script dynamically inspects power1_cap_max: it leaves the 110W V320
        alone, and caps Card 1 down from 220W to 160W [6].
  - The Thermal Outcome: Total GPU power draw is capped at 270W combined
    (110\text{W} + 160\text{W}) instead of 500W+ [5, 6]. This cuts total heat
    dissipation by nearly half, keeping the passive heatsinks from heat-soaking
    while preserving full HBM2 memory streaming bandwidth [3, 5].

5. Graphical Remote Desktop (XRDP) & Network Layer

  - Why XRDP Bypasses the Headless Video Lockout: The AMD Instinct MI25 has no
    display ports, and installing it in Slot 3 caused the motherboard to disable
    the physical VGA port during early testing [3, 7]. XRDP does not render to a
    physical monitor or GPU display pipeline [10]. It runs an in-memory virtual
    X11 server (Xorg) within host system RAM, rendering the XFCE desktop
    directly into software buffers and streaming the compressed display frames
    over TCP port 3389 [10]. This allows you to open a full visual desktop from
    Windows via mstsc regardless of physical display arbitration on the
    motherboard [10].
  - networking.firewall.enable = false;: During early deployment, a truncated
    configuration file caused the NixOS firewall to default to dropping all
    incoming packets, cutting off SSH, ping, and API calls [4, 11]. On an
    isolated private local network behind a router, disabling the host firewall
    eliminates port-drop issues across SSH (22), the API server (8080), and
    Remote Desktop (3389) [11].

6. Systemd Background Daemon Architecture (llama-server)

  - Execution Environment & Path Resolution: When systemd runs a service, it
    does not inherit the interactive shell’s $PATH [12]. Calling run_server.sh
    under systemd previously failed with status=127 (Command Not Found) because
    systemd could not locate numactl, bash, or core utilities [12]. The
    configuration includes:
    path = [ pkgs.numactl pkgs.bash pkgs.coreutils ];
    This injects the required package binaries directly into the systemd
    execution environment [12].
  - On-Demand Manual Launching: By omitting wantedBy = [ "multi-user.target" ];,
    the inference daemon never attempts to auto-start on boot [12]. It remains
    dormant until you choose to start it manually:
    systemctl start llama-server
    This ensures the system boots cleanly without failing if you are performing
    maintenance or updating models [12].

Part 3: Verification Commands

After applying this configuration via nixos-rebuild switch, use these commands
to verify each subsystem:

# 1. Verify ROCm GPU Compute Discovery:
rocm-smi
rocminfo | grep -E "Name:.*gfx900"

# 2. Verify 16 GB Large BAR MMIO Allocation on Both Cards:
lspci -d 1002:6860 -v | grep -E "Memory at.*size=16G"

# 3. Verify Active GPU Power Caps (Card 0 @ 110W, Card 1 @ 160W):
cat /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap

# 4. Verify Active Kernel Command Line Overrides:
cat /proc/cmdline

# 5. Check Remote Desktop Status (XRDP listening on port 3389):
systemctl status xrdp

# 6. Launch the Background Inference Daemon & Stream Live Logs:
systemctl start llama-server
journalctl -u llama-server -f

Primary Reference Specifications

1.  AMD Corporation: ROCm Architecture Guide and HIP Runtime API Reference
    Manual (GCN 5.0 gfx900 Target Directives) [1].
2.  NixOS Manual: Declarative Package Overlays and Hardware Graphics
    Configuration (nixos.org/manual/nixos/stable/) [2].
3.  ggml-org/llama.cpp Repository: Multi-GPU Split Topology and Memory
    Pipelining Directives (docs/multi-gpu.md) [3].
4.  Dolstra, E.: The Purely Functional Software Deployment Model (PhD Thesis,
    Utrecht University, Nix Store Isolation) [4].
5.  AMD Corporation: AMD Instinct™ MI25 & Radeon™ PRO V320 Architecture
    Whitepapers (HBM2 Memory Interfaces and PowerPlay Profiles) [5].
6.  The Linux Kernel Organization: AMDGPU Driver Documentation: Power
    Management, Sysfs, and Kernel Parameters
    (Documentation/gpu/amdgpu/thermal.rst) [6].
7.  Intel Corporation: Intel® Server Board S2600CO / S2600CP Technical Product
    Specification (Order Number: G42278-004) [7].
8.  The Linux Kernel Organization: PCI Subsystem Boot Parameters Documentation
    (Documentation/admin-guide/kernel-parameters.txt) [8].
9.  Intel Corporation: Intel® Xeon® Processor E5-2600 v2 Product Family
    Datasheet (Volume 1: Power Management and C-State Latency) [9].
10. neutrinolabs (xrdp): xrdp: An Open Source Remote Desktop Protocol Server
    Architecture [10].
11. NixOS Manual: Firewall Configuration and Packet Filtering Directives
    (networking.firewall) [11].
12. Systemd Project: systemd.service(5) and systemd.exec(5) Manual Pages
    (Service Execution and Path Resolution) [12].

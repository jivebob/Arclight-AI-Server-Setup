Technical Report: Intel S2600CO Firmware Upgrade & BIOS Configuration Guide

Target Hardware: Intel Server Board S2600CO / S2600CP Family (Intel C602 Chipset
/ Dual LGA2011)
Target Accelerators: Dual AMD Instinct MI25 / Radeon Pro V320 (Vega 10 / gfx900)
Deployment Target: High-Throughput Local LLM Inference (llama.cpp / ROCm)

0. Prerequisite Advisory (Read Before Installing GPUs)

CRITICAL PRE-INSTALLATION WARNING:
Do not physically install the AMD Instinct MI25 cards into the PCIe slots until
your operating system is fully installed, your user account is configured, and
remote network access (SSH) is verified.

The AMD Instinct MI25 is a headless datacenter compute accelerator with no
physical display outputs, yet its firmware identifies across the bus as a
standard PCI Class 0300 (VGA Compatible Controller). On the Intel C602 server
platform, the motherboard BIOS will arbitrate video to the PCIe slot, which can
leave your local monitor completely dark on boot.

Ensure that before inserting the cards:

1.  The operating system installation is finalized on disk.
2.  A standard user account (and/or root password login) is confirmed working.
3.  OpenSSH daemon is enabled, active, and accessible from another machine on
    your local network.

1. The Firmware Reflash: Why Stock BIOS Fails

The Problem with Factory Firmware

Early revisions of the Intel S2600CO firmware (e.g., BIOS versions 01.xx.xxxx
through early 02.xx.xxxx) were authored in 2012–2013, prior to the widespread
enterprise deployment of GPUs requiring massive 16 GB+ PCIe Base Address
Registers (BARs).

Under factory/early firmware:

1.  Broken MMIO High-Base Allocation: The Integrated I/O (IIO) initialization
    code inside early AMI Aptio 4 UEFI firmware fails to construct a wide
    enough 64-bit continuous root window above the 4 GB physical boundary.
2.  Resource Exhaustion POST Halts: Installing two accelerators requiring 16 GB
    framebuffers each (32 GB total continuous MMIO aperture) triggers a fatal
    hardware halt during PCI enumeration:
    ERROR: POST 0146: PCI out of resources
3.  PCIe Link Training Degraded: Early PCIe lane-negotiation firmware frequently
    fails to train Gen 3 link speeds when high-density switches or bifurcated
    enterprise accelerators are seated in CPU 2's PCIe Slot 5.

The Required Firmware Baseline

To support dual 16 GB Large BAR endpoints, the server board must be updated to
the late-lifecycle Intel Firmware Update Package (SUP / OFU) release:

  - BIOS Version: 02.06.0007 (or custom unlocked/engineering builds based on
    this release)
  - Integrated BMC Firmware: 01.29 or later
  - Intel Management Engine (ME) Firmware: 02.01.07.383
  - Sensor Data Record (SDR): Revision 1.13

Flashing Procedure

The update must be flashed cleanly using the Intel One-Boot Flash Update (OFU)
or via the built-in UEFI Shell:

1.  Extract the Intel System Update Package onto a FAT32-formatted USB flash
    drive.
2.  Boot the server into the Internal UEFI Shell (Boot Maintenance Manager \to
    Boot Options).
3.  Identify the filesystem mapped to your flash drive (typically fs0:):
    Shell> fs0:
    fs0:\> cd UpdatePackages
    fs0:\UpdatePackages> startup.nsh
4.  Let the automated script flash the BIOS, ME, SDR, and BMC sequentially. Do
    not power cycle the system during this process.
5.  Once complete, perform a clean AC power cycle (unplug both power cords
    for 30 seconds) to force the Management Engine to reload the new operational
    parameters.

2. Mandatory BIOS Settings & Technical Rationales

After flashing, press <F2> during early POST to enter the AMI Aptio Setup
Utility. Configure the following parameters across the respective submenus:

A. Advanced \to PCI Configuration

Advanced
└── PCI Configuration
    ├── Memory Mapped I/O above 4GB   ===> [ Enabled ]
    ├── Maximize Memory below 4GB    ===> [ Disabled ]
    ├── Memory Mapped I/O Size       ===> [ 256G ]
    └── PCIe Port Oprom Control
        ├── Slot 3 Option ROM        ===> [ Disabled ]
        └── Slot 5 Option ROM        ===> [ Disabled ]

1. Memory Mapped I/O above 4GB \implies [ Enabled ]

  - Technical Reason: Each AMD Instinct MI25 requires a continuous 16 GB PCIe
    Base Address Register (BAR 0) to map its physical High Bandwidth Memory
    (HBM2) into the processor's address space. Two cards demand a combined 32 GB
    address window.
  - Why it matters: 32-bit address space physically terminates at 4 GB. Without
    Above 4G Decoding enabled at the firmware level, all PCIe apertures must fit
    within the tiny 32-bit space below 4 GB (which is already crowded by BIOS
    ROMs, APIC, and legacy I/O). The kernel will fail device initialization
    with:
    pci 0000:06:00.0: BAR 0: no space for [mem size 0x400000000 64bit pref]
    pci 0000:06:00.0: BAR 0: failed to assign
    Enabling this setting instructs the CPU's Integrated I/O (IIO) complex to
    allocate 64-bit address lines for PCIe device discovery.

2. Maximize Memory below 4GB \implies [ Disabled ]

  - Technical Reason: When enabled, the BIOS attempts to expand the 32-bit
    address space available for legacy OS RAM by squeezing the low-memory MMIO
    hole as small as possible.
  - Why it matters: This starves PCIe bridge controllers and root ports of their
    essential 32-bit legacy allocations (BAR 1/2/5 control registers), causing
    the firmware to halt on boot with POST Error 146: PCI out of resources.

3. Memory Mapped I/O Size \implies [ 256G ] (or [ 512G ])

  - Technical Reason: Defines the physical high-memory MMIO boundary allocated
    to each CPU socket.
  - Why it matters: On a dual-socket system, Slot 3 is wired to CPU 1 (Socket 0)
    and Slot 5 is wired to CPU 2 (Socket 1). Setting Memory Mapped I/O Size to
    Auto frequently results in an uneven or undersized allocation on Socket 1.
    Manually fixing this window to 256G guarantees that both sockets have wide,
    non-overlapping 64-bit physical address apertures, completely preventing bus
    allocation collisions across the QPI link.

4. Slot 3 & Slot 5 Option ROM \implies [ Disabled ] (or Do Not Launch)

  - Technical Reason: Option ROMs contain legacy x86 or UEFI execution code
    intended to run before the OS boots (such as RAID controllers or video
    initialization drivers).
  - Why it matters: Compute accelerators do not provide standard display
    functionality. If the motherboard tries to execute Option ROM code from an
    enterprise compute card during the Driver Execution Environment (DXE) POST
    phase, the system will hang indefinitely at diagnostic checkpoint codes 0x92
    (PCI Bus Initialization) or 0x94 (PCI Device Enumeration).

B. Advanced \to Processor Configuration

Advanced
└── Processor Configuration
    ├── Intel(R) Hyper-Threading Technology ===> [ Disabled ]
    ├── Intel(R) VT for Directed I/O (VT-d)  ===> [ Enabled ]
    ├── Enhanced Intel SpeedStep(R) (EIST)   ===> [ Enabled ]
    ├── Intel(R) Turbo Boost Technology      ===> [ Enabled ]
    └── CPU C-State                          ===> [ Disabled ] (or [ C1 Only ])

1. Intel(R) Hyper-Threading Technology \implies [ Disabled ]

  - Technical Reason: Simultaneous Multi-Threading (SMT) creates two virtual,
    logical execution contexts that compete for the physical execution units
    (ALUs, vector registers, and L1/L2 caches) of a single core.
  - Why it matters: In llama.cpp and ggml, CPU-side thread barriers synchronize
    sampling, prompt ingestion, and tokenization. Running SMT threads on Ivy
    Bridge-EP cores causes thread starvation and context-switching overhead.
    Disabling Hyper-Threading enforces 1:1 execution on physical cores (6
    physical threads per socket), which provides lower latency variance and
    prevents CPU cache thrashing.

2. Intel(R) VT for Directed I/O (VT-d) \implies [ Enabled ]

  - Technical Reason: Enables the hardware I/O Memory Management Unit (IOMMU) on
    the Intel C602 chipset.
  - Why it matters: Required for modern Linux kernel device isolation and memory
    mapping. When paired with the kernel command-line argument iommu=pt
    (Passthrough mode), hardware direct-memory-access (DMA) operations bypass
    software translation layers, eliminating virtualization penalties during
    host-to-device weight streaming.

3. CPU C-State \implies [ Disabled ] (or [ C1 Only ])

  - Technical Reason: C-states govern idle CPU power-saving modes. Deep states
    (C3, C6) power down core execution pipelines and flush L1/L2 caches when the
    CPU is not actively computing.
  - Why it matters: During full GPU offload, the host CPU must wake up to
    synchronize and dispatch commands between every transformer layer. Waking
    from a deep C6 state on an Ivy Bridge CPU introduces an
    80\text{–}100\,\mu\text{s} penalty per wakeup. Across 30 layers and
    multi-head forward passes, deep sleep wakeups add \approx 4.8\text{ ms} of
    pure latency per token. Forcing the processor to remain in C1 ensures core
    execution pipelines are ready to dispatch in under 2\,\mu\text{s}.

4. Enhanced Intel SpeedStep (EIST) & Turbo Boost \implies [ Enabled ]

  - Technical Reason: Allows CPU clock frequency to scale up to maximum rated
    single-core and all-core Turbo limits dynamically.
  - Why it matters: Required for the Linux performance governor
    (powerManagement.cpuFreqGovernor = "performance") to lock CPU execution to
    its maximum clock ceiling without throttling downward during memory-idle
    pauses.

C. Advanced \to Memory Configuration

Advanced
└── Memory Configuration
    ├── Node Interleaving                    ===> [ Disabled ]
    └── Memory Operating Mode                ===> [ Independent ]

1. Node Interleaving \implies [ Disabled ]

  - Technical Reason: This is a counter-intuitive setting in Intel server
    firmware:
      - Node Interleaving: Enabled forces Uniform Memory Access (UMA), stripping
        physical socket boundaries and interleaving memory pages across both
        processors in a single flat pool.
      - Node Interleaving: Disabled enables Non-Uniform Memory Access (NUMA) in
        the operating system.
  - Why it matters: Disabling node interleaving exposes NUMA Node 0 (Socket 0)
    and NUMA Node 1 (Socket 1) directly to the Linux kernel. This allows
    llama.cpp to be pinned strictly to Socket 0's physical cores and its
    dedicated Quad-Channel memory bus, preventing high-latency cross-socket QPI
    memory transfers.

2. Memory Operating Mode \implies [ Independent ] (or [ Auto ])

  - Technical Reason: Governs memory controller channel lockstepping and
    mirroring.
  - Why it matters: Ensures all four memory channels per processor function
    independently. This allows Socket 0 to operate in 100% symmetric
    Quad-Channel mode (providing full \approx 35\text{ GB/s} bandwidth) even if
    Socket 1 is populated with an asymmetric memory layout.

D. Advanced \to System Acoustic and Performance Configuration

Advanced
└── System Acoustic and Performance Configuration
    └── Set Fan Profile                      ===> [ Performance ]

1. Set Fan Profile \implies [ Performance ]

  - Technical Reason: Commands the Integrated Baseboard Management Controller
    (BMC) to apply aggressive, high-duty-cycle Pulse-Width Modulation (PWM)
    curves to all connected fan headers.
  - Why it matters: The AMD Instinct MI25 is a passively cooled datacenter
    accelerator with zero onboard fans. It relies entirely on forced,
    high-static-pressure chassis airflow (\ge 35\text{–}45\text{ CFM} per card
    across its dense copper heatsink fins). Leaving the motherboard fan profile
    on "Acoustic" or "Quiet" will result in rapid heat-soaking, causing the GPU
    junction temperature to hit its 115^\circ\text{C} threshold and trigger
    emergency hardware thermal shutdown within 60 to 90 seconds of sustained
    inference.

E. Boot Options

Boot Options
└── Boot Mode                                ===> [ Legacy ] (or [ UEFI ])

1. Boot Mode \implies [ Legacy ] (or [ UEFI ] matching disk partition scheme)

  - Technical Reason: Determines whether the system initializes via standard
    Master Boot Record (MBR) INT19h interrupts or the modern Unified Extensible
    Firmware Interface (UEFI) GPT driver stack.
  - Why it matters: If your storage array was partitioned with a legacy MBR
    partition table (/dev/sda), this must be set to Legacy. Selecting UEFI on an
    MBR disk will cause the firmware to fail device discovery and drop to an
    empty UEFI shell prompt. (If using GPT partitions with an EFI System
    Partition, select UEFI).

3. Post-Configuration Verification Checklist

After saving the settings (<F10>) and booting into the operating system, verify
that the hardware initialization succeeded by running these three diagnostic
commands in your terminal:

# 1. Verify that both 16 GB Large BAR apertures are allocated in 64-bit high memory:
lspci -d 1002:6860 -v | grep -E "Memory at.*size=16G"
# -> SUCCESS: Exactly two lines must be returned ending in [size=16G].

# 2. Verify that NUMA separation is properly exposed to the kernel:
numactl -H
# -> SUCCESS: Must show distinct 'node 0' and 'node 1' memory pools.

# 3. Verify CPU power and C-state clamping:
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name
# -> SUCCESS: Only shallow C-states (POLL, C1) should be active.


SIDE NOTES
#u may have to set ur pcie speed from 3 to 2 at the time this board was made apperently there were issues with running acceleratirs at ful pcie speeds 

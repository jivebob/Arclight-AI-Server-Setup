Project Arclight: Engineering Handover & Technical Report
Introduction

Several months ago I made the questionable decision to see whether modern AI workloads could be run efficiently on a legacy enterprise server using surplus AMD Instinct MI25 accelerators.

At the time this seemed like a perfectly reasonable weekend project.

Several months later, after firmware archaeology, hardware modifications, operating-system patching, power-system redesigns, source-code modifications, and more troubleshooting than I care to remember, I can confidently report that the experiment was a success.

Would it have been easier to buy newer hardware?

Absolutely.

Would that have been nearly as interesting?

Absolutely not.

The goal of Project Arclight was simple:

Determine whether dual Vega 10 enterprise accelerators could execute modern large language models at practical inference speeds on inexpensive second-hand hardware.

The answer, as demonstrated throughout this repository, is yes.

What follows is the documented path to get there.

Hardware Configuration
Motherboard
Intel Server Board S2600CO
Intel C602 Chipset
Legacy BIOS Platform

Processors
2x Intel Xeon E5-2600 v2

Total Physical Cores:
12

Hyperthreading:
Disabled


For this workload SMT provided little benefit and was disabled.

Memory
72GB DDR3 ECC Registered

NUMA Node 0:
48GB

NUMA Node 1:
24GB


The memory layout is not perfectly symmetrical, but it proved sufficient for stable operation.

Graphics Accelerators
GPU 0:
AMD Radeon Pro V320

GPU 1:
AMD Instinct MI25

Combined VRAM:
32.7GB HBM2

GPU Identification Note

Many readers will immediately notice that one card reports itself as a Radeon Pro V320 while the other reports itself as an Instinct MI25.

This is expected.

The V320 was originally an MI25-class Vega 10 accelerator that had previously been reflashed with a different datacentre-oriented vBIOS before it came into my possession.

As a result:

GPU 0 identifies as a Radeon Pro V320

GPU 1 identifies as an AMD Instinct MI25


Despite the different names, both cards are Vega 10 accelerators and function correctly within the same ROCm environment.

It is also worth noting that I deliberately chose not to reflash either card during this project.

Could I have done so?

Probably.

Would it have simplified things?

Possibly.

Would that have removed one more unnecessary challenge from an already unnecessary challenge?

Also yes.

The objective of the project was to get the hardware running successfully in the condition I received it rather than attempting to standardise both cards.

Important Deployment Note

Before installing either GPU:

Configure SSH First

I cannot stress this enough.

Install NixOS

Enable OpenSSH

Verify Network Connectivity

Verify SSH Login

THEN install the GPUs


The reason is fairly simple.

Both cards identify themselves as VGA-class devices despite lacking physical display outputs.

Once installed, the motherboard frequently disables or deprioritises the onboard graphics controller.

The result is:

No video output

No monitor signal

No visible boot process


This does not necessarily mean the server failed to start.

In many cases it is booting perfectly normally.

You simply have no way of seeing it.

Most of the development work performed on Project Arclight was conducted remotely through SSH for this exact reason.

Save yourself the frustration and configure remote management before installing the accelerators.

BIOS Requirements

Before attempting anything else:

Update the BIOS.

The early BIOS releases for the Intel S2600CO lack features necessary for modern high-memory PCIe accelerators.

Most notably:

Above 4G Decoding


must be available.

Without it you can expect PCI resource allocation errors and failed GPU initialisation.

BIOS Notice

The BIOS image used for this project is not included.

Yes, I have a copy.

No, I am not uploading it.

While obtaining the final S2600CO BIOS revision proved essential to the project, the firmware remains Intel intellectual property and I would prefer not to attract the attention of Intel's legal department.

As a result:

NO BIOS FILES ARE INCLUDED


The version information used during testing will be documented wherever possible.

Future builders will need to locate the firmware through their own legitimate research and archival efforts.

Consider it the tutorial level before the real game begins.

Cooling System Modifications

The MI25 and V320 are passive datacentre accelerators.

Unfortunately, "passive cooling" in datacentre terminology usually means:

Bring your own hurricane.


The factory airflow arrangement could not adequately cool both Vega 10 cards under sustained AI workloads.

A custom cooling system was therefore developed.

Cooling Modifications

The original shrouds were retained and modified.

Changes included:

Shrouds opened using a metal hole saw

Dedicated high-throughput blower fans
mounted directly to the shrouds

Fan assemblies permanently secured
using JB Weld

Additional squirrel-cage exhaust fan
installed behind both accelerators


The squirrel-cage fan functions primarily as a chassis exhaust accelerator rather than a direct GPU cooler.

Each processor heatsink assembly additionally received:

High-static-pressure fan


mounted to the removable side access panel using:

Neodymium magnet mounts


This arrangement made servicing significantly easier while maintaining excellent airflow characteristics.

The final solution proved stable throughout extended testing and sustained inference workloads.

Power Delivery

The MI25 platform requires:

Dual 8-Pin PCIe Power


per accelerator.

A dedicated Antminer power supply was used to provide GPU power independently from the server's primary power subsystem.

To ensure correct startup behaviour:

Internal PSU
+
External GPU PSU


were linked via an isolated relay circuit.

The relay was controlled from the server's internal 5V rail and allowed both power systems to start in coordination.

Additional grounding measures were implemented to maintain a common chassis reference.

The end result was stable and repeatable operation.

Operating System
NixOS 24.05
Linux Kernel 6.6.68


Primary administration:

SSH


Secondary administration:

XRDP

Required Kernel Parameters

The following represent the final stable configuration.

boot.kernelParams = [
  "pci=realloc"
  "pci=nocrs"
  "pci=pcie_bus_perf"
  "iommu=pt"
  "amdgpu.noretry=0"
  "amdgpu.runpm=0"
  "nosmt"
  "processor.max_cstate=1"
  "intel_idle.max_cstate=1"
  "console=tty0"
  "console=ttyS1,115200n8"
];


These settings were collected one lesson at a time.

Common Problems Encountered
PCI Allocation Failures

Error:

can't assign; no space


Cause:

C602 MMIO limitations


Fix:

pci=realloc
pci=nocrs

GPU Resume Failures

Error:

amdgpu_device_ip_resume failed (-22)


Cause:

BACO power-management behaviour


Fix:

amdgpu.runpm=0

Illegal Instruction Crashes

Error:

SIGILL
Illegal Instruction


Cause:

AVX2 assumptions inside modern builds


The Xeon E5 v2 platform supports AVX1 but not AVX2.

Build options were adjusted accordingly.

ROCm Compatibility Issues

Cause:

Differences between modern llama.cpp
and older ROCm implementations.


Fix:

Compatibility patches described within the repository.

ROCm Environment

Required variables:

export HSA_OVERRIDE_GFX_VERSION=9.0.0
export HSA_ENABLE_SDMA=0
export HIP_VISIBLE_DEVICES=0,1


These were required for stable operation and proper device discovery.

llama.cpp Build Configuration

Enabled:

AVX
F16C


Disabled:

AVX2
FMA
BMI2
AVX512


This configuration matches Ivy Bridge capabilities and avoids illegal-instruction faults.

Thermal Power Management

A dedicated startup service was used to:

Lock GPU DPM Levels

Apply Power Caps


Final operating target:

160W per accelerator


which provided a good balance between stability and performance.

Validation Checklist

Before launching any workload:

GPU Visibility
rocm-smi


Expected:

2 GPUs Detected

Architecture Detection
rocminfo


Expected:

gfx900
gfx900

BAR Allocation
lspci -d 1002:6860 -v


Expected:

size=16G


If you do not see this value:

STOP

Fix BIOS configuration first.


Nothing else matters until this works.

Model Configuration

Primary test model:

Gemma 4 26B-A4B-IT
Q8_0


Configuration:

Context:
8192

Tensor Split:
1,1

GPU Layers:
999

Host Spillover:
0 Bytes


All model weights remained resident in VRAM.

This was one of the primary objectives of the project.

Performance Results
Short Context Burst
40 - 43 TPS

Sustained Generation
31 TPS

Worst-Case Context
26 - 28 TPS


at:

8192 token context

Lessons Learned

Enterprise hardware remains useful far longer than most people assume.

Intel occasionally hides critical BIOS revisions well enough to qualify as an archaeological dig.

Passive cooling is not actually cooling. It is a contractual agreement requiring you to solve the airflow problem yourself.

Power delivery deserves just as much engineering attention as compute performance.

Unsupported hardware combinations are often simply undocumented hardware combinations.

Most seemingly impossible projects eventually become merely stubborn projects.

The difference between complete failure and complete success may occasionally be one kernel parameter hidden inside a decade-old forum post.

Document everything. Future-you will have forgotten what present-you spent three days figuring out.

Final Thoughts

Project Arclight began with a simple question:

Can modern AI inference be performed efficiently on legacy datacentre hardware?

The answer is yes.

The platform successfully achieved:

Dual Vega 10 Acceleration

100% In-VRAM Inference

30+ TPS Sustained Performance

Modern llama.cpp Compatibility

Stable NixOS Deployment


Whether this was the easiest route to that result is highly debatable.

Whether it was an interesting route is not.

If this report saves another builder a few days, weeks, or months of troubleshooting, firmware hunting, source patching, or general confusion, then publishing it was worthwhile.

Good luck.

And remember:

If something stops working, check the BIOS, check your kernel parameters, check ROCm, and only then begin questioning your life choices.

{
  description = "Project Arclight: Dual AMD Instinct MI25 + Intel C602 Inference Node";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # The custom patched llama.cpp package (Build 11493+ with Gemma 4 support)
      llama-cpp-mi25 = pkgs.stdenv.mkDerivation rec {
        pname = "llama-cpp-mi25";
        version = "b11493";

        src = pkgs.fetchFromGitHub {
          owner = "ggml-org";
          repo = "llama.cpp";
          rev = "847f447c3";
          hash = "sha256-nU9zZ51TjB5Yq4fM5nJz3G5R3P0q5W0Y7X9Z51TjB5Y="; # Update if hash differs
        };

        nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config pkgs.git ];
        buildInputs = [
          pkgs.rocmPackages.clr
          pkgs.rocmPackages.hipblas
          pkgs.rocmPackages.rocblas
        ];

        # Applies the unified patch cleanly
        patches = [
          ./patches/mi25-ivybridge.patch
        ];

        cmakeFlags = [
          "-DGGML_HIP=ON"
          "-DGPU_TARGETS=gfx900"
          "-DCMAKE_BUILD_TYPE=Release"
          "-DGGML_NATIVE=OFF"
          "-DGGML_CPU_ALL_VARIANTS=OFF"
          "-DGGML_BACKEND_DL=OFF"
          "-DGGML_AVX=ON"
          "-DGGML_F16C=ON"
          "-DGGML_AVX2=OFF"
          "-DGGML_FMA=OFF"
          "-DLLAMA_AVX=ON"
          "-DLLAMA_F16C=ON"
          "-DLLAMA_AVX2=OFF"
          "-DLLAMA_FMA=OFF"
          "-DCMAKE_C_FLAGS=-mavx -mf16c -mno-avx2 -mno-fma -mno-bmi2 -mno-avx512f"
          "-DCMAKE_CXX_FLAGS=-mavx -mf16c -mno-avx2 -mno-fma -mno-bmi2 -mno-avx512f"
        ];
      };

      # The complete NixOS hardware and service configuration
      arclightModule = { config, pkgs, lib, ... }: {
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

        powerManagement.cpuFreqGovernor = "performance";

        fileSystems."/dev/hugepages" = {
          device = "hugetlbfs";
          fsType = "hugetlbfs";
          options = [ "pagesize=1G" "mode=0777" ];
        };

        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "yes";
            PasswordAuthentication = true;
          };
        };

        networking.firewall.enable = false;

        # XRDP Remote Desktop over virtual RAM framebuffer
        services.xserver = {
          enable = true;
          desktopManager.xfce.enable = true;
        };
        services.xrdp = {
          enable = true;
          defaultWindowManager = "startxfce4";
          openFirewall = true;
        };

        hardware.opengl = {
          enable = true;
          extraPackages = with pkgs.rocmPackages; [ clr clr.icd ];
        };

        # DPM Performance Lock & 160W Thermal Safety Daemon
        systemd.services.mi25-dpm-lock = {
          description = "Lock AMD MI25 GPUs to High DPM and Enforce 160W Power Caps";
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

        environment.systemPackages = [
          llama-cpp-mi25
          pkgs.rocmPackages.clr
          pkgs.rocmPackages.hipblas
          pkgs.rocmPackages.rocblas
          pkgs.rocmPackages.rocm-smi
          pkgs.rocmPackages.rocminfo
          pkgs.numactl
          pkgs.pciutils
          pkgs.firefox
        ];

        environment.sessionVariables = {
          HSA_OVERRIDE_GFX_VERSION = "9.0.0";
          HSA_ENABLE_SDMA = "0";
          HIP_VISIBLE_DEVICES = "0,1";
        };
      };

    in {
      # Standalone build output: nix build .#llama-cpp-mi25
      packages.${system}.default = llama-cpp-mi25;
      packages.${system}.llama-cpp-mi25 = llama-cpp-mi25;

      # Importable NixOS module for other users' configs
      nixosModules.default = arclightModule;
      nixosModules.arclight = arclightModule;

      # Turnkey NixOS system: nixos-rebuild switch --flake .#arclight
      nixosConfigurations.arclight = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          arclightModule
          ({ ... }: {
            boot.loader.grub.enable = true;
            boot.loader.grub.device = "/dev/sda";
            system.stateVersion = "24.05";
          })
        ];
      };
    };
}

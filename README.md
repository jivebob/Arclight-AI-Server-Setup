# Arclight Engine: AI Inference Server Setup

This repository documents the real-world deployment and operation of an Arclight Engines AI inference server. Built from actual installation trials, configuration hurdles, and optimization tests, this guide serves as a practical blueprint for running local inference stacks.

> **Warning:** This is not a beginner-friendly project. If you are looking for an out-of-the-box solution that sets up in an hour, this repository is not for you. Deploying this architecture requires hands-on hardware configuration, and patience.

---

## Repository Structure

The project is organized into modular directories to keep deployments clean:

* **[ConTainersScripts](https://github.com/jivebob/Arclight-AI-Server-Setup/tree/main/ConTainersScripts):** Container templates (`[Containerfile](https://github.com/jivebob/Arclight-AI-Server-Setup/blob/main/ConTainersScripts/Containerfile)`), Nix configurations (`[flake.nix](https://github.com/jivebob/Arclight-AI-Server-Setup/blob/main/ConTainersScripts/flake.nix)`), and deployment scripts.
* **[Guides](https://github.com/jivebob/Arclight-AI-Server-Setup/tree/main/Guides):** Step-by-step walkthroughs (`[WALK-THROUGH.md](https://github.com/jivebob/Arclight-AI-Server-Setup/tree/main/Guides/WALK-THROUGH.md)`) and operational documentation.
* **[TechSpecSheets](https://github.com/jivebob/Arclight-AI-Server-Setup/tree/main/TechSpecSheets):** Technical notes, hardware logs, and performance metrics (`[TECHNICAL-NOTES.md](https://github.com/jivebob/Arclight-AI-Server-Setup/tree/main/TechSpecSheets/TECHNICAL-NOTES.md)`).
* **[Legal](https://github.com/jivebob/Arclight-AI-Server-Setup/tree/main/Legal):** Licensing terms and liability disclaimers.

---

## Hardware & Firmware Notice

While the software stack and containers provided here are flexible across various environments (supporting AVX/AVX2 instruction sets and modular card setups), the physical hardware implementation is entirely on you.

* **Motherboard Target:** Built and tested around the **Intel Server Board S2600CO**. 
* **Firmware:** Official Intel support for this board is discontinued. If you are sourcing system BIOS packages (such as System BIOS 02.06.0005 inclusive of Management Engine and BMC components), you will need to rely on archived community resources. *Flashing server firmware carries inherent risks—proceed entirely at your own risk.*

---

## License

This project is released under the **[AGPL-3.0 license](https://github.com/jivebob/Arclight-AI-Server-Setup/blob/main/Legal/LICENSE.md)**. You are free to use, modify, and distribute this work provided that derivative works remain open under the same terms.

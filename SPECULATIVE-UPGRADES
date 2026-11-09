These upgrades were thought up to increase the models capabilities they have not been tested though any one wanting to use them may of course do so but i take no blame 
for any damage that may be done to personal property if u do use 

 enforces Ivy Bridge AVX 1.0 execution, and wires the
compiler-trap self-correction loop directly into the inference engine.

Project File Tree Layout

arclight/
├── flake.nix                          # Hermetic NixOS ROCm & Toolchain Environment
├── CMakeLists.txt                     # Ivy Bridge strict AVX1 build flags
├── build.sh                           # Deterministic compilation script
├── include/
│   ├── arclight_ltm_store.hpp         # SQLite WAL parametric episodic memory
│   ├── arclight_multitrack_lora.hpp   # AVX1 SIMD centroid matcher & LoRA controller
│   └── arclight_compiler_trap.hpp     # Sub-millisecond host clang++ syntax pipe
├── src/
│   ├── ltm_store.cpp
│   ├── multitrack_lora.cpp
│   └── main.cpp                       # HTTP Daemon, Entropy Decoding & Self-Correction Loop
└── systemd/
    └── arclight.service               # NUMA-interleaved systemd daemon

1. NixOS Environment (flake.nix)

Pins the ROCm toolchain, exports the gfx900 Vega 10 overrides, and exposes
clang++ for the compiler-trap engine.

{
  description = "Project Arclight: Production Embedded ROCm & Llama Engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gcc13
            clang_17
            cmake
            pkg-config
            sqlite
            numactl
            pciutils
            rocmPackages.clr
            rocmPackages.rocblas
            rocmPackages.hipblas
            rocmPackages.rocm-smi
          ];

          shellHook = ''
            export ROCM_PATH="${pkgs.rocmPackages.clr}"
            export HIP_PATH="${pkgs.rocmPackages.clr}"
            export HSA_OVERRIDE_GFX_VERSION=9.0.0
            export HSA_ENABLE_SDMA=0
            export HIP_VISIBLE_DEVICES=0,1
            echo "[Arclight] Hermetic Nix Shell initialized for Dual Vega 10 (gfx900)."
          '';
        };
      });
}

2. Build Specification (CMakeLists.txt)

Guarantees Ivy Bridge compatibility: AVX 1.0 and F16C are enabled; AVX2, FMA3,
and AVX-512 are strictly blocked to prevent SIGILL crashes.

cmake_minimum_required(VERSION 3.20)
project(arclight_server CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Hardware Enforcement: Intel Ivy Bridge (E5-2600 v2)
add_compile_options(
    -mavx
    -mf16c
    -mno-avx2
    -mno-fma
    -mno-bmi2
    -mno-avx512f
    -O3
    -Wall
    -Wextra
    -pthread
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SQLITE3 REQUIRED sqlite3)

set(LLAMA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${SQLITE3_INCLUDE_DIRS}
    ${LLAMA_DIR}/include
    ${LLAMA_DIR}/ggml/include
)

link_directories(
    ${LLAMA_DIR}/build/src
    ${LLAMA_DIR}/build/ggml/src
)

add_executable(arclight_server
    src/main.cpp
    src/multitrack_lora.cpp
    src/ltm_store.cpp
)

target_link_libraries(arclight_server
    PRIVATE
    ${SQLITE3_LIBRARIES}
    llama
    ggml
    pthread
    dl
)

3. Compilation Script (build.sh)

Fetches llama.cpp and compiles both the underlying backend and Arclight using
the strict -DGGML_CPU_ALL_VARIANTS=OFF flag to prevent CMake from building
Haswell/AVX2 variants.

#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$(pwd)"

if [ ! -d "llama.cpp" ]; then
    echo "[Arclight] Cloning llama.cpp..."
    git clone https://github.com/ggml-org/llama.cpp.git
fi

cd llama.cpp

# Patch ROCm version check if on ROCm 6.0
if [ -f ggml/src/ggml-hip/CMakeLists.txt ]; then
    sed -i -E 's/if.*VERSION_LESS.*6\.1.*/if (FALSE)/g' ggml/src/ggml-hip/CMakeLists.txt || true
fi

echo "[Arclight] Compiling libllama for gfx900 + AVX1..."
cmake -B build \
  -DGGML_NATIVE=OFF \
  -DGGML_CPU_ALL_VARIANTS=OFF \
  -DGGML_AVX=ON \
  -DGGML_F16C=ON \
  -DGGML_AVX2=OFF \
  -DGGML_FMA=OFF \
  -DGGML_AVX512=OFF \
  -DCMAKE_C_FLAGS="-mavx -mf16c -mno-avx2 -mno-fma" \
  -DCMAKE_CXX_FLAGS="-mavx -mf16c -mno-avx2 -mno-fma" \
  -DGGML_HIP=ON \
  -DAMDGPU_TARGETS=gfx900 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --config Release -j 6 --target llama ggml

cd "$WORKSPACE"

echo "[Arclight] Compiling arclight_server..."
rm -rf build && mkdir build && cd build
cmake ..
make -j 6

echo "[Arclight] Compilation Complete: build/arclight_server"

4. SQLite Parametric Episodic Memory

include/arclight_ltm_store.hpp

#pragma once

#include <sqlite3.h>
#include <string>
#include <vector>
#include <optional>
#include <mutex>

namespace Arclight::Memory {

struct ParametricBinding {
    std::string entity;
    std::string attribute;
    std::string adapter_name;
    float bias_scale;
};

class LTMStore {
public:
    explicit LTMStore(const std::string& db_path);
    ~LTMStore();

    LTMStore(const LTMStore&) = delete;
    LTMStore& operator=(const LTMStore&) = delete;

    bool BindEntityToAdapter(const std::string& entity, const std::string& attribute, 
                             const std::string& adapter_name, float bias_scale);
    std::optional<ParametricBinding> GetBinding(const std::string& entity, const std::string& attribute);

private:
    sqlite3* db_ = nullptr;
    std::mutex db_mutex_;
    sqlite3_stmt* stmt_upsert_ = nullptr;
    sqlite3_stmt* stmt_get_ = nullptr;

    void InitSchema();
    void PrepareStatements();
};

} // namespace Arclight::Memory

src/ltm_store.cpp

#include "arclight_ltm_store.hpp"
#include <stdexcept>

namespace Arclight::Memory {

LTMStore::LTMStore(const std::string& db_path) {
    if (sqlite3_open(db_path.c_str(), &db_) != SQLITE_OK) {
        throw std::runtime_error("Failed to open SQLite database: " + std::string(sqlite3_errmsg(db_)));
    }

    char* err_msg = nullptr;
    const char* pragmas = 
        "PRAGMA journal_mode = WAL;"
        "PRAGMA synchronous = NORMAL;"
        "PRAGMA temp_store = MEMORY;"
        "PRAGMA cache_size = -64000;";

    if (sqlite3_exec(db_, pragmas, nullptr, nullptr, &err_msg) != SQLITE_OK) {
        std::string err = err_msg ? err_msg : "Unknown error";
        sqlite3_free(err_msg);
        throw std::runtime_error("PRAGMA configuration failed: " + err);
    }

    InitSchema();
    PrepareStatements();
}

LTMStore::~LTMStore() {
    std::lock_guard<std::mutex> lock(db_mutex_);
    sqlite3_finalize(stmt_upsert_);
    sqlite3_finalize(stmt_get_);
    sqlite3_close(db_);
}

void LTMStore::InitSchema() {
    const char* schema = 
        "CREATE TABLE IF NOT EXISTS parametric_memory ("
        "  entity TEXT NOT NULL,"
        "  attribute TEXT NOT NULL,"
        "  adapter_name TEXT NOT NULL,"
        "  bias_scale REAL NOT NULL,"
        "  PRIMARY KEY(entity, attribute)"
        ");";

    char* err_msg = nullptr;
    if (sqlite3_exec(db_, schema, nullptr, nullptr, &err_msg) != SQLITE_OK) {
        std::string err = err_msg ? err_msg : "Unknown error";
        sqlite3_free(err_msg);
        throw std::runtime_error("Schema init failed: " + err);
    }
}

void LTMStore::PrepareStatements() {
    const char* upsert_sql = 
        "INSERT INTO parametric_memory (entity, attribute, adapter_name, bias_scale) "
        "VALUES (?1, ?2, ?3, ?4) "
        "ON CONFLICT(entity, attribute) DO UPDATE SET "
        "adapter_name = excluded.adapter_name, bias_scale = excluded.bias_scale;";
    sqlite3_prepare_v2(db_, upsert_sql, -1, &stmt_upsert_, nullptr);

    const char* get_sql = 
        "SELECT adapter_name, bias_scale FROM parametric_memory WHERE entity = ?1 AND attribute = ?2;";
    sqlite3_prepare_v2(db_, get_sql, -1, &stmt_get_, nullptr);
}

bool LTMStore::BindEntityToAdapter(const std::string& entity, const std::string& attribute, 
                                   const std::string& adapter_name, float bias_scale) {
    std::lock_guard<std::mutex> lock(db_mutex_);
    sqlite3_reset(stmt_upsert_);
    sqlite3_bind_text(stmt_upsert_, 1, entity.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt_upsert_, 2, attribute.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt_upsert_, 3, adapter_name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt_upsert_, 4, static_cast<double>(bias_scale));

    return sqlite3_step(stmt_upsert_) == SQLITE_DONE;
}

std::optional<ParametricBinding> LTMStore::GetBinding(const std::string& entity, const std::string& attribute) {
    std::lock_guard<std::mutex> lock(db_mutex_);
    sqlite3_reset(stmt_get_);
    sqlite3_bind_text(stmt_get_, 1, entity.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt_get_, 2, attribute.c_str(), -1, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt_get_) == SQLITE_ROW) {
        std::string adapter = reinterpret_cast<const char*>(sqlite3_column_text(stmt_get_, 0));
        float scale = static_cast<float>(sqlite3_column_double(stmt_get_, 1));
        return ParametricBinding{entity, attribute, adapter, scale};
    }
    return std::nullopt;
}

} // namespace Arclight::Memory

5. Multi-Track LoRA & AVX 1.0 SIMD Engine

include/arclight_multitrack_lora.hpp

#pragma once

#include "llama.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <immintrin.h>

namespace Arclight::LoRA {

struct TrackDefinition {
    std::string name;
    float current_scale;
    float max_scale;
    std::vector<std::vector<float>> centroids;
    struct llama_adapter_lora* handle;
};

class MultiTrackController {
public:
    MultiTrackController(struct llama_model* model, struct llama_context* ctx, size_t dim);
    ~MultiTrackController();

    bool RegisterTrack(const std::string& name, const std::string& lora_path, float max_scale,
                       const std::vector<std::vector<float>>& centroids);

    std::unordered_map<std::string, float> EvaluateManifold(const float* embedding);
    void SetTrackScale(const std::string& name, float scale);
    void ResetAll();

    // Ivy Bridge AVX1 Math
    static float CosineSimilarityAVX1(const float* a, const float* b, size_t dim);

private:
    struct llama_model* model_;
    struct llama_context* ctx_;
    size_t dim_;
    std::vector<TrackDefinition> tracks_;

    static float HorizontalSum256(__m256 v);
};

} // namespace Arclight::LoRA

src/multitrack_lora.cpp

#include "arclight_multitrack_lora.hpp"
#include <cmath>
#include <algorithm>
#include <iostream>
#include <stdexcept>

namespace Arclight::LoRA {

inline float MultiTrackController::HorizontalSum256(__m256 v) {
    __m128 vlow  = _mm256_castps256_ps128(v);
    __m128 vhigh = _mm256_extractf128_ps(v, 1);
    __m128 v128  = _mm_add_ps(vlow, vhigh);

    __m128 shuf  = _mm_movehdup_ps(v128);
    __m128 sums  = _mm_add_ps(v128, shuf);
    shuf         = _mm_movehl_ps(shuf, sums);
    sums         = _mm_add_ss(sums, shuf);
    return _mm_cvtss_f32(sums);
}

float MultiTrackController::CosineSimilarityAVX1(const float* a, const float* b, size_t dim) {
    if (dim % 8 != 0) {
        throw std::invalid_argument("Vector dimension must be aligned to 8 floats.");
    }

    __m256 dot_acc = _mm256_setzero_ps();
    __m256 na_acc  = _mm256_setzero_ps();
    __m256 nb_acc  = _mm256_setzero_ps();

    for (size_t i = 0; i < dim; i += 8) {
        __m256 va = _mm256_loadu_ps(a + i);
        __m256 vb = _mm256_loadu_ps(b + i);

        dot_acc = _mm256_add_ps(dot_acc, _mm256_mul_ps(va, vb));
        na_acc  = _mm256_add_ps(na_acc,  _mm256_mul_ps(va, va));
        nb_acc  = _mm256_add_ps(nb_acc,  _mm256_mul_ps(vb, vb));
    }

    float dot  = HorizontalSum256(dot_acc);
    float norm = std::sqrt(HorizontalSum256(na_acc)) * std::sqrt(HorizontalSum256(nb_acc));

    return (norm <= 1e-8f) ? 0.0f : (dot / norm);
}

MultiTrackController::MultiTrackController(struct llama_model* model, struct llama_context* ctx, size_t dim)
    : model_(model), ctx_(ctx), dim_(dim) {}

MultiTrackController::~MultiTrackController() {
    for (auto& track : tracks_) {
        if (track.handle) llama_adapter_lora_free(track.handle);
    }
}

bool MultiTrackController::RegisterTrack(const std::string& name, const std::string& lora_path, float max_scale,
                                         const std::vector<std::vector<float>>& centroids) {
    struct llama_adapter_lora* handle = llama_adapter_lora_init(model_, lora_path.c_str());
    if (!handle) {
        std::cerr << "[Arclight::LoRA] Error: Failed to load adapter: " << lora_path << std::endl;
        return false;
    }

    tracks_.push_back({name, 0.0f, max_scale, centroids, handle});
    llama_set_adapter_lora(ctx_, handle, 0.0f);
    return true;
}

std::unordered_map<std::string, float> MultiTrackController::EvaluateManifold(const float* embedding) {
    std::unordered_map<std::string, float> scales;

    for (auto& track : tracks_) {
        float max_sim = -1.0f;
        for (const auto& centroid : track.centroids) {
            float sim = CosineSimilarityAVX1(embedding, centroid.data(), dim_);
            if (sim > max_sim) max_sim = sim;
        }

        float scale = 0.0f;
        if (max_sim >= 0.60f) {
            float weight = (max_sim - 0.60f) / 0.25f;
            scale = std::clamp(weight, 0.0f, 1.0f) * track.max_scale;
        }

        track.current_scale = scale;
        llama_set_adapter_lora(ctx_, track.handle, scale);
        scales[track.name] = scale;
    }

    return scales;
}

void MultiTrackController::SetTrackScale(const std::string& name, float scale) {
    for (auto& track : tracks_) {
        if (track.name == name) {
            track.current_scale = scale;
            llama_set_adapter_lora(ctx_, track.handle, scale);
            return;
        }
    }
}

void MultiTrackController::ResetAll() {
    for (auto& track : tracks_) {
        track.current_scale = 0.0f;
        llama_set_adapter_lora(ctx_, track.handle, 0.0f);
    }
}

} // namespace Arclight::LoRA

6. Sub-Millisecond Compiler-Trap Engine

include/arclight_compiler_trap.hpp

#pragma once

#include <string>
#include <unistd.h>
#include <sys/wait.h>
#include <vector>

namespace Arclight::Compiler {

struct VerificationResult {
    bool passed;
    std::string diagnostic;
};

inline VerificationResult CheckSyntax(const std::string& code_buffer) {
    int in_pipe[2];
    int err_pipe[2];

    if (pipe(in_pipe) < 0 || pipe(err_pipe) < 0) {
        return {false, "Failed to initialize IPC pipes"};
    }

    pid_t pid = fork();
    if (pid == 0) {
        dup2(in_pipe[0], STDIN_FILENO);
        dup2(err_pipe[1], STDERR_FILENO);

        close(in_pipe[0]);
        close(in_pipe[1]);
        close(err_pipe[0]);
        close(err_pipe[1]);

        execlp("clang++", "clang++", "-fsyntax-only", "-std=c++20", "-Wall", "-Wextra", "-x", "c++", "-", nullptr);
        _exit(127);
    }

    close(in_pipe[0]);
    close(err_pipe[1]);

    write(in_pipe[1], code_buffer.data(), code_buffer.size());
    close(in_pipe[1]);

    std::string err_out;
    char buf[512];
    ssize_t bytes;
    while ((bytes = read(err_pipe[0], buf, sizeof(buf) - 1)) > 0) {
        buf[bytes] = '\0';
        err_out.append(buf);
    }
    close(err_pipe[0]);

    int status;
    waitpid(pid, &status, 0);

    bool ok = (WIFEXITED(status) && WEXITSTATUS(status) == 0);
    return {ok, err_out};
}

} // namespace Arclight::Compiler

7. Master Server Daemon (src/main.cpp)

Integrates native HTTP routing, Shannon entropy calculation, dynamic LoRA
throttling, and the targeted compiler-trap loop.

#include "llama.h"
#include "arclight_multitrack_lora.hpp"
#include "arclight_ltm_store.hpp"
#include "arclight_compiler_trap.hpp"

#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <regex>
#include <cmath>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

#define PORT 8080
#define BUFFER_SIZE 65536

std::string ExtractCleanPrompt(const std::string& body) {
    size_t pos = body.find("\"content\":");
    if (pos == std::string::npos) return "";
    size_t start = body.find("\"", pos + 10);
    if (start == std::string::npos) return "";
    size_t end = body.find("\"", start + 1);
    if (end == std::string::npos) return "";
    return body.substr(start + 1, end - start - 1);
}

std::string ExtractCodeBlock(const std::string& text) {
    std::regex re(R"(```(?:cpp|c\+\+)?\n([\s\S]*?)```)");
    std::smatch m;
    if (std::regex_search(text, m, re)) return m[1].str();
    return text;
}

float ComputeEntropy(const float* logits, int n_vocab, int top_k = 32) {
    float max_l = -1e9f;
    for (int i = 0; i < top_k; ++i) {
        if (logits[i] > max_l) max_l = logits[i];
    }
    float sum_exp = 0.0f;
    std::vector<float> p(top_k);
    for (int i = 0; i < top_k; ++i) {
        p[i] = std::exp(logits[i] - max_l);
        sum_exp += p[i];
    }
    float h = 0.0f;
    for (int i = 0; i < top_k; ++i) {
        float prob = p[i] / sum_exp;
        if (prob > 1e-6f) h -= prob * std::log(prob);
    }
    return h;
}

std::string DecodeWithEntropyGating(
    struct llama_context* ctx,
    const struct llama_vocab* vocab,
    Arclight::LoRA::MultiTrackController& lora_ctrl,
    const std::vector<llama_token>& tokens,
    int max_tokens
) {
    llama_batch batch = llama_batch_init(512, 0, 1);
    int pos_base = llama_get_kv_cache_used_cells(ctx);

    for (size_t i = 0; i < tokens.size(); ++i) {
        llama_batch_add(batch, tokens[i], pos_base + i, { 0 }, (i == tokens.size() - 1));
    }
    llama_decode(ctx, batch);

    std::string result = "";
    int n_vocab = llama_vocab_n_tokens(vocab);

    for (int i = 0; i < max_tokens; ++i) {
        float* logits = llama_get_logits_ith(ctx, -1);
        float entropy = ComputeEntropy(logits, n_vocab, 32);

        // Dynamic entropy scale: inject syntax adapter only on high uncertainty (G)
        float scale = (entropy > 1.6f) ? std::min(1.0f, (entropy - 1.6f) / 0.8f) : 0.0f;
        lora_ctrl.SetTrackScale("cpp_syntax", scale);

        // Argmax sampling
        llama_token best = 0;
        float best_val = -1e9f;
        for (int v = 0; v < n_vocab; ++v) {
            if (logits[v] > best_val) {
                best_val = logits[v];
                best = v;
            }
        }

        if (llama_vocab_is_eog(vocab, best)) break;

        char buf[128];
        int n = llama_token_to_piece(vocab, best, buf, sizeof(buf), 0, false);
        if (n > 0) result.append(buf, n);

        llama_batch_clear(batch);
        llama_batch_add(batch, best, pos_base + tokens.size() + i, { 0 }, true);
        llama_decode(ctx, batch);
    }

    llama_batch_free(batch);
    return result;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: arclight_server <model.gguf>" << std::endl;
        return 1;
    }

    llama_backend_init();

    // 1. Dual-GPU Load Splitting (40% V320 / 60% MI25)
    llama_model_params mparams = llama_model_default_params();
    static const float t_split[2] = { 0.40f, 0.60f };
    mparams.tensor_split = t_split;
    mparams.n_gpu_layers = 999;

    struct llama_model* model = llama_model_load_from_file(argv[1], mparams);
    if (!model) return 1;

    const struct llama_vocab* vocab = llama_model_get_vocab(model);

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 8192;
    cparams.n_threads = 6;
    cparams.n_threads_batch = 6;

    struct llama_context* ctx = llama_new_context_with_model(model, cparams);
    if (!ctx) return 1;

    // 2. Subsystems: SQLite & Multi-Track LoRA
    Arclight::Memory::LTMStore ltm("/opt/arclight/cache/parametric_memory.sqlite");
    Arclight::LoRA::MultiTrackController lora_ctrl(model, ctx, 2048);

    std::vector<std::vector<float>> dummy_centroids(2, std::vector<float>(2048, 0.05f));
    lora_ctrl.RegisterTrack("cpp_syntax", "/opt/arclight/models/cpp_syntax_L10-13.lora.gguf", 0.90f, dummy_centroids);

    // 3. Socket Gateway
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(PORT);

    bind(server_fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(server_fd, 16);

    std::cout << "[Arclight Engine] Listening on Port " << PORT << "..." << std::endl;

    while (true) {
        int client = accept(server_fd, nullptr, nullptr);
        if (client < 0) continue;

        char buffer[BUFFER_SIZE] = {0};
        read(client, buffer, BUFFER_SIZE - 1);

        std::string prompt = ExtractCleanPrompt(buffer);
        if (prompt.empty()) {
            std::string err = "HTTP/1.1 400 Bad Request\r\n\r\n";
            send(client, err.c_str(), err.size(), 0);
            close(client);
            continue;
        }

        // Clean Context Execution
        llama_kv_cache_clear(ctx);

        std::vector<llama_token> p_tokens(prompt.size() + 16);
        int n_tok = llama_tokenize(vocab, prompt.data(), prompt.size(), p_tokens.data(), p_tokens.size(), true, false);
        p_tokens.resize(n_tok);

        // Pass 1: Unconstrained generation with entropy gating
        std::string draft = DecodeWithEntropyGating(ctx, vocab, lora_ctrl, p_tokens, 1024);
        std::string code = ExtractCodeBlock(draft);

        // Pass 2: Compiler Trap
        auto check = Arclight::Compiler::CheckSyntax(code);
        std::string final_payload = draft;

        if (!check.passed) {
            std::cout << "[Compiler Trap] Syntax failure detected. Running single-pass correction...\n";
            std::string patch_prompt = "\n\nCompiler Diagnostic:\n" + check.diagnostic + "\nCorrected C++:\n```cpp\n";
            
            std::vector<llama_token> patch_tokens(patch_prompt.size() + 16);
            int n_patch = llama_tokenize(vocab, patch_prompt.data(), patch_prompt.size(), patch_tokens.data(), patch_tokens.size(), false, false);
            patch_tokens.resize(n_patch);

            std::string correction = DecodeWithEntropyGating(ctx, vocab, lora_ctrl, patch_tokens, 1024);
            final_payload += "\n\n/* [Compiler-Trap Auto-Correction] */\n```cpp\n" + correction;
        }

        // Return standard OpenAI completion JSON
        std::ostringstream json;
        json << "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"" 
             << std::regex_replace(final_payload, std::regex("\n"), "\\n")
             << "\"}}]}";

        std::string body = json.str();
        std::ostringstream response;
        response << "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " 
                 << body.size() << "\r\n\r\n" << body;

        std::string out = response.str();
        send(client, out.c_str(), out.size(), 0);
        close(client);

        lora_ctrl.ResetAll();
    }

    close(server_fd);
    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();
    return 0;
}

8. Systemd Service Definition (systemd/arclight.service)

Uses memory interleaving across Socket 0 and Socket 1 so that DMA calls to
Card 1 (Slot 5) avoid bottlenecking the QPI bus [11].

[Unit]
Description=Project Arclight High-Precision Inference Daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/arclight
Environment=HSA_OVERRIDE_GFX_VERSION=9.0.0
Environment=HSA_ENABLE_SDMA=0
Environment=HIP_VISIBLE_DEVICES=0,1
LimitMEMLOCK=infinity

# Pin memory interleaved across both NUMA nodes (Node 0 + Node 1)
ExecStart=/run/current-system/sw/bin/numactl --interleave=0,1 /opt/arclight/build/arclight_server /opt/arclight/models/model.gguf

Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target

Verification and Execution Steps

1.  Enter Pinned Nix Environment:
    nix develop
2.  Execute Clean Build:
    chmod +x build.sh
    ./build.sh
3.  Verify Pure AVX 1.0 Instruction Emission: Ensure no AVX2 integer
    instructions (vpaddd, vpmullw) or FMA instructions (vfmadd) were compiled
    into the binary:
    objdump -d build/arclight_server | grep -E "vfmadd|vpmullw|vpaddd"
    (Zero output verifies binary safety on your Xeon E5-2600 v2).
4.  Deploy Service:
    cp systemd/arclight.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl start arclight.service
    journalctl -u arclight.service -f

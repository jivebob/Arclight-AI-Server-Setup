Dockerfile
FROM docker.io/rocm/dev-ubuntu-22.04:6.0.2

ENV DEBIAN_FRONTEND=noninteractive
ENV HSA_OVERRIDE_GFX_VERSION=9.0.0
ENV HSA_ENABLE_SDMA=0
ENV HIP_VISIBLE_DEVICES=0,1

# 1. Install core build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    pkg-config \
    ca-certificates \
    numactl \
    && rm -rf /var/lib/apt/lists/*

# 2. Clone modern llama.cpp (b11493+ with Gemma 4 support)
WORKDIR /build
RUN git clone https://github.com/ggml-org/llama.cpp.git && \
    cd llama.cpp && \
    git checkout 847f447c3

WORKDIR /build/llama.cpp

# 3. Apply our verified patches directly
RUN sed -i -E 's/if.*VERSION_LESS.*6\.1.*/if (FALSE)/g' ggml/src/ggml-hip/CMakeLists.txt && \
    sed -i 's/#define cudaStreamWaitEvent hipStreamWaitEvent/inline static hipError_t ggml_hipStreamWaitEvent(hipStream_t stream, hipEvent_t event, unsigned int flags = 0) { return hipStreamWaitEvent(stream, event, flags); }\n#define cudaStreamWaitEvent ggml_hipStreamWaitEvent/g' ggml/src/ggml-cuda/vendors/hip.h && \
    sed -i 's/-mavx2//g' CMakeLists.txt && \
    sed -i 's/-mfma//g' CMakeLists.txt && \
    sed -i -E 's/ggml_add_cpu_backend_variant\((haswell|skylakex|icelake|alderlake|sapphirerapids)/# &/g' ggml/src/ggml-cpu/CMakeLists.txt

# 4. Compile strictly for gfx900 on Ivy Bridge AVX1 + F16C
RUN cmake -B build \
    -DGGML_HIP=ON \
    -DGPU_TARGETS=gfx900 \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=OFF \
    -DGGML_CPU_ALL_VARIANTS=OFF \
    -DGGML_BACKEND_DL=OFF \
    -DGGML_AVX=ON \
    -DGGML_F16C=ON \
    -DGGML_AVX2=OFF \
    -DGGML_FMA=OFF \
    -DLLAMA_AVX=ON \
    -DLLAMA_F16C=ON \
    -DLLAMA_AVX2=OFF \
    -DLLAMA_FMA=OFF \
    -DCMAKE_C_FLAGS="-mavx -mf16c -mno-avx2 -mno-fma -mno-bmi2 -mno-avx512f" \
    -DCMAKE_CXX_FLAGS="-mavx -mf16c -mno-avx2 -mno-fma -mno-bmi2 -mno-avx512f" && \
    cmake --build build --config Release -j 6

# 5. Runtime environment
WORKDIR /opt/arclight
RUN cp /build/llama.cpp/build/bin/llama-server /usr/local/bin/ && \
    cp /build/llama.cpp/build/bin/llama-cli /usr/local/bin/ && \
    rm -rf /build

VOLUME ["/models"]
EXPOSE 8080

ENTRYPOINT ["llama-server"]
CMD ["--model", "/models/model.gguf", "--host", "0.0.0.0", "--port", "8080", "--n-gpu-layers", "999", "--split-mode", "layer", "--tensor-split", "1,1", "--ctx-size", "8192", "--flash-attn", "off", "--cache-type-k", "f16", "--cache-type-v", "f16"]

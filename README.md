# AMD-RDNA3-Vulkan-1.4.344-VIBE-CODING
흔한 폰덕후의 Gemini와 협력해본 바이브코딩 (Feat. AMD RDNA3)

# Vulkan 1.4 & Low-Level ISA Pipeline Archive
> **Target Architectures:** AMD RDNA3 (Wave32/Wave64) & ARM SVE2/SME2
> **Key Features:** Low-Level Parallel Compute, Subgroup Reduction, Packed SIMD Operations, Buffer Alignment Guard

---

## 1. AMD RDNA Wave32 Target - FP32 Single Pipeline
```glsl
#version 460
#extension GL_KHR_shader_subgroup_basic: require
#extension GL_KHR_shader_subgroup_arithmetic: require

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in; // Wave32 Alignment

layout(set = 0, binding = 0) readonly buffer InputFP32 {
    float in_data32[];
};

layout(set = 0, binding = 1) writeonly buffer OutputFP32 {
    float out_data32[];
};

void main() {
    uint idx = gl_GlobalInvocationID.x;
    
    // IEEE 754 Standard FP32 Pass
    float val = in_data32[idx];
    float res = val * val + 2.0f;
    
    // Wave32 Subgroup Reduction
    out_data32[idx] = subgroupAdd(res);
}

#version 460
#extension GL_KHR_shader_subgroup_basic: require
#extension GL_KHR_shader_subgroup_arithmetic: require

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in; // Wave64 Alignment

layout(set = 0, binding = 0) readonly buffer InputFP32_W64 {
    float in_data32_w64[];
};

layout(set = 0, binding = 1) writeonly buffer OutputFP32_W64 {
    float out_data32_w64[];
};

void main() {
    uint idx = gl_GlobalInvocationID.x;
    float val = in_data32_w64[idx];
    float res = val * val + 2.0f;
    
    // Wave64 Subgroup Reduction
    out_data32_w64[idx] = subgroupAdd(res);
}

#version 460
#extension GL_EXT_shader_16bit_storage: require
#extension GL_KHR_shader_subgroup_basic: require
#extension GL_KHR_shader_subgroup_arithmetic: require

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) readonly buffer InputFP16_W32 {
    float16_t in_data16_w32[];
};

layout(set = 0, binding = 1) writeonly buffer OutputFP16_W32 {
    float16_t out_data16_w32[];
};

void main() {
    uint idx = gl_GlobalInvocationID.x;
    
    // Native FP16 Pipeline Pass
    float16_t val = in_data16_w32[idx];
    float16_t res = val * val + float16_t(2.0);
    
    // 16-bit Subgroup Operation
    out_data16_w32[idx] = subgroupAdd(res);
}

#version 460
#extension GL_EXT_shader_16bit_storage: require
#extension GL_KHR_shader_subgroup_basic: require
#extension GL_KHR_shader_subgroup_arithmetic: require

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) readonly buffer InputFP16_W64 {
    float16_t in_data16_w64[];
};

layout(set = 0, binding = 1) writeonly buffer OutputFP16_W64 {
    float16_t out_data16_w64[];
};

void main() {
    uint idx = gl_GlobalInvocationID.x;
    float16_t val = in_data16_w64[idx];
    float16_t res = val * val + float16_t(2.0);
    out_data16_w64[idx] = subgroupAdd(res);
}

#version 460
#extension GL_KHR_shader_subgroup_basic: require
#extension GL_KHR_shader_subgroup_arithmetic: require
#extension GL_EXT_shader_16bit_storage: require

// 2048-bit (256 bytes) Stream Sample -> 64 x 32-bit Slots
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) readonly buffer SampleBuffer2048 {
    uint data2048[];
};

layout(set = 0, binding = 1) writeonly buffer ResultBuffer {
    uint processedResult[];
};

// Local Data Share (LDS) for Workgroup Tile Synchronization
shared uint Tile2048[64];

void main() {
    uint localID = gl_LocalInvocationID.x; // 0~63
    uint groupID = gl_WorkGroupID.x;
    uint globalIdx = (groupID * 64) + localID;

    // 1. Load Stream Data
    uint rawValue = data2048[globalIdx];

    // 2. Subgroup Bit Manipulation (Emulating SVE2 Predicate Operations)
    uint computed = rawValue ^ (rawValue << 1);

    // 3. Tile Store & Workgroup Barrier
    Tile2048[localID] = computed;
    memoryBarrierShared();
    barrier();

    // 4. Output Store Stage
    processedResult[globalIdx] = Tile2048[localID];
}

#version 460
#extension GL_EXT_shader_16bit_storage: require
#extension GL_KHR_shader_subgroup_basic: require
#extension GL_KHR_shader_subgroup_arithmetic: require

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) readonly buffer FP32Input {
    float fp32_in[];
};

layout(set = 0, binding = 1) readonly buffer FP16PackedInput {
    uint fp16_packed_in[];
};

layout(set = 0, binding = 2) writeonly buffer OutputBuffer {
    float result_out[];
};

void main() {
    uint globalID = gl_GlobalInvocationID.x;
    uint waveSize = gl_SubgroupSize; // Dynamic Subgroup Size Bound Check

    // [Path A] Native FP32 Pipeline
    float val_f32 = fp32_in[globalID];
    float computed_f32 = val_f32 * val_f32 + 1.5f;

    // [Path B] Packed FP16x2 Pipeline (SIMD Unpack)
    uint packed_val = fp16_packed_in[globalID];
    vec2 unpacked_f16 = unpackHalf2x16(packed_val);
    vec2 computed_f16 = unpacked_f16 * unpacked_f16 + vec2(1.5h);

    // IEEE 754 Promotion & Reduction
    float final_reduced = computed_f32 + (float(computed_f16.x) + float(computed_f16.y));

    // Branching according to Wavefront Size (Wave32 vs Wave64)
    if (waveSize == 32) {
        result_out[globalID] = subgroupAdd(final_reduced) * 0.5f;
    } else {
        result_out[globalID] = subgroupAdd(final_reduced);
    }
}

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#if defined(_ARM_FEATURE_SVE) && defined(_ARM_FEATURE_SME2)
#include <arm_sve.h>
#include <arm_sme.h>
#endif

#define MES_BUFFER_ALIGNMENT 64
#define MES_PACKET_MASK 0xFFFFFFFFFFFFFFFFULL

// 64-byte Aligned AMD MES Command Packet
alignas(MES_BUFFER_ALIGNMENT) typedef struct {
    uint64_t header_flags;
    uint64_t payload_addr;
    uint32_t size_bytes;
    uint32_t reserved;
    uint64_t extension_meta;
} mes_64bit_packet_t;

static inline bool validate_and_align_buffer(void* raw_ptr, size_t size, mes_64bit_packet_t* out_packet) {
    if (!raw_ptr || !out_packet) return false;

    uintptr_t addr = (uintptr_t)raw_ptr;
    if ((addr & (MES_BUFFER_ALIGNMENT - 1)) != 0) {
        return false; // Alignment Fault
    }

    out_packet->header_flags = 0x1ULL;
    out_packet->payload_addr = (uint64_t)addr;
    out_packet->size_bytes = (uint32_t)size;
    out_packet->reserved = 0;
    out_packet->extension_meta = MES_PACKET_MASK;

#if defined(_ARM_FEATURE_SVE) && defined(_ARM_FEATURE_SME2)
    svbool_t pg = svwhilelt_b8(0, size);
    (void)pg;
#endif

    return true;
}

int process_mes_sme2_aligned_payload(void* input_buffer, size_t buffer_size) {
    mes_64bit_packet_t packet;
    if (!validate_and_align_buffer(input_buffer, buffer_size, &packet)) {
        return -1;
    }
    return 0;
}

#version 460
#extension GL_EXT_shader_16bit_storage: require
#extension GL_EXT_shader_explicit_arithmetic_types_int8: require
#extension GL_EXT_shader_explicit_arithmetic_types_int16: require

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) readonly buffer InputBuffer16 {
    int16_t packedInt16Data[];
};

layout(set = 0, binding = 1) writeonly buffer OutputBuffer32 {
    int32_t resultData[];
};

void main() {
    uint idx = gl_GlobalInvocationID.x;

    // Unpack INT8 values from Packed INT16
    int16_t raw16 = packedInt16Data[idx];
    int8_t val_low = int8_t(raw16 & 0x00FF);
    int8_t val_high = int8_t((raw16 >> 8) & 0x00FF);

    // INT32 Promotion and Accumulation
    int32_t a = int32_t(val_low);
    int32_t b = int32_t(val_high);
    int32_t computed = (a * b) + (a + b);

    resultData[idx] = computed;
}

#version 460
#extension GL_EXT_shader_16bit_storage: require
#extension GL_KHR_shader_subgroup_arithmetic: require

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) readonly buffer InputBuffer {
    uint packedData[];
};

layout(set = 0, binding = 1) writeonly buffer OutputBuffer {
    float resultData[];
};

void main() {
    uint idx = gl_GlobalInvocationID.x;

    // Unpack FP16x2 from 32-bit Container
    uint raw32 = packedData[idx];
    vec2 unpacked_f16 = unpackHalf2x16(raw32);

    // RDNA SIMD Dual Half-Precision Processing
    vec2 computed_f16 = unpacked_f16 * unpacked_f16;

    // Convert to IEEE 754 FP32 Precision Format
    float final_f32 = float(computed_f16.x) + float(computed_f16.y);

    resultData[idx] = final_f32;
}

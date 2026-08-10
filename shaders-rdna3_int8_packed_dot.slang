// 해당코드는 Codex로 수정됨
// Vulkan SPIR-V reference implementation for two signed INT8 values packed
// into one uint16_t storage element.

[[vk::binding(0, 0)]]
StructuredBuffer<uint16_t> packedInt16Data;

[[vk::binding(1, 0)]]
RWStructuredBuffer<int32_t> resultData;

struct DispatchInfo
{
    uint32_t elementCount;
};

[[vk::push_constant]]
ConstantBuffer<DispatchInfo> dispatchInfo;

int32_t decodeSignedByte(uint32_t bits)
{
    uint32_t byteValue = bits & 0xffu;
    return int32_t(byteValue ^ 0x80u) - 128;
}

int32_t dotInt8x2(vector<int8_t, 2> lhs, vector<int8_t, 2> rhs)
{
    // Slang's generic dot(int8, int8) returns int8_t. Emit OpSDot directly so
    // the result is accumulated in signed INT32 without narrowing overflow.
    return spirv_asm
    {
        OpCapability DotProduct;
        OpCapability DotProductInputAll;
        OpSDot $$int result $lhs $rhs;
    };
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
    uint32_t idx = dispatchThreadID.x;
    if (idx >= dispatchInfo.elementCount)
    {
        return;
    }

    uint32_t packed = uint32_t(packedInt16Data[idx]);
    int32_t low = decodeSignedByte(packed);
    int32_t high = decodeSignedByte(packed >> 8u);

    vector<int8_t, 2> lhs = vector<int8_t, 2>(int8_t(low), int8_t(high));
    vector<int8_t, 2> rhs = vector<int8_t, 2>(int8_t(high), int8_t(1));

    // Exactly preserves: low * high + low + high.
    resultData[idx] = dotInt8x2(lhs, rhs) + low;
}

# RDNA3 INT8 packed-dot debugging notes

> 해당코드는 Codex로 수정됨

이 문서는 `AMD RDNA3 INT16 유닛 INT8 중첩연산.pdf`의 아이디어를 컴파일 가능한 형태로 옮기면서 확인한 문제와 수정 내용을 기록한다. 원본 PDF는 아이디어 기록으로 보존한다. `shaders/rdna3_int8_packed_dot.slang`은 실제 SPIR-V 출력을 확인한 기준 구현이고, `shaders/rdna3_int8_packed_dot.comp`는 Vulkan GLSL 대응본이다.

## 확인된 문제

1. 원본은 두 INT8 값을 INT32로 승격한 뒤 `(a * b) + (a + b)`를 계산한다. 이 코드는 결과 자체는 유효하지만, 전용 INT8 dot-product 명령 사용을 보장하지 않는다.
2. `shaderInt8`은 8비트 정수 타입 사용을 허용할 뿐이다. `dotEXT`를 사용하려면 Vulkan 1.3 코어 기능인 `shaderIntegerDotProduct`도 활성화해야 한다.
3. 기준 Slang 셰이더가 생성한 SPIR-V는 `UniformAndStorageBuffer16BitAccess` capability를 선언한다. 따라서 `VkPhysicalDevice16BitStorageFeatures::uniformAndStorageBuffer16BitAccess`를 활성화해야 한다. 16비트 값에는 직접 시프트와 마스킹을 적용하지 않고 먼저 `uint`로 승격한다.
4. 원본에는 디스패치 범위 검사가 없다. 수정본은 push constant의 `elementCount`를 검사하며, 호스트는 이 값이 입력과 출력 버퍼의 원소 수를 넘지 않도록 설정해야 한다.
5. 기능 지원이 곧 하드웨어 가속을 뜻하지 않는다. `integerDotProduct8BitSignedAccelerated` 속성이 `VK_TRUE`인지 별도로 확인해야 한다.
6. Slang의 일반 `dot()`에 `vector<int8_t, 2>`를 넘기면 결과 타입도 `int8_t`가 되어 누산 결과가 좁아진다. 기준 구현은 inline SPIR-V로 입력은 INT8, 결과는 INT32인 `OpSDot`을 명시한다.
7. 기준 타깃은 Vulkan 1.4가 지원하는 SPIR-V 1.6이다. 정수 dot-product 명령은 SPIR-V 1.6 코어이므로 Slang inline SPIR-V에는 `SPV_KHR_integer_dot_product` 확장 선언을 넣지 않는다. GLSL 대응본은 고수준 언어에서 `dotEXT`를 노출하기 위해 `GL_EXT_integer_dot_product`를 계속 요구한다.

## 필요한 Vulkan 기능

Vulkan 1.4에서는 아래 기능들이 코어에 포함되어 있지만 여전히 명시적으로 질의하고 활성화해야 한다.

```cpp
VkPhysicalDeviceShaderIntegerDotProductFeatures supportedDot{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_INTEGER_DOT_PRODUCT_FEATURES};
VkPhysicalDevice16BitStorageFeatures supportedStorage16{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES};
VkPhysicalDeviceShaderFloat16Int8Features supportedInt8{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES};
VkPhysicalDeviceFeatures2 supported{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};

supported.pNext = &supportedInt8;
supportedInt8.pNext = &supportedStorage16;
supportedStorage16.pNext = &supportedDot;
vkGetPhysicalDeviceFeatures2(physicalDevice, &supported);

if (!supportedInt8.shaderInt8 ||
    !supportedStorage16.uniformAndStorageBuffer16BitAccess ||
    !supportedDot.shaderIntegerDotProduct) {
    throw std::runtime_error("Required INT8 packed-dot features are unavailable");
}

VkPhysicalDeviceShaderIntegerDotProductFeatures requestedDot{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_INTEGER_DOT_PRODUCT_FEATURES};
requestedDot.shaderIntegerDotProduct = VK_TRUE;

VkPhysicalDevice16BitStorageFeatures requestedStorage16{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES};
requestedStorage16.uniformAndStorageBuffer16BitAccess = VK_TRUE;
requestedStorage16.pNext = &requestedDot;

VkPhysicalDeviceShaderFloat16Int8Features requestedInt8{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES};
requestedInt8.shaderInt8 = VK_TRUE;
requestedInt8.pNext = &requestedStorage16;

VkPhysicalDeviceFeatures2 requested{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
requested.pNext = &requestedInt8;

VkDeviceCreateInfo createInfo{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
createInfo.pNext = &requested;
createInfo.pEnabledFeatures = nullptr;
// Fill queueCreateInfoCount, pQueueCreateInfos, extension fields, and so on.
```

가속 여부는 프로퍼티 체인에서 별도로 확인한다.

```cpp
VkPhysicalDeviceShaderIntegerDotProductProperties dotProperties{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_INTEGER_DOT_PRODUCT_PROPERTIES};
VkPhysicalDeviceProperties2 properties{
    VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
properties.pNext = &dotProperties;
vkGetPhysicalDeviceProperties2(physicalDevice, &properties);

const bool signedInt8DotIsAccelerated =
    dotProperties.integerDotProduct8BitSignedAccelerated == VK_TRUE;
```

## 검증 방법

```powershell
slangc shaders/rdna3_int8_packed_dot.slang `
  -entry main -stage compute -target spirv `
  -profile spirv_1_6 -o rdna3_int8_packed_dot.spv

slangc shaders/rdna3_int8_packed_dot.slang `
  -entry main -stage compute -target spirv-asm `
  -profile spirv_1_6 -o rdna3_int8_packed_dot.spv-asm

Select-String -Path rdna3_int8_packed_dot.spv-asm `
  -Pattern 'OpSDot %int'

python -m unittest tests/test_packed_int8_reference.py
```

Vulkan GLSL 대응본은 `glslang` 또는 Vulkan SDK의 `glslangValidator`로 별도 컴파일할 수 있다.

SPIR-V에서 `OpSDot`가 확인되어도 RDNA3의 실제 기계 명령은 드라이버가 최종 결정한다. Radeon GPU Analyzer나 드라이버 파이프라인 실행 파일 조회 기능으로 ISA를 확인해야 전용 경로 사용을 입증할 수 있다.

## 참고한 공식 문서

- [VkPhysicalDeviceShaderFloat16Int8Features](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceShaderFloat16Int8Features.html)
- [VkPhysicalDevice16BitStorageFeatures](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDevice16BitStorageFeatures.html)
- [VkPhysicalDeviceShaderIntegerDotProductFeatures](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceShaderIntegerDotProductFeatures.html)
- [Vulkan SPIR-V environment](https://docs.vulkan.org/spec/latest/appendices/spirvenv.html)
- [GL_EXT_shader_16bit_storage](https://docs.vulkan.org/glslext/latest/glslext/ext/GL_EXT_shader_16bit_storage.html)
- [GL_EXT_integer_dot_product](https://docs.vulkan.org/glslext/latest/glslext/ext/GLSL_EXT_integer_dot_product.html)

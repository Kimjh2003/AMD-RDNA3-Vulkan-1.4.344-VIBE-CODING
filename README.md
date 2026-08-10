# AMD-RDNA3-Vulkan-1.4.344-VIBE-CODING

AMD RDNA3를 타겟 ISA로 지정하여
Vulkan 1.4.344 API를 기반으로
WaveFront 32/64 분배 전제 조건 설정 후
FP16 , INT8 중첩 연산 및
각 정밀도에 대한 연산 로직을 바이브 코딩 산출로 시연해 봤습니다
실 구동은 해보지 않은 관계로 구현하시는 프로그램에
써보신 다음 시연해보시고 피드백 및 출처 남기기 부탁드립니다

## 검증 가능한 INT8 중첩 연산 예시

> 해당코드는 Codex로 수정됨

기존 PDF의 `INT16` 공간에 signed `INT8` 두 개를 패킹하는 아이디어를 검증 가능한 Vulkan SPIR-V 1.6 경로로 정리했습니다.

- [`shaders/rdna3_int8_packed_dot.slang`](shaders/rdna3_int8_packed_dot.slang): INT8 입력과 INT32 결과를 강제하고 SPIR-V 1.6 `OpSDot` 생성을 검증한 기준 셰이더
- [`shaders/rdna3_int8_packed_dot.comp`](shaders/rdna3_int8_packed_dot.comp): `GL_EXT_integer_dot_product`를 사용하는 Vulkan GLSL 대응본
- [`docs/rdna3_int8_debug_notes.md`](docs/rdna3_int8_debug_notes.md): 필요한 Vulkan 기능, 가속 여부 확인, 검증 절차
- [`tests/test_packed_int8_reference.py`](tests/test_packed_int8_reference.py): 가능한 65,536개 `uint16_t` 패턴 전체에 대해 원본 수식과 수정 수식의 결과가 같은지 검사

원본 PDF는 아이디어 기록으로 보존합니다. 실제 RDNA3 전용 명령 사용 여부는 SPIR-V의 `OpSDot` 확인에 더해 드라이버가 생성한 ISA까지 확인해야 합니다.

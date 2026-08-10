# 해당코드는 Codex로 수정됨
import unittest


def decode_signed_byte(bits: int) -> int:
    byte_value = bits & 0xFF
    return (byte_value ^ 0x80) - 0x80


def original_expression(packed: int) -> int:
    low = decode_signed_byte(packed)
    high = decode_signed_byte(packed >> 8)
    return (low * high) + low + high


def dot_expression(packed: int) -> int:
    low = decode_signed_byte(packed)
    high = decode_signed_byte(packed >> 8)

    lhs = (low, high)
    rhs = (high, 1)
    return sum(a * b for a, b in zip(lhs, rhs)) + low


class PackedInt8ReferenceTest(unittest.TestCase):
    def test_signed_boundaries(self) -> None:
        self.assertEqual(decode_signed_byte(0x00), 0)
        self.assertEqual(decode_signed_byte(0x7F), 127)
        self.assertEqual(decode_signed_byte(0x80), -128)
        self.assertEqual(decode_signed_byte(0xFF), -1)

    def test_all_uint16_patterns_preserve_the_original_result(self) -> None:
        for packed in range(1 << 16):
            with self.subTest(packed=packed):
                self.assertEqual(dot_expression(packed), original_expression(packed))


if __name__ == "__main__":
    unittest.main()

"""Fixed arithmetic/byte-order goldens independent of the RTL decoder."""
import unittest
from rv32_reference import RV32Reference
from run_upgrade import image, i_type, r_type, store, EBREAK

class RV32OracleTests(unittest.TestCase):
    def test_integer_boundaries(self):
        words=[0x800000b7,i_type(0x13,0,2,0,-1),i_type(0x13,0,3,0,31),
               r_type(32,5,4,1,3),r_type(0,5,5,1,3),r_type(0,2,6,1,2),
               r_type(0,3,7,1,2),i_type(0x13,0,8,1,-1),r_type(0,1,9,8,2),0x00000517,EBREAK]
        cpu=RV32Reference(image(words)); cpu.run()
        golden={0:0,1:0x80000000,2:0xffffffff,3:31,4:0xffffffff,
                5:1,6:1,7:1,8:0x7fffffff,9:0x80000000,10:36}
        for register,value in golden.items():
            with self.subTest(register=register): self.assertEqual(cpu.regs[register],value)
        self.assertEqual(cpu.trap,3)

    def test_little_endian_lanes(self):
        words=[i_type(0x13,0,1,0,0x600),i_type(0x03,0,2,1,1),
               i_type(0x03,4,3,1,1),i_type(0x03,1,4,1,2),
               i_type(0x03,5,5,1,2),i_type(0x03,2,6,1,0),
               store(1,1,2,2),store(0,1,5,0),EBREAK]
        binary=bytearray(image(words)); binary.extend(bytes(0x604-len(binary)))
        binary[0x600:0x604]=bytes.fromhex('0180ffa5')
        cpu=RV32Reference(binary); cpu.run()
        self.assertEqual(cpu.regs[2:7],[0xffffff80,0x80,0xffffa5ff,0xa5ff,0xa5ff8001])
        self.assertEqual(cpu.memory[0x600:0x604],bytes.fromhex('ff8080ff'))
        self.assertEqual(cpu.trace[-2]['strb'],12)
        self.assertEqual(cpu.trace[-1]['strb'],1)

    def test_jalr_clears_low_bit_and_traps_before_link_write(self):
        cpu=RV32Reference(image([i_type(0x13,0,2,0,7),i_type(0x67,0,1,2,0),EBREAK])); cpu.run()
        self.assertEqual((cpu.pc,cpu.trap,cpu.regs[1]),(4,0,0))

if __name__=='__main__': unittest.main()

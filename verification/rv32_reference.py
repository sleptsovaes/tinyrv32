"""Instruction-level oracle for the latency-tolerant core (little-endian RV32I).

No timing/prediction logic is shared with RTL. Traps stop the execution
environment; this model does not implement privileged trap handlers.
"""
from collections import Counter

MASK = 0xffffffff
UART = 0x10000000
STATUS = 0x10000004
TRACE_FIELDS = ('pc','instruction','next_pc','rd','rd_data','store','address','store_data','strb')


def sx(value, width):
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


class Trap(Exception):
    def __init__(self, cause):
        self.cause = cause


class RV32Reference:
    def __init__(self, image, memory_bytes=16384):
        if len(image) > memory_bytes:
            raise ValueError('Image exceeds RAM')
        self.memory = bytearray(memory_bytes)
        self.memory[:len(image)] = image
        self.regs = [0]*32
        self.pc = 0
        self.trace = []
        self.coverage = Counter()
        self.uart = []
        self.status = None
        self.trap = None

    def read(self, address, size):
        if address % size:
            raise Trap(4)
        if not 0 <= address <= len(self.memory)-size:
            raise ValueError(f'Out-of-range load {address:08x}')
        return int.from_bytes(self.memory[address:address+size], 'little')

    def step(self):
        pc = self.pc
        if pc % 4 or not 0 <= pc <= len(self.memory)-4:
            raise ValueError(f'Invalid fetch {pc:08x}')
        ins = int.from_bytes(self.memory[pc:pc+4], 'little')
        op, f3, f7 = ins & 127, (ins >> 12)&7, ins >> 25
        rd, r1, r2 = (ins>>7)&31, (ins>>15)&31, (ins>>20)&31
        a, b = self.regs[r1], self.regs[r2]
        ni = (pc+4)&MASK
        value = None; address = data = strb = store = 0
        name = ''
        imm = sx(ins>>20,12)
        try:
            if op in (0x37,0x17):
                name = 'LUI' if op == 0x37 else 'AUIPC'
                value = (ins & 0xfffff000) + (pc if op == 0x17 else 0)
            elif op in (0x6f,0x67):
                if op == 0x6f:
                    off = sx(((ins>>31)<<20)|(((ins>>12)&255)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&1023)<<1),21)
                    ni=(pc+off)&MASK; name='JAL'
                else:
                    if f3: raise Trap(2)
                    ni=((a+imm)&MASK)&~1; name='JALR'
                value=pc+4
            elif op == 0x63:
                off=sx(((ins>>31)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&63)<<5)|(((ins>>8)&15)<<1),13)
                outcomes={0:('BEQ',a==b),1:('BNE',a!=b),4:('BLT',sx(a,32)<sx(b,32)),
                          5:('BGE',sx(a,32)>=sx(b,32)),6:('BLTU',a<b),7:('BGEU',a>=b)}
                if f3 not in outcomes: raise Trap(2)
                name,taken=outcomes[f3]
                self.coverage[name+('_taken' if taken else '_not_taken')]+=1
                if taken: ni=(pc+off)&MASK
            elif op in (0x13,0x33):
                rhs=imm&MASK if op==0x13 else b
                shift=(ins>>20)&31 if op==0x13 else b&31
                if op==0x33:
                    if f7 not in (0,32) or (f7==32 and f3 not in (0,5)): raise Trap(2)
                elif f3==1 and f7!=0 or f3==5 and f7 not in (0,32): raise Trap(2)
                table={0:('SUB',a-rhs) if op==0x33 and f7==32 else ('ADD',a+rhs),
                       1:('SLL',a<<shift),2:('SLT',int(sx(a,32)<sx(rhs,32))),
                       3:('SLTU',int(a<rhs)),4:('XOR',a^rhs),
                       5:('SRA',sx(a,32)>>shift) if f7==32 else ('SRL',a>>shift),
                       6:('OR',a|rhs),7:('AND',a&rhs)}
                name,value=table[f3]
                if op==0x13: name = 'SLTIU' if name=='SLTU' else name+'I'
            elif op == 0x03:
                if f3 not in (0,1,2,4,5): raise Trap(2)
                size={0:1,1:2,2:4,4:1,5:2}[f3]
                value=self.read((a+imm)&MASK,size)
                if f3 in (0,1): value=sx(value,8*size)
                name={0:'LB',1:'LH',2:'LW',4:'LBU',5:'LHU'}[f3]
            elif op == 0x23:
                if f3 not in (0,1,2): raise Trap(2)
                size=1<<f3
                off=sx(((ins>>25)<<5)|((ins>>7)&31),12)
                address=(a+off)&MASK
                if address%size: raise Trap(6)
                store=1; strb=((1<<size)-1)<<(address%4)
                data=(b<<(8*(address%4)))&MASK
                name={0:'SB',1:'SH',2:'SW'}[f3]
                if address==UART:
                    self.uart.append(b&255)
                elif address==STATUS:
                    self.status=b&MASK
                elif 0<=address<=len(self.memory)-size:
                    self.memory[address:address+size]=(b&((1<<(8*size))-1)).to_bytes(size,'little')
                else: raise ValueError(f'Out-of-range store {address:08x}')
            elif op == 0x0f and f3 == 0:
                name='FENCE'
            elif op == 0x73:
                raise Trap(3 if ins==0x00100073 else 11 if ins==0x00000073 else 2)
            else: raise Trap(2)
            if ni%4: raise Trap(0)
        except Trap as error:
            self.trap=error.cause
            return False
        write_rd=rd if value is not None and rd else 0
        if write_rd: self.regs[rd]=value&MASK
        self.regs[0]=0
        record=dict(zip(TRACE_FIELDS,[pc,ins,ni,write_rd,self.regs[rd] if write_rd else 0,
                                     store,address,data,strb]))
        self.trace.append(record)
        self.coverage[name]+=1
        self.pc=ni
        return True

    def run(self, limit=200000):
        for _ in range(limit):
            if not self.step(): return
        raise ValueError('Reference instruction limit exceeded')

    def expected(self):
        return dict(pc=self.pc,registers=self.regs,
                    memory=[int.from_bytes(self.memory[i:i+4],'little')
                            for i in range(0,len(self.memory),4)],
                    trace=self.trace,trap=self.trap,uart=self.uart,status=self.status,
                    coverage=dict(self.coverage))

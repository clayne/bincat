import pytest
import os
from util import PowerPC

powerpc = PowerPC(os.path.join(os.path.dirname(os.path.realpath(__file__)),'powerpc.ini.in'))
compare = powerpc.compare


def test_nop(tmpdir):
    asm = """
        ori %r0,%r31,0
        nop
    """
    compare(tmpdir, asm, [])


def test_assign(tmpdir):
    asm = """
        lis %r3, 0x1234
        ori %r3, %r3, 0x5678
    """
    compare(tmpdir, asm, ["r3"])

def test_assign2(tmpdir):
    asm = """
        lis %r3, 0x1234
        ori %r3, %r3, 0x5678
        lis %r4, 0xffff
        ori %r4, %r4, 0xA5A5
        lis %r5, 0xA1B2
        ori %r5, %r5, 0xD4C3
    """
    compare(tmpdir, asm, ["r3", "r4", "r5"])

def test_add(tmpdir):
    asm = """
        lis %r3, 0x1234
        ori %r3, %r3, 0x5678
        lis %r4, 0xabcd
        ori %r4, %r4, 0xffff
        add %r5, %r3, %r4
    """
    compare(tmpdir, asm, ["r3", "r4", "r5" ])

def test_xxx(tmpdir):
    asm = """
    sradi %r3, %r4, 5
    std %r3, 20(%r5)
    stswi %r3, %r4, 3
    tlbia
    """
    compare(tmpdir, asm, ["r3", "r4", "r5" ])

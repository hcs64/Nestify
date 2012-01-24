#!/usr/bin/python

def print_cycles(name, cycles):
    print "byte %s_cycles[1] = {%d}" % (name, cycles)

def print_udp(bytes):
    rows = int((bytes + 2)/3)
    print "    cu_update_data_ptr(%d)" % rows

def line_to_offset(lines):
    return "dlist_data_%d+%d" % ((lines+2)%3, (lines+2)/3)

print "// generated code (codegen.py) follows:"
print
print "// ******** runtime commands"

# set N lines

# 1-7
for n in range(1, 8):
    name = "rt_set_%d_lines" % n
    print_cycles(name, 22+n*8)
    print "function %s()\n{" % name
    print "    cu_set_addr()"
    for i in range(n):
        print "    cu_write_line(%s)" % line_to_offset(i)
    print_udp(2+n)
    print "}\n"

# special cases for 8
print """inline ct_set_8_lines(page)
{
    lda #page
    sta $2006
    lda dlist_data_0, Y
    sta $2006"""

for i in range(0,8):
    print "    cu_write_line(dlist_data_%d+%d)" % ((1+i)%3, (1+i)/3)

print "    cu_update_data_ptr(3)\n}\n"

for n in range(0,32):
    name = "rt_set_8_lines_%d" % n
    print_cycles(name, 90)
    print "function %s() { ct_set_8_lines(%d) }\n" % (name, n)

# clear N lines
for n in range(1,9):
    name = "rt_clr_%d_lines" % n
    print_cycles(name, 24+n*4)
    print "function %s()\n{" % name
    print "    cu_set_addr()\n    lda #0"
    for i in range(n):
        print "    sta $2007"

    print_udp(2)
    print "}\n"

# operate on N lines

# special case for 1
print """// 42 cycles
inline ct_X_1_lines(op)
{
    cu_set_addr_prep(page)
    cu_op_line(op, dlist_data_0+2)

    stx $2006
    sta $2007

    cu_update_data_ptr(1)
}
"""
print_cycles("rt_and_1_lines", 52)
print "function rt_and_1_lines() { ct_X_1_lines(and) }\n"
print_cycles("rt_ora_1_lines", 52)
print "function rt_ora_1_lines() { ct_X_1_lines(ora) }\n"

# 2-7
for n in range(2,8):
    print "inline ct_X_%d_lines(op)\n{" % n
    print "    cu_set_addr_prep()"
    for i in range(n):
        print "    cu_op_sta_line(op, %s, %d, %d)" % (line_to_offset(i), i, n)
    print "    stx $2006"
    print_udp(2+n)
    print "    cu_jmp_zpwr_lines(%d)\n}\n" % n

    name = "rt_and_%d_lines" % n
    print_cycles(name, 37+n*17)
    print "function noreturn %s() { ct_X_%d_lines(and) }\n" % (name, n)

    name = "rt_ora_%d_lines" % n
    print_cycles(name, 37+n*17)
    print "function noreturn %s() { ct_X_%d_lines(ora) }\n" % (name, n)

# special cases for 8
print """inline ct_X_8_lines(op, page)
{
    lda #page
    sta $2006
    ldx dlist_data_0, Y
    stx $2006
    sta $2006
    lda $2007"""

for i in range(0,8):
    print "    cu_op_sta_line(op, dlist_data_%d+%d, %d, %d)" % ((1+i)%3, (1+i)/3, i, 8)

print "    cu_update_data_ptr(3)"
print "    stx $2006\n    cu_jmp_zpwr_lines(%d)\n}\n" % n

for n in range(0,32):
    name = "rt_and_8_lines_%d" % n
    print_cycles(name, 177)
    print "function noreturn %s() { ct_X_8_lines(and, %d) }\n" % (name, n)

    name = "rt_ora_8_lines_%d" % n
    print_cycles(name, 177)
    print "function noreturn %s() { ct_X_8_lines(ora, %d) }\n" % (name, n)

# copy & operate

# special case to simply copy the whole tile
print_cycles("rt_copy_tile", 151)
print """function noreturn rt_copy_tile()
{
    cu_set_addr_prep()
    cu_copy_line(0)
    cu_copy_line(1)
    cu_copy_line(2)
    cu_copy_line(3)
    cu_copy_line(4)
    cu_copy_line(5)
    cu_copy_line(6)
    cu_copy_line(7)

    lda flip_nametable, X
    sta $2006
    cu_update_data_ptr(1)
    jmp zp_writer
}\n"""

for length in range(1,8):
    for start in range(0,8-length+1):
        end = start + length-1

        print "inline ct_copy_X_%d_%d(op)\n{" % (start, end)

        print "    cu_set_addr_prep()"
        for i in range(8):
            if i >= start and i <= end:
                print "    cu_updt_line(op, %s, %d)" % (line_to_offset(i-start), i)
            else:
                print "    cu_copy_line(%d)" % i


        print "    lda flip_nametable, X\n    sta $2006"
        print_udp(2+length)
        print "    jmp zp_writer\n}\n"

        name = "rt_copy_and_%d_%d" % (start, end)
        print_cycles(name, 95+length*11+(8-length)*7)
        print "function noreturn %s() { ct_copy_X_%d_%d(and) }\n" % (name, start, end)

        name = "rt_copy_ora_%d_%d" % (start, end)
        print_cycles(name, 95+length*11+(8-length)*7)
        print "function noreturn %s() { ct_copy_X_%d_%d(ora) }\n" % (name, start, end)


# set N lines, clear others

for length in range(1,8):
    for start in range(0,8-length+1):
        end = start + length-1

        name = "ct_setclr_%d_%d" % (start, end)
        print_cycles(name, 30+8*length+4*(8-length))
        print "function %s()\n{" % name

        print "    cu_set_addr()\n    ldx #0"
        for i in range(8):
            if i >= start and i <= end:
                print "    cu_write_line(%s)" % line_to_offset(i-start)
            else:
                print "    sta $2007"

        print_udp(2+length)
        print "}\n"


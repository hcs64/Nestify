#!/usr/bin/python

def print_cycles(name, cycles):
    print "byte %s_cycles[1] = {%d}" % (name, cycles)

def line_to_offset(lines):
    return "(dlist_bitmap_%d-1)+%d" % (lines/2, lines % 2)

print "// generated code (codegen.py) follows:"
print
print "// ******** runtime commands"

# set N lines

# 1-7
for n in range(1, 8):
    name = "rt_set_%d_lines" % n
    print_cycles(name, 23+n*8)
    print "function %s()\n{" % name
    print "    cu_set_addr()"
    for i in range(n):
        print "    cu_write_line(%s)" % line_to_offset(i)
    print "}\n"

# special cases for 8
print """inline ct_set_8_lines(page)
{
    cu_set_addr_page(page)"""

for i in range(0,8):
    print "    cu_write_line(%s)" % line_to_offset(i)

print "}\n"

for n in range(0,32):
    name = "rt_set_8_lines_%d" % n
    print_cycles(name, 85)
    print "function %s() { ct_set_8_lines(%d) }\n" % (name, n)

# clear N lines
for n in range(1,9):
    name = "rt_clr_%d_lines" % n
    print_cycles(name, 25+n*4)
    print "function %s()\n{" % name
    print "    cu_set_addr()\n    lda #0"
    for i in range(n):
        print "    sta $2007"

    print "}\n"

# operate on N lines

# special case for 1
print """inline ct_X_1_lines(op)
{
    cu_set_addr_prep()
    cu_op_line(op, dlist_bitmap_0-1)

    sty $2006
    sta $2007
}
"""
print_cycles("rt_and_1_lines", 47)
print "function rt_and_1_lines() { ct_X_1_lines(and) }\n"
print_cycles("rt_ora_1_lines", 47)
print "function rt_ora_1_lines() { ct_X_1_lines(ora) }\n"

# 2-7
for n in range(2,8):
    print "inline ct_X_%d_lines(op)\n{" % n
    print "    cu_set_addr_prep()"
    for i in range(n):
        print "    cu_op_sta_line(op, %s, %d, %d)" % (line_to_offset(i), i, n)
    print "    sty $2006"
    print "    cu_jmp_zpwr_lines(%d)\n}\n" % n

    name = "rt_and_%d_lines" % n
    print_cycles(name, 38+n*17)
    print "function noreturn %s() { ct_X_%d_lines(and) }\n" % (name, n)

    name = "rt_ora_%d_lines" % n
    print_cycles(name, 38+n*17)
    print "function noreturn %s() { ct_X_%d_lines(ora) }\n" % (name, n)

# special cases for 8
print """inline ct_X_8_lines(op, page)
{
    cu_set_addr_prep_page(page)"""

for i in range(0,8):
    print "    cu_op_sta_line(op, %s, %d, %d)" % (line_to_offset(i), i, 8)

print "    sty $2006\n    jmp zp_writer\n}\n"

for n in range(0,32):
    name = "rt_and_8_lines_%d" % n
    print_cycles(name, 174)
    print "function noreturn %s() { ct_X_8_lines(and, %d) }\n" % (name, n)

    name = "rt_ora_8_lines_%d" % n
    print_cycles(name, 174)
    print "function noreturn %s() { ct_X_8_lines(ora, %d) }\n" % (name, n)

# copy & operate

# special case to simply copy the whole tile
print_cycles("rt_copy_tile", 145)
print """function noreturn rt_copy_tile()
{
    cu_set_addr_prep_flip()

    cu_copy_line(0)
    cu_copy_line(1)
    cu_copy_line(2)
    cu_copy_line(3)
    cu_copy_line(4)
    cu_copy_line(5)
    cu_copy_line(6)
    cu_copy_line(7)

    sty $2006
    jmp zp_writer
}\n"""

# 1-7
for length in range(1,8):
    for start in range(0,8-length+1):
        end = start + length-1

        print "inline ct_copy_X_%d_%d(op)\n{" % (start, end)

        print "    cu_set_addr_prep_flip()"
        for i in range(8):
            if i >= start and i <= end:
                print "    cu_updt_line(op, %s, %d)" % (line_to_offset(i-start), i)
            else:
                print "    cu_copy_line(%d)" % i


        print "    sty $2006"
        print "    jmp zp_writer\n}\n"

        name = "rt_copy_and_%d_%d" % (start, end)
        print_cycles(name, 88+length*11+(8-length)*7)
        print "function noreturn %s() { ct_copy_X_%d_%d(and) }\n" % (name, start, end)

        name = "rt_copy_ora_%d_%d" % (start, end)
        print_cycles(name, 88+length*11+(8-length)*7)
        print "function noreturn %s() { ct_copy_X_%d_%d(ora) }\n" % (name, start, end)

# special cases for 8
print """inline ct_copy_X_all(op, page)
{
    cu_set_addr_prep_flip_page(page)"""

for i in range(0,8):
    print "    cu_updt_line(op, %s, %d)" % (line_to_offset(i), i)

print "    sty $2006\n    jmp zp_writer\n}\n"

for n in range(0,32):
    name = "rt_copy_and_all_%d" % n
    print_cycles(name, 174)
    print "function noreturn %s() { ct_copy_X_all(and, %d) }\n" % (name, n)

for n in range(0,32):
    name = "rt_copy_ora_all_%d" % n
    print_cycles(name, 174)
    print "function noreturn %s() { ct_copy_X_all(ora, %d) }\n" % (name, n)

# set N lines, clear others

for length in range(1,8):
    for start in range(0,8-length+1):
        end = start + length-1

        name = "rt_setclr_%d_%d" % (start, end)
        print_cycles(name, 25+8*length+4*(8-length))
        print "function %s()\n{" % name

        print "    cu_set_addr()\n    ldy #0"
        for i in range(8):
            if i >= start and i <= end:
                print "    cu_write_line(%s)" % line_to_offset(i-start)
            else:
                print "    sty $2007"

        print "}\n"


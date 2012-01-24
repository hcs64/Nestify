#!/usr/bin/python

def print_header(name, args = ""):
    print "inline ct_%s(page%s)\n{" % (name, args)

def print_udp(databytes):
    print "    cu_update_data_ptr(%d)" % databytes

def print_inst(name, specialname = "", args = "", needret = 0):
    fcnstr = "function noreturn"
    if needret:
        fcnstr = "function"

    if specialname == "":
        specialname = name

    for i in range(3):
        print "%s cmd%d_%s() { ct_%s(%d%s) }" % (fcnstr, i, specialname, name, i, args)

    print

print "// generated code (codegen.py) follows:"
print
print "// ******** runtime command templates"

# set N lines

for n in range(1, 9):
    name = "set_%d_lines" % n
    print_header(name)
    print "    cu_set_addr(page)"
    for i in range(n):
        print "    cu_write_line(page, %d)" % i
    print_udp(2+n)
    print "}\n"
    print_inst(name, name, "", 1)

# clear N lines
for n in range(1,9):
    name = "clr_%d_lines" % n
    print_header(name)
    print "    cu_set_addr(page)\n    lda #0"
    for i in range(n):
        print "    sta $2007"

    print_udp(2)
    print "}\n"
    print_inst(name, name, "", 1)


# operate on N lines

# special case for 1
print """// 42 cycles
inline ct_X_1_lines(page, op)
{
    cu_set_addr_prep(page)  // 24
    cu_op_line(page, op, 0) // 8

    stx $2006   // 4
    sta $2007   // 4

    cu_update_data_ptr_lines(1) // 6
}"""

print_inst("X_1_lines", "and_1_lines", ", and", 1)
print_inst("X_1_lines", "ora_1_lines", ", ora", 1)

for n in range(2,9):
    name = "X_%d_lines" % n
    print_header(name, ", op")
    print "    cu_set_addr_prep(page)"
    for i in range(n):
        print "    cu_op_sta_line(page, op, %d, %d)" % (i, n)
    print "    stx $2006"
    print_udp(2+n)
    print "    cu_jmp_zpwr_lines(%d)\n}\n" % n
    print_inst(name, "and_%d_lines" % n, ", and")
    print_inst(name, "ora_%d_lines" % n, ", ora")


# copy & operate

# special case to simply copy the whole tile
print """inline ct_copy_tile(page)
{
    cu_set_addr_prep(page)
    cu_copy_line(page, 0)
    cu_copy_line(page, 1)
    cu_copy_line(page, 2)
    cu_copy_line(page, 3)
    cu_copy_line(page, 4)
    cu_copy_line(page, 5)
    cu_copy_line(page, 6)
    cu_copy_line(page, 7)

    stx $2006
    cu_update_data_ptr(2)
    jmp zp_writer
}\n"""

print_inst("copy_tile", "")

for length in range(1,8):
    for start in range(0,8-length+1):
        end = start + length-1
        name = "copy_X_%d_%d" % (start, end)
        print_header(name, ", op")

        print "    cu_set_addr_prep(page)"
        for i in range(8):
            if i >= start and i <= end:
                print "    cu_updt_line(page, %d, op)" % i
            else:
                print "    cu_copy_line(page, %d)" % i


        print "    stx $2006"
        print_udp(2+length)
        print "    jmp zp_writer\n}\n"

        print_inst(name, "copy_and_%d_%d" % (start, end), ", and")
        print_inst(name, "copy_ora_%d_%d" % (start, end), ", ora")

# set N lines, clear others

for length in range(1,8):
    for start in range(0,8-length+1):
        end = start + length-1
        name = "setclr_%d_%d" % (start, end)
        print_header(name)

        print "    cu_set_addr(page)\n    ldx #0"
        for i in range(8):
            if i >= start and i <= end:
                print "    cu_write_line(page, %d)" % (i-start)
            else:
                print "    stx $2007"


        print_udp(2+length)
        print "}\n"

        print_inst(name, "", "", 1)

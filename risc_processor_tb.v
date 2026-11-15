`timescale 1ns/1ps

module risc_processor_tb;

    reg clk;
    reg reset;

    risc_processor dut (
        .clk(clk),
        .reset(reset)
    );

    // 10 ns clock period.
    always #5 clk = ~clk;

    // R-type encoder.
    function [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            enc_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
        end
    endfunction

    // I-type encoder (ADDI and LW).
    function [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_i = {imm, rs1, funct3, rd, opcode};
        end
    endfunction

    // S-type encoder (SW).
    function [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_s = {imm[11:5], rs2, rs1, funct3,
                     imm[4:0], 7'b0100011};
        end
    endfunction

    // B-type encoder (BEQ).
    function [31:0] enc_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], 7'b1100011};
        end
    endfunction

    integer i;
    integer errors;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        errors = 0;

        // Load NOPs into instruction memory before releasing reset.
        for (i = 0; i < 32; i = i + 1)
            dut.imem[i] = 32'h00000013;

        // Program:
        // 0: ADDI x1, x0, 10
        // 1: ADDI x2, x0, 20
        // 2: ADD  x3, x1, x2       -> 30
        // 3: SUB  x4, x2, x1       -> 10
        // 4: AND  x6, x1, x2       -> 0
        // 5: OR   x7, x1, x2       -> 30
        // 6: SW   x3, 0(x0)        -> data_memory[0] = 30
        // 7: LW   x5, 0(x0)        -> x5 = 30
        // 8: BEQ  x3, x5, +8       -> skip instruction 9
        // 9: ADDI x8, x0, 99       -> must NOT execute
        // 10: ADDI x9, x0, 7       -> executes after branch

        dut.imem[0]  = enc_i(12'd10, 5'd0, 3'b000, 5'd1, 7'b0010011);
        dut.imem[1]  = enc_i(12'd20, 5'd0, 3'b000, 5'd2, 7'b0010011);
        dut.imem[2]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);
        dut.imem[3]  = enc_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4);
        dut.imem[4]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd6);
        dut.imem[5]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd7);
        dut.imem[6]  = enc_s(12'd0, 5'd3, 5'd0, 3'b010);
        dut.imem[7]  = enc_i(12'd0, 5'd0, 3'b010, 5'd5, 7'b0000011);
        dut.imem[8]  = enc_b(13'd8, 5'd5, 5'd3, 3'b000);
        dut.imem[9]  = enc_i(12'd99, 5'd0, 3'b000, 5'd8, 7'b0010011);
        dut.imem[10] = enc_i(12'd7, 5'd0, 3'b000, 5'd9, 7'b0010011);

        // Hold reset across at least one rising edge.
        #12;
        reset = 1'b0;

        // Run through instruction 10, including the taken branch.
        repeat (11) @(negedge clk);
        #1;

        $display("--------------------------------------");
        $display("32-bit RISC Processor Verification");
        $display("--------------------------------------");
        $display("x1  = %0d (expected 10)", dut.regs[1]);
        $display("x2  = %0d (expected 20)", dut.regs[2]);
        $display("x3  = %0d (expected 30)", dut.regs[3]);
        $display("x4  = %0d (expected 10)", dut.regs[4]);
        $display("x5  = %0d (expected 30)", dut.regs[5]);
        $display("x6  = %0d (expected 0)",  dut.regs[6]);
        $display("x7  = %0d (expected 30)", dut.regs[7]);
        $display("x8  = %0d (expected 0; skipped)", dut.regs[8]);
        $display("x9  = %0d (expected 7)",  dut.regs[9]);
        $display("DMEM[0] = %0d (expected 30)", dut.dmem[0]);

        if (dut.regs[1]  !== 32'd10) errors = errors + 1;
        if (dut.regs[2]  !== 32'd20) errors = errors + 1;
        if (dut.regs[3]  !== 32'd30) errors = errors + 1;
        if (dut.regs[4]  !== 32'd10) errors = errors + 1;
        if (dut.regs[5]  !== 32'd30) errors = errors + 1;
        if (dut.regs[6]  !== 32'd0)  errors = errors + 1;
        if (dut.regs[7]  !== 32'd30) errors = errors + 1;
        if (dut.regs[8]  !== 32'd0)  errors = errors + 1;
        if (dut.regs[9]  !== 32'd7)  errors = errors + 1;
        if (dut.dmem[0]  !== 32'd30) errors = errors + 1;
        if (dut.regs[0]  !== 32'd0)  errors = errors + 1;

        if (errors == 0)
            $display("RESULT: TEST PASSED");
        else
            $display("RESULT: TEST FAILED - %0d error(s)", errors);

        $display("--------------------------------------");
        $finish;
    end

endmodule

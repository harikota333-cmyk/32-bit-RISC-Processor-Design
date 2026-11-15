`timescale 1ns/1ps

// Educational 32-bit single-cycle RISC processor.
// Supported instructions: ADD, SUB, AND, OR, ADDI, LW, SW, BEQ.
// This is a small RISC-V-inspired teaching CPU, not a complete RV32I implementation.

module risc_processor (
    input wire clk,
    input wire reset
);

    reg [31:0] pc;
    reg [31:0] imem [0:31];
    reg [31:0] dmem [0:31];
    reg [31:0] regs [0:31];

    wire [31:0] instr;
    wire [6:0] opcode;
    wire [4:0] rd, rs1, rs2;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [31:0] imm;
    wire [31:0] alu_a, alu_b;
    wire [31:0] alu_result;
    wire [31:0] read_data;
    wire [31:0] write_back_data;

    reg reg_write;
    reg mem_write;
    reg mem_read;
    reg alu_src;
    reg branch;
    reg [1:0] alu_control;

    assign instr  = imem[pc[6:2]];
    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // Immediate generation for I-type, S-type and B-type instructions.
    assign imm =
        (opcode == 7'b0010011 || opcode == 7'b0000011) ?
            {{20{instr[31]}}, instr[31:20]} :
        (opcode == 7'b0100011) ?
            {{20{instr[31]}}, instr[31:25], instr[11:7]} :
        (opcode == 7'b1100011) ?
            {{19{instr[31]}}, instr[31], instr[7],
             instr[30:25], instr[11:8], 1'b0} :
            32'b0;

    assign alu_a = regs[rs1];
    assign alu_b = alu_src ? imm : regs[rs2];

    // Main control decoder.
    always @(*) begin
        reg_write   = 1'b0;
        mem_write   = 1'b0;
        mem_read    = 1'b0;
        alu_src     = 1'b0;
        branch      = 1'b0;
        alu_control = 2'b00;

        case (opcode)
            7'b0110011: begin // R-type
                reg_write = 1'b1;
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0100000)
                            alu_control = 2'b01; // SUB
                        else
                            alu_control = 2'b00; // ADD
                    end
                    3'b111: alu_control = 2'b10; // AND
                    3'b110: alu_control = 2'b11; // OR
                    default: begin
                        reg_write = 1'b0; // unsupported R-type function
                    end
                endcase
            end

            7'b0010011: begin // ADDI
                if (funct3 == 3'b000) begin
                    reg_write = 1'b1;
                    alu_src = 1'b1;
                    alu_control = 2'b00;
                end
            end

            7'b0000011: begin // LW
                if (funct3 == 3'b010) begin
                    reg_write = 1'b1;
                    mem_read = 1'b1;
                    alu_src = 1'b1;
                    alu_control = 2'b00;
                end
            end

            7'b0100011: begin // SW
                if (funct3 == 3'b010) begin
                    mem_write = 1'b1;
                    alu_src = 1'b1;
                    alu_control = 2'b00;
                end
            end

            7'b1100011: begin // BEQ
                if (funct3 == 3'b000)
                    branch = 1'b1;
            end

            default: begin
                // Unsupported instruction: no state changes except PC + 4.
            end
        endcase
    end

    // ALU.
    reg [31:0] alu_result_reg;
    assign alu_result = alu_result_reg;

    always @(*) begin
        case (alu_control)
            2'b00: alu_result_reg = alu_a + alu_b;
            2'b01: alu_result_reg = alu_a - alu_b;
            2'b10: alu_result_reg = alu_a & alu_b;
            2'b11: alu_result_reg = alu_a | alu_b;
            default: alu_result_reg = 32'b0;
        endcase
    end

    assign read_data = dmem[alu_result[6:2]];
    assign write_back_data = mem_read ? read_data : alu_result;

    // Sequential state updates.
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'b0;
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
                dmem[i] <= 32'b0;
            end
        end else begin
            // x0 is hardwired to zero.
            regs[0] <= 32'b0;

            if (mem_write)
                dmem[alu_result[6:2]] <= regs[rs2];

            if (reg_write && (rd != 5'd0))
                regs[rd] <= write_back_data;

            if (branch && (regs[rs1] == regs[rs2]))
                pc <= pc + imm;
            else
                pc <= pc + 32'd4;
        end
    end

endmodule

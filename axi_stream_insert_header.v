module axi_stream_insert_header #(
parameter DATA_WD = 32,
parameter DATA_BYTE_WD = DATA_WD / 8,
parameter BYTE_CNT_WD = $clog2(DATA_BYTE_WD)
) (
input clk,
input rst_n,
// AXI Stream input original data
input valid_in,
input [DATA_WD-1 : 0] data_in,
input [DATA_BYTE_WD-1 : 0] keep_in,
input last_in,
output ready_in,
// AXI Stream output with header inserted
output valid_out,
output [DATA_WD-1 : 0] data_out,
output [DATA_BYTE_WD-1 : 0] keep_out,
output last_out,
input ready_out,
// The header to be inserted to AXI Stream input
input valid_insert,
input [DATA_WD-1 : 0] data_insert,
input [DATA_BYTE_WD-1 : 0] keep_insert,
input [BYTE_CNT_WD-1 : 0] byte_insert_cnt,
output ready_insert
);
// Your code here

reg reg_ready_in;
reg reg_valid_out;
reg reg_ready_insert;
reg [DATA_WD-1 : 0] reg_data_out;
reg [DATA_BYTE_WD-1 : 0] reg_keep_out;
reg reg_last_out;

assign ready_in = reg_ready_in;
assign valid_out = reg_valid_out;
assign ready_insert = reg_ready_insert;
assign data_out = reg_data_out;
assign keep_out = reg_keep_out;
assign last_out = reg_last_out;

reg [7:0] data_reg [0:7]; //8*8寄存器，用于存储header和data
    
    genvar j;
    generate for (j = 3'b0; j < 8; j=j+1) begin
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n)
                data_reg[j] <= 8'b0;
            //第一拍输入header中的有效位数
            else if(ready_insert == 1 && valid_insert == 1 && j >= 0 && j < byte_insert_cnt)begin
                data_reg[j] <= data_insert[DATA_WD - 1 - (DATA_BYTE_WD - byte_insert_cnt + j) * 8 -: 8];
            end
            //第一拍输入data信号
            else if(ready_in == 1 && valid_in == 1 && j >= byte_insert_cnt && j < (byte_insert_cnt + DATA_BYTE_WD))begin
                data_reg[j] <= data_in[DATA_WD - 1 - (j - byte_insert_cnt) * 8 -: 8];
            end
            //最后一位data信号到来时补0
            else if(j >= (byte_insert_cnt + DATA_BYTE_WD) && last_in)begin
                data_reg[j] <= 0;
            end
            //中间每一拍将后四位的值赋给前四位，然后将新的data信号写入寄存器
            else if(ready_out == 1 && ready_insert == 0 && ready_in == 1)begin
                if(j >= byte_insert_cnt && j < (byte_insert_cnt + DATA_BYTE_WD))
                    data_reg[j] <= data_in[DATA_WD - 1 - (j - byte_insert_cnt) * 8 -: 8];
                else if(j >= 0 && j < 4)
                    data_reg[j] <= data_reg[j+4];
            end
            else begin
                data_reg[j] <= data_reg[j]; 
            end   
        end
    end
    endgenerate


    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            reg_ready_insert <= 1;
            reg_ready_in <= 1;
        end 
        else begin 
            if(valid_in == 1 && valid_insert == 1)begin
                reg_ready_insert <= 0;
            end
            if(last_in) begin
                reg_ready_in <= 0;    
            end
        end
     end  
     
     //记录header信号和最后一拍data信号中一共有效位的个数
     reg [3:0]valid_cnt;
     
     always@(posedge clk or negedge rst_n)begin
     if(!rst_n)
        valid_cnt <= 0;
     else
        valid_cnt <= last_in?swar(keep_in) + byte_insert_cnt : valid_cnt;        
    end
    
    wire [2:0] remainder;
    assign remainder = (valid_cnt % 4);
    
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            reg_keep_out <= 0;
        else begin
            case(remainder) 
                0:reg_keep_out <= 4'b1111;
                1:reg_keep_out <= 4'b1000;
                2:reg_keep_out <= 4'b1100;
                3:reg_keep_out <= 4'b1110;
            endcase
        end
    end
    
    reg [1:0]r_last_in;
    always@(posedge clk)begin
        r_last_in[0] <= last_in;
        r_last_in[1] <= r_last_in[0];
    end
    
    integer i; 
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            reg_last_out <= 0;
            reg_data_out <= 32'b0;
            reg_valid_out <= 0;
        end
        //每次输出前四个字节
        else if(ready_out == 1 && ready_insert == 0 && r_last_in[1] == 0)begin
            reg_valid_out <= 1;
            for (i = 0; i < DATA_BYTE_WD; i = i + 1) begin
                reg_data_out[(DATA_BYTE_WD-i) * 8 - 1 -: 8] <= data_reg[i];
            end
        end
        //最后一拍输出后四个字节
        else if(r_last_in[1])begin
            reg_last_out <= 1;
            for (i = 0; i < DATA_BYTE_WD; i = i + 1) begin
                reg_data_out[(DATA_BYTE_WD-i) * 8 - 1 -: 8] <= data_reg[i + 4];
            end
        end
        else begin 
            for (i = 0; i < DATA_BYTE_WD; i = i + 1) begin
                reg_data_out[(DATA_BYTE_WD-i) * 8 - 1 -: 8] <=data_out[(DATA_BYTE_WD-i) * 8 - 1 -: 8];
            end 
        end
    end
    
    function [DATA_WD-1:0]swar;
        input [DATA_WD-1:0] data_in;
        reg [DATA_WD-1:0] i;
        begin
            i = data_in;
            i = (i & 32'h55555555) + ({1'b0, i[DATA_WD-1:1]} & 32'h55555555);
            i = (i & 32'h33333333) + ({1'b0, i[DATA_WD-1:2]} & 32'h33333333);
            i = (i & 32'h0F0F0F0F) + ({1'b0, i[DATA_WD-1:4]} & 32'h0F0F0F0F);
            i = i * (32'h01010101);
            swar = i[31:24];    
        end        
    endfunction
endmodule
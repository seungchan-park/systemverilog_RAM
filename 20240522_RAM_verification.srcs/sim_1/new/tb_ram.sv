`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/22 14:32:18
// Design Name: 
// Module Name: tb_ram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

interface ram_interface;
    logic       clk;
    logic       wr_en;
    logic [9:0] addr;
    logic [7:0] wdata;
    logic [7:0] rdata;
endinterface  //ram_interface

class transaction;
    rand bit       wr_en;  // rand: 무작위, randc: 순환
    rand bit [9:0] addr;
    rand bit [7:0] wdata;
    bit      [7:0] rdata;

    task display(string name);
        $display("[%s] wr_en: %x, addr: %x, wdata: %x, rdata: %x", name, wr_en,
                 addr, wdata, rdata);
    endtask

    // 제약사항, 제약설정
    //constraint c_addr {addr < 10;}
    constraint c_addr {addr inside {[10 : 19]};}  // 10~19 중에 생성
    constraint c_wdata1 {wdata < 100;}
    constraint c_wdata2 {wdata > 10;}
    //constraint c_wr_en {wr_en dist {0:=100, 1:=110};} // 비율 조정: 전체(220) 중에 비율
    constraint c_wr_en {
        wr_en dist {
            0 :/ 60,
            1 :/ 40
        };
    }  // 비율 조정: 백분율
endclass  //transaction

class generator;
    transaction trans;
    mailbox #(transaction) gen2drv_mbox; // #(transaction) 안해줘도 알아서 판단함?
    event gen_next_event;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction  //new()

    task run(int count);
        repeat (count) begin
            trans = new();
            assert (trans.randomize())
            else $error("[GEN] trans.randomize() error!");
            gen2drv_mbox.put(trans);
            trans.display("[GEN]");
            @(gen_next_event);
        end
    endtask
endclass  //generator

class driver;
    transaction trans;
    mailbox #(transaction) gen2drv_mbox;
    virtual ram_interface ram_if;

    function new(virtual ram_interface ram_if,
                 mailbox#(transaction) gen2drv_mbox);
        this.ram_if = ram_if;
        this.gen2drv_mbox = gen2drv_mbox;
    endfunction  //new()

    task reset();
        ram_if.wr_en <= 1'b0;
        ram_if.addr  <= 0;
        ram_if.wdata <= 0;
        repeat (5) @(posedge ram_if.clk);
    endtask

    task run();
        forever begin
            gen2drv_mbox.get(
                trans);  // mailbox reference memory는 지워진다
            ram_if.wr_en <= trans.wr_en;
            ram_if.addr  <= trans.addr;
            ram_if.wdata <= trans.wdata;
            // if (trans.wr_en) begin  // read
            //     ram_if.wr_en <= trans.wr_en;
            //     ram_if.addr  <= trans.addr;
            // end else begin  // write
            //     ram_if.wr_en <= trans.wr_en;
            //     ram_if.addr  <= trans.addr;
            //     ram_if.wdata <= trans.wdata;
            // end
            trans.display("[DRV]");
            @(posedge ram_if.clk);
            // output
        end
    endtask
endclass  //driver

class monitor;
    virtual ram_interface ram_if;
    mailbox #(transaction) mon2scb_mbox;
    transaction trans;

    function new(virtual ram_interface ram_if,
                 mailbox#(transaction) mon2scb_mbox);
        this.ram_if = ram_if;
        this.mon2scb_mbox = mon2scb_mbox;
    endfunction  //new()

    task run();
        forever begin
            trans = new();
            @(posedge ram_if.clk);
            trans.wr_en = ram_if.wr_en;
            trans.addr  = ram_if.addr;
            trans.wdata = ram_if.wdata;
            trans.rdata = ram_if.rdata;
            trans.display("[MON]");
            mon2scb_mbox.put(trans);
        end
    endtask
endclass  //monitor

class scoreboard;
    mailbox #(transaction) mon2scb_mbox;
    transaction trans;
    event gen_next_event;

    int total_cnt, pass_cnt, fail_cnt, write_cnt;
    logic [7:0] mem[0:2**10-1];

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
        total_cnt = 0;
        pass_cnt = 0;
        fail_cnt = 0;
        write_cnt = 0;

        for (int i = 0; i < 2 ** 10; i++) begin
            mem[i] = 0;
        end
    endfunction  //new()

    task run();
        forever begin
            mon2scb_mbox.get(trans);
            trans.display("[SCB]");
            if (trans.wr_en) begin  // read
                if (mem[trans.addr] == trans.rdata) begin
                    $display(" --> READ PASS! mem[%x] == %x", trans.addr,
                             trans.rdata);
                    pass_cnt++;
                end else begin
                    $display(" --> READ FAIL! mem[%x] != %x", trans.addr,
                             trans.rdata);
                    fail_cnt++;
                end
            end else begin  // write
                mem[trans.addr] = trans.wdata;
                $display("--> WRITE! mem[%x] = %x", trans.addr, trans.wdata);
                write_cnt++;
            end
            total_cnt++;
            ->gen_next_event;
        end
    endtask
endclass  //scoreboard

class environment;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;

    event                  gen_next_event;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    function new(virtual ram_interface ram_if);
        gen2drv_mbox = new();
        mon2scb_mbox = new();

        gen = new(gen2drv_mbox, gen_next_event);
        drv = new(ram_if, gen2drv_mbox);
        mon = new(ram_if, mon2scb_mbox);
        scb = new(mon2scb_mbox, gen_next_event);
    endfunction  //new()

    task report();
        $display("==================================");
        $display("==         Final Report         ==");
        $display("==================================");
        $display("Total Test : %d", scb.total_cnt);
        $display("Pass Test : %d", scb.pass_cnt);
        $display("Fail Test : %d", scb.fail_cnt);
        $display("WRITE CNT : %d", scb.write_cnt);
        $display("==================================");
        $display("==    testbench is finished!    ==");
        $display("==================================");
    endtask

    task pre_run();
        drv.reset();
    endtask

    task run();
        fork
            gen.run(1000);
            drv.run();
            mon.run();
            scb.run();
        join_any
        report();
        #10 $finish;
    endtask

    task run_test();
        pre_run();
        run();
    endtask
endclass  //environment

module tb_ram ();
    environment env;
    ram_interface ram_if ();

    ram dut (
        .clk(ram_if.clk),
        .address(ram_if.addr),
        .wdata(ram_if.wdata),
        .wr_en(ram_if.wr_en),
        .rdata(ram_if.rdata)
    );

    always #5 ram_if.clk = ~ram_if.clk;

    initial begin
        ram_if.clk = 1'b0;
    end

    initial begin
        env = new(ram_if);
        env.run_test();
    end
endmodule



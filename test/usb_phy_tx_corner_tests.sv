// TX directed corner-case tests. All tests use the existing PHY driver,
// TX wire checker, and scoreboard. Run each test with USB_SPEED=0/1/2.

class usb_phy_tx_directed_base_test extends usb_phy_base_test;
  `uvm_component_utils(usb_phy_tx_directed_base_test)
  int unsigned start_checked;
  int unsigned start_failed;

  function new(string name="usb_phy_tx_directed_base_test", uvm_component parent=null);
    super.new(name,parent);
  endfunction

  task wait_reset_release();
    wait(env_cfg.phy_cfg.vif.rst_n === 1'b1);
    repeat (2) @(posedge env_cfg.phy_cfg.vif.clk);
  endtask

  task send_packet(input byte unsigned data[$], input bit sof=0,
                   input int unsigned gap=0);
    phy_directed_tx_seq seq;
    seq = phy_directed_tx_seq::type_id::create("directed_seq");
    seq.packet_speed = env_cfg.speed;
    seq.sof_packet = sof;
    seq.inter_byte_gap = gap;
    foreach (data[i]) seq.payload.push_back(data[i]);
    seq.start(env.phy_ag.sequencer);
    // Driver returns after the EOP has left the TX pins. Allow monitor/checker
    // analysis updates to settle before inspecting counters or starting next packet.
    repeat (3) @(posedge env_cfg.phy_cfg.vif.clk);
  endtask

  task begin_tx_test();
    if (env == null || env.phy_ag == null || env.phy_ag.sequencer == null)
      `uvm_fatal("TX_CORNER", "PHY environment/sequencer is unavailable")
    if (env.tx_wire_checker == null || env.scoreboard == null)
      `uvm_fatal("TX_CORNER", "TX wire checker and scoreboard are required")
    wait_reset_release();
    start_checked = env.tx_wire_checker.packets_checked;
    start_failed  = env.tx_wire_checker.packets_failed;
  endtask

  task end_tx_test(input int unsigned expected_packets, input string label);
    int unsigned timeout;
    timeout = 0;
    while ((env.tx_wire_checker.packets_checked - start_checked < expected_packets) &&
           timeout < 1000000) begin
      @(posedge env_cfg.phy_cfg.vif.clk);
      timeout++;
    end
    if (env.tx_wire_checker.packets_checked - start_checked != expected_packets)
      `uvm_error("TX_CORNER", $sformatf("%s expected %0d checked packets, observed %0d",
                 label, expected_packets, env.tx_wire_checker.packets_checked-start_checked))
    if (env.tx_wire_checker.packets_failed != start_failed)
      `uvm_error("TX_CORNER", $sformatf("%s: TX wire checker reported %0d new failed packets",
                 label, env.tx_wire_checker.packets_failed-start_failed))
    if (env.tx_wire_checker.symbol_errors != 0 &&
        env.tx_wire_checker.packets_failed != start_failed)
      `uvm_error("TX_CORNER", $sformatf("%s: physical symbol errors detected",label))
  endtask
endclass

class usb_phy_tx_data_pattern_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_data_pattern_test)
  function new(string name="usb_phy_tx_data_pattern_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    p.push_back(8'h00); send_packet(p); p.delete();
    p.push_back(8'hff); send_packet(p); p.delete();
    p.push_back(8'haa); send_packet(p); p.delete();
    p.push_back(8'h55); send_packet(p); p.delete();
    p.push_back(8'h7e); send_packet(p); p.delete();
    p.push_back(8'h81); send_packet(p); p.delete();
    p.push_back(8'hf0); send_packet(p); p.delete();
    p.push_back(8'h0f); send_packet(p); p.delete();
    p.push_back(8'h96); send_packet(p); p.delete();
    p.push_back(8'h69); send_packet(p);
    end_tx_test(10,"data patterns"); phase.drop_objection(this);
  endtask
endclass

class usb_phy_tx_bitstuff_boundary_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_bitstuff_boundary_test)
  function new(string name="usb_phy_tx_bitstuff_boundary_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    p.push_back(8'hff); send_packet(p); p.delete();
    p.push_back(8'hff); p.push_back(8'hff); send_packet(p); p.delete();
    // Three trailing ones in E0 followed by three leading ones in 07:
    // exercises a six-one run crossing the byte boundary.
    p.push_back(8'he0); p.push_back(8'h07); send_packet(p); p.delete();
    p.push_back(8'h1f); p.push_back(8'hfc); p.push_back(8'hff); send_packet(p);
    end_tx_test(4,"bit-stuff boundary patterns"); phase.drop_objection(this);
  endtask
endclass

class usb_phy_tx_nrzi_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_nrzi_test)
  function new(string name="usb_phy_tx_nrzi_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    p.push_back(8'h00); p.push_back(8'h00); send_packet(p); p.delete();
    p.push_back(8'hff); p.push_back(8'hff); send_packet(p); p.delete();
    p.push_back(8'haa); p.push_back(8'h55); send_packet(p); p.delete();
    p.push_back(8'h01); p.push_back(8'h80); p.push_back(8'h7f); send_packet(p);
    end_tx_test(4,"NRZI transition patterns"); phase.drop_objection(this);
  endtask
endclass

class usb_phy_tx_sync_eop_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_sync_eop_test)
  function new(string name="usb_phy_tx_sync_eop_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    p.push_back(8'h00); send_packet(p); p.delete();
    p.push_back(8'hff); send_packet(p); p.delete();
    p.push_back(8'ha5); p.push_back(8'h5a); send_packet(p);
    if (env_cfg.speed == HS) begin
      p.delete(); p.push_back(8'hc3); send_packet(p,1'b1);
    end
    end_tx_test((env_cfg.speed == HS) ? 4 : 3,"SYNC/EOP"); phase.drop_objection(this);
  endtask
endclass

class usb_phy_tx_fifo_boundary_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_fifo_boundary_test)
  function new(string name="usb_phy_tx_fifo_boundary_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    int lengths[$];
    phase.raise_objection(this); begin_tx_test();
    lengths.push_back(1); lengths.push_back(15); lengths.push_back(16);
    lengths.push_back(17); lengths.push_back(31); lengths.push_back(64);
    foreach (lengths[n]) begin
      p.delete();
      for (int i=0;i<lengths[n];i++) p.push_back((i%2)==0 ? 8'hff : 8'h00);
      send_packet(p);
    end
    end_tx_test(6,"FIFO boundary lengths 1/15/16/17/31/64"); phase.drop_objection(this);
  endtask
endclass

class usb_phy_tx_backpressure_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_backpressure_test)
  function new(string name="usb_phy_tx_backpressure_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    // Long burst exceeds the 16-entry TX FIFO capacity over the packet lifetime.
    for (int i=0;i<64;i++) p.push_back((i%4==0) ? 8'hff : (i%4==1) ? 8'h00 : (i%4==2) ? 8'haa : 8'h55);
    send_packet(p);
    end_tx_test(1,"TX FIFO backpressure");
    if (env.tx_wire_checker.ready_stall_cycles == 0)
      `uvm_warning("TX_BACKPRESSURE", "No ready stall observed; stimulus did not exercise FIFO-full backpressure")
    phase.drop_objection(this);
  endtask
endclass

class usb_phy_tx_back_to_back_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_back_to_back_test)
  function new(string name="usb_phy_tx_back_to_back_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    for (int n=0;n<8;n++) begin
      p.delete(); p.push_back(8'(n)); p.push_back(8'hff); p.push_back(8'(~n));
      send_packet(p);
    end
    end_tx_test(8,"back-to-back TX packets"); phase.drop_objection(this);
  endtask
endclass

class usb_phy_tx_interpacket_gap_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_interpacket_gap_test)
  function new(string name="usb_phy_tx_interpacket_gap_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    p.push_back(8'h12); send_packet(p); p.delete();
    repeat (clocks_per_bit_local(env_cfg.speed)*2) @(posedge env_cfg.phy_cfg.vif.clk);
    p.push_back(8'h34); send_packet(p); p.delete();
    repeat (clocks_per_bit_local(env_cfg.speed)*8) @(posedge env_cfg.phy_cfg.vif.clk);
    p.push_back(8'h56); send_packet(p);
    end_tx_test(3,"inter-packet gap"); phase.drop_objection(this);
  endtask
  function int clocks_per_bit_local(speed_t s); case(s) LS:return 320; FS:return 40; HS:return 1; default:return 1; endcase endfunction
endclass

class usb_phy_tx_sof_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_sof_test)
  function new(string name="usb_phy_tx_sof_test",uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    byte unsigned p[$];
    phase.raise_objection(this); begin_tx_test();
    p.push_back(8'h2d); p.push_back(8'h00);
    if (env_cfg.speed == HS) send_packet(p,1'b1);
    else send_packet(p,1'b0);
    end_tx_test(1,"SOF packet"); phase.drop_objection(this);
  endtask
endclass

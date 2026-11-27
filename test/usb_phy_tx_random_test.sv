// Unified constrained-random USB PHY TX test with per-packet speed changes.
// Speed is changed only between complete packets while the bus and RX are idle.
// This is a PHY configuration stress test; it is not USB bus-level speed negotiation.

class usb_phy_tx_rand_packet_cfg extends uvm_object;
  `uvm_object_utils(usb_phy_tx_rand_packet_cfg)

  rand byte unsigned payload[];
  rand int unsigned inter_byte_gap;
  rand bit sof_packet;

  // Fixed before randomization by the test. HS TX consumes one byte in
  // approximately 8 system clocks, so its source gap must remain below that
  // service rate. LS/FS have much longer byte times and can use a wider gap.
  speed_t packet_speed;

  constraint c_payload_size {
    payload.size() inside {[1:64]};
  }

  constraint c_inter_byte_gap {
    if (packet_speed == HS)
      inter_byte_gap inside {[0:4]};
    else
      inter_byte_gap inside {[0:20]};
  }

  function new(string name="usb_phy_tx_rand_packet_cfg");
    super.new(name);
    packet_speed = FS;
  endfunction
endclass

class usb_phy_tx_random_test extends usb_phy_tx_directed_base_test;
  `uvm_component_utils(usb_phy_tx_random_test)

  // randc ensures LS, FS and HS are each selected once before a speed repeats.
  randc speed_t next_packet_speed;
  constraint c_packet_speed {
    next_packet_speed inside {LS, FS, HS};
  }

  int unsigned num_packets;
  int unsigned start_symbols;
  int unsigned start_symbol_errors;
  int unsigned start_timing_errors;
  int unsigned speed_count_ls;
  int unsigned speed_count_fs;
  int unsigned speed_count_hs;
  bit loopback_enabled;

  function new(string name="usb_phy_tx_random_test",
               uvm_component parent=null);
    super.new(name,parent);
    num_packets = 100;
  endfunction

  function int unsigned clocks_per_bit_local(speed_t speed);
    case (speed)
      LS: return 320;
      FS: return 40;
      HS: return 1;
      default: return 40;
    endcase
  endfunction

  // Change speed only after the previous packet and any loopback RX activity finish.
  task switch_speed_at_packet_boundary(speed_t new_speed);
    virtual usb_phy_if #(8) vif;
    virtual usb_bus_if bus_vif;
    int unsigned timeout;

    vif = env_cfg.phy_cfg.vif;
    bus_vif = env_cfg.usb_bfm_cfg.bus_vif;
    timeout = 0;

    while ((vif.tx_valid !== 1'b0) ||
           (vif.RxActive !== 1'b0) ||
           (bus_vif.device_oe !== 1'b0) ||
           (vif.sie_valid !== 1'b0)) begin
      @(posedge vif.clk);
      timeout++;
      if (timeout >= 1000000)
        `uvm_fatal("TX_RANDOM_SPEED",
          "Timeout waiting for TX, RX and external BFM to become idle")
    end

    // Leave an idle guard interval at the old speed before changing PHY mode.
    repeat (2 * clocks_per_bit_local(env_cfg.speed)) @(posedge vif.clk);

    if (vif.tx_valid !== 1'b0 || vif.RxActive !== 1'b0 ||
        bus_vif.device_oe !== 1'b0)
      `uvm_fatal("TX_RANDOM_SPEED", "Bus became active during speed-change guard interval")

    // Update every UVM configuration object and the actual DUT speed input.
    env_cfg.set_speed(new_speed);
    @(negedge vif.clk);
    vif.usb_speed = new_speed;

    // Allow speed-dependent TX/RX logic and monitors to settle before SOP.
    repeat (8) @(posedge vif.clk);

    `uvm_info("TX_RANDOM_SPEED",
      $sformatf("Per-packet USB speed changed to %s", new_speed.name()), UVM_LOW)
  endtask

  task run_phase(uvm_phase phase);
    usb_phy_tx_rand_packet_cfg rand_cfg;
    byte unsigned packet_bytes[$];
    int unsigned packets_sent;
    bit packet_sof;

    phase.raise_objection(this);
    begin_tx_test();

    if (!$value$plusargs("TX_RANDOM_PACKETS=%d", num_packets))
      num_packets = 100;
    if (num_packets == 0)
      `uvm_fatal("TX_RANDOM", "TX_RANDOM_PACKETS must be greater than zero")

    if (!$value$plusargs("USB_TX_RX_LOOPBACK=%d", loopback_enabled))
      loopback_enabled = 1'b0;

    start_checked       = env.tx_wire_checker.packets_checked;
    start_failed        = env.tx_wire_checker.packets_failed;
    start_symbols       = env.tx_wire_checker.symbols_checked;
    start_symbol_errors = env.tx_wire_checker.symbol_errors;
    start_timing_errors = env.tx_wire_checker.timing_errors;

    speed_count_ls = 0;
    speed_count_fs = 0;
    speed_count_hs = 0;
    packets_sent = 0;

    `uvm_info("TX_RANDOM", $sformatf(
      "Starting per-packet randomized TX: packets=%0d loopback=%0b initial_speed=%s",
      num_packets, loopback_enabled, env_cfg.speed.name()), UVM_LOW)

    while (packets_sent < num_packets) begin
      if (!this.randomize())
        `uvm_fatal("TX_RANDOM", "Per-packet USB speed randomization failed")

      // Change the speed at an idle packet boundary. The first packet also
      // goes through this path so the speed selection is visible in the log.
      switch_speed_at_packet_boundary(next_packet_speed);

      rand_cfg = usb_phy_tx_rand_packet_cfg::type_id::create(
                   $sformatf("rand_cfg_%0d", packets_sent));
      rand_cfg.packet_speed = env_cfg.speed;
      if (!rand_cfg.randomize())
        `uvm_fatal("TX_RANDOM", "Random packet payload/gap randomization failed")

      packet_sof = (env_cfg.speed == HS) ? rand_cfg.sof_packet : 1'b0;
      packet_bytes.delete();
      foreach (rand_cfg.payload[i])
        packet_bytes.push_back(rand_cfg.payload[i]);

      case (env_cfg.speed)
        LS: speed_count_ls++;
        FS: speed_count_fs++;
        HS: speed_count_hs++;
        default: `uvm_fatal("TX_RANDOM", "Illegal speed selected")
      endcase

      `uvm_info("TX_RANDOM_PACKET", $sformatf(
        "Packet=%0d/%0d speed=%s length=%0d inter_byte_gap=%0d SOF=%0b loopback=%0b",
        packets_sent+1, num_packets, env_cfg.speed.name(), packet_bytes.size(),
        rand_cfg.inter_byte_gap, packet_sof, loopback_enabled), UVM_LOW)

      send_packet(packet_bytes, packet_sof, rand_cfg.inter_byte_gap);
      packets_sent++;
    end

    end_tx_test(num_packets, "per-packet randomized-speed TX packets");

    if (env.tx_wire_checker.packets_failed != start_failed)
      `uvm_error("TX_RANDOM", "New TX wire-checker packet failures detected")
    if (env.tx_wire_checker.symbol_errors != start_symbol_errors)
      `uvm_error("TX_RANDOM", "New physical symbol mismatches detected")
    if (env.tx_wire_checker.timing_errors != start_timing_errors)
      `uvm_error("TX_RANDOM", "New TX timing mismatches detected")

    `uvm_info("TX_RANDOM_SUMMARY", $sformatf(
      "Sent=%0d checked=%0d LS=%0d FS=%0d HS=%0d symbols=%0d symbol_errors=%0d timing_errors=%0d packet_failures=%0d loopback=%0b",
      packets_sent,
      env.tx_wire_checker.packets_checked-start_checked,
      speed_count_ls, speed_count_fs, speed_count_hs,
      env.tx_wire_checker.symbols_checked-start_symbols,
      env.tx_wire_checker.symbol_errors-start_symbol_errors,
      env.tx_wire_checker.timing_errors-start_timing_errors,
      env.tx_wire_checker.packets_failed-start_failed,
      loopback_enabled), UVM_LOW)

    phase.drop_objection(this);
  endtask
endclass
